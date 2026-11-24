module ui

import math

// Sanal liste: yalnız görünen satırlar (üst ve alt vl_buffer satır tamponuyla) düğüm üretir; öncesi ve
// sonrası sabit yükseklikli iki boşluk düğümü toplam içerik yüksekliğini korur (total * row_h).
// Çağıran her satırı fixed(row_h) yükseklikte açmalı ve dolgusuz kutu kullanmalıdır.
// Kaydırma ofseti kutunun etiketinin kalıcı durumundadır; scroll_to ile dışarıdan verilebilir
// (kare dışında ya da begin öncesi çağrılmalı; ofset begin'de içerik sınırına kıskaçlanır).

const vl_buffer = 2

pub struct VirtualList {
pub:
	first int // ilk çizilecek satır dizini
	count int // çizilecek satır sayısı (first .. first+count)
}

// Kaydırma kutusunu açar (kutu scroll_y olarak açılır), görünür aralığı hesaplar ve öncesi boşluğu ekler.
// Görünüm yüksekliği sabit boyutlu kutuda b.height'tan, değilse önceki karenin kutusundan alınır.
pub fn (mut c Context) virtual_list_begin(label string, total int, row_h f32, b Box) VirtualList {
	assert row_h > 0, 'ui: sanal liste satır yüksekliği pozitif olmalı'
	id := c.id(label)
	view := if b.height.kind == .fixed { b.height.value } else { (c.prev_rect(id) or { Rect{ h: c.vh } }).h }
	c.open(label, Box{
		dir:         .column
		width:       b.width
		height:      b.height
		align_cross: b.align_cross
		bg:          b.bg
		border:      b.border
		border_w:    b.border_w
		radius:      b.radius
		clip:        true
		scroll_y:    true
	})
	h := c.probe(id)
	mut off := f32(0)
	has_state := h >= 0 && c.states[h].id == id
	if has_state {
		off = c.states[h].scroll
	}
	content := f32(total) * row_h
	max_off := if content > view { content - view } else { f32(0) }
	if off > max_off {
		off = max_off
	}
	if off < 0 {
		off = 0
	}
	if has_state {
		c.states[h].scroll = off
	}
	mut first := 0
	mut stop := 0
	if total > 0 {
		first_vis := int(math.floor(f64(off / row_h)))
		last_vis := int(math.ceil(f64((off + view) / row_h)))
		first = clamp_int(first_vis - vl_buffer, 0, total)
		stop = clamp_int(last_vis + vl_buffer, 0, total)
	}
	count := if stop > first { stop - first } else { 0 }
	c.leaf(.plain, Box{
		width:  grow()
		height: fixed(f32(first) * row_h)
	})
	c.vl_bottom = f32(total - first - count) * row_h
	return VirtualList{
		first: first
		count: count
	}
}

// Alt boşluğu ekler ve kaydırma kutusunu kapatır.
pub fn (mut c Context) virtual_list_end() {
	c.leaf(.plain, Box{
		width:  grow()
		height: fixed(c.vl_bottom)
	})
	c.close()
}

// Kaydırma ofseti (piksel). Etiket begin'deki gibi çözülür; liste yoksa 0.
pub fn (c &Context) scroll_offset(label string) f32 {
	id := c.id(label)
	h := c.probe(id)
	if h < 0 || c.states[h].id != id {
		return 0
	}
	return c.states[h].scroll
}

// Kaydırma ofsetini verir; sonraki karede begin içerik sınırına kıskaçlar.
pub fn (mut c Context) scroll_to(label string, offset f32) {
	id := c.id(label)
	h := c.touch(id)
	if h >= 0 {
		c.states[h].scroll = if offset < 0 { f32(0) } else { offset }
	}
}

fn clamp_int(v int, lo int, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
