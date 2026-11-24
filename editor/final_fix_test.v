module editor

import ecs
import os
import protocol
import sim
import ui

// M4c son düzeltme turu (I2, R12, M1, M2): gerçek Server + Context, sentetik kareler, GL yok.

fn ff_server() protocol.Server {
	return protocol.Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

fn ff_frame(mut c ui.Context, mut e Editor, mut srv protocol.Server, inp ui.Input) EditorFrame {
	c.begin(inp, 1440, 900, 1.0)
	fr := e.frame(mut c, mut srv)
	c.end()
	return fr
}

fn ff_idle(mut c ui.Context, mut e Editor, mut srv protocol.Server) {
	ff_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
}

fn ff_key(k ui.Key, ctrl bool) ui.Input {
	mut inp := ui.Input{ mouse_x: -1, mouse_y: -1 }
	inp.keys[0] = k
	inp.key_count = 1
	inp.ctrl = ctrl
	return inp
}

// Düğmeye tıklama: üzerine gel, bas, bırak (üç kare). Konum bir önceki karenin düzeninden okunur.
fn ff_click_rect(mut c ui.Context, mut e Editor, mut srv protocol.Server, r ui.Rect) {
	x := r.x + r.w / 2
	y := r.y + r.h / 2
	ff_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: x, mouse_y: y })
	mut down := ui.Input{ mouse_x: x, mouse_y: y }
	down.down[0] = true
	down.pressed[0] = true
	ff_frame(mut c, mut e, mut srv, down)
	mut up := ui.Input{ mouse_x: x, mouse_y: y }
	up.released[0] = true
	ff_frame(mut c, mut e, mut srv, up)
}

// Geçici yol: varsa silinmiş bir .vscene adı; ileri eğik çizgili.
fn ff_tmp(tag string) string {
	dir := os.temp_dir().replace('\\', '/')
	path := '${dir}/vcore_m4c_fix_${tag}_${os.getpid()}.vscene'
	os.rm(path) or {}
	return path
}

// Tek varlıklı (Transform + Sprite) sahne dosyası: yükleme testleri için.
fn ff_scene_file(tag string) string {
	path := ff_tmp(tag)
	mut writer := ff_server()
	writer.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":5,"y":5},"Sprite":{"size":4}}}}') or {
		panic('yanit yok')
	}
	writer.handle('{"jsonrpc":"2.0","id":2,"method":"scene.save","params":{"path":"${path}"}}') or { panic('yanit yok') }
	writer.close()
	return path
}

fn ff_spawn(mut srv protocol.Server) ecs.EntityID {
	resp := srv.handle('{"jsonrpc":"2.0","id":5,"method":"entity.spawn","params":{"components":{"Transform":{"x":1,"y":2},"Sprite":{"size":4}}}}') or {
		panic('yanit yok')
	}
	return protocol.response_entity(resp) or { panic('kimlik yok') }
}

// I2: olmayan dosya boş sahne başlatır: yol korunur, hata yok, kirli değil.
fn test_missing_scene_starts_empty_with_path() {
	path := ff_tmp('missing')
	mut srv := ff_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new(path)
	ff_idle(mut c, mut e, mut srv)
	assert e.load_error() == '', 'olmayan dosyada hata olmamali: ${e.load_error()}'
	assert e.path.str() == path, 'yol korunmali: ${e.path.str()}'
	assert e.file_label() == os.file_name(path), 'ad yoldan gelmeli: ${e.file_label()}'
	assert srv.world().alive_count() == 0, 'bos sahne'
	assert !e.dirty(srv.change_count()), 'yeni bos sahne kirli gorunmemeli'
}

