module ui

import memory

fn wgt_atlas() Atlas {
	return Atlas.build(1.0) or { panic(err) }
}

fn mouse_at(x f32, y f32) Input {
	return Input{
		mouse_x: x
		mouse_y: y
	}
}

fn press_at(x f32, y f32) Input {
	mut inp := mouse_at(x, y)
	inp.down[0] = true
	inp.pressed[0] = true
	return inp
}

fn release_at(x f32, y f32) Input {
	mut inp := mouse_at(x, y)
	inp.released[0] = true
	return inp
}

fn timed(inp Input, t f64) Input {
	mut out := inp
	out.time_ms = t
	return out
}

fn wgt_count_rects(l &DrawList) u32 {
	mut n := u32(0)
	for i in 0 .. l.len() {
		if l.at(i).kind == u32(DrawKind.rect) {
			n++
		}
	}
	return n
}

// Etkileşim önceki karenin düzenini kullanır: her girdi iki kare işlenir. İlk kare
// kenar olaylarını (basış, bırakma, tuş, tekerlek) taşımaz; düzen ve imleç geçmişini kurar.
fn wgt_frame(mut c Context, inp Input, body fn (mut c Context)) {
	mut warm := inp
	warm.pressed = [3]bool{}
	warm.released = [3]bool{}
	warm.key_count = 0
	warm.wheel_y = 0
	c.begin(warm, 400, 300, 1.0)
	body(mut c)
	c.end()
	c.begin(inp, 400, 300, 1.0)
	body(mut c)
	c.end()
}

// Kapanışlar değeri kopyalar; sayaçlar bu yapı üzerinden (işaretçiyle) paylaşılır.
struct Tally {
mut:
	ok      int
	other   int
	off     int
	changes int
	value   bool
	open    bool
	size    f32
	hv      f32
	clicks  int
	enabled bool
}

fn wgt_scroll_of(c &Context, id u32) f32 {
	return c.states[c.probe(id)].scroll
}

fn test_button_clicks_on_release_inside_only() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.button('ok', .primary) {
			tp.ok++
		}
		if c.button('other', .secondary) {
			tp.other++
		}
		if c.button_ex('off', .primary, false) {
			tp.off++
		}
	}
	wgt_frame(mut c, mouse_at(5, 5), body)
	wgt_frame(mut c, press_at(5, 5), body)
	wgt_frame(mut c, release_at(5, 5), body)
	assert t.ok == 1
	wgt_frame(mut c, mouse_at(5, 5), body)
	assert t.ok == 1

	// Dışarıda bırakma: tıklama yok, sonraki kare başka düğmede normal çalışır.
	wgt_frame(mut c, press_at(5, 5), body)
	wgt_frame(mut c, release_at(300, 200), body)
	assert t.ok == 1
	wgt_frame(mut c, press_at(5, 40), body)
	wgt_frame(mut c, release_at(5, 40), body)
	assert t.other == 1

	// Devre dışı düğme hiç tıklanmaz.
	wgt_frame(mut c, press_at(5, 70), body)
	wgt_frame(mut c, release_at(5, 70), body)
	assert t.off == 0
	assert t.ok == 1
	assert t.other == 1
}

fn test_checkbox_toggles_and_section_collapses() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.checkbox('cb', mut &tp.value) {
			tp.changes++
		}
		tp.open = c.section('sec', 'Başlık')
		if tp.open {
			c.text('içerik', .body, text_primary)
		}
	}
	wgt_frame(mut c, mouse_at(5, 5), body)
	wgt_frame(mut c, press_at(5, 5), body)
	wgt_frame(mut c, release_at(5, 5), body)
	assert t.value
	assert t.changes == 1
	wgt_frame(mut c, mouse_at(5, 5), body)
	assert t.value
	assert t.changes == 1

	// Varsayılan açık; başlığa tıklamak kapatır ve içerik düğümleri kaybolur.
	wgt_frame(mut c, mouse_at(5, 40), body)
	assert t.open
	open_nodes := c.n
	wgt_frame(mut c, press_at(5, 40), body)
	wgt_frame(mut c, release_at(5, 40), body)
	assert !t.open
	assert c.n == open_nodes - 1
	wgt_frame(mut c, mouse_at(5, 40), body)
	assert !t.open
}

