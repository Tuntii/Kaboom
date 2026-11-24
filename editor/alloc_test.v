module editor

import memory
import protocol
import sim
import ui

// Boşta (girdi ve istek yok) editör karesi kararlı durumda heap tahsisi yapmaz; -d track_heap ile anlamlıdır.
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