// I2: olmayan yola başlanınca Ctrl+S dosyayı oluşturur.
fn test_ctrl_s_creates_missing_scene_at_path() {
	path := ff_tmp('create')
	mut srv := ff_server()
	defer {
		srv.close()
		os.rm(path) or {}
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new(path)
	ff_idle(mut c, mut e, mut srv)
	assert !os.exists(path), 'basta dosya olmamali'
	ff_frame(mut c, mut e, mut srv, ff_key(.s, true))
	assert os.exists(path), 'Ctrl+S yolda dosyayi olusturmali'
	assert e.load_error() == '', 'hata olmamali: ${e.load_error()}'
}

// R12: başarılı ajan yüklemesi yolu benimser, sahneyi temiz kılar ve not gösterir.
fn test_agent_load_adopts_path_cleans_and_notes() {
	path := ff_scene_file('adopt')
	defer {
		os.rm(path) or {}
	}
	mut srv := ff_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	ff_idle(mut c, mut e, mut srv)
	resp := srv.handle('{"jsonrpc":"2.0","id":3,"method":"scene.load","params":{"path":"${path}"}}') or {
		panic('yanit yok')
	}
	assert protocol.response_ok(resp), resp
	ff_idle(mut c, mut e, mut srv)
	assert e.path.str() == path, 'ajanin yolu benimsenmeli: ${e.path.str()}'
	assert !e.dirty(srv.change_count()), 'yukleme sonrasi sahne temiz olmali'
	assert e.note_text() == 'ajan sahneyi yükledi: ${os.file_name(path)}', 'not: ${e.note_text()}'
}

// M1: açık menü varken Delete seçili varlığı silmez (kısayollar menüye bırakılır).
fn test_open_menu_gates_delete_shortcut() {
	mut srv := ff_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ff_spawn(mut srv)
	e.sv.sel = id
	ff_idle(mut c, mut e, mut srv)
	ff_idle(mut c, mut e, mut srv)
	btn := e.add_component_rect(&c) or { panic('ekle dugmesi yok') }
	ff_click_rect(mut c, mut e, mut srv, btn)
	ff_idle(mut c, mut e, mut srv)
	ff_idle(mut c, mut e, mut srv)
	assert c.menu_open(), 'menu acik olmali'
	ff_frame(mut c, mut e, mut srv, ff_key(.delete, false))
	assert srv.world().is_alive(id), 'menu acikken Delete varligi silmemeli'
}

// M1: menüyü kapatan Esc, yol alanını da kapatmaz.
fn test_menu_escape_does_not_close_path_field() {
	mut srv := ff_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ff_spawn(mut srv)
	e.sv.sel = id
	ff_idle(mut c, mut e, mut srv)
	ff_idle(mut c, mut e, mut srv)
	// Yol alanı açık (Aç düğmesinin kendisi bu testin konusu değil).
	e.show_field(.open)
	ff_idle(mut c, mut e, mut srv)
	assert e.file_field == .open, 'yol alani acik olmali'
	btn := e.add_component_rect(&c) or { panic('ekle dugmesi yok') }
	ff_click_rect(mut c, mut e, mut srv, btn)
	ff_idle(mut c, mut e, mut srv)
	ff_idle(mut c, mut e, mut srv)
	ff_frame(mut c, mut e, mut srv, ff_key(.escape, false))
	assert e.file_field == .open, 'menu Esc i yol alanini kapatmamali'
}

// M2: başarısız editör isteği durum çubuğunda hata olarak görünür (flash).
fn test_failed_editor_request_flashes_error() {
	mut srv := ff_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	ff_idle(mut c, mut e, mut srv)
	ghost := ecs.EntityID(999999)
	e.sv.sel = ghost
	e.set_transform(mut srv, 'x', 2)
	assert e.flash_text() != '', 'component.set hatasi durum cubugunda gorunmeli'
	e.flash_len = 0
	e.comp_request(mut srv, 'component.remove', ghost, 'Sprite')
	assert e.flash_text() != '', 'component.remove hatasi durum cubugunda gorunmeli'
}

// M2: başarılı istek başka bir bildirimi silmez.
fn test_successful_request_keeps_unrelated_note() {
	mut srv := ff_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	ff_idle(mut c, mut e, mut srv)
	e.set_note('ilgisiz bildirim')
	e.spawn_at_camera(mut srv)
	assert e.note_text() == 'ilgisiz bildirim', 'basarili istek bildirimi silmemeli: ${e.note_text()}'
}

// M2 (a): yükleme hatası, çözümleme hatasının üzerine yazılmaz.
fn test_load_error_keeps_field_error() {
	mut srv := ff_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	ff_idle(mut c, mut e, mut srv)
	e.set_error('sahne alanları çözülemedi: Transform bileşeni kayıtlı değil')
	e.set_load_error('could not read file')
	assert e.load_error().contains('alanları'), 'çözümleme hatası korunmalı: ${e.load_error()}'
}
