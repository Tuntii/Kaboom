module ui

pub struct Rect {
pub mut:
	x f32
	y f32
	w f32
	h f32
}

fn (r Rect) contains(x f32, y f32) bool {
	return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
}

// Kesişim boşsa sıfır dikdörtgen döner.
fn (r Rect) intersect(o Rect) Rect {
	x0 := if r.x > o.x { r.x } else { o.x }
	y0 := if r.y > o.y { r.y } else { o.y }
	x1 := if r.x + r.w < o.x + o.w { r.x + r.w } else { o.x + o.w }
	y1 := if r.y + r.h < o.y + o.h { r.y + r.h } else { o.y + o.h }
	if x1 <= x0 || y1 <= y0 {
		return Rect{}
	}
	return Rect{
		x: x0
		y: y0
		w: x1 - x0
		h: y1 - y0
	}
}

pub enum Key {
	none
	tab
	enter
	escape
	backspace
	delete
	left
	right
	up
	down
	home
	end
	space
	a
	s
	y
	z
	f5
	f6
	f10
}

// Mantıksal piksel; buton 0 sol, 1 sağ, 2 orta.
pub struct Input {
pub mut:
	mouse_x    f32
	mouse_y    f32
	down       [3]bool
	pressed    [3]bool
	released   [3]bool
	wheel_y    f32
	keys       [16]Key
	key_repeat [16]bool // keys[i] bir otomatik tekrar mı (basılı tutma)
	key_count  int
	chars      [32]u32
	char_count int
	ctrl       bool
	shift      bool
	alt        bool
	space      bool // Boşluk basılı (tutulan durum; keys kenar olaylarıdır)
	time_ms    f64
}

// render bu düzeni okur: 72 bayt, alanlar sırayla bellekte.
pub enum DrawKind as u32 {
	rect
	glyph
}

pub struct DrawCmd {
pub mut:
	x            f32
	y            f32
	w            f32
	h            f32
	u0           f32
	v0           f32
	u1           f32
	v1           f32
	cx0          f32
	cy0          f32
	cx1          f32
	cy1          f32
	color        u32
	border_color u32
	radius       f32
	border       f32
	kind         u32
	pad          u32
}

// Sabit kapasiteli; kare başına tahsis yok, dolunca düşürür.
pub struct DrawList {
mut:
	cmds      []DrawCmd
	n         u32
	dropped_n u32
}

pub fn DrawList.new(cap u32) DrawList {
	return DrawList{
		cmds: []DrawCmd{len: int(cap)}
	}
}

pub fn (mut l DrawList) clear() {
	l.n = 0
}

pub fn (mut l DrawList) push(c DrawCmd) bool {
	if l.n >= u32(l.cmds.len) {
		l.dropped_n++
		return false
	}
	l.cmds[l.n] = c
	l.n++
	return true
}

pub fn (l &DrawList) len() u32 {
	return l.n
}

pub fn (l &DrawList) at(i u32) DrawCmd {
	return l.cmds[i]
}

pub fn (l &DrawList) data() voidptr {
	return l.cmds.data
}

pub fn (l &DrawList) dropped() u32 {
	return l.dropped_n
}
