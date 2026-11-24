module ui

import math

fn layout_atlas(scale f32) Atlas {
	return Atlas.build(scale) or { panic(err) }
}

fn count_kind(l &DrawList, kind DrawKind) u32 {
	mut n := u32(0)
	for i in 0 .. l.len() {
		if l.at(i).kind == u32(kind) {
			n++
		}
	}
	return n
}

// Renk eşleşen ilk rect komutunu döner (kutu konumu için).
fn find_rect(l &DrawList, color Color) DrawCmd {
	for i in 0 .. l.len() {
		cmd := l.at(i)
		if cmd.kind == u32(DrawKind.rect) && cmd.color == u32(color) {
			return cmd
		}
	}
	panic('rect bulunamadı')
}

fn test_row_padding_gap() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 400, 100, 1.0)
	c.open('row', Box{
		dir:     .row
		width:   fixed(400)
		height:  fixed(100)
		padding: pad_all(8)
		gap:     4
	})
	for _ in 0 .. 3 {
		c.open('cell', Box{
			width:  fixed(50)
			height: fixed(20)
			bg:     surface_2
		})
		c.close()
	}
	c.close()
	l := c.end()
	mut xs := []f32{}
	for i in 0 .. l.len() {
		cmd := l.at(i)
		if cmd.w == 50 {
			xs << cmd.x
		}
	}
	assert xs == [f32(8), 62, 116]
}

fn test_grow_splits_remaining() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 300, 100, 1.0)
	c.open('row', Box{
		dir:    .row
		width:  fixed(300)
		height: fixed(40)
	})
	c.open('fixed', Box{ width: fixed(100), height: fixed(10), bg: surface_1 })
	c.close()
	c.open('g1', Box{ width: grow(), height: fixed(10), bg: surface_2 })
	c.close()
	c.open('g2', Box{ width: grow(), height: fixed(10), bg: surface_hover })
	c.close()
	c.close()
	l := c.end()
	assert find_rect(l, surface_1).w == 100
	assert find_rect(l, surface_2).w == 100
	assert find_rect(l, surface_2).x == 100
	assert find_rect(l, surface_hover).w == 100
	assert find_rect(l, surface_hover).x == 200
}

fn test_align_center_and_end() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 200, 300, 1.0)
	c.open('center', Box{
		dir:         .column
		width:       fixed(200)
		height:      fixed(100)
		align_cross: .center
	})
	c.open('c_child', Box{ width: fixed(50), height: fixed(20), bg: surface_1 })
	c.close()
	c.close()
	c.open('end', Box{
		dir:        .column
		width:      fixed(200)
		height:     fixed(100)
		align_main: .end
	})
	c.open('e_child', Box{ width: fixed(50), height: fixed(20), bg: surface_2 })
	c.close()
	c.close()
	l := c.end()
	assert find_rect(l, surface_1).x == 75
	assert find_rect(l, surface_2).y == 180
}

fn test_fit_wraps_children() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 300, 300, 1.0)
	c.open('fit', Box{
		dir:     .row
		padding: pad_all(4)
		gap:     2
		bg:      surface_1
	})
	c.open('a', Box{ width: fixed(20), height: fixed(10) })
	c.close()
	c.open('b', Box{ width: fixed(20), height: fixed(10) })
	c.close()
	c.close()
	l := c.end()
	r := find_rect(l, surface_1)
	assert r.w == 50
	assert r.h == 18
}

fn test_min_max_clamp() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 500, 100, 1.0)
	c.open('row', Box{
		dir:    .row
		width:  fixed(500)
		height: fixed(40)
	})
	c.open('capped', Box{
		width:  Size{
			kind: .grow
			max:  120
		}
		height: fixed(10)
		bg:     surface_1
	})
	c.close()
	c.close()
	l := c.end()
	assert find_rect(l, surface_1).w == 120
}

fn test_tiny_viewport_no_negative_sizes() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 200, 150, 1.0)
	c.open('row', Box{ dir: .row, width: grow(), height: grow() })
	c.open('left', Box{ width: fixed(240), height: grow(), bg: surface_1 })
	c.close()
	c.open('mid', Box{ width: grow(), height: grow(), bg: surface_2 })
	c.close()
	c.open('right', Box{ width: fixed(300), height: grow(), bg: surface_hover })
	c.close()
	c.close()
	l := c.end()
	for i in 0 .. l.len() {
		cmd := l.at(i)
		assert cmd.w >= 0
		assert cmd.h >= 0
	}
}

