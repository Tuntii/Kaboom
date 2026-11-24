module ui

import memory

// Vitrin kararlı durumda kare başına tahsis yapmaz; yalnızca -d track_heap ile anlamlıdır.
fn showcase_step(mut c Context, mut st ShowcaseState, page ShowcasePage, t f64, k int) {
	mut inp := Input{
		mouse_x: f32(100 + (k * 7) % 300)
		mouse_y: f32(60 + (k * 5) % 200)
		time_ms: t
	}
	if k % 9 == 0 {
		inp.pressed[0] = true
		inp.down[0] = true
	} else if k % 9 == 1 {
		inp.released[0] = true
	}
	if k % 13 == 5 {
		inp.chars[0] = u32(0x61)
		inp.char_count = 1
	}
	c.begin(inp, 1440, 900, 1.0)
	showcase(mut c, mut st, page)
	c.end()
}

fn test_showcase_steady_state_zero_alloc() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap ile calistir')
		return
	}
	atlas := Atlas.build(1.0) or { panic(err) }
	mut c := Context.new(&atlas, 4096, 8192) or { panic(err) }
	mut st := ShowcaseState.new()
	for k in 0 .. 10 {
		showcase_step(mut c, mut st, .editor, f64(k) * 16, k)
		showcase_step(mut c, mut st, .widgets, f64(k) * 16, k)
	}
	before := memory.heap_alloc_count()
	for k in 10 .. 110 {
		showcase_step(mut c, mut st, .editor, f64(k) * 16, k)
	}
	for k in 110 .. 210 {
		showcase_step(mut c, mut st, .widgets, f64(k) * 16, k)
	}
	assert memory.heap_alloc_count() - before == 0
}

fn test_showcase_no_dropped_cmds() {
	atlas := Atlas.build(1.0) or { panic(err) }
	mut c := Context.new(&atlas, 4096, 8192) or { panic(err) }
	mut st := ShowcaseState.new()
	for page in [ShowcasePage.editor, ShowcasePage.widgets] {
		for k in 0 .. 3 {
			c.begin(Input{ mouse_x: f32(k), mouse_y: 10 }, 1440, 900, 1.0)
			showcase(mut c, mut st, page)
			l := c.end()
			assert l.dropped() == 0, 'kayip komut: ${l.dropped()}'
		}
		assert c.node_overflow() == 0, 'dugum tasmasi: ${c.node_overflow()}'
	}
}
