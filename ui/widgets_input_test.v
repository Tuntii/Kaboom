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
	last    NumberFieldResult
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
		c.number_field('n', mut &tp.value, 'px', 0, 1, min, max)
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
		if c.number_field('n', mut &tp.value, 'px', 0, 1, 0, 0) {
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
		if c.number_field('n', mut &tp.value, 'px', 0, 1, 0, 0) {
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

// Tıklama: hover, basış, bırakma (üç kare).
fn in_tap(mut c Context, body fn (mut c Context), x f32, y f32) {
	wgt_frame(mut c, mouse_at(x, y), body)
	wgt_frame(mut c, press_at(x, y), body)
	wgt_frame(mut c, release_at(x, y), body)
}

// Alanın düğüm dikdörtgeni ve içindeki imleç (1 px kutu) dikdörtgeni.
fn in_field_caret(c &Context, fid u32) (Rect, Rect) {
	mut fi := -1
	for i in 0 .. c.n {
		if c.nodes[i].id == fid && c.nodes[i].kind == .plain {
			fi = i
			break
		}
	}
	assert fi >= 0
	f := c.nodes[fi]
	field := Rect{
		x: f.pos[0]
		y: f.pos[1]
		w: f.sz[0]
		h: f.sz[1]
	}
	mut caret := Rect{}
	for j in 0 .. c.n {
		nd := c.nodes[j]
		if nd.parent == fi && nd.kind == .plain && nd.sz[0] == 1 {
			caret = Rect{
				x: nd.pos[0]
				y: nd.pos[1]
				w: nd.sz[0]
				h: nd.sz[1]
			}
		}
	}
	return field, caret
}

// Düzenlenen sayı alanı odağı kaybedince (metin alanına tıklama) değer uygulanır.
fn test_number_commits_when_text_field_takes_focus() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.number_field('n', mut &tp.value, 'px', 0, 1, 0, 0) {
			tp.changed++
		}
		if c.text_field('alan', mut tp.buf, 120) {
			tp.enter++
		}
	}
	in_tap(mut c, body, 10, 10)
	wgt_frame(mut c, in_text('7'), body)
	assert t.value == 0
	in_tap(mut c, body, 10, 40)
	assert t.value == 7
	assert t.changed == 1
}

// Boş bir kare, ilk tuşu değiştirmez: ilk yazım metni siler, sonrası ekler.
fn test_number_first_keystroke_replaces_after_idle() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{
		value: 12
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.number_field('n', mut &tp.value, 'px', 0, 1, 0, 0) {
			tp.changed++
		}
	}
	in_tap(mut c, body, 10, 10)
	wgt_frame(mut c, Input{}, body)
	wgt_frame(mut c, in_text('5'), body)
	wgt_frame(mut c, in_key(.enter), body)
	assert t.value == 5
	assert t.changed == 1
}

// Metin alanı genişliğinden uzun yazı: imleç alanın içinde kalır; Home ofseti sıfırlar.
fn test_text_field_scrolls_caret_in_view() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.text_field('alan', mut tp.buf, 80) {
			tp.enter++
		}
	}
	wgt_frame(mut c, in_key(.tab), body)
	// Bir karede en fazla 32 karakter gelir (platform sınırı).
	wgt_frame(mut c, in_text('abcdefghijklmnopqrstuvwxyz'), body)
	wgt_frame(mut c, in_text('0123456789'), body)
	fid := c.id('alan')
	assert c.states[c.probe(fid)].scroll > 0
	field, caret := in_field_caret(&c, fid)
	assert caret.x >= field.x && caret.x + caret.w <= field.x + field.w

	wgt_frame(mut c, in_key(.home), body)
	assert c.states[c.probe(fid)].scroll == 0
	field2, caret2 := in_field_caret(&c, fid)
	assert caret2.x >= field2.x && caret2.x + caret2.w <= field2.x + field2.w
}

