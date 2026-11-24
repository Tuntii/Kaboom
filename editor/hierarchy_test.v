module editor

import ecs
import protocol
import sim
import ui

// Hiyerarşi testleri: gerçek Server + Context; sanal fare/klavye kareleri (GL yok).
fn hier_server() protocol.Server {
	return protocol.Server.new(sim.Config{ capacity: 2048, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

fn hier_handle(mut srv protocol.Server, line string) string {
	return srv.handle(line) or { panic('yanit yok') }
}

fn hier_field(srv &protocol.Server, comp u16, id u64, name string) f32 {
	sc := srv.registry().component(comp) or { panic('bileşen yok') }
	fi := sc.field_index(name) or { panic('alan yok') }
	st := srv.world().store(comp)
	row := st.row_of(ecs.EntityID(id).index()) or { panic('satır yok') }
	return unsafe { st.column_f32(fi)[row] }
}

fn test_hierarchy_lists_live_entities() {
	mut srv := hier_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	mut ids := []u64{}
	for _ in 0 .. 6 {
		ids << hier_spawn(mut srv, 0, 0, 1)
	}
	// Delikli dünya: 1 ve 3 silinir; 2 Body alır (rozet T B S).
	hier_handle(mut srv, '{"jsonrpc":"2.0","id":1,"method":"entity.despawn","params":{"entity":${ids[1]}}}')
	hier_handle(mut srv, '{"jsonrpc":"2.0","id":1,"method":"entity.despawn","params":{"entity":${ids[3]}}}')
	hier_handle(mut srv, '{"jsonrpc":"2.0","id":1,"method":"component.add","params":{"entity":${ids[2]},"component":"Body"}}')
	hier_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert e.hier.nrows == 4
	assert e.hier.label(0) == '#0'
	assert e.hier.label(1) == '#2'
	assert e.hier.label(2) == '#4'
	assert e.hier.label(3) == '#5'
	assert e.hier.badge(0) == 'T S'
	assert e.hier.badge(1) == 'T B S'
}

fn test_plus_spawns_at_camera_and_selects() {
	mut srv := hier_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	e.cam.cx = 5
	e.cam.cy = -3
	e.cam.view_h = 60
	hier_warm(mut c, mut e, mut srv)
	// Ekle düğmesi: başlık satırının sağ ucunda (sol panel genişliği eksi dolgu); başlık, araç çubuğunun (40) altında, 40..80.
	hier_click(mut c, mut e, mut srv, e.left_w - ui.space_3 - ui.control_h / 2, ui.toolbar_h + ui.toolbar_h / 2)
	assert srv.world().alive_count() == 1
	has, id := e.sv.selected()
	assert has
	assert e.hier.nrows == 1
	assert e.hier.ids[0] == id
	raw := u64(id)
	assert hier_field(&srv, ecs.transform_id, raw, 'x') == f32(5)
	assert hier_field(&srv, ecs.transform_id, raw, 'y') == f32(-3)
	assert hier_field(&srv, ecs.sprite_id, raw, 'size') == f32(3)
	assert hier_field(&srv, ecs.sprite_id, raw, 'r') == f32(0.8)
	assert hier_field(&srv, ecs.sprite_id, raw, 'g') == f32(0.8)
	assert hier_field(&srv, ecs.sprite_id, raw, 'b') == f32(0.85)
}

fn test_delete_despawns_selected() {
	mut srv := hier_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := hier_spawn(mut srv, 0, 0, 1)
	hier_warm(mut c, mut e, mut srv)
	e.sv.sel = ecs.EntityID(id)
	mut inp := ui.Input{ mouse_x: -1, mouse_y: -1 }
	inp.keys[0] = .delete
	inp.key_count = 1
	hier_frame(mut c, mut e, mut srv, inp)
	assert !srv.world().is_alive(ecs.EntityID(id))
	assert e.sv.sel == none
}

fn test_agent_despawn_clears_selection() {
	mut srv := hier_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := hier_spawn(mut srv, 0, 0, 1)
	hier_warm(mut c, mut e, mut srv)
	e.sv.sel = ecs.EntityID(id)
	hier_handle(mut srv, '{"jsonrpc":"2.0","id":1,"method":"entity.despawn","params":{"entity":${id}}}')
	hier_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert e.sv.sel == none
	assert e.hier.nrows == 0
}

fn test_selecting_in_scene_reveals_row() {
	mut srv := hier_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	for _ in 0 .. 59 {
		hier_spawn(mut srv, 1000, 1000, 4)
	}
	last := hier_spawn(mut srv, 0, 0, 4)
	scene := hier_warm(mut c, mut e, mut srv)
	sx, sy := e.cam.world_to_screen(scene, 0, 0)
	hier_click(mut c, mut e, mut srv, sx, sy)
	assert hier_sel(&e) == last
	hier_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	// Başlangıçta görünür pencere ~33 satır (59. satır dışarıda): satır ancak reveal ile listeye girer.
	assert e.hier.first <= 59
	assert 59 < e.hier.first + e.hier.nrows
}

fn hier_spawn(mut srv protocol.Server, x f32, y f32, size f32) u64 {
	line := '{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":${x},"y":${y}},"Sprite":{"size":${size}}}}}'
	resp := srv.handle(line) or { panic('yanit yok') }
	id := protocol.response_entity(resp) or { panic('varlik kimligi yok') }
	return u64(id)
}

fn hier_sel(e &Editor) u64 {
	id := e.sv.sel or { return 0 }
	return u64(id)
}

fn hier_frame(mut c ui.Context, mut e Editor, mut srv protocol.Server, inp ui.Input) EditorFrame {
	c.begin(inp, 1440, 900, 1.0)
	fr := e.frame(mut c, mut srv)
	c.end()
	return fr
}

// İki boş kare: sahne dikdörtgeni önceki karenin düzeninden okunur.
fn hier_warm(mut c ui.Context, mut e Editor, mut srv protocol.Server) ui.Rect {
	hier_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fr := hier_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	return fr.scene
}

// Tıklama: üzerine gel, bas, bırak.
fn hier_click(mut c ui.Context, mut e Editor, mut srv protocol.Server, x f32, y f32) {
	hier_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: x, mouse_y: y })
	mut down := ui.Input{ mouse_x: x, mouse_y: y }
	down.down[0] = true
	down.pressed[0] = true
	hier_frame(mut c, mut e, mut srv, down)
	mut up := ui.Input{ mouse_x: x, mouse_y: y }
	up.released[0] = true
	hier_frame(mut c, mut e, mut srv, up)
}
