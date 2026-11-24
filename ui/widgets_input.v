module ui

import math

// Sürüklemede adım/4 mantıksal piksel başına bir adım (Shift ×10).
const drag_px_div = f32(4)

// UTF-8 metin tamponu; kapasite sabit, tahsis yok. Uzunluk bayt cinsinden.
pub struct TextBuf {
pub mut:
	data [256]u8
	len  int
}

// Tahsissiz görünüm: tampona bakar, kopyalamaz (çağıran karede tamponu değiştirmemeli).
pub fn (b &TextBuf) str() string {
	return unsafe { tos(&b.data[0], b.len) }
}

// Sığmayan son kod noktası atlanır; tampon kod noktası ortasında kesilmez.
pub fn (mut b TextBuf) set(s string) {
	mut n := if s.len < b.data.len { s.len } else { b.data.len }
	for n > 0 && n < s.len && (s[n] & 0xC0) == 0x80 {
		n--
	}
	for i in 0 .. n {
		b.data[i] = s[i]
	}
	b.len = n
}

fn (b &TextBuf) prev(cur int) int {
	mut p := cur - 1
	for p > 0 && (b.data[p] & 0xC0) == 0x80 {
		p--
	}
	return p
}

fn (b &TextBuf) next(cur int) int {
	mut n := cur + 1
	for n < b.len && (b.data[n] & 0xC0) == 0x80 {
		n++
	}
	return n
}

// [from, to) aralığını siler.
fn (mut b TextBuf) cut(from int, to int) {
	for i in to .. b.len {
		b.data[from + i - to] = b.data[i]
	}
	b.len -= to - from
}

// Kod noktasını imleç konumuna ekler; sığmazsa (false, cur) döner ve tampon değişmez.
fn (mut b TextBuf) insert(cur int, cp u32) (bool, int) {
	mut tmp := [4]u8{}
	n := utf8_put(cp, mut tmp)
	if b.len + n > b.data.len {
		return false, cur
	}
	for i := b.len - 1; i >= cur; i-- {
		b.data[i + n] = b.data[i]
	}
	for i in 0 .. n {
		b.data[cur + i] = tmp[i]
	}
	b.len += n
	return true, cur + n
}

fn utf8_put(cp u32, mut out [4]u8) int {
	if cp < 0x80 {
		out[0] = u8(cp)
		return 1
	}
	if cp < 0x800 {
		out[0] = u8(0xC0 | (cp >> 6))
		out[1] = u8(0x80 | (cp & 0x3F))
		return 2
	}
	if cp < 0x10000 {
		out[0] = u8(0xE0 | (cp >> 12))
		out[1] = u8(0x80 | ((cp >> 6) & 0x3F))
		out[2] = u8(0x80 | (cp & 0x3F))
		return 3
	}
	out[0] = u8(0xF0 | (cp >> 18))
	out[1] = u8(0x80 | ((cp >> 12) & 0x3F))
	out[2] = u8(0x80 | ((cp >> 6) & 0x3F))
	out[3] = u8(0x80 | (cp & 0x3F))
	return 4
}

// Ondalık sayının bayt biçimi: nan, inf, -inf; sıfırın işareti yok. Tahsissiz.
// shortcut: 32 bayta sığmayan (1e31 üstü) tam kısım baştan kırpılır, ihtiyaç olursa üssel biçim eklenir
pub fn format_f32(v f32, decimals int, mut out [32]u8) int {
	x := f64(v)
	if x != x {
		return put_lit(mut out, 'nan')
	}
	if x > 3.4028235e38 {
		return put_lit(mut out, 'inf')
	}
	if x < -3.4028235e38 {
		return put_lit(mut out, '-inf')
	}
	d := if decimals < 0 { 0 } else if decimals > 9 { 9 } else { decimals }
	scale := f64(u64(1)) * math.pow(10, f64(d))
	a := math.abs(x)
	mut ip := math.floor(a)
	mut fr := u64(math.round((a - ip) * scale))
	if f64(fr) >= scale {
		ip += 1
		fr = 0
	}
	neg := x < 0 && (ip > 0 || fr > 0)
	mut digits := [32]u8{}
	mut k := 0
	mut q := ip
	for {
		dg := q - math.floor(q / 10) * 10
		digits[k] = u8(48 + int(dg))
		k++
		q = math.floor(q / 10)
		if q < 1 || k == digits.len {
			break
		}
	}
	mut n := 0
	if neg {
		out[n] = `-`
		n++
	}
	for j := k - 1; j >= 0 && n < out.len; j-- {
		out[n] = digits[j]
		n++
	}
	if d > 0 && n + 1 + d <= out.len {
		out[n] = `.`
		n++
		mut f := fr
		mut j := d - 1
		for j >= 0 {
			out[n + j] = u8(48 + int(f % 10))
			f /= 10
			j--
		}
		n += d
	}
	return n
}