// Tab, sayı alanından çıkar ve düzenlemeyi uygular; metin alanından Tab sayı alanına döner.
fn test_tab_leaves_number_field_and_commits() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.number_field('n', mut &tp.value, 'px', 0, 1, 0, 0) {
			tp.changed++
		}
		if c.text_field('alan', mut tp.buf, 120) {
			tp.enter++
		}
	}
	wgt_frame(mut c, in_key(.tab), body)
	assert c.focused_id() == c.id('n')
	wgt_frame(mut c, in_key(.enter), body)
	wgt_frame(mut c, in_text('7'), body)
	wgt_frame(mut c, in_key(.tab), body)
	assert c.focused_id() == c.id('alan')
	assert t.value == 7
	assert t.changed == 1
	wgt_frame(mut c, in_key(.tab), body)
	assert c.focused_id() == c.id('n')
}

// Sayı alanında Space düzenlemeyi başlatır (tek tetikleme); Enter bir kez uygular.
fn test_number_space_starts_enter_commits_once() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.number_field('n', mut &tp.value, 'px', 0, 1, 0, 0) {
			tp.changed++
		}
	}
	wgt_frame(mut c, in_key(.tab), body)
	wgt_frame(mut c, in_key(.space), body)
	assert t.changed == 0
	assert c.num_id == c.id('n')
	wgt_frame(mut c, in_text('4'), body)
	wgt_frame(mut c, in_key(.enter), body)
	assert t.value == 4
	assert t.changed == 1
	wgt_frame(mut c, Input{}, body)
	assert t.changed == 1
}

// Esc açık menüyü kapatır.
fn test_menu_closes_on_escape() {
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
	in_tap(mut c, body, 5, 5)
	assert t.open
	wgt_frame(mut c, in_key(.escape), body)
	assert !t.open
}

// Sayı alanı ayarlı ondalık sayısını her zaman gösterir: -4 → "-4.00".
fn test_number_field_fixed_decimals() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{
		value: -4
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		c.number_field('n', mut &tp.value, 'm', 2, 0.1, -100, 100)
	}
	wgt_frame(mut c, Input{}, body)
	mut s := ''
	for b in c.num_bufs[0] {
		if b == 0 {
			break
		}
		s += b.ascii_str()
	}
	assert s == '-4.00'
}

// Menü genişliği tetikleyiciden ve menu_min_w'den dar değil; öğe menü iç genişliğini tam kaplar.
fn test_menu_min_width() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	mut rw := MenuRects{}
	mut rp := &rw
	// Ölçüler bir önceki kareden okunur (prev_rect); menü açık kalan karelerde dolar.
	body := fn [mut tp, mut rp] (mut c Context) {
		tp.open = c.menu_button('m', 'Menü')
		if tp.open {
			c.menu_item('Birinci')
			c.menu_end()
		}
		c.push_id(1)
		mid := c.id('m')
		c.pop_id()
		c.push_id(2)
		iid := c.id('Birinci')
		c.pop_id()
		if r := c.prev_rect(c.id('m')) {
			rp.trig_w = r.w
		}
		if r := c.prev_rect(mid) {
			rp.menu_w = r.w
		}
		if r := c.prev_rect(iid) {
			rp.item_w = r.w
		}
	}
	wgt_frame(mut c, timed(mouse_at(5, 5), 1000), body)
	wgt_frame(mut c, timed(press_at(5, 5), 1000), body)
	wgt_frame(mut c, timed(release_at(5, 5), 1000), body)
	assert t.open
	wgt_frame(mut c, timed(mouse_at(6, 6), 1200), body)
	assert rw.menu_w >= rw.trig_w
	assert rw.menu_w >= menu_min_w
	assert rw.item_w == rw.menu_w - 2 * space_1
}

struct MenuRects {
mut:
	trig_w f32
	menu_w f32
	item_w f32
}

fn in_key_rep(k Key) Input {
	mut inp := in_key(k)
	inp.key_repeat[0] = true
	return inp
}

