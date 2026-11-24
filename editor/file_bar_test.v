module editor

import os
import ecs
import protocol
import sim
import ui

// Geri al / yinele, kaydet / aç, kaydedilmemiş değişiklik şeridi ve durum çubuğu hataları (M4c Görev 9).
// Test dosyaları ayrı derlenir: yardımcılar editor_test.v'deki ile aynıdır.

fn edt_server() protocol.Server {
	return protocol.Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

fn edt_frame(mut c ui.Context, mut e Editor, mut srv protocol.Server, inp ui.Input) EditorFrame {
	c.begin(inp, 1440, 900, 1.0)
	fr := e.frame(mut c, mut srv)
	c.end()
	return fr
}

fn edt_click(mut c ui.Context, mut e Editor, mut srv protocol.Server, label string) {
	r := c.last_rect(label) or { panic('dugme yok: ${label}') }
	x := r.x + r.w / 2
	y := r.y + r.h / 2
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: x, mouse_y: y })
	mut down := ui.Input{ mouse_x: x, mouse_y: y }
	down.down[0] = true
	down.pressed[0] = true
	edt_frame(mut c, mut e, mut srv, down)
	mut up := ui.Input{ mouse_x: x, mouse_y: y }
	up.released[0] = true
	edt_frame(mut c, mut e, mut srv, up)
}

fn edt_key(k ui.Key) ui.Input {
	mut inp := ui.Input{ mouse_x: -1, mouse_y: -1 }
	inp.keys[0] = k
	inp.key_count = 1
	return inp
}

fn fb_spawn(mut srv protocol.Server) ecs.EntityID {
	resp := srv.handle('{"jsonrpc":"2.0","id":3,"method":"entity.spawn"}') or { panic('yanit yok') }
	return protocol.response_entity(resp) or { panic('kimlik yok') }
}

fn fb_ctrl(k ui.Key, shift bool) ui.Input {
	mut inp := edt_key(k)
	inp.ctrl = true
	inp.shift = shift
	return inp
}

// Şerit düğmeleri push_id(1) altında çizilir: kimlik aynı yığında hesaplanır.
fn fb_strip_id(mut c ui.Context, label string) u32 {
	c.push_id(1)
	id := c.id(label)
	c.pop_id()
	return id
}

fn fb_click_id(mut c ui.Context, mut e Editor, mut srv protocol.Server, id u32) {
	r := c.last_rect_id(id) or { panic('dugme yok') }
	x := r.x + r.w / 2
	y := r.y + r.h / 2
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: x, mouse_y: y })
	mut down := ui.Input{ mouse_x: x, mouse_y: y }
	down.down[0] = true
	down.pressed[0] = true
	edt_frame(mut c, mut e, mut srv, down)
	mut up := ui.Input{ mouse_x: x, mouse_y: y }
	up.released[0] = true
	edt_frame(mut c, mut e, mut srv, up)
}

fn fb_tmp(name string) string {
	return os.join_path(os.temp_dir(), 'vcore_m4c9_${name}_${os.getpid()}.vscene')
}

fn test_ctrl_z_y_undo_redo() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fb_spawn(mut srv)
	assert srv.world().alive_count() == 1
	edt_frame(mut c, mut e, mut srv, fb_ctrl(.z, false))
	assert srv.world().alive_count() == 0, 'Ctrl+Z geri alir'
	edt_frame(mut c, mut e, mut srv, fb_ctrl(.z, true))
	assert srv.world().alive_count() == 1, 'Ctrl+Shift+Z yineler'
	edt_frame(mut c, mut e, mut srv, fb_ctrl(.z, false))
	assert srv.world().alive_count() == 0
	edt_frame(mut c, mut e, mut srv, fb_ctrl(.y, false))
	assert srv.world().alive_count() == 1, 'Ctrl+Y yineler'
}

fn test_undo_buttons_disabled_when_empty() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	// Bos yiginda dugmeler etkisiz: tiklama hata ya da bildirim uretmez.
	edt_click(mut c, mut e, mut srv, 'Geri al')
	edt_click(mut c, mut e, mut srv, 'Yinele')
	assert e.flash_text() == '', 'bos yiginda hata yok'
	fb_spawn(mut srv)
	edt_click(mut c, mut e, mut srv, 'Geri al')
	assert srv.world().alive_count() == 0, 'etkin dugme geri alir'
	edt_click(mut c, mut e, mut srv, 'Yinele')
	assert srv.world().alive_count() == 1, 'etkin dugme yineler'
}

fn test_undo_remaps_selection() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut e := Editor.new('')
	a := fb_spawn(mut srv)
	resp := srv.handle('{"jsonrpc":"2.0","id":4,"method":"entity.despawn","params":{"entity":${u64(a)}}}') or {
		panic('yanit yok')
	}
	assert protocol.response_ok(resp)
	// Secili varlik (kare basinda dusmeden once) geri alimda yeni id'ye tasinir.
	e.sv.sel = a
	e.history_step(mut srv, true)
	has, sel := e.sv.selected()
	assert has && sel != a, 'secim yeni id\'ye tasinmali'
	assert srv.world().is_alive(sel)
}

fn test_undo_skipped_while_drag_group_open() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut e := Editor.new('')
	fb_spawn(mut srv)
	e.ins.grouping = true
	e.history_step(mut srv, true)
	assert srv.world().alive_count() == 1, 'surukleme grubu acikken geri alma istenmez'
}