fn put_lit(mut out [32]u8, s string) int {
	for i in 0 .. s.len {
		out[i] = s[i]
	}
	return s.len
}

// Ayrıştırma: [+-] rakam [. rakam] [eE [+-] rakam]; başka her şey none. Tahsissiz.
pub fn parse_f32(s string) ?f32 {
	mut i := 0
	mut neg := false
	if i < s.len && (s[i] == `-` || s[i] == `+`) {
		neg = s[i] == `-`
		i++
	}
	mut mant := f64(0)
	mut digits := 0
	mut frac := 0
	for i < s.len && s[i] >= `0` && s[i] <= `9` {
		mant = mant * 10 + f64(s[i] - `0`)
		digits++
		i++
	}
	if i < s.len && (s[i] == `.` || s[i] == `,`) { // Türkçe numpad ondalık virgülü
		i++
		for i < s.len && s[i] >= `0` && s[i] <= `9` {
			mant = mant * 10 + f64(s[i] - `0`)
			digits++
			frac++
			i++
		}
	}
	if digits == 0 {
		return none
	}
	mut exp := 0
	if i < s.len && (s[i] == `e` || s[i] == `E`) {
		i++
		mut eneg := false
		if i < s.len && (s[i] == `-` || s[i] == `+`) {
			eneg = s[i] == `-`
			i++
		}
		mut ed := 0
		for i < s.len && s[i] >= `0` && s[i] <= `9` {
			exp = exp * 10 + int(s[i] - `0`)
			ed++
			i++
		}
		if ed == 0 {
			return none
		}
		if eneg {
			exp = -exp
		}
	}
	if i != s.len {
		return none
	}
	e := exp - frac
	v := if e >= 0 { mant * math.pow(10, f64(e)) } else { mant / math.pow(10, f64(-e)) }
	r := f32(if neg { -v } else { v })
	return r
}

// Düzenleme tuş ve karakterlerinin sonucu.
struct EditOut {
mut:
	changed bool
	enter   bool
	esc     bool
}

// Karakter ve tuşları tampona uygular; imleç bayt konumu kod noktası sınırında kalır.
fn edit_keys(mut buf TextBuf, cur0 int, inp Input) (EditOut, int) {
	mut out := EditOut{}
	mut cur := cur0
	if cur > buf.len {
		cur = buf.len
	}
	for i in 0 .. inp.char_count {
		cp := inp.chars[i]
		if cp < 32 || cp == 127 {
			continue
		}
		ok, nc := buf.insert(cur, cp)
		if ok {
			out.changed = true
			cur = nc
		}
	}
	for i in 0 .. inp.key_count {
		// Otomatik tekrar yalnızca düzenleme tuşlarında (ok, Backspace, Delete, Home, End) etkili.
		if inp.key_repeat[i] && (inp.keys[i] == .enter || inp.keys[i] == .escape) {
			continue
		}
		match inp.keys[i] {
			.enter {
				out.enter = true
			}
			.escape {
				out.esc = true
			}
			.backspace {
				if cur > 0 {
					p := buf.prev(cur)
					buf.cut(p, cur)
					cur = p
					out.changed = true
				}
			}
			.delete {
				if cur < buf.len {
					n := buf.next(cur)
					buf.cut(cur, n)
					out.changed = true
				}
			}
			.left {
				if cur > 0 {
					cur = buf.prev(cur)
				}
			}
			.right {
				if cur < buf.len {
					cur = buf.next(cur)
				}
			}
			.home {
				cur = 0
			}
			.end {
				cur = buf.len
			}
			else {}
		}
	}
	return out, cur
}