fn test_long_text_clipped_to_parent() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 400, 100, 1.0)
	c.open('clipped', Box{ width: fixed(60), height: fixed(30), clip: true })
	c.text('Çok uzun bir metin satırı burada kırpılmalı ve taşmamalı', .body, text_primary)
	c.close()
	l := c.end()
	assert count_kind(l, .glyph) > 0
	for i in 0 .. l.len() {
		cmd := l.at(i)
		if cmd.kind == u32(DrawKind.glyph) {
			assert cmd.cx0 >= 0
			assert cmd.cx1 <= 60
			assert cmd.cy1 <= 30
		}
	}
}

fn test_rect_edges_snap_at_fractional_scale() {
	mut atl := layout_atlas(1.5)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 101, 50, 1.5)
	c.open('row', Box{ dir: .row, width: grow(), height: grow() })
	for col in [surface_1, surface_2, surface_hover] {
		c.open('col', Box{ width: grow(), height: grow(), bg: col })
		c.close()
	}
	c.close()
	l := c.end()
	assert count_kind(l, .rect) == 3
	for i in 0 .. l.len() {
		cmd := l.at(i)
		assert cmd.x == f32(int(cmd.x))
		assert cmd.y == f32(int(cmd.y))
		assert cmd.x + cmd.w == f32(int(cmd.x + cmd.w))
		assert cmd.y + cmd.h == f32(int(cmd.y + cmd.h))
	}
}

fn test_overlay_drawn_after_tree() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 300, 300, 1.0)
	c.open('tree', Box{ width: fixed(100), height: fixed(100), bg: surface_1 })
	c.close()
	c.overlay('menu', 10, 10, Box{ width: fixed(40), height: fixed(40), bg: accent })
	c.close()
	l := c.end()
	last := l.at(l.len() - 1)
	assert last.color == u32(accent)
	assert last.w == 40
}

fn test_ids_stable_and_push_id() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	first := c.id('btn')
	c.begin(Input{}, 100, 100, 1.0)
	c.open('btn', Box{})
	c.close()
	c.end()
	assert c.id('btn') == first
	c.push_id(1)
	a := c.id('btn')
	c.pop_id()
	c.push_id(2)
	b := c.id('btn')
	c.pop_id()
	assert a != b
	assert a != first
}

fn test_prev_rect_available_next_frame() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	panel := c.id('panel')
	c.begin(Input{}, 200, 200, 1.0)
	c.open('panel', Box{ width: fixed(40), height: fixed(30) })
	c.close()
	c.end()
	c.begin(Input{}, 200, 200, 1.0)
	c.open('panel', Box{ width: fixed(40), height: fixed(30) })
	c.close()
	r := c.prev_rect(panel) or { panic('önceki kare dikdörtgeni yok') }
	assert r.w == 40
	assert r.h == 30
	c.end()
}

fn test_node_overflow_counted() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 8, 4096) or { panic(err) }
	c.begin(Input{}, 200, 200, 1.0)
	for _ in 0 .. 20 {
		c.text('x', .body, text_primary)
	}
	c.end()
	assert c.node_overflow() > 0
}

fn test_grow_redistributes_after_max() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 500, 100, 1.0)
	c.open('row', Box{ dir: .row, width: fixed(500), height: fixed(40) })
	c.open('a', Box{
		width:  Size{
			kind: .grow
			max:  120
		}
		height: fixed(10)
		bg:     surface_1
	})
	c.close()
	c.open('b', Box{ width: grow(), height: fixed(10), bg: surface_2 })
	c.close()
	c.close()
	l := c.end()
	assert find_rect(l, surface_1).w == 120
	assert find_rect(l, surface_2).w == 380
	assert find_rect(l, surface_2).x == 120
}

fn test_grow_min_raises_child() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 300, 100, 1.0)
	c.open('row', Box{ dir: .row, width: fixed(300), height: fixed(40) })
	c.open('a', Box{
		width:  Size{
			kind: .grow
			min:  150
		}
		height: fixed(10)
		bg:     surface_1
	})
	c.close()
	c.open('b', Box{ width: grow(), height: fixed(10), bg: surface_2 })
	c.close()
	c.open('c', Box{ width: grow(), height: fixed(10), bg: surface_hover })
	c.close()
	c.close()
	l := c.end()
	assert find_rect(l, surface_1).w == 150
	assert find_rect(l, surface_2).w == 75
	assert find_rect(l, surface_hover).w == 75
}

