module editor

import ecs
import protocol
import sim
import ui

// Sahne görünümü testleri: gerçek Server + Context; sanal fare/klavye kareleri (GL yok).
fn sv_server() protocol.Server {
	return protocol.Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

fn sv_frame(mut c ui.Context, mut e Editor, mut srv protocol.Server, inp ui.Input) EditorFrame {
	c.begin(inp, 1440, 900, 1.0)
	fr := e.frame(mut c, mut srv)
	c.end()
	return fr
}

// Transform + Sprite'lı varlık; kimlik yanıttan okunur.
fn sv_spawn(mut srv protocol.Server, x f32, y f32, size f32) u64 {
	line := '{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":${x},"y":${y}},"Sprite":{"size":${size}}}}}'
	resp := srv.handle(line) or { panic('yanit yok') }
	id := protocol.response_entity(resp) or { panic('varlik kimligi yok: ${resp}') }
	return u64(id)
}

fn sv_sel(e &Editor) u64 {
	id := e.sv.sel or { return 0 }
	return u64(id)
}

fn sv_x(srv &protocol.Server, id u64) f32 {
	tx := srv.registry().component(ecs.transform_id) or { panic('Transform yok') }
	fx := tx.field_index('x') or { panic('x yok') }
	st := srv.world().store(ecs.transform_id)
	row := st.row_of(ecs.EntityID(id).index()) or { panic('satir yok') }
	return unsafe { st.column_f32(fx)[row] }
}

// Boşta iki kare: sahne dikdörtgeni bir önceki karenin düzeninden okunur.
fn sv_warm(mut c ui.Context, mut e Editor, mut srv protocol.Server) ui.Rect {
	sv_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fr := sv_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	return fr.scene
}

// Fare üzerine gelir (bir kare), basar (bir kare).
fn sv_press(mut c ui.Context, mut e Editor, mut srv protocol.Server, x f32, y f32, space bool) {
	sv_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: x, mouse_y: y, space: space })
	mut down := ui.Input{ mouse_x: x, mouse_y: y, space: space }
	down.down[0] = true
	down.pressed[0] = true
	sv_frame(mut c, mut e, mut srv, down)
}

// Basılı fare ile hareket karesi (isteğe bağlı Esc).
fn sv_drag(mut c ui.Context, mut e Editor, mut srv protocol.Server, x f32, y f32, esc bool) {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	inp.down[0] = true
	if esc {
		inp.keys[0] = .escape
		inp.key_count = 1
	}
	sv_frame(mut c, mut e, mut srv, inp)
}

fn sv_release(mut c ui.Context, mut e Editor, mut srv protocol.Server, x f32, y f32) {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	inp.released[0] = true
	sv_frame(mut c, mut e, mut srv, inp)
}

// Tıklama: üzerine gel, bas, bırak.
fn sv_click(mut c ui.Context, mut e Editor, mut srv protocol.Server, x f32, y f32) {
	sv_press(mut c, mut e, mut srv, x, y, false)
	sv_release(mut c, mut e, mut srv, x, y)
}

// Dünya noktasının ekran konumu, kamera ve sahne dikdörtgeninden.
fn sv_at(e &Editor, r ui.Rect, x f32, y f32) (f32, f32) {
	return e.cam.world_to_screen(r, x, y)
}

fn test_pick_topmost_sprite() {
	mut srv := sv_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	_ = sv_spawn(mut srv, 0, 0, 4)
	top := sv_spawn(mut srv, 0, 0, 4)
	r := sv_warm(mut c, mut e, mut srv)
	sx, sy := sv_at(&e, r, 0, 0)
	sv_click(mut c, mut e, mut srv, sx, sy)
	assert sv_sel(&e) == top, 'en üstte çizilen (satır sırasında sonuncu) seçilmeli: ${sv_sel(&e)}'
}

fn test_click_empty_clears_selection() {
	mut srv := sv_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := sv_spawn(mut srv, 0, 0, 4)
	r := sv_warm(mut c, mut e, mut srv)
	sx, sy := sv_at(&e, r, 0, 0)
	sv_click(mut c, mut e, mut srv, sx, sy)
	assert sv_sel(&e) == id
	ex, ey := sv_at(&e, r, 5, 5)
	sv_click(mut c, mut e, mut srv, ex, ey)
	assert sv_sel(&e) == 0, 'boşa tık seçimi temizler'
}

