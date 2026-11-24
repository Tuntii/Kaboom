module ui

import math
import memory

// v test her dosyayı ayrı derler: çerçeve yardımcıları widgets_test.v ile aynıdır.
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

// Etkileşim önceki karenin düzenini kullanır: her girdi iki kare işlenir; kenar olayları yalnızca ikinci geçişte.
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

// Girdi widget'ları testleri; kareler wgt_frame ile iki geçişli işlenir.
struct InTally {
mut:
	buf     TextBuf
	value   f32
	enter   int
	changed int
	sel     int
	open    bool
	tip     bool
}

fn in_fmt(v f32, dec int) string {
	mut out := [32]u8{}
	n := format_f32(v, dec, mut out)
	return out[..n].bytestr()
}

fn in_parse(s string) f32 {
	return parse_f32(s) or { f32(-999) }
}

fn in_no_parse(s string) bool {
	_ := parse_f32(s) or { return true }
	return false
}

// Metnin her kod noktası ayrı karakter olarak gider; tahsissiz (literal dilimlenmez).
fn in_text(s string) Input {
	mut inp := Input{}
	mut k := 0
	for k < s.len {
		cp, nx := utf8_next(s, k)
		inp.chars[inp.char_count] = cp
		inp.char_count++
		k = nx
	}
	return inp
}

fn in_key(k Key) Input {
	mut inp := Input{}
	inp.keys[0] = k
	inp.key_count = 1
	return inp
}

fn test_format_f32_cases() {
	assert in_fmt(1.5, 2) == '1.50'
	assert in_fmt(-f32(0), 1) == '0.0'
	assert in_fmt(12345.678, 1) == '12345.7'
	assert in_fmt(f32(math.nan()), 0) == 'nan'
	assert in_fmt(f32(math.inf(1)), 0) == 'inf'
	assert in_fmt(-3, 0) == '-3'
}

fn test_parse_f32_cases() {
	assert in_parse('1.5') == 1.5
	assert in_parse('-2') == -2
	assert in_parse('.5') == 0.5
	assert in_parse('1e3') == 1000
	assert in_no_parse('')
	assert in_no_parse('abc')
	assert in_no_parse('1.2.3')
}

fn test_text_field_typing_and_backspace() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.text_field('alan', mut tp.buf, 120) {
			tp.enter++
		}
	}
	wgt_frame(mut c, in_key(.tab), body)
	assert c.focused_id() == c.id('alan')
	wgt_frame(mut c, in_text('çay'), body)
	assert t.buf.str() == 'çay'
	assert t.buf.len == 4
	wgt_frame(mut c, in_key(.backspace), body)
	assert t.buf.str() == 'ça'
	assert t.buf.len == 3
}

fn test_text_field_escape_restores() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	t.buf.set('ab')
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.text_field('alan', mut tp.buf, 120) {
			tp.enter++
		}
	}
	wgt_frame(mut c, in_key(.tab), body)
	wgt_frame(mut c, in_text('c'), body)
	assert t.buf.str() == 'abc'
	wgt_frame(mut c, in_key(.escape), body)
	assert t.buf.str() == 'ab'
	assert c.focused_id() != c.id('alan')
}

fn test_text_field_capacity() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.text_field('alan', mut tp.buf, 120) {
			tp.enter++
		}
	}
	wgt_frame(mut c, in_key(.tab), body)
	// 300 'é' (her biri 2 bayt): 256 bayta sığan son kod noktası tam kalmalı.
	for _ in 0 .. 60 {
		wgt_frame(mut c, in_text('ééééé'), body)
	}
	s := t.buf.str()
	assert t.buf.len <= 256
	assert t.buf.len == 256
	mut k := 0
	mut ok := true
	for k < s.len {
		cp, nx := utf8_next(s, k)
		if cp != 0xE9 {
			ok = false
		}
		k = nx
	}
	assert ok && k == 256
}

// Boşluk tuşu metin alanında bir boşluk ekler (Space tuşu tıklama üretmez); Enter bir kez onaylar.
fn test_text_field_space_and_enter_once() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.text_field('alan', mut tp.buf, 120) {
			tp.enter++
		}
	}
	wgt_frame(mut c, in_key(.tab), body)
	mut sp := in_text('a ')
	sp.keys[0] = .space
	sp.key_count = 1
	wgt_frame(mut c, sp, body)
	assert t.buf.str() == 'a '
	assert t.enter == 0
	wgt_frame(mut c, in_key(.enter), body)
	assert t.enter == 1
	wgt_frame(mut c, Input{}, body)
	assert t.enter == 1
}

fn in_drag(mut c Context, body fn (mut c Context), shift bool) {
	wgt_frame(mut c, mouse_at(10, 10), body)
	wgt_frame(mut c, press_at(10, 10), body)
	mut mv := mouse_at(50, 10)
	mv.down[0] = true
	mv.shift = shift
	wgt_frame(mut c, mv, body)
	wgt_frame(mut c, release_at(50, 10), body)
}

fn in_drag_value(atl &Atlas, min f32, max f32, shift bool) f32 {
	mut c := Context.new(atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp, min, max] (mut c Context) {
		c.number_field('n', mut &tp.value, 'px', 1, min, max)
	}
	in_drag(mut c, body, shift)
	return t.value
}

// 40 px sürükleme, adım 1: 40 / 4 = 10; Shift ×10; max 50 kıskaçlar.
fn test_number_field_drag_changes_value() {
	mut atl := wgt_atlas()
	assert in_drag_value(&atl, 0, 0, false) == 10
	assert in_drag_value(&atl, 0, 0, true) == 100
	assert in_drag_value(&atl, 0, 50, true) == 50
}