// Kırpılmış ebeveynin dışındaki çocuk hiçbir komut üretmez.
fn test_child_outside_clip_emits_nothing() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 300, 100, 1.0)
	c.open('clipped', Box{ dir: .row, width: fixed(60), height: fixed(30), clip: true })
	c.open('spacer', Box{ width: fixed(100), height: fixed(10) })
	c.close()
	c.open('outside', Box{ width: fixed(50), height: fixed(20), bg: surface_1 })
	c.close()
	c.close()
	l := c.end()
	assert l.len() == 0
}

// Fit ebeveyn, grow çocukların en küçük (içerik) genişliğini alır; çocuklar o genişliğe dolar.
fn test_grow_child_contributes_min_content_to_fit_parent() {
	mut atl := layout_atlas(1.0)
	w_short := atl.measure('abc', .body)
	w_long := atl.measure('abcdefgh', .body)
	mut c := Context.new(&atl, 1024, 4096) or { panic(err) }
	c.begin(Input{}, 400, 100, 1.0)
	c.open('col', Box{ dir: .column, width: fit(), height: fixed(100) })
	c.open('a', Box{ width: grow(), height: fit() })
	c.text('abc', .body, text_primary)
	c.close()
	c.open('b', Box{ width: grow(), height: fit() })
	c.text('abcdefgh', .body, text_primary)
	c.close()
	c.close()
	c.end()
	col := layout_node(&c, c.id('col'))
	a := layout_node(&c, c.id('a'))
	b := layout_node(&c, c.id('b'))
	assert w_short < w_long
	assert col.sz[0] == w_long
	assert a.sz[0] == w_long
	assert b.sz[0] == w_long
}

// Kimliğin ilk düğümü (test yardımcısı).
fn layout_node(c &Context, id u32) Node {
	for i in 0 .. c.n {
		if c.nodes[i].id == id {
			return c.nodes[i]
		}
	}
	panic('düğüm yok')
}
// Ayırıcı ve kenarlık: fiziksel kalınlık her konumda aynı tamsayı; 1.25 ve 1.5 ölçeklerinde.
fn test_hairlines_and_borders_integer_thickness() {
	for sc in [f32(1.25), f32(1.5)] {
		want := f32(math.max(f64(1), math.floor(1 * f64(sc) + 0.5)))
		mut atl := layout_atlas(sc)
		mut c := Context.new(&atl, 256, 256) or { panic(err) }
		c.begin(Input{}, 200, 200, sc)
		for i in 0 .. 4 {
			c.leaf(.plain, Box{
				width:  fixed(10)
				height: fixed(7.3 + 2.1 * f32(i))
			})
			c.separator()
		}
		c.open('bx', Box{
			width:    fixed(50)
			height:   fixed(20)
			bg:       surface_2
			border:   border_strong
			border_w: 1
		})
		c.close()
		c.end()
		mut seps := 0
		for k in 0 .. c.list.len() {
			cmd := c.list.at(k)
			if cmd.color == u32(border) {
				seps++
				assert cmd.h == want
			}
			if cmd.color == u32(surface_2) {
				assert cmd.border == want
			}
		}
		assert seps == 4
	}
}

// Kırpma dışındaki satırların alt ağaçlarına inilmez: görünür satırlar kadar ziyaret, çıktı değişmez.
fn test_paint_skips_offclip_subtrees() {
	mut atl := layout_atlas(1.0)
	mut c := Context.new(&atl, 4096, 8192) or { panic(err) }
	c.begin(Input{}, 300, 300, 1.0)
	c.open('list', Box{
		dir:    .column
		width:  fixed(100)
		height: fixed(100)
		clip:   true
	})
	for k in 0 .. 1000 {
		c.push_id(k)
		c.open('row', Box{
			width:  grow()
			height: fixed(row_h)
		})
		c.text('x', .body, text_primary)
		c.close()
		c.pop_id()
	}
	c.close()
	l := c.end()
	// 100 px kutuda 4 satır (kısmen görünen dahil) ve kutu: ziyaret sayısı satır mertebesinde.
	assert c.paint_visits() <= 12, 'ziyaret: ${c.paint_visits()}'
	assert l.len() == 4, 'komut: ${l.len()}'
}
