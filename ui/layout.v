module ui

import math

pub enum Dir {
	row
	column
}

pub enum Align {
	start
	center
	end
	between
}

pub enum SizeKind {
	fit
	fixed
	grow
	percent
}

// max == 0 sınırsız.
pub struct Size {
pub:
	kind  SizeKind
	value f32
	min   f32
	max   f32
}

pub fn fit() Size {
	return Size{
		kind: .fit
	}
}

pub fn fixed(v f32) Size {
	return Size{
		kind:  .fixed
		value: v
	}
}

pub fn grow() Size {
	return Size{
		kind: .grow
	}
}

pub fn percent(p f32) Size {
	return Size{
		kind:  .percent
		value: p
	}
}

pub struct Pad {
pub:
	l f32
	t f32
	r f32
	b f32
}

pub fn pad_all(v f32) Pad {
	return Pad{
		l: v
		t: v
		r: v
		b: v
	}
}

pub fn pad_xy(x f32, y f32) Pad {
	return Pad{
		l: x
		t: y
		r: x
		b: y
	}
}

pub struct Box {
pub:
	dir         Dir
	width       Size
	height      Size
	padding     Pad
	gap         f32
	align_main  Align
	align_cross Align
	bg          Color
	border      Color
	border_w    f32
	radius      f32
	clip        bool
	scroll_y    bool
}

enum NodeKind {
	plain
	text
	icon
}

// Düğümler oluşturulma sırasında (ebeveyn önce) dizilir; sıra düzen geçişlerini belirler.
struct Node {
mut:
	id      u32
	box     Box
	kind    NodeKind
	parent  int
	first   int
	last    int
	next    int
	slot    int
	is_root bool
	frozen  bool // grow dağıtımında min/max ile sabitlendi
	text    string
	role    TextRole
	icon    Icon
	color   Color
	content [2]f32 // çocuksuz yaprakların doğal boyutu; kapsayıcılarda çocuklardan hesaplanır
	intr    [2]f32 // ebeveynin hesaba katacağı boyut (min/max kıskaçlı)
	sz      [2]f32
	pos     [2]f32
}

// Eksen 0 = x (genişlik), 1 = y (yükseklik).
fn axis_size(b Box, a int) Size {
	return if a == 0 { b.width } else { b.height }
}

fn axis_pad(p Pad, a int) f32 {
	return if a == 0 { p.l + p.r } else { p.t + p.b }
}

fn is_main(d Dir, a int) bool {
	return (d == .row) == (a == 0)
}

fn clamp_size(s Size, v f32) f32 {
	mut r := v
	if r < s.min {
		r = s.min
	}
	if s.max > 0 && r > s.max {
		r = s.max
	}
	if r < 0 {
		r = 0
	}
	return r
}

// Sabit ve içerik boyutu yerinde kalır; grow ebeveyn, percent oranı kadar alır.
fn resolve_size(s Size, intr f32, avail f32) f32 {
	return match s.kind {
		.fixed, .fit { intr }
		.grow { clamp_size(s, avail) }
		.percent { clamp_size(s, s.value * avail) }
	}
}

fn intr_of(s Size, content f32, pad f32) f32 {
	v := match s.kind {
		.fixed { s.value }
		.fit { content + pad }
		else { f32(0) }
	}

	return clamp_size(s, v)
}

fn align_offset(a Align, free f32) f32 {
	return match a {
		.center { free / 2 }
		.end { free }
		else { f32(0) }
	}
}

fn snap(v f32) f32 {
	return f32(math.round(f64(v)))
}

// Ölçü, ebeveynden aşağı: önce doğal boyutlar yukarı, sonra kalan alan aşağı.
fn (mut c Context) layout() {
	for a in 0 .. 2 {
		c.measure_axis(a)
		c.fit_axis(a)
	}
	c.place()
}

// Alttan yukarı (ters oluşturma sırası): doğal boyutları hesaplar.
fn (mut c Context) measure_axis(a int) {
	for i := c.n - 1; i >= 0; i-- {
		mut nd := &c.nodes[i]
		mut content := nd.content[a]
		if nd.first >= 0 {
			content = 0
			main := is_main(nd.box.dir, a)
			mut cnt := 0
			mut ch := nd.first
			for ch >= 0 {
				v := c.nodes[ch].intr[a]
				if main {
					content += v
				} else if v > content {
					content = v
				}
				cnt++
				ch = c.nodes[ch].next
			}
			if main && cnt > 1 {
				content += nd.box.gap * f32(cnt - 1)
			}
		}
		nd.content[a] = content
		nd.intr[a] = intr_of(axis_size(nd.box, a), content, axis_pad(nd.box.padding, a))
	}
}

