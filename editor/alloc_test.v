module editor

import memory
import protocol
import sim
import ecs
import ui

// Boşta (girdi ve istek yok) editör karesi kararlı durumda heap tahsisi yapmaz; -d track_heap ile anlamlıdır.
// Seçili varlık ve görünür gizmo (seçim çerçevesi, üç tutamaç) dahildir.
fn test_idle_frames_zero_alloc() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap ile calistir')
		return
	}
	mut srv := protocol.Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	srv.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":0,"y":0},"Sprite":{"size":4}}}}') or {
		panic('yanit yok')
	}
	mut fr := EditorFrame{}
	for k in 0 .. 10 {
		c.begin(ui.Input{ mouse_x: -1, mouse_y: -1, time_ms: f64(k) * 16 }, 1440, 900, 1.0)
		fr = e.frame(mut c, mut srv)
		c.end()
	}
	// Seçim: merkeze tıklama (üzerine gel, bas, bırak); sonra boşta kareler.
	r := fr.scene
	sx, sy := e.cam.world_to_screen(r, 0, 0)
	for inp in [ui.Input{ mouse_x: sx, mouse_y: sy }, press_input(sx, sy), release_input(sx, sy)] {
		c.begin(inp, 1440, 900, 1.0)
		e.frame(mut c, mut srv)
		c.end()
	}
	assert e.sv.sel != none, 'gizmo testinin önkoşulu: varlık seçili'
	before := memory.heap_alloc_count()
	for k in 10 .. 110 {
		c.begin(ui.Input{ mouse_x: -1, mouse_y: -1, time_ms: f64(k) * 16 }, 1440, 900, 1.0)
		e.frame(mut c, mut srv)
		c.end()
	}
	assert memory.heap_alloc_count() - before == 0
}

fn press_input(x f32, y f32) ui.Input {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	inp.down[0] = true
	inp.pressed[0] = true
	return inp
}

fn release_input(x f32, y f32) ui.Input {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	inp.released[0] = true
	return inp
}

// 1.000 canlı varlıkla boşta kareler (seçili varlık dahil) heap tahsisi yapmaz.
fn test_idle_frames_zero_alloc_1000_entities() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap ile calistir')
		return
	}
	mut srv := protocol.Server.new(sim.Config{ capacity: 2048, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	mut sel := ecs.EntityID(0)
	for i in 0 .. 1000 {
		resp := srv.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":${i % 40},"y":0},"Sprite":{"size":1}}}}') or {
			panic('yanit yok')
		}
		if i == 500 {
			sel = protocol.response_entity(resp) or { panic('kimlik yok') }
		}
	}
	e.sv.sel = sel
	for k in 0 .. 10 {
		c.begin(ui.Input{ mouse_x: -1, mouse_y: -1, time_ms: f64(k) * 16 }, 1440, 900, 1.0)
		e.frame(mut c, mut srv)
		c.end()
	}
	before := memory.heap_alloc_count()
	for k in 10 .. 110 {
		c.begin(ui.Input{ mouse_x: -1, mouse_y: -1, time_ms: f64(k) * 16 }, 1440, 900, 1.0)
		e.frame(mut c, mut srv)
		c.end()
	}
	assert memory.heap_alloc_count() - before == 0
}