fn test_save_with_path_clears_dirty() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	path := fb_tmp('save')
	defer {
		os.rm(path) or {}
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	e.path.set(path) // Editor.new(path) başlangıçta yüklemeye çalışır; dosya yoksa yol silinir
	fb_spawn(mut srv)
	assert e.saved_count != srv.change_count(), 'kirli'
	edt_click(mut c, mut e, mut srv, 'Kaydet')
	assert e.saved_count == srv.change_count(), "kayit kirliligi temizler: flash=${e.flash_text()}"
	assert os.exists(path)
}

fn test_save_without_path_opens_field() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	path := fb_tmp('field')
	defer {
		os.rm(path) or {}
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	edt_click(mut c, mut e, mut srv, 'Kaydet')
	assert e.file_field == .save, 'yol yoksa yol alani acilir'
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert c.last_rect('Yol') != none, 'alan cizilir'
	e.field.set(path)
	edt_frame(mut c, mut e, mut srv, edt_key(.enter))
	assert e.file_field == .idle, 'Enter alani kapatir'
	assert e.path.str() == path
	assert os.exists(path)
}

fn test_open_loads_scene_and_clears_selection() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	path := fb_tmp('open')
	defer {
		os.rm(path) or {}
	}
	mut e := Editor.new('')
	fb_spawn(mut srv)
	assert e.save_to(mut srv, path)
	fb_spawn(mut srv)
	assert srv.world().alive_count() == 2
	e.sv.sel = fb_spawn(mut srv)
	assert e.open_path(mut srv, path)
	assert srv.world().alive_count() == 1, 'dosya yuklenir'
	has, _ := e.sv.selected()
	assert !has, 'yukleme secimi temizler'
	assert e.saved_count == srv.change_count(), 'yukleme temiz baslangic'
	assert e.path.str() == path
}

fn test_dirty_close_shows_confirm_strip() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	path := fb_tmp('close')
	defer {
		os.rm(path) or {}
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	e.path.set(path) // Editor.new(path) başlangıçta yüklemeye çalışır; dosya yoksa yol silinir
	fb_spawn(mut srv)
	e.request_close()
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert e.confirm == .close, 'kirliyken kapatma seridi acilir'
	assert !e.should_close(), 'serit varken pencere acik kalir'
	assert c.last_rect('confirm') != none, 'serit cizilir'
	fb_click_id(mut c, mut e, mut srv, fb_strip_id(mut c, 'Vazgeç'))
	assert e.confirm == .idle && !e.should_close(), 'Vazgec seridi kapatir'
	e.request_close()
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fb_click_id(mut c, mut e, mut srv, fb_strip_id(mut c, 'Kaydet'))
	assert e.should_close(), 'Kaydet kaydedip kapatir'
	assert os.exists(path)
}

fn test_close_clean_closes_at_once() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	e.request_close()
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert e.should_close(), 'temiz degisiklikte hemen kapanir'
}

fn test_save_error_shows_status() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fb_spawn(mut srv)
	assert !e.save_to(mut srv, 'C:/vcore_no_such_dir_m4c9/x.vscene')
	assert e.flash_text().len > 0, 'hata durum cubugunda gorunur'
	assert e.saved_count != srv.change_count(), 'basarisiz kayit kirli kalir'
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1, time_ms: 3999 })
	assert e.flash_text().len > 0, '4 sn dolmadan gorunur'
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1, time_ms: 4001 })
	assert e.flash_text() == '', '4 sn sonra kaybolur'
}

fn test_poll_close_clean_closes_at_once() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	e.request_close()
	e.poll_close(mut srv)
	assert e.should_close(), 'kucultulmus temiz pencere hemen kapanir'
}

fn test_poll_close_dirty_keeps_request_pending() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fb_spawn(mut srv)
	e.request_close()
	e.poll_close(mut srv)
	assert !e.should_close(), 'kirli pencere kare cizilmeden kapanmaz'
	assert e.confirm_pending(), 'serit bekleyen istek olarak kalir'
	assert e.confirm == .close
}

fn test_esc_closes_field_and_cancels_confirm() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	edt_click(mut c, mut e, mut srv, 'Kaydet')
	assert e.file_field == .save
	edt_frame(mut c, mut e, mut srv, edt_key(.escape))
	assert e.file_field == .idle, 'Esc yol alanini kapatir'
	fb_spawn(mut srv)
	e.request_close()
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert e.confirm == .close
	edt_frame(mut c, mut e, mut srv, edt_key(.escape))
	assert e.confirm == .idle && !e.should_close(), 'Esc bekleyen istegi iptal eder'
}

fn test_strip_save_failure_keeps_window_open() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fb_spawn(mut srv)
	e.path.set('C:/vcore_no_such_dir_m4c9/x.vscene')
	e.request_close()
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert e.confirm == .close
	fb_click_id(mut c, mut e, mut srv, fb_strip_id(mut c, 'Kaydet'))
	assert !e.should_close(), 'kayit basarisizsa pencere acik kalir'
	assert e.confirm == .close, 'serit acik kalir'
	assert e.flash_text().len > 0, 'hata gorunur'
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert e.flash_text().len > 0, 'hata durum cubugunda kare boyunca gorunur'
}