// Metni değiştiren girdi var mı (yazılabilir karakter, Backspace, Delete).
fn edit_hits(inp Input) bool {
	for i in 0 .. inp.char_count {
		if inp.chars[i] >= 32 && inp.chars[i] != 127 {
			return true
		}
	}
	for i in 0 .. inp.key_count {
		if inp.keys[i] == .backspace || inp.keys[i] == .delete {
			return true
		}
	}
	return false
}

// Odaktaki alan: imleç metni böler, imleç 1 px text_primary; odakta değilse tek parça.
fn (mut c Context) field_text(buf &TextBuf, cur int, role TextRole, color Color, caret bool) {
	if !caret {
		c.text(buf.str(), role, color)
		return
	}
	c.text(unsafe { tos(&buf.data[0], cur) }, role, color)
	lh := c.atl.line_height(role)
	c.leaf(.plain, Box{
		width:  fixed(1)
		height: fixed(lh)
		bg:     text_primary
	})
	after := if cur < buf.len { unsafe { tos(&buf.data[cur], buf.len - cur) } } else { '' }
	c.text(after, role, color)
}

// Metin alanı iç genişliği: kenar boşlukları ve 1 px imleç düşülür.
fn text_inner(width f32) f32 {
	return width - 2 * space_2 - 1
}

fn (mut c Context) begin_num(id u32, v f32, decimals int) {
	mut tmp := [32]u8{}
	n := format_f32(v, decimals, mut tmp)
	c.num_buf.set(unsafe { tos(&tmp[0], n) })
	c.num_cur = c.num_buf.len
	c.num_fresh = true
	c.num_id = id
}

// Düzenleme bitince sayı alanı odaktan da çıkar (Enter, Esc ya da odak kaybı).
fn (mut c Context) end_num(id u32) {
	c.num_id = 0
	if c.focus == id {
		c.focus = 0
	}
}