// Gizmo x kolu basılı sürüklenir: tek geri alma adımı, değer başlangıç + dünya deltası.
fn test_gizmo_drag_is_one_undo_step() {
	mut srv := sv_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := sv_spawn(mut srv, 0, 0, 4)
	r := sv_warm(mut c, mut e, mut srv)
	sx, sy := sv_at(&e, r, 0, 0)
	sv_click(mut c, mut e, mut srv, sx, sy)
	assert sv_sel(&e) == id

	k := r.h / e.cam.view_h
	gx := sx + 30
	gy := sy
	u0, _ := srv.history_lens()
	sv_press(mut c, mut e, mut srv, gx, gy, false)
	sv_drag(mut c, mut e, mut srv, gx + 20, gy, false)
	sv_drag(mut c, mut e, mut srv, gx + 40, gy, false)
	sv_release(mut c, mut e, mut srv, gx + 40, gy)
	want := 40 / k
	assert sv_close(sv_x(&srv, id), want), 'x = başlangıç + dünya deltası: ${sv_x(&srv, id)} ≠ ${want}'
	u1, _ := srv.history_lens()
	assert u1 == u0 + 1, 'sürükleme tek geri alma adımı: ${u0} → ${u1}'
	_ = srv.history_undo() or { panic(err) }
	assert sv_close(sv_x(&srv, id), 0), 'tek geri alma başlangıca döndürür: ${sv_x(&srv, id)}'
}

// Sürüklerken Esc: değer başlangıca döner, geri al yığını değişmez.
fn test_gizmo_drag_escape_cancels() {
	mut srv := sv_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := sv_spawn(mut srv, 0, 0, 4)
	r := sv_warm(mut c, mut e, mut srv)
	sx, sy := sv_at(&e, r, 0, 0)
	sv_click(mut c, mut e, mut srv, sx, sy)

	u0, r0 := srv.history_lens()
	gx := sx + 30
	gy := sy
	sv_press(mut c, mut e, mut srv, gx, gy, false)
	sv_drag(mut c, mut e, mut srv, gx + 30, gy, false)
	assert sv_x(&srv, id) > 0, 'sürükleme sırasında değer değişir'
	sv_drag(mut c, mut e, mut srv, gx + 50, gy, true)
	assert sv_close(sv_x(&srv, id), 0), 'Esc değeri başlangıca döndürür: ${sv_x(&srv, id)}'
	sv_release(mut c, mut e, mut srv, gx + 50, gy)
	assert sv_close(sv_x(&srv, id), 0), 'bırakma iptalden sonra değeri değiştirmez'
	u1, r1 := srv.history_lens()
	assert u1 == u0 && r1 == r0, 'iptal yığınları değiştirmez: ${u0},${r0} → ${u1},${r1}'
}

// Boşluk basılıyken sol sürükleme pan'dir: kamera kayar, varlık seçilmez.
fn test_space_drag_pans_not_selects() {
	mut srv := sv_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := sv_spawn(mut srv, 0, 0, 4)
	r := sv_warm(mut c, mut e, mut srv)
	sx, sy := sv_at(&e, r, 0, 0)
	k := r.h / e.cam.view_h
	sv_press(mut c, mut e, mut srv, sx, sy, true)
	mut mv := ui.Input{ mouse_x: sx + 40, mouse_y: sy, space: true }
	mv.down[0] = true
	sv_frame(mut c, mut e, mut srv, mv)
	sv_release(mut c, mut e, mut srv, sx + 40, sy)
	assert sv_sel(&e) == 0, 'boşluk + sürükleme seçim yapmaz'
	assert sv_close(e.cam.cx, -40 / k), 'kamera fareyle ters yönde kayar: ${e.cam.cx}'
	assert sv_close(sv_x(&srv, id), 0), 'pan varlığı taşımaz'
}

// Sahne sağ kenarına yakın varlık: gizmo kolu sahne dışına taşar ama görünen kısım sahne içinde kalır.
fn test_overlays_stay_in_scene_rect() {
	mut srv := sv_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	r := sv_warm(mut c, mut e, mut srv)
	k := r.h / e.cam.view_h
	// Kökeni sağ kenardan 20 px içeride; 64 px'lik kol kenarın dışına çıkar.
	id := sv_spawn(mut srv, f32((r.w / 2 - 20) / k), 0, 4)
	sv_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	sx, sy := sv_at(&e, r, f32((r.w / 2 - 20) / k), 0)
	sv_click(mut c, mut e, mut srv, sx, sy)
	assert sv_sel(&e) == id
	sv_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	sel_t := c.last_rect('sel_t') or { panic('seçim çerçevesi çizilmedi') }
	assert sel_t.x >= r.x && sel_t.x + sel_t.w <= r.x + r.w + 1e-3
	for label in ['sel_t', 'sel_b', 'sel_l', 'sel_r', 'gz_x', 'gz_y', 'gz_c'] {
		if rr := c.last_rect(label) {
			assert rr.x >= r.x - 1e-3 && rr.x + rr.w <= r.x + r.w + 1e-3, '${label} yatay taşma: ${rr}'
			assert rr.y >= r.y - 1e-3 && rr.y + rr.h <= r.y + r.h + 1e-3, '${label} dikey taşma: ${rr}'
		}
	}
}

