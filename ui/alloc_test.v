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

// Editör senaryosu: Bileşen ekle menüsünü aç-Esc, x alanını tıklayıp yaz-Enter, Oynat üzerinde ipucu.
// Her döngü 14 karedir; menü, düzenleme ve ipucu ölçülen karelerde gerçekten görünmeli (boş geçiş yok).
struct EditorRun {
mut:
	menu_open bool
	editing   bool
	tip       bool
}

fn editor_menu_open(c &Context, label string) bool {
	h := c.probe(c.id(label))
	return h >= 0 && c.states[h].id == c.id(label) && c.states[h].flag(off_open)
}

fn editor_script_input(c &Context, j int, t f64) Input {
	target := match j {
		0, 1, 2, 3 { 'add_component' }
		4, 5, 6, 7, 8 { 'x' }
		else { 'Oynat' }
	}
	r := c.last_rect(target) or { Rect{} }
	mut inp := Input{
		mouse_x: r.x + r.w / 2
		mouse_y: r.y + r.h / 2
		time_ms: t
	}
	match j {
		1, 5 {
			inp.pressed[0] = true
			inp.down[0] = true
		}
		2, 6 {
			inp.released[0] = true
		}
		3 {
			inp.keys[0] = .escape
			inp.key_count = 1
		}
		7 {
			inp.chars[0] = u32(0x37)
			inp.char_count = 1
		}
		8 {
			inp.keys[0] = .enter
			inp.key_count = 1
		}
		else {}
	}
	return inp
}

fn editor_script_step(mut c Context, mut st ShowcaseState, j int, t f64, mut run EditorRun) {
	inp := editor_script_input(&c, j, t)
	c.begin(inp, 1440, 900, 1.0)
	showcase(mut c, mut st, .editor)
	c.end()
	if j == 2 && editor_menu_open(&c, 'add_component') {
		run.menu_open = true
	}
	if j == 6 && c.num_id != 0 {
		run.editing = true
	}
	if (j == 11 || j == 12) && c.tip_shown {
		run.tip = true
	}
}

fn test_showcase_editor_interactions_zero_alloc() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap ile calistir')
		return
	}
	atlas := Atlas.build(1.0) or { panic(err) }
	mut c := Context.new(&atlas, 4096, 8192) or { panic(err) }
	mut st := ShowcaseState.new()
	mut warm := EditorRun{}
	for k in 0 .. 14 {
		editor_script_step(mut c, mut st, k, f64(k) * 600, mut warm)
	}
	mut run := EditorRun{}
	before := memory.heap_alloc_count()
	for k in 14 .. 28 {
		editor_script_step(mut c, mut st, k % 14, f64(k) * 600, mut run)
	}
	assert memory.heap_alloc_count() - before == 0
	assert run.menu_open, 'bilesen ekle menusu acilmadi'
	assert run.editing, 'x alani duzenlemeye gecmedi'
	assert run.tip, 'Oynat ipucu gosterilmedi'
}