fn test_splitter_drag_clamped() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{
		size: 240
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		c.splitter('sp', mut &tp.size, 100, 400)
	}
	wgt_frame(mut c, mouse_at(2, 10), body)
	wgt_frame(mut c, press_at(2, 10), body)

	mut right := mouse_at(502, 10)
	right.down[0] = true
	wgt_frame(mut c, right, body)
	assert t.size == 400

	mut left := mouse_at(-498, 10)
	left.down[0] = true
	wgt_frame(mut c, left, body)
	assert t.size == 100
}

fn test_tab_cycles_focus() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	body := fn (mut c Context) {
		c.button('a', .secondary)
		c.button('b', .secondary)
		c.button('c', .secondary)
	}
	mut tab := Input{}
	tab.keys[0] = .tab
	tab.key_count = 1

	wgt_frame(mut c, tab, body)
	assert c.focused_id() == c.id('a')
	wgt_frame(mut c, tab, body)
	assert c.focused_id() == c.id('b')
	wgt_frame(mut c, tab, body)
	assert c.focused_id() == c.id('c')

	mut back := tab
	back.shift = true
	wgt_frame(mut c, back, body)
	assert c.focused_id() == c.id('b')
}

fn test_wheel_scrolls_and_clamps() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	body := fn (mut c Context) {
		c.open('list', Box{
			dir:      .column
			width:    fixed(200)
			height:   fixed(200)
			scroll_y: true
		})
		for _ in 0 .. 100 {
			c.open('row', Box{
				width:  grow()
				height: fixed(row_h)
			})
			c.close()
		}
		c.close()
	}
	list := c.id('list')
	mut down := mouse_at(50, 50)
	down.wheel_y = -100
	wgt_frame(mut c, down, body)
	// İçerik 100 × row_h, kutu 200: en fazla ofset 2400.
	assert wgt_scroll_of(&c, list) == 100 * row_h - 200

	mut up := mouse_at(50, 50)
	up.wheel_y = 100
	wgt_frame(mut c, up, body)
	assert wgt_scroll_of(&c, list) == 0
}

fn test_scroll_box_clips_children() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 300, 300, 1.0)
	c.open('list', Box{
		dir:      .column
		width:    fixed(100)
		height:   fixed(50)
		scroll_y: true
	})
	c.open('a', Box{
		width:  fixed(100)
		height: fixed(50)
		bg:     surface_1
	})
	c.close()
	// Kutunun tamamen dışında: hiçbir komut üretmemeli.
	c.open('b', Box{
		width:  fixed(100)
		height: fixed(20)
		bg:     surface_2
	})
	c.close()
	c.close()
	l := c.end()
	assert wgt_count_rects(l) == 1
}

fn test_overlay_blocks_hover_below() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{}
	mut tp := &t
	covered := fn [mut tp] (mut c Context) {
		if c.button('under', .secondary) {
			tp.clicks++
		}
		c.overlay('ov', 0, 0, Box{
			width:  fixed(100)
			height: fixed(100)
		})
		c.close()
	}
	wgt_frame(mut c, mouse_at(5, 5), covered)
	wgt_frame(mut c, press_at(5, 5), covered)
	wgt_frame(mut c, release_at(5, 5), covered)
	assert t.clicks == 0

	// Denetim: aynı düğme, overlay yokken tıklanır.
	open := fn [mut tp] (mut c Context) {
		if c.button('under', .secondary) {
			tp.clicks++
		}
	}
	wgt_frame(mut c, mouse_at(5, 5), open)
	wgt_frame(mut c, press_at(5, 5), open)
	wgt_frame(mut c, release_at(5, 5), open)
	assert t.clicks == 1
}

fn test_hover_transition_follows_motion_ms() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		c.open('h', Box{
			width:  fixed(100)
			height: fixed(20)
		})
		c.close()
		tp.hv = c.hover_t(c.id('h'), c.interact(c.id('h'), false).hovered)
	}
	wgt_frame(mut c, timed(mouse_at(5, 5), 1000), body)
	wgt_frame(mut c, timed(mouse_at(5, 5), 1050), body)
	assert t.hv > 0 && t.hv < 1
	wgt_frame(mut c, timed(mouse_at(5, 5), 1100), body)
	assert t.hv == 1
	wgt_frame(mut c, timed(mouse_at(300, 200), 1200), body)
	assert t.hv == 1
	wgt_frame(mut c, timed(mouse_at(300, 200), 1300), body)
	assert t.hv == 0
}