fn sv_close(a f32, b f32) bool {
	d := if a > b { a - b } else { b - a }
	return d < 1e-3
}

// Küçük geçmiş alanı: 4 komutluk hazırlama alanı; uzun sürüklemede grup taşar.
fn sv_server_small() protocol.Server {
	return protocol.Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024, history_capacity: 4, history_groups: 8 }) or {
		panic(err)
	}
}

// Taşan grupta Esc iptali reddedilir: değer yine başlangıçta kalmalı (sessizce commit edilmez), bildirim görünmeli.
fn test_esc_overflow_restores_value_and_notes() {
	mut srv := sv_server_small()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := sv_spawn(mut srv, 0, 0, 4)
	r := sv_warm(mut c, mut e, mut srv)
	sx, sy := sv_at(&e, r, 0, 0)
	sv_click(mut c, mut e, mut srv, sx, sy)
	assert sv_sel(&e) == id

	u0, r0 := srv.history_lens()
	gx := sx + 30
	gy := sy
	sv_press(mut c, mut e, mut srv, gx, gy, false)
	for k in 1 .. 13 {
		sv_drag(mut c, mut e, mut srv, gx + f32(k) * 5, gy, false)
	}
	assert sv_x(&srv, id) > 0, 'taşmadan önce değer değişmiş olmalı'
	sv_drag(mut c, mut e, mut srv, gx + 70, gy, true)
	assert sv_close(sv_x(&srv, id), 0), 'Esc taşmada da değeri başlangıca yazar: ${sv_x(&srv, id)}'
	sv_release(mut c, mut e, mut srv, gx + 70, gy)
	assert sv_close(sv_x(&srv, id), 0), 'bırakma sonrası değer başlangıçta kalır'
	u1, r1 := srv.history_lens()
	assert u1 == u0 && r1 == r0, 'taşan grup yığına girmez: ${u0},${r0} → ${u1},${r1}'
	assert e.note_text().contains('geri alma geçmişi doldu'), 'bildirim: ${e.note_text()}'
}

// Seçili varlık: orta kare 10 px, uç tutamakları 8 px, eksen çizgisi 2 px; seçim çerçevesinin dış hale kenarları var.
fn test_gizmo_handles_drawn() {
	mut srv := sv_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	r := sv_warm(mut c, mut e, mut srv)
	id := sv_spawn(mut srv, 0, 0, 4)
	sx, sy := sv_at(&e, r, 0, 0)
	sv_click(mut c, mut e, mut srv, sx, sy)
	assert sv_sel(&e) == id
	sv_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	mid := c.last_rect('gz_c') or { panic('orta tutamaç çizilmedi') }
	assert mid.w == 10 && mid.h == 10, 'orta kare 10 px: ${mid}'
	xt := c.last_rect('gz_x_tip') or { panic('X uç tutamacı yok') }
	assert xt.w == 8 && xt.h == 8, 'uc 8 px: ${xt}'
	yt := c.last_rect('gz_y_tip') or { panic('Y uç tutamacı yok') }
	assert yt.w == 8 && yt.h == 8, 'uc 8 px: ${yt}'
	xv := c.last_rect('gz_x_vis') or { panic('X ekseni yok') }
	assert xv.h == 2, 'eksen cizgisi 2 px: ${xv}'
	yv := c.last_rect('gz_y_vis') or { panic('Y ekseni yok') }
	assert yv.w == 2, 'eksen cizgisi 2 px: ${yv}'
	halo := c.last_rect('sel_h_t') or { panic('seçim hale kenarı yok') }
	sel := c.last_rect('sel_t') or { panic('seçim çerçevesi yok') }
	assert halo.y == sel.y + 1, 'hale accent halkasinin 1 px icinde: ${halo} ${sel}'
}