// Yukarıdan aşağı: kökleri ve çocukları ebeveyn alanına göre boyutlandırır.
fn (mut c Context) fit_axis(a int) {
	for i in 0 .. c.n {
		mut nd := &c.nodes[i]
		if nd.is_root {
			avail := if a == 0 { c.vw } else { c.vh }
			nd.sz[a] = resolve_size(axis_size(nd.box, a), nd.intr[a], avail)
		}
		if nd.first < 0 {
			continue
		}
		main := is_main(nd.box.dir, a)
		inner := nd.sz[a] - axis_pad(nd.box.padding, a)
		mut cnt := 0
		mut grow_n := 0
		mut fixed_sum := f32(0)
		mut ch := nd.first
		for ch >= 0 {
			cnt++
			s := axis_size(c.nodes[ch].box, a)
			if s.kind == .grow {
				grow_n++
			} else if main {
				fixed_sum += resolve_size(s, c.nodes[ch].intr[a], inner)
			}
			ch = c.nodes[ch].next
		}
		if main && grow_n > 0 {
			c.distribute_grow(nd.first, inner - fixed_sum - nd.box.gap * f32(cnt - 1), a)
		}
		ch = nd.first
		for ch >= 0 {
			s := axis_size(c.nodes[ch].box, a)
			if !main || s.kind != .grow {
				c.nodes[ch].sz[a] = resolve_size(s, c.nodes[ch].intr[a], inner)
			}
			ch = c.nodes[ch].next
		}
	}
}

// Ana eksende grow payları: min/max ile sabitlenen çocuklar düşülür, kalan alan yeniden paylaşılır; yeni sabitleme kalmayınca biter.
fn (mut c Context) distribute_grow(first int, rem f32, a int) {
	mut ch := first
	for ch >= 0 {
		c.nodes[ch].frozen = false
		ch = c.nodes[ch].next
	}
	for {
		mut free_n := 0
		mut used := f32(0)
		ch = first
		for ch >= 0 {
			if axis_size(c.nodes[ch].box, a).kind == .grow {
				if c.nodes[ch].frozen {
					used += c.nodes[ch].sz[a]
				} else {
					free_n++
				}
			}
			ch = c.nodes[ch].next
		}
		if free_n == 0 {
			return
		}
		share := if rem - used > 0 { (rem - used) / f32(free_n) } else { f32(0) }
		mut changed := false
		ch = first
		for ch >= 0 {
			s := axis_size(c.nodes[ch].box, a)
			if s.kind == .grow && !c.nodes[ch].frozen {
				v := clamp_size(s, share)
				if v != share {
					c.nodes[ch].frozen = true
					c.nodes[ch].sz[a] = v
					changed = true
				}
			}
			ch = c.nodes[ch].next
		}
		if !changed {
			ch = first
			for ch >= 0 {
				if axis_size(c.nodes[ch].box, a).kind == .grow && !c.nodes[ch].frozen {
					c.nodes[ch].sz[a] = share
				}
				ch = c.nodes[ch].next
			}
			return
		}
	}
}

// Konumlar: padding, gap, hizalama ve kaydırma ofseti (kalıcı durumda, [0, içerik-kutu] aralığına kıskaçlı).
fn (mut c Context) place() {
	for i in 0 .. c.n {
		mut nd := &c.nodes[i]
		if nd.first < 0 {
			continue
		}
		p := nd.box.padding
		main_x := nd.box.dir == .row
		gap := nd.box.gap
		inner_w := nd.sz[0] - p.l - p.r
		inner_h := nd.sz[1] - p.t - p.b
		main_inner := if main_x { inner_w } else { inner_h }
		cross_inner := if main_x { inner_h } else { inner_w }
		mut cnt := 0
		mut total := f32(0)
		mut cross_max := f32(0)
		mut ch := nd.first
		for ch >= 0 {
			cnt++
			mv := if main_x { c.nodes[ch].sz[0] } else { c.nodes[ch].sz[1] }
			cv := if main_x { c.nodes[ch].sz[1] } else { c.nodes[ch].sz[0] }
			total += mv
			if cv > cross_max {
				cross_max = cv
			}
			ch = c.nodes[ch].next
		}
		total += gap * f32(cnt - 1)
		free := main_inner - total
		mut prog := align_offset(nd.box.align_main, free)
		mut extra := f32(0)
		if nd.box.align_main == .between && cnt > 1 && free > 0 {
			extra = free / f32(cnt - 1)
		}
		mut off := f32(0)
		if nd.box.scroll_y && nd.slot >= 0 {
			content := (if main_x { cross_max } else { total }) + p.t + p.b
			max_off := if content > nd.sz[1] { content - nd.sz[1] } else { f32(0) }
			off = c.states[nd.slot].scroll
			if off > max_off {
				off = max_off
			}
			if off < 0 {
				off = 0
			}
			c.states[nd.slot].scroll = off
		}
		ch = nd.first
		for ch >= 0 {
			mut cn := &c.nodes[ch]
			mv := if main_x { cn.sz[0] } else { cn.sz[1] }
			cv := if main_x { cn.sz[1] } else { cn.sz[0] }
			cross := align_offset(nd.box.align_cross, cross_inner - cv)
			if main_x {
				cn.pos[0] = nd.pos[0] + p.l + prog
				cn.pos[1] = nd.pos[1] + p.t + cross - off
			} else {
				cn.pos[0] = nd.pos[0] + p.l + cross
				cn.pos[1] = nd.pos[1] + p.t + prog - off
			}
			prog += mv + gap + extra
			ch = cn.next
		}
	}
}