fn test_mix_endpoints_and_midpoint() {
	a := Color(0x00000000)
	b := Color(0xFFFFFFFF)
	assert mix(a, b, 0) == a
	assert mix(a, b, 1) == b
	assert mix(a, b, 2) == b
	assert mix(a, b, 0.5) == Color(0x80808080)
}

// -d track_heap ile: kararlı durumda widget karesi V heap tahsisi yapmaz.
fn test_widget_frame_has_zero_heap_allocs() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap ile calistir')
		return
	}
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		c.toolbar_begin()
		if c.icon_button('new', .plus, false) {
			tp.clicks++
		}
		c.toolbar_end()
		if c.button('ok', .primary) {
			tp.ok++
		}
		if c.checkbox('cb', mut &tp.value) {
			tp.changes++
		}
		if c.section('sec', 'Başlık') {
			c.list_row('row', 'satır', true)
		}
		c.splitter('sp', mut &tp.size, 100, 400)
		c.separator()
		c.statusbar_begin()
		c.statusbar_text('durum')
		c.statusbar_end()
	}
	mut press := press_at(5, 5)
	wgt_frame(mut c, press, body)
	before := memory.heap_alloc_count()
	for k in 0 .. 10 {
		if k % 2 == 0 {
			wgt_frame(mut c, press, body)
		} else {
			wgt_frame(mut c, release_at(5, 5), body)
		}
	}
	assert memory.heap_alloc_count() == before
}

fn wgt_count_glyph_uv(l &DrawList, u0 f32, v0 f32) u32 {
	mut n := u32(0)
	for i in 0 .. l.len() {
		cmd := l.at(i)
		if cmd.kind == u32(DrawKind.glyph) && cmd.u0 == u0 && cmd.v0 == v0 {
			n++
		}
	}
	return n
}

// Odaktaki düğme Enter ile bir kez etkinleşir; devre dışıysa etkinleşmez.
fn test_enter_activates_focused_button() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{
		enabled: true
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.button_ex('ok', .primary, tp.enabled) {
			tp.ok++
		}
	}
	mut tab := Input{}
	tab.keys[0] = .tab
	tab.key_count = 1
	wgt_frame(mut c, tab, body)
	assert c.focused_id() == c.id('ok')

	mut enter := Input{}
	enter.keys[0] = .enter
	enter.key_count = 1
	wgt_frame(mut c, enter, body)
	assert t.ok == 1
	wgt_frame(mut c, Input{}, body)
	assert t.ok == 1

	// Odakta kalan düğme devre dışı kalırsa Enter etkinleştirmez.
	t.enabled = false
	wgt_frame(mut c, enter, body)
	assert t.ok == 1
}

// Odaktaki onay kutusu Space ile çevrilir.
fn test_space_toggles_focused_checkbox() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.checkbox('cb', mut &tp.value) {
			tp.changes++
		}
	}
	mut tab := Input{}
	tab.keys[0] = .tab
	tab.key_count = 1
	wgt_frame(mut c, tab, body)
	assert c.focused_id() == c.id('cb')
	assert t.changes == 0

	mut space := Input{}
	space.keys[0] = .space
	space.key_count = 1
	wgt_frame(mut c, space, body)
	assert t.value
	assert t.changes == 1
	wgt_frame(mut c, space, body)
	assert !t.value
	assert t.changes == 2
}

// İşaretli onay kutusu check ikonunu, işaretsiz olan hiç ikon çizmez.
fn test_checked_checkbox_draws_check_glyph() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	check := atl.icon(.check)

	mut on := true
	c.begin(Input{}, 400, 300, 1.0)
	c.checkbox('cb', mut &on)
	l_on := c.end()
	assert wgt_count_glyph_uv(l_on, check.u0, check.v0) == 1

	mut off := false
	c.begin(Input{}, 400, 300, 1.0)
	c.checkbox('cb', mut &off)
	l_off := c.end()
	assert wgt_count_glyph_uv(l_off, check.u0, check.v0) == 0
}
