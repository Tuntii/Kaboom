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
	warm.char_count = 0
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
		c.splitter('sp', mut &tp.size, 100, 400, true)
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

// Sağ panel ayırıcısı: sağa sürükleme size'ı azaltır (grows_right false), sınırlar aynı kalır.
fn test_splitter_right_panel_drag_inverted() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{
		size: 240
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		c.splitter('sp', mut &tp.size, 100, 400, false)
	}
	wgt_frame(mut c, mouse_at(2, 10), body)
	wgt_frame(mut c, press_at(2, 10), body)

	mut right := mouse_at(52, 10)
	right.down[0] = true
	wgt_frame(mut c, right, body)
	assert t.size == 190

	mut left := mouse_at(-398, 10)
	left.down[0] = true
	wgt_frame(mut c, left, body)
	assert t.size == 400

	mut far_right := mouse_at(1002, 10)
	far_right.down[0] = true
	wgt_frame(mut c, far_right, body)
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
		c.splitter('sp', mut &tp.size, 100, 400, true)
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

fn wgt_count_cmds(l &DrawList, kind DrawKind, color u32) u32 {
	mut n := u32(0)
	for i in 0 .. l.len() {
		cmd := l.at(i)
		if cmd.kind == u32(kind) && cmd.color == color {
			n++
		}
	}
	return n
}

struct PropTally {
mut:
	a f32
	b f32
}

// Özellik satırları: iki satırda alanlar aynı x'te; sağ kenar panelin iç sağ kenarında.
fn test_property_row_label_column_aligned() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := PropTally{
		a: 1
		b: -4
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		c.open('pan', Box{
			dir:     .column
			width:   fixed(300)
			height:  fit()
			padding: pad_all(space_3)
			gap:     space_2
		})
		c.property_row_begin('X')
		c.number_field('x', mut &tp.a, 'm', 2, 0.1, -100, 100)
		c.property_row_end()
		c.property_row_begin('Y')
		c.number_field('y', mut &tp.b, 'm', 2, 0.1, -100, 100)
		c.property_row_end()
		c.close()
	}
	wgt_frame(mut c, Input{}, body)
	pan := c.last_rect('pan') or { panic('pan yok') }
	fx := c.last_rect('x') or { panic('x yok') }
	fy := c.last_rect('y') or { panic('y yok') }
	assert fx.x == fy.x
	assert fx.x + fx.w == pan.x + pan.w - space_3
}

// Devre dışı birincil düğme: surface_2 zemin, text_muted metin, accent yok.
fn test_disabled_button_uses_muted() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 400, 300, 1.0)
	c.button_ex('Birincil', .primary, false)
	l := c.end()
	assert wgt_count_cmds(l, .rect, u32(surface_2)) >= 1
	assert wgt_count_cmds(l, .glyph, u32(text_muted)) >= 1
	assert wgt_count_cmds(l, .rect, u32(accent)) == 0
	assert wgt_count_cmds(l, .glyph, u32(accent_text)) == 0
}

// Ayırıcının görünen çizgisi 1 mantıksal px; tıklama alanı ayrı ve görünmez.
fn test_splitter_visible_line_is_1px() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{
		size: 240
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		c.splitter('sp', mut &tp.size, 100, 400, true)
	}
	wgt_frame(mut c, Input{}, body)
	c.begin(Input{}, 400, 300, 1.0)
	body(mut c)
	l := c.end()
	assert wgt_count_cmds(l, .rect, u32(border)) == 1
	for i in 0 .. l.len() {
		cmd := l.at(i)
		if cmd.kind == u32(DrawKind.rect) && cmd.color == u32(border) {
			assert cmd.w == 1
		}
	}
}

fn wgt_count_rings(l &DrawList) u32 {
	mut n := u32(0)
	for i in 0 .. l.len() {
		cmd := l.at(i)
		if cmd.color == 0 && cmd.border_color == u32(accent) {
			n++
		}
	}
	return n
}

// Fare tıklaması düğmeye odak vermez: Space ikinci kez etkinleştirmez, odak halkası çizilmez.
fn test_mouse_click_gives_button_no_focus() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{
		enabled: true
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.button_ex('kaydet', .primary, tp.enabled) {
			tp.ok++
		}
	}
	wgt_frame(mut c, mouse_at(20, 10), body)
	wgt_frame(mut c, press_at(20, 10), body)
	wgt_frame(mut c, release_at(20, 10), body)
	assert t.ok == 1
	assert c.focused_id() == 0
	assert wgt_count_rings(&c.list) == 0
	mut space := Input{}
	space.keys[0] = .space
	space.key_count = 1
	wgt_frame(mut c, space, body)
	assert t.ok == 1
}