fn (mut c Context) paint(i int, clip Rect) {
	r := Rect{
		x: c.nodes[i].pos[0]
		y: c.nodes[i].pos[1]
		w: c.nodes[i].sz[0]
		h: c.nodes[i].sz[1]
	}
	// Boş kırpma: alt ağaç çizilmez, boş kırpmalı komut üretilmez.
	if clip.w <= 0 || clip.h <= 0 {
		return
	}
	b := c.nodes[i].box
	child_clip := if b.clip { clip.intersect(r) } else { clip }
	vis := clip.intersect(r)
	if vis.w > 0 && vis.h > 0 {
		if (u32(b.bg) & 0xFF) != 0 || (b.border_w > 0 && (u32(b.border) & 0xFF) != 0) {
			c.emit_rect(r, clip, b)
		}
		match c.nodes[i].kind {
			.text { c.emit_text(i, clip) }
			.icon { c.emit_icon(i, clip) }
			.plain {}
		}
	}

	mut ch := c.nodes[i].first
	for ch >= 0 {
		c.paint(ch, child_clip)
		ch = c.nodes[ch].next
	}
}

// Kenarlar fiziksel piksele yuvarlanır; komut sırası çizim sırası.
fn (mut c Context) emit_rect(r Rect, clip Rect, b Box) {
	sc := c.scale
	x0 := snap(r.x * sc)
	y0 := snap(r.y * sc)
	x1 := snap((r.x + r.w) * sc)
	y1 := snap((r.y + r.h) * sc)
	wu, hu := c.atl.white_uv()
	c.list.push(DrawCmd{
		x:            x0
		y:            y0
		w:            x1 - x0
		h:            y1 - y0
		u0:           wu
		v0:           hu
		u1:           wu
		v1:           hu
		cx0:          snap(clip.x * sc)
		cy0:          snap(clip.y * sc)
		cx1:          snap((clip.x + clip.w) * sc)
		cy1:          snap((clip.y + clip.h) * sc)
		color:        u32(b.bg)
		border_color: u32(b.border)
		radius:       b.radius * sc
		border:       b.border_w * sc
		kind:         u32(DrawKind.rect)
	})
}

fn (mut c Context) emit_glyph(g Glyph, ox f32, oy f32, color u32, clip Rect) {
	sc := c.scale
	c.list.push(DrawCmd{
		x:     ox + g.x0
		y:     oy + g.y0
		w:     g.x1 - g.x0
		h:     g.y1 - g.y0
		u0:    g.u0
		v0:    g.v0
		u1:    g.u1
		v1:    g.v1
		cx0:   snap(clip.x * sc)
		cy0:   snap(clip.y * sc)
		cx1:   snap((clip.x + clip.w) * sc)
		cy1:   snap((clip.y + clip.h) * sc)
		color: color
		kind:  u32(DrawKind.glyph)
	})
}

// Pen konumu fiziksel pikselde birikir; glif başlangıçları tam piksele yuvarlanır.
fn (mut c Context) emit_text(i int, clip Rect) {
	sc := c.scale
	role := c.nodes[i].role
	base_x := c.nodes[i].pos[0] * sc
	base_y := snap(c.nodes[i].pos[1] * sc + c.atl.ascent(role) * sc)
	color := u32(c.nodes[i].color)
	s := c.nodes[i].text
	mut pen := f32(0)
	mut prev := u32(0)
	mut k := 0
	for k < s.len {
		cp, next := utf8_next(s, k)
		if k > 0 {
			pen += c.atl.kern(role, prev, cp)
		}
		g := c.atl.glyph(role, cp)
		if g.x1 > g.x0 {
			c.emit_glyph(g, snap(base_x + pen), base_y, color, clip)
		}
		pen += g.advance
		prev = cp
		k = next
	}
}

fn (mut c Context) emit_icon(i int, clip Rect) {
	sc := c.scale
	g := c.atl.icon(c.nodes[i].icon)
	c.emit_glyph(g, snap(c.nodes[i].pos[0] * sc), snap(c.nodes[i].pos[1] * sc),
		u32(c.nodes[i].color), clip)
}