// min == max == 0 sınırsız.
fn num_clamp(v f32, min f32, max f32) f32 {
	if min == 0 && max == 0 {
		return v
	}
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

// Metin alanı: odaklıyken yazılır; Enter onaylar (true), Esc odak anındaki metne döner.
// Yatay kaydırma: imleç iç genişlikte kalır (kalıcı ofset, kutu scroll_x ile uygular).
pub fn (mut c Context) text_field(label string, mut buf TextBuf, width f32) bool {
	id := c.id(label)
	it := c.interact_kb(id, true, false, true)
	if it.focused {
		if c.txt_id != id {
			c.txt_id = id
			c.txt_snap = buf
			c.txt_cur = buf.len
		}
	} else if c.txt_id == id {
		c.txt_id = 0
	}
	mut enter := false
	if it.focused {
		r, nc := edit_keys(mut buf, c.txt_cur, c.inp)
		c.txt_cur = nc
		enter = r.enter
		if r.esc {
			buf = c.txt_snap
			c.txt_cur = buf.len
			c.txt_id = 0
			if c.focus == id {
				c.focus = 0
			}
		}
	}
	// Kaydırma ofseti, düzen geçişinden önce: imleç soldan ya da sağdan taşarsa kenara yapıştırılır.
	h := c.touch(id)
	if h >= 0 {
		mut sc := f32(0)
		if c.txt_id == id {
			cx := c.atl.measure(unsafe { tos(&buf.data[0], c.txt_cur) }, .body)
			inner := text_inner(width)
			sc = c.states[h].scroll
			if cx - sc < 0 {
				sc = cx
			}
			if cx - sc > inner {
				sc = cx - inner
			}
		}
		c.states[h].scroll = sc
	}
	c.open(label, Box{
		dir:         .row
		width:       fixed(width)
		height:      fixed(control_h)
		padding:     pad_xy(space_2, 0)
		align_cross: .center
		bg:          surface_2
		border:      if it.focused { accent } else { border_strong }
		border_w:    1
		radius:      radius_control
		clip:        true
		scroll_x:    true
	})
	c.field_text(&buf, c.txt_cur, .body, text_primary, c.txt_id == id)
	c.close()
	return enter
}

// Sayı alanı olayları: bu karede ne oldu (sürükleme olayları ilgili karede, değişiklik her karede).
pub struct NumberFieldResult {
pub mut:
	changed        bool // bu karede değer değişti (sürükleme her karesi ya da yazılı onay)
	drag_started   bool // eşik aşıldığı kare
	drag_ended     bool // sürükleme normal bitti (fare bırakıldı)
	drag_cancelled bool // sürükleme sırasında Esc: değer sürükleme başlangıcına döndü
	committed      bool // yazılı düzenleme Enter ya da odak kaybıyla uygulandı
}

// Sayı alanı seçenekleri. min == max == 0 sınırsız; error doluysa alan danger kenarlıkla ve altında hata satırıyla çizilir.
pub struct NumberFieldOpts {
pub:
	unit     string
	decimals int = 2
	step     f32 = f32(0.1)
	min      f32
	max      f32
	readonly bool   // odaklanmaz, sürüklenmez, düzenlenmez; metin text_muted
	error    string // çağıranın sahip olduğu metin; kare başına tahsis yok
}

// Sayı alanı: yatay sürükleme değeri değiştirir; tıklayıp bırakma düzenleme moduna geçer.
// Değer her zaman decimals basamakla gösterilir ("-4.00"). Etiket alanın dışında çizilir (property_row_begin).
// Enter ayrıştırıp uygular; ayrıştırılamazsa eski değer kalır. Değer değiştiyse true.
// Odak başka alana geçerse bekleyen düzenleme aynı kare uygulanır (commit on blur).
pub fn (mut c Context) number_field(label string, mut value &f32, unit string, decimals int, step f32, min f32, max f32) bool {
	return c.number_field_ex(label, mut value, NumberFieldOpts{
		unit:     unit
		decimals: decimals
		step:     step
		min:      min
		max:      max
	}).changed
}

// number_field'ın olay raporlu biçimi; sürükleme başlangıcı ve Esc iptali alan durumunda tutulur.
pub fn (mut c Context) number_field_ex(label string, mut value &f32, o NumberFieldOpts) NumberFieldResult {
	id := c.id(label)
	h := c.touch(id)
	mut r := NumberFieldResult{}
	mut it := Interaction{}
	if o.readonly {
		if c.active == id {
			c.active = 0
		}
		if c.num_id == id {
			c.num_id = 0
		}
		if c.focus == id {
			c.focus = 0
			c.focus_visible = false
		}
	} else {
		it = c.interact_kb(id, true, c.num_id != id, true)
	}
	editing := c.num_id == id
	if c.inp.pressed[0] && it.hovered {
		c.num_moved = false
	}
	cur := unsafe { *value }
	mut v := cur
	if it.dragging && !editing {
		v = c.num_drag(h, cur, it.drag_dx, o, mut r)
	}
	// Sürükleme bitti (bırakıldı ya da hiç başlamadı): başlangıç ve iptal bayrakları silinir.
	if h >= 0 && !it.dragging {
		if c.states[h].flag(off_num_drag) {
			c.states[h].set_flag(off_num_drag, false)
			r.drag_ended = true
		}
		c.states[h].set_flag(off_num_cancel, false)
	}
	if it.clicked && !c.num_moved && !editing {
		c.begin_num(id, cur, o.decimals)
	}
	if editing {
		if c.num_fresh && edit_hits(c.inp) {
			c.num_buf.len = 0
			c.num_cur = 0
			c.num_fresh = false
		}
		e, nc := edit_keys(mut c.num_buf, c.num_cur, c.inp)
		c.num_cur = nc
		// Enter, Esc ya da odak kaybı düzenlemeyi bitirir; Esc değeri değiştirmez.
		if e.enter || !it.focused {
			if nv := parse_f32(c.num_buf.str()) {
				v = num_clamp(nv, o.min, o.max)
				r.committed = true
			}
			c.end_num(id)
		} else if e.esc {
			c.end_num(id)
		}
	}
	if it.clicked {
		c.num_moved = false
	}
	r.changed = v != cur
	if r.changed {
		unsafe {
			*value = v
		}
	}
	k := c.num_n % c.num_bufs.len
	c.num_n++
	n := format_f32(v, o.decimals, mut c.num_bufs[k])
	ro := o.readonly
	err := o.error.len > 0
	// Özellik satırında panelin kalanını doldurur; tek başınayken sabit genişlik.
	w := if c.in_prop { grow() } else { fixed(num_field_w) }
	if err {
		// Hata satırı alanın altına girer; kapsayıcının kimliği alan kimliğinden türer (etiket çakışmaz).
		c.push_id(int(id))
		c.open('num_err', Box{
			dir:    .column
			width:  grow()
			height: fit()
		})
		c.pop_id()
	}
	edge := if err {
		danger
	} else if it.focused && !ro {
		accent
	} else {
		border_strong
	}
	c.open(label, Box{
		dir:         .row
		width:       w
		height:      fixed(control_h)
		padding:     pad_xy(space_2, 0)
		gap:         space_2
		align_cross: .center
		bg:          surface_2
		border:      edge
		border_w:    1
		radius:      radius_control
		clip:        true
	})
	fg := if ro { text_muted } else { text_primary }
	if c.num_id == id {
		c.field_text(&c.num_buf, c.num_cur, .mono, fg, true)
	} else {
		c.text(unsafe { tos(&c.num_bufs[k][0], n) }, .mono, fg)
	}
	c.spacer()
	if o.unit.len > 0 {
		c.text(o.unit, .body, if ro { text_muted } else { text_secondary })
	}
	c.close()
	if err {
		c.text(o.error, .caption, danger)
		c.close()
	}
	return r
}

// Sürükleme adımı: eşik karesinde başlangıç değeri alan durumuna yazılır; Esc başlangıca döndürür ve iptal bayrağını kurar.
// Esc sonrası basılı tutuluyorsa değer değişmez (bırakılana dek sürükleme yok).
fn (mut c Context) num_drag(h int, cur f32, dx f32, o NumberFieldOpts, mut r NumberFieldResult) f32 {
	c.num_moved = true
	if h >= 0 && c.states[h].flag(off_num_cancel) {
		return cur
	}
	if h >= 0 && !c.states[h].flag(off_num_drag) {
		c.states[h].set_flag(off_num_drag, true)
		c.states[h].set_f32(off_num_v0, cur)
		r.drag_started = true
	}
	if h >= 0 && c.key_pressed(.escape) {
		c.states[h].set_flag(off_num_drag, false)
		c.states[h].set_flag(off_num_cancel, true)
		r.drag_cancelled = true
		return c.states[h].f32_at(off_num_v0)
	}
	mult := if c.inp.shift { f32(10) } else { f32(1) }
	return num_clamp(cur + dx * o.step / drag_px_div * mult, o.min, o.max)
}

// Rengin opaklığını a (0..1) ile çarpar; menü açılışı için.
fn fade(col Color, a f32) Color {
	al := f32(u32(col) & 0xFF) * a
	return col.with_alpha(u8(math.round(f64(al))))
}

// Açılır menü düğmesi: açık durumu kalıcı; açıksa true, çağıran menu_item'ları ve menu_end'i çağırır.
// Dışarı basış ya da Esc kapatır; açılış opaklığı ve kayması motion_ms içinde.
pub fn (mut c Context) menu_button(label string, text string) bool {
	return c.menu_button_ex(label, text, fit(), none)
}

// Tetikleyici genişliği ve baştaki ikon verilebilir; menü genişliği max(tetikleyici, menu_min_w).
pub fn (mut c Context) menu_button_ex(label string, text string, width Size, lead ?Icon) bool {
	id := c.id(label)
	it := c.interact(id, true)
	c.push_id(1)
	mid := c.id(label)
	c.pop_id()
	h := c.touch(id)
	mut open := h >= 0 && c.states[h].flag(off_open)
	menu_r := c.prev_rect(mid) or { Rect{} }
	if it.clicked {
		open = !open
	} else if open && (c.key_pressed(.escape) || (c.inp.pressed[0] && !it.hovered && !menu_r.contains(c.inp.mouse_x, c.inp.mouse_y))) {
		open = false
	}
	if h >= 0 {
		c.states[h].set_flag(off_open, open)
	}
	c.menu_cur = id
	t := c.hover_t(mid, open)
	c.menu_alpha = t
	bt := c.hover_t(id, it.hovered)
	bg, fg, edge, edge_w := button_style(.secondary, true, bt)
	c.open(label, Box{
		dir:         .row
		width:       width
		height:      fixed(control_h)
		padding:     pad_xy(space_3, 0)
		gap:         space_2
		align_cross: .center
		bg:          bg
		border:      edge
		border_w:    edge_w
		radius:      radius_control
	})
	if i := lead {
		c.icon(i, text_secondary)
	}
	c.text(text, .body_strong, fg)
	c.close()
	if open {
		b := c.prev_rect(id) or { Rect{} }
		menu_w := if b.w > menu_min_w { b.w } else { menu_min_w }
		c.push_id(1)
		c.overlay(label, b.x, b.y + b.h + space_1 - menu_slide * (1 - t), Box{
			dir:      .column
			width:    fixed(menu_w)
			height:   fit()
			padding:  pad_all(space_1)
			bg:       fade(surface_2, t)
			border:   fade(border_strong, t)
			border_w: 1
			radius:   radius_menu
		})
		c.pop_id()
	}
	return open
}

// Yukarıdan kayma (px); menü açılışında 0'a iner.
const menu_slide = space_1

// Menü öğesi: tıklanınca true ve menü kapanır.
pub fn (mut c Context) menu_item(text string) bool {
	c.push_id(2)
	iid := c.id(text)
	it := c.interact(iid, true)
	t := c.hover_t(iid, it.hovered)
	c.open(text, Box{
		dir:         .row
		width:       grow()
		height:      fixed(row_h)
		padding:     pad_xy(space_2, 0)
		align_cross: .center
		bg:          fade(mix(surface_hover.with_alpha(0), surface_hover, t), c.menu_alpha)
		radius:      radius_control
	})
	c.pop_id()
	c.text(text, .body, fade(text_primary, c.menu_alpha))
	c.close()
	if it.clicked {
		h := c.touch(c.menu_cur)
		if h >= 0 {
			c.states[h].set_flag(off_open, false)
		}
	}
	return it.clicked
}

pub fn (mut c Context) menu_end() {
	c.close()
}

// İpucu: son açılan kutunun üzerinde tooltip_delay_ms durunca kutunun 8 px altında, sol kenarı hizalı gösterilir.
pub fn (mut c Context) tooltip(text string) {
	if c.last_id == 0 {
		return
	}
	h := c.touch(c.last_id)
	if h < 0 {
		return
	}
	now := c.inp.time_ms
	mut s := &c.states[h]
	if c.hit_prev != c.last_id {
		s.tip_on = false
		return
	}
	if !s.tip_on {
		s.tip_on = true
		s.tip_since = now
	}
	if now - s.tip_since < tooltip_delay_ms {
		return
	}
	c.tip_shown = true
	r := c.prev_rect(c.last_id) or { Rect{} }
	c.overlay('tooltip', r.x, r.y + r.h + space_2, Box{
		dir:      .column
		width:    fit()
		height:   fit()
		padding:  pad_xy(space_2, space_1)
		bg:       surface_2
		border:   border_strong
		border_w: 1
		radius:   radius_control
	})
	c.text(text, .caption, text_primary)
	c.close()
}