// Sayı alanı gizlenince bekleyen düzenleme atılır; ajan değeri değiştirir, yeniden gösterilen alan eski metni yazmaz.
fn test_hidden_number_edit_is_discarded() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{
		value: 3
		open:  true
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if tp.open {
			c.push_id(1)
			if c.number_field('x', mut &tp.value, '', 0, 1, 0, 0) {
				tp.changed++
			}
			c.pop_id()
		}
	}
	in_tap(mut c, body, 20, 10)
	wgt_frame(mut c, in_text('9'), body)
	assert c.num_id != 0
	t.open = false
	wgt_frame(mut c, Input{}, body)
	assert c.num_id == 0
	t.value = 5
	t.open = true
	wgt_frame(mut c, Input{}, body)
	in_tap(mut c, body, 20, 10)
	wgt_frame(mut c, in_key(.enter), body)
	assert t.value == 5
	assert t.changed == 0
}

// Odaklanamaz kimlikli panele basış odağı bırakır; bekleyen sayı düzenlemesi bu blurda uygulanır.
fn test_click_on_panel_blurs_number_field() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.number_field('n', mut &tp.value, '', 0, 1, 0, 0) {
			tp.changed++
		}
		c.open('scene', Box{
			width:  fixed(200)
			height: fixed(100)
		})
		c.close()
	}
	in_tap(mut c, body, 20, 10)
	wgt_frame(mut c, in_text('9'), body)
	wgt_frame(mut c, mouse_at(60, 60), body)
	wgt_frame(mut c, press_at(60, 60), body)
	assert c.focused_id() == 0
	wgt_frame(mut c, release_at(60, 60), body)
	assert t.value == 9
	assert t.changed == 1
}

// 2 px titreme tıklamayı sürükleme yapmaz: değer aynı kalır, düzenleme açılır.
fn test_number_jitter_click_enters_edit_without_change() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{
		value: 5
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.number_field('n', mut &tp.value, '', 0, 1, 0, 0) {
			tp.changed++
		}
	}
	wgt_frame(mut c, mouse_at(20, 10), body)
	wgt_frame(mut c, press_at(20, 10), body)
	mut mv := mouse_at(22, 10)
	mv.down[0] = true
	wgt_frame(mut c, mv, body)
	wgt_frame(mut c, release_at(22, 10), body)
	assert c.num_id == c.id('n')
	assert t.value == 5
	assert t.changed == 0
}

// Eşiği (3 px) aşan sürükleme: ilk delta basıştan ölçülür; 10 px, adım 1 → 2.5.
fn test_number_drag_past_threshold_changes_value() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if c.number_field('n', mut &tp.value, '', 0, 1, 0, 0) {
			tp.changed++
		}
	}
	wgt_frame(mut c, mouse_at(20, 10), body)
	wgt_frame(mut c, press_at(20, 10), body)
	mut mv := mouse_at(30, 10)
	mv.down[0] = true
	wgt_frame(mut c, mv, body)
	wgt_frame(mut c, release_at(30, 10), body)
	assert t.value == 2.5
	assert t.changed == 1
	assert c.num_id == 0
}

// Ondalık virgül (Türkçe klavye numpad): 2,5 → 2.5; birden fazla virgül geçersiz.
fn test_parse_f32_accepts_decimal_comma() {
	assert in_parse('2,5') == 2.5
	assert in_no_parse('1,2,3')
}

// Bitmemiş özellik satırı (property_row_end yok) sonraki karede sayı alanını yaymaz.
fn test_in_prop_reset_each_frame() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		if tp.open {
			c.property_row_begin('satir')
		} else {
			if c.number_field('n', mut &tp.value, '', 0, 1, 0, 0) {
				tp.changed++
			}
		}
	}
	t.open = true
	wgt_frame(mut c, Input{}, body)
	t.open = false
	wgt_frame(mut c, Input{}, body)
	mut fi := -1
	for i in 0 .. c.n {
		if c.nodes[i].id == c.id('n') && c.nodes[i].kind == .plain {
			fi = i
		}
	}
	assert fi >= 0
	assert c.nodes[fi].sz[0] == num_field_w
}

fn test_backspace_repeat_deletes_again() {
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
	wgt_frame(mut c, in_text('abc'), body)
	wgt_frame(mut c, in_key(.backspace), body)
	assert t.buf.str() == 'ab'
	wgt_frame(mut c, in_key_rep(.backspace), body)
	assert t.buf.str() == 'a'
}