fn in_typed(atl &Atlas, text string) (f32, int) {
	mut c := Context.new(atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.number_field('n', mut &tp.value, 'px', 1, 0, 0) {
			tp.changed++
		}
	}
	wgt_frame(mut c, mouse_at(10, 10), body)
	wgt_frame(mut c, press_at(10, 10), body)
	wgt_frame(mut c, release_at(10, 10), body)
	wgt_frame(mut c, in_text(text), body)
	wgt_frame(mut c, in_key(.enter), body)
	return t.value, t.changed
}

fn test_number_field_typed_entry() {
	mut atl := wgt_atlas()
	v, n := in_typed(&atl, '2.5')
	assert v == 2.5
	assert n == 1
	bad, m := in_typed(&atl, 'x')
	assert bad == 0
	assert m == 0
}

fn test_menu_opens_selects_closes() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		tp.open = c.menu_button('m', 'Menü')
		if tp.open {
			if c.menu_item('bir') {
				tp.sel = 1
			}
			if c.menu_item('iki') {
				tp.sel = 2
			}
			c.menu_end()
		}
	}
	wgt_frame(mut c, timed(mouse_at(5, 5), 1000), body)
	wgt_frame(mut c, timed(press_at(5, 5), 1000), body)
	wgt_frame(mut c, timed(release_at(5, 5), 1000), body)
	assert t.open
	// Açılış animasyonu bitince ilk öğe (y 36..62) tıklanır.
	wgt_frame(mut c, timed(mouse_at(10, 45), 1200), body)
	wgt_frame(mut c, timed(press_at(10, 45), 1200), body)
	wgt_frame(mut c, timed(release_at(10, 45), 1200), body)
	assert t.sel == 1
	wgt_frame(mut c, timed(mouse_at(300, 200), 1300), body)
	assert !t.open

	// Dışarı tıklama menüyü kapatır.
	wgt_frame(mut c, timed(mouse_at(5, 5), 1400), body)
	wgt_frame(mut c, timed(press_at(5, 5), 1400), body)
	wgt_frame(mut c, timed(release_at(5, 5), 1400), body)
	assert t.open
	wgt_frame(mut c, timed(press_at(300, 200), 1500), body)
	assert !t.open
}

fn test_menu_open_animates() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		tp.open = c.menu_button('m', 'Menü')
		if tp.open {
			c.menu_end()
		}
	}
	wgt_frame(mut c, timed(mouse_at(5, 5), 1000), body)
	wgt_frame(mut c, timed(press_at(5, 5), 1000), body)
	wgt_frame(mut c, timed(release_at(5, 5), 1000), body)
	assert t.open
	assert c.menu_alpha < 1
	wgt_frame(mut c, timed(mouse_at(300, 200), 1100), body)
	assert c.menu_alpha == 1
}

fn test_tooltip_after_delay() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		c.button('x', .secondary)
		c.tooltip('ipucu')
		tp.tip = c.tip_shown
	}
	wgt_frame(mut c, timed(mouse_at(5, 5), 1000), body)
	wgt_frame(mut c, timed(mouse_at(5, 5), 1400), body)
	assert !t.tip
	wgt_frame(mut c, timed(mouse_at(5, 5), 1600), body)
	assert t.tip
}

// Sahne: iki sekme (x, alan), yazı, Backspace, sayı sürükleme, menü açma, ipucu.
fn in_scenario(mut c Context, body fn (mut c Context), t0 f64) bool {
	wgt_frame(mut c, timed(in_key(.tab), t0), body)
	wgt_frame(mut c, timed(in_key(.tab), t0 + 50), body)
	wgt_frame(mut c, timed(in_text('ab'), t0 + 100), body)
	wgt_frame(mut c, timed(in_key(.backspace), t0 + 200), body)
	wgt_frame(mut c, timed(mouse_at(10, 70), t0 + 300), body)
	wgt_frame(mut c, timed(press_at(10, 70), t0 + 400), body)
	mut mv := mouse_at(50, 70)
	mv.down[0] = true
	wgt_frame(mut c, timed(mv, t0 + 500), body)
	wgt_frame(mut c, timed(release_at(50, 70), t0 + 600), body)
	wgt_frame(mut c, timed(mouse_at(10, 98), t0 + 700), body)
	wgt_frame(mut c, timed(press_at(10, 98), t0 + 800), body)
	wgt_frame(mut c, timed(release_at(10, 98), t0 + 900), body)
	wgt_frame(mut c, timed(mouse_at(10, 10), t0 + 1000), body)
	wgt_frame(mut c, timed(mouse_at(10, 10), t0 + 1300), body)
	wgt_frame(mut c, timed(mouse_at(10, 10), t0 + 1600), body)
	return c.tip_shown
}

// -d track_heap ile: yazı, sürükleme, açık menü ve ipucu kareleri V heap tahsisi yapmaz.
fn test_input_widgets_zero_heap_allocs() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap ile calistir')
		return
	}
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		c.button('x', .secondary)
		c.tooltip('ipucu')
		if c.text_field('alan', mut tp.buf, 120) {
			tp.enter++
		}
		if c.number_field('n', mut &tp.value, 'px', 1, 0, 0) {
			tp.changed++
		}
		tp.open = c.menu_button('m', 'Menü')
		if tp.open {
			if c.menu_item('bir') {
				tp.sel++
			}
			c.menu_end()
		}
	}
	in_scenario(mut c, body, 1000)
	before := memory.heap_alloc_count()
	shown := in_scenario(mut c, body, 10000)
	assert memory.heap_alloc_count() == before
	assert shown
}