// Klavyeyle (Tab) odaklanan düğmede halka çizilir ve Enter etkinleştirir.
fn test_tab_focus_draws_ring_and_enter_fires() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{
		enabled: true
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.button_ex('kaydet', .primary, tp.enabled) {
			tp.ok++
		}
	}
	mut tab := Input{}
	tab.keys[0] = .tab
	tab.key_count = 1
	wgt_frame(mut c, tab, body)
	assert c.focused_id() == c.id('kaydet')
	assert wgt_count_rings(&c.list) == 1
	mut enter := Input{}
	enter.keys[0] = .enter
	enter.key_count = 1
	wgt_frame(mut c, enter, body)
	assert t.ok == 1
}

// Tekrar (autorepeat) Enter düğmeyi etkinleştirmez.
fn test_enter_repeat_does_not_activate() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := Tally{
		enabled: true
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.button_ex('kaydet', .primary, tp.enabled) {
			tp.ok++
		}
	}
	mut tab := Input{}
	tab.keys[0] = .tab
	tab.key_count = 1
	wgt_frame(mut c, tab, body)
	mut rep := Input{}
	rep.keys[0] = .enter
	rep.key_repeat[0] = true
	rep.key_count = 1
	wgt_frame(mut c, rep, body)
	assert t.ok == 0
}

struct SecProbe {
mut:
	open     bool
	trailing bool
	clicks   int
}

// Sağ uçtaki ikon bölümü katlamaz; yalnızca trailing_clicked olur.
fn test_section_ex_trailing_icon_click() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut p := SecProbe{}
	mut pp := &p
	body := fn [mut pp] (mut c Context) {
		r := c.section_ex('sec', 'Başlık', SectionOpts{
			trailing_icon: Icon.trash
		})
		pp.open = r.open
		if r.trailing_clicked {
			pp.trailing = true
			pp.clicks++
		}
	}
	// Başlık 400 px genişlikte, row_h yüksekte; sağ uç ikon kutusunun içi.
	tx := f32(400) - row_h / 2
	ty := row_h / 2
	wgt_frame(mut c, mouse_at(tx, ty), body)
	wgt_frame(mut c, press_at(tx, ty), body)
	wgt_frame(mut c, release_at(tx, ty), body)
	assert p.trailing
	assert p.clicks == 1
	assert p.open
}

// default_open false: ilk karede kapalı; tıklanınca açılır ve kalıcıdır.
fn test_section_ex_default_closed() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut p := SecProbe{}
	mut pp := &p
	body := fn [mut pp] (mut c Context) {
		r := c.section_ex('sec', 'Başlık', SectionOpts{
			default_open: false
		})
		pp.open = r.open
		if r.open {
			c.text('içerik', .body, text_primary)
		}
	}
	wgt_frame(mut c, mouse_at(5, 5), body)
	assert !p.open
	wgt_frame(mut c, press_at(5, 5), body)
	wgt_frame(mut c, release_at(5, 5), body)
	assert p.open
	wgt_frame(mut c, mouse_at(5, 5), body)
	assert p.open
}

// Sığmayan metin sonunda … (U+2026) ile, kod noktası sınırında kesilir; sığan metin kesilmez.
fn test_text_trunc_adds_ellipsis_at_codepoint_boundary() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	s := 'Kaydedilmemiş değişiklikler'
	max_w := f32(60)
	c.begin(Input{}, 400, 300, 1.0)
	c.text_trunc(s, .body, text_primary, max_w)
	c.text_trunc('ab', .body, text_primary, 100)
	c.end()
	mut long := -1
	mut short := -1
	for k in 0 .. c.n {
		if c.nodes[k].kind == .text {
			if c.nodes[k].text == s {
				long = k
			} else {
				short = k
			}
		}
	}
	assert long >= 0 && short >= 0
	assert c.nodes[long].ell
	assert c.nodes[long].content[0] <= max_w
	assert c.nodes[long].ell_at < s.len
	// Kesim noktası baştan yürüyüşle bulunan bir kod noktası sınırı olmalı.
	mut k := 0
	mut boundary := false
	for k <= c.nodes[long].ell_at {
		if k == c.nodes[long].ell_at {
			boundary = true
			break
		}
		_, nx := utf8_next(s, k)
		k = nx
	}
	assert boundary
	assert !c.nodes[short].ell
}

// Durum tablosu dolunca taşma sayılır (sessiz düşme yok).
fn test_state_table_overflow_counted() {
	mut atl := wgt_atlas()
	// Küçük kapasite: durum tablosu 8 yuvalıdır.
	mut c := Context.new(&atl, 4, 256) or { panic(err) }
	c.begin(Input{}, 400, 300, 1.0)
	for k in 0 .. 40 {
		c.interact(c.id('k${k}'), false)
	}
	c.end()
	assert c.state_overflow() > 0
}

// Ölçek eşleşince begin normal çalışır (eşleşmeyen ölçek assert ile durur; kod incelemesiyle doğrulanır).
fn test_begin_scale_matches_atlas_ok() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 400, 300, 1.0)
	c.text('tamam', .body, text_primary)
	c.end()
	assert c.node_overflow() == 0
	assert c.n > 1
}
