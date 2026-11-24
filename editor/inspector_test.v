module editor

import ecs
import protocol
import sim
import ui

// Inspektör testleri: gerçek Server + Context, sentetik fare/klavye kareleri (GL yok).
fn ins_server() protocol.Server {
	return protocol.Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

fn ins_frame(mut c ui.Context, mut e Editor, mut srv protocol.Server, inp ui.Input) {
	c.begin(inp, 1440, 900, 1.0)
	e.frame(mut c, mut srv)
	c.end()
}

fn ins_hover(x f32, y f32) ui.Input {
	return ui.Input{ mouse_x: x, mouse_y: y }
}

fn ins_down(x f32, y f32, pressed bool) ui.Input {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	inp.down[0] = true
	inp.pressed[0] = pressed
	return inp
}

fn ins_up(x f32, y f32) ui.Input {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	inp.released[0] = true
	return inp
}

fn ins_key(x f32, y f32, k ui.Key) ui.Input {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	inp.keys[0] = k
	inp.key_count = 1
	return inp
}

fn ins_text(x f32, y f32, s string) ui.Input {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	for i, ch in s {
		inp.chars[i] = u32(ch)
	}
	inp.char_count = s.len
	return inp
}

// Üzerine gel, bas, bırak (üç kare): sayı alanında yazma kipine girer.
fn ins_click(mut c ui.Context, mut e Editor, mut srv protocol.Server, x f32, y f32) {
	ins_frame(mut c, mut e, mut srv, ins_hover(x, y))
	ins_frame(mut c, mut e, mut srv, ins_down(x, y, true))
	ins_frame(mut c, mut e, mut srv, ins_up(x, y))
}

// Sürükleme: basılı fare x0'dan x1'e iki adımda (eşik aşılır), sonra bırakılır.
fn ins_drag(mut c ui.Context, mut e Editor, mut srv protocol.Server, x0 f32, y f32, x1 f32) {
	ins_frame(mut c, mut e, mut srv, ins_hover(x0, y))
	ins_frame(mut c, mut e, mut srv, ins_down(x0, y, true))
	mid := x0 + (x1 - x0) / 2
	ins_frame(mut c, mut e, mut srv, ins_down(mid, y, false))
	ins_frame(mut c, mut e, mut srv, ins_down(x1, y, false))
	ins_frame(mut c, mut e, mut srv, ins_up(x1, y))
}

// Transform x/y + Sprite size; Sprite r=0 (aralık [0, 1]). Varlık seçili, iki kare düzen için.
fn ins_setup(mut c ui.Context, mut e Editor, mut srv protocol.Server) u64 {
	resp := srv.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1,"y":2},"Sprite":{"size":4}}}}') or {
		panic('yanit yok')
	}
	id := u64(protocol.response_entity(resp) or { panic('kimlik yok') })
	e.sv.sel = ecs.EntityID(id)
	ins_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	ins_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	return id
}

fn ins_field_index(srv &protocol.Server, comp u16, field string) u16 {
	cs := srv.registry().component(comp) or { panic('bileşen yok') }
	return cs.field_index(field) or { panic('alan yok: ${field}') }
}

fn ins_field_rect(e &Editor, c &ui.Context, srv &protocol.Server, comp u16, field string) ui.Rect {
	fi := ins_field_index(srv, comp, field)
	return e.inspector_rect(c, hit_field, comp, fi) or { panic('alan kutusu yok: ${field}') }
}

fn ins_field_value(srv &protocol.Server, id u64, comp u16, field string) f32 {
	fi := ins_field_index(srv, comp, field)
	return read_f32(srv.world(), ecs.EntityID(id), comp, fi) or { panic('alan okunamadı') }
}

fn ins_undo_count(srv &protocol.Server) int {
	u, _ := srv.history_lens()
	return u
}

fn test_inspector_shows_components_and_fields() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	ins_setup(mut c, mut e, mut srv)
	for f in ['x', 'y', 'prev_x', 'prev_y'] {
		r := ins_field_rect(&e, &c, &srv, ecs.transform_id, f)
		assert r.h > 0
	}
	for f in ['size', 'r', 'g', 'b'] {
		r := ins_field_rect(&e, &c, &srv, ecs.sprite_id, f)
		assert r.h > 0
	}
	assert e.inspector_rect(&c, hit_section, ecs.transform_id, 0) != none
	assert e.inspector_rect(&c, hit_section, ecs.sprite_id, 0) != none
}

fn test_field_drag_is_one_undo_step() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	r := ins_field_rect(&e, &c, &srv, ecs.transform_id, 'x')
	undo0 := ins_undo_count(&srv)
	ins_drag(mut c, mut e, mut srv, r.x + r.w / 2, r.y + r.h / 2, r.x + r.w / 2 + 40)
	x := ins_field_value(&srv, id, ecs.transform_id, 'x')
	assert x > 1
	assert ins_undo_count(&srv) == undo0 + 1
	srv.history_undo() or { panic(err) }
	assert ins_field_value(&srv, id, ecs.transform_id, 'x') == 1
}