// Tek geçiş: olaylar yalnızca bu karede işlenir (sürükleme olaylarının hangi karede geldiği ölçülebilsin).
fn nf_once(mut c Context, inp Input, body fn (mut c Context)) {
	c.begin(inp, 400, 300, 1.0)
	body(mut c)
	c.end()
}

fn nf_held(x f32, y f32) Input {
	mut inp := mouse_at(x, y)
	inp.down[0] = true
	return inp
}

fn nf_text_nodes(c &Context, s string) int {
	mut n := 0
	for i in 0 .. c.n {
		if c.nodes[i].kind == .text && c.nodes[i].text == s {
			n++
		}
	}
	return n
}

fn nf_glyphs_with(l &DrawList, col u32) int {
	mut n := 0
	for i in 0 .. l.len() {
		cmd := l.at(i)
		if cmd.kind == u32(DrawKind.glyph) && cmd.color == col {
			n++
		}
	}
	return n
}

fn nf_rects_with_border(l &DrawList, col u32) int {
	mut n := 0
	for i in 0 .. l.len() {
		cmd := l.at(i)
		if cmd.kind == u32(DrawKind.rect) && cmd.border_color == col {
			n++
		}
	}
	return n
}

// Sürükleme: eşik karesi drag_started (ve değer değişir), tutulan kare olay üretmez, bırakma drag_ended.
fn test_number_field_drag_events() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		tp.last = c.number_field_ex('n', mut &tp.value, NumberFieldOpts{ step: 1 })
	}
	nf_once(mut c, Input{}, body)
	nf_once(mut c, mouse_at(10, 10), body)
	nf_once(mut c, press_at(10, 10), body)
	nf_once(mut c, nf_held(20, 10), body)
	assert t.last.drag_started
	assert t.last.changed
	assert t.value == 2.5
	nf_once(mut c, nf_held(20, 10), body)
	assert !t.last.drag_started
	assert !t.last.changed
	assert !t.last.drag_ended
	nf_once(mut c, release_at(20, 10), body)
	assert t.last.drag_ended
	assert !t.last.drag_started
	nf_once(mut c, Input{}, body)
	assert !t.last.drag_ended
	assert !t.last.drag_started
	assert !t.last.changed
	assert !t.last.drag_cancelled
}

// Sürükleme sırasında Esc: değer başlangıca döner, drag_cancelled bildirilir; bırakma drag_ended üretmez.
fn test_number_field_drag_cancel_reports() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{
		value: 5
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		tp.last = c.number_field_ex('n', mut &tp.value, NumberFieldOpts{ step: 1 })
	}
	nf_once(mut c, Input{}, body)
	nf_once(mut c, mouse_at(10, 10), body)
	nf_once(mut c, press_at(10, 10), body)
	nf_once(mut c, nf_held(20, 10), body)
	assert t.value == 7.5
	mut esc := nf_held(20, 10)
	esc.keys[0] = .escape
	esc.key_count = 1
	nf_once(mut c, esc, body)
	assert t.last.drag_cancelled
	assert !t.last.drag_ended
	assert t.last.changed
	assert t.value == 5
	nf_once(mut c, release_at(20, 10), body)
	assert !t.last.drag_ended
	assert !t.last.drag_cancelled
	assert c.num_id == 0
	assert t.value == 5
}

// Tıkla-bırak sonrası "3" + Enter: committed ve changed birlikte bildirilir.
fn test_number_field_typed_commit_reports() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		tp.last = c.number_field_ex('n', mut &tp.value, NumberFieldOpts{})
	}
	nf_once(mut c, Input{}, body)
	nf_once(mut c, mouse_at(10, 10), body)
	nf_once(mut c, press_at(10, 10), body)
	nf_once(mut c, release_at(10, 10), body)
	assert c.num_id != 0
	nf_once(mut c, in_text('3'), body)
	assert !t.last.committed
	nf_once(mut c, in_key(.enter), body)
	assert t.last.committed
	assert t.last.changed
	assert t.value == 3
	nf_once(mut c, Input{}, body)
	assert !t.last.committed
	assert !t.last.changed
}