fn test_field_drag_cancel_restores() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	r := ins_field_rect(&e, &c, &srv, ecs.transform_id, 'x')
	x0 := r.x + r.w / 2
	y0 := r.y + r.h / 2
	undo0 := ins_undo_count(&srv)
	ins_frame(mut c, mut e, mut srv, ins_hover(x0, y0))
	ins_frame(mut c, mut e, mut srv, ins_down(x0, y0, true))
	ins_frame(mut c, mut e, mut srv, ins_down(x0 + 40, y0, false))
	assert ins_field_value(&srv, id, ecs.transform_id, 'x') > 1
	// Esc sürüklemeyi basılı fareyle iptal eder (fare bırakılmadan).
	mut esc := ins_down(x0 + 40, y0, false)
	esc.keys[0] = .escape
	esc.key_count = 1
	ins_frame(mut c, mut e, mut srv, esc)
	assert ins_field_value(&srv, id, ecs.transform_id, 'x') == 1
	assert !e.ins.grouping
	ins_frame(mut c, mut e, mut srv, ins_up(x0 + 40, y0))
	assert ins_field_value(&srv, id, ecs.transform_id, 'x') == 1
	assert ins_undo_count(&srv) == undo0
	assert !e.ins.grouping
}

fn test_typed_commit_sets_value() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	r := ins_field_rect(&e, &c, &srv, ecs.transform_id, 'x')
	x := r.x + r.w / 2
	y := r.y + r.h / 2
	undo0 := ins_undo_count(&srv)
	ins_click(mut c, mut e, mut srv, x, y)
	ins_frame(mut c, mut e, mut srv, ins_text(x, y, '2.5'))
	ins_frame(mut c, mut e, mut srv, ins_key(x, y, .enter))
	assert ins_field_value(&srv, id, ecs.transform_id, 'x') == 2.5
	assert ins_undo_count(&srv) == undo0 + 1
}

fn test_out_of_range_shows_error_and_sends_nothing() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	r := ins_field_rect(&e, &c, &srv, ecs.sprite_id, 'r')
	x := r.x + r.w / 2
	y := r.y + r.h / 2
	undo0 := ins_undo_count(&srv)
	ins_click(mut c, mut e, mut srv, x, y)
	ins_frame(mut c, mut e, mut srv, ins_text(x, y, '2'))
	ins_frame(mut c, mut e, mut srv, ins_key(x, y, .enter))
	ri := ins_field_index(&srv, ecs.sprite_id, 'r')
	assert e.ins.err_text(ecs.EntityID(id), ecs.sprite_id, ri) == 'Sprite.r must be in [0, 1]'
	assert ins_field_value(&srv, id, ecs.sprite_id, 'r') == 0
	assert ins_undo_count(&srv) == undo0
	// Geçerli bir yazılı değer hatayı temizler.
	// Reddedilen değer düzenlemede kalır; Esc düzenlemeyi bırakır ve hatayı temizler.
	ins_frame(mut c, mut e, mut srv, ins_key(x, y, .escape))
	assert e.ins.err_text(ecs.EntityID(id), ecs.sprite_id, ri) == ''
	assert ins_field_value(&srv, id, ecs.sprite_id, 'r') == 0
	// Geçerli bir yazılı değer hatayı temizler.
	ins_click(mut c, mut e, mut srv, x, y)
	ins_frame(mut c, mut e, mut srv, ins_text(x, y, '0.5'))
	ins_frame(mut c, mut e, mut srv, ins_key(x, y, .enter))
	assert ins_field_value(&srv, id, ecs.sprite_id, 'r') == 0.5
	assert e.ins.err_text(ecs.EntityID(id), ecs.sprite_id, ri) == ''
}

fn test_drag_clamps_to_schema_range() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	r := ins_field_rect(&e, &c, &srv, ecs.sprite_id, 'r')
	ins_drag(mut c, mut e, mut srv, r.x + r.w / 2, r.y + r.h / 2, r.x + r.w / 2 + 5000)
	assert ins_field_value(&srv, id, ecs.sprite_id, 'r') == 1
}

fn test_readonly_prev_fields_not_editable() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	before := ins_field_value(&srv, id, ecs.transform_id, 'prev_x')
	r := ins_field_rect(&e, &c, &srv, ecs.transform_id, 'prev_x')
	undo0 := ins_undo_count(&srv)
	ins_drag(mut c, mut e, mut srv, r.x + r.w / 2, r.y + r.h / 2, r.x + r.w / 2 + 40)
	assert ins_field_value(&srv, id, ecs.transform_id, 'prev_x') == before
	assert ins_undo_count(&srv) == undo0
	assert !e.ins.grouping
}

fn test_remove_component_icon() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	h := e.inspector_rect(&c, hit_section, ecs.sprite_id, 0) or { panic('Sprite bölümü yok') }
	// Çöp ikonu başlığın sağ ucunda, row_h karelik düğme.
	x := h.x + h.w - ui.row_h / 2
	y := h.y + h.h / 2
	ins_click(mut c, mut e, mut srv, x, y)
	ins_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert !srv.world().has(ecs.EntityID(id), ecs.sprite_id)
	assert srv.world().has(ecs.EntityID(id), ecs.transform_id)
}

fn test_add_component_menu() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	// İlk eksik bileşen (kayıt sırası): menüde ilk öğe.
	reg := srv.registry()
	mut missing := ecs.transform_id
	for comp in u16(0) .. reg.count() {
		if !srv.world().has(ecs.EntityID(id), comp) {
			missing = comp
			break
		}
	}
	assert !srv.world().has(ecs.EntityID(id), missing)
	btn := e.inspector_rect(&c, hit_add, 0, 0) or { panic('ekle düğmesi yok') }
	x := btn.x + btn.w / 2
	y := btn.y + btn.h / 2
	ins_click(mut c, mut e, mut srv, x, y)
	// Menü açık; öğeler bir kare çizilince klavye gezintisi çalışır: aşağı, Enter.
	ins_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	ins_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	ins_frame(mut c, mut e, mut srv, ins_key(-1, -1, .down))
	ins_frame(mut c, mut e, mut srv, ins_key(-1, -1, .enter))
	ins_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert srv.world().has(ecs.EntityID(id), missing)
}

fn test_external_change_updates_field_when_not_editing() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	line := '{"jsonrpc":"2.0","id":1,"method":"component.set","params":{"entity":${id},"component":"Transform","field":"x","value":7}}'
	_ = srv.handle(line) or { panic('yanit yok') }
	ins_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert ins_field_value(&srv, id, ecs.transform_id, 'x') == 7
	// Gösterilen değer dünyadan gelir: sürükleme 7'den başlar, 1'den değil.
	r := ins_field_rect(&e, &c, &srv, ecs.transform_id, 'x')
	ins_drag(mut c, mut e, mut srv, r.x + r.w / 2, r.y + r.h / 2, r.x + r.w / 2 + 40)
	assert ins_field_value(&srv, id, ecs.transform_id, 'x') > 7
}

// Uzun sürüklemede gösterilen değer (her kare) aralık dışına çıkmaz; dünya değeri de kıstırılır.
fn test_displayed_value_stays_in_range_during_long_drag() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	r := ins_field_rect(&e, &c, &srv, ecs.sprite_id, 'r')
	x0 := r.x + r.w / 2
	y := r.y + r.h / 2
	ins_frame(mut c, mut e, mut srv, ins_hover(x0, y))
	ins_frame(mut c, mut e, mut srv, ins_down(x0, y, true))
	mut x := x0
	for _ in 0 .. 40 {
		x += 15
		ins_frame(mut c, mut e, mut srv, ins_down(x, y, false))
		shown := e.inspector_shown(ecs.sprite_id, ins_field_index(&srv, ecs.sprite_id, 'r')) or { panic('gösterilen değer yok') }
		assert shown >= 0 && shown <= 1, 'gösterilen ${shown}'
		assert ins_field_value(&srv, id, ecs.sprite_id, 'r') <= 1
	}
	assert e.inspector_shown(ecs.sprite_id, ins_field_index(&srv, ecs.sprite_id, 'r')) or { panic('yok') } == 1
	ins_frame(mut c, mut e, mut srv, ins_up(x, y))
	assert ins_field_value(&srv, id, ecs.sprite_id, 'r') == 1
}

// Aralık hatası: alan düzenleme modunda kalır, yazılan metin korunur, hata görünür; Esc düzenlemeyi ve hatayı bırakır.
fn test_rejected_value_stays_in_edit() {
	mut srv := ins_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := ins_setup(mut c, mut e, mut srv)
	r := ins_field_rect(&e, &c, &srv, ecs.sprite_id, 'r')
	x := r.x + r.w / 2
	y := r.y + r.h / 2
	ri := ins_field_index(&srv, ecs.sprite_id, 'r')
	ins_click(mut c, mut e, mut srv, x, y)
	ins_frame(mut c, mut e, mut srv, ins_text(x, y, '2'))
	ins_frame(mut c, mut e, mut srv, ins_key(x, y, .enter))
	ins_frame(mut c, mut e, mut srv, ins_hover(x, y))
	assert c.keyboard_captured(), 'reddedilen değerde alan düzenlemede kalmalı'
	assert e.ins.err_text(ecs.EntityID(id), ecs.sprite_id, ri) == 'Sprite.r must be in [0, 1]'
	assert ins_field_value(&srv, id, ecs.sprite_id, 'r') == 0
	ins_frame(mut c, mut e, mut srv, ins_key(x, y, .escape))
	assert !c.keyboard_captured(), 'Esc duzenlemeyi birakmali'
	assert e.ins.err_text(ecs.EntityID(id), ecs.sprite_id, ri) == '', 'Esc hatayi temizlemeli'
	assert ins_field_value(&srv, id, ecs.sprite_id, 'r') == 0
}