// Salt okunur: tıklama, sürükleme ve yazma değeri değiştirmez, odak almaz, metin text_muted çizilir.
fn test_number_field_readonly_ignores_input() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{
		value: 4
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		tp.last = c.number_field_ex('n', mut &tp.value, NumberFieldOpts{
			readonly: true
		})
	}
	nf_once(mut c, Input{}, body)
	nf_once(mut c, mouse_at(10, 10), body)
	nf_once(mut c, press_at(10, 10), body)
	assert c.focused_id() == 0
	nf_once(mut c, nf_held(60, 10), body)
	nf_once(mut c, release_at(60, 10), body)
	nf_once(mut c, mouse_at(10, 10), body)
	nf_once(mut c, press_at(10, 10), body)
	nf_once(mut c, release_at(10, 10), body)
	assert c.num_id == 0
	nf_once(mut c, in_text('9'), body)
	nf_once(mut c, in_key(.enter), body)
	assert t.value == 4
	assert !t.last.changed
	assert !t.last.drag_started
	assert !t.last.committed
	assert nf_glyphs_with(c.list, u32(text_muted)) > 0
	assert nf_glyphs_with(c.list, u32(text_primary)) == 0
}

// Hata: kenarlık danger, altında danger renkli hata metni (glifleri) bir satır olarak çizilir.
fn test_number_field_error_draws_hint() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{
		value: 2
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		tp.last = c.number_field_ex('n', mut &tp.value, NumberFieldOpts{
			error: 'Sprite.r must be in [0, 1]'
		})
	}
	nf_once(mut c, Input{}, body)
	nf_once(mut c, Input{}, body)
	assert nf_rects_with_border(c.list, u32(danger)) > 0
	assert nf_text_nodes(&c, 'Sprite.r must be in [0, 1]') == 1
	assert nf_glyphs_with(c.list, u32(danger)) > 0
}

// Odaktaki alan dışarıdan değişirse düzenleme bitene kadar kullanıcının metni görünür; Esc sonrası yeni değer.
fn test_number_field_external_change_while_editing() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{
		value: 3
	}
	mut tp := &t
	body := fn [mut tp] (mut c Context) {
		tp.last = c.number_field_ex('n', mut &tp.value, NumberFieldOpts{
			decimals: 0
		})
	}
	nf_once(mut c, Input{}, body)
	nf_once(mut c, mouse_at(10, 10), body)
	nf_once(mut c, press_at(10, 10), body)
	nf_once(mut c, release_at(10, 10), body)
	assert c.num_id != 0
	t.value = 7
	nf_once(mut c, Input{}, body)
	assert c.num_id != 0
	assert nf_text_nodes(&c, '3') == 1
	assert nf_text_nodes(&c, '7') == 0
	assert t.value == 7
	nf_once(mut c, in_key(.escape), body)
	assert c.num_id == 0
	assert t.value == 7
	nf_once(mut c, Input{}, body)
	assert nf_text_nodes(&c, '7') == 1
	assert nf_text_nodes(&c, '3') == 0
}

// Düzenleme modunda klavye yakalanır (sayı ve metin alanı); düzenleme bitince serbest.
fn test_keyboard_captured_while_editing() {
	mut atl := wgt_atlas()
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	mut t := InTally{}
	mut tp := &t

	body := fn [mut tp] (mut c Context) {
		tp.last = c.number_field_ex('n', mut &tp.value, NumberFieldOpts{})
		c.text_field('alan', mut tp.buf, 120)
	}
	nf_once(mut c, Input{}, body)
	assert !c.keyboard_captured()
	nf_once(mut c, mouse_at(10, 10), body)
	nf_once(mut c, press_at(10, 10), body)
	nf_once(mut c, release_at(10, 10), body)
	assert c.keyboard_captured()
	nf_once(mut c, in_key(.enter), body)
	assert !c.keyboard_captured()
	nf_once(mut c, in_key(.tab), body)
	assert c.focused_id() == c.id('n')
	nf_once(mut c, in_key(.tab), body)
	assert c.focused_id() == c.id('alan')
	nf_once(mut c, Input{}, body)
	assert c.keyboard_captured()
}
