module ui

struct VlProbe {
mut:
	first int
	count int
}

fn vl_test_body(mut pp &VlProbe, total int) fn (mut c Context) {
	return fn [mut pp, total] (mut c Context) {
		vl := c.virtual_list_begin('list', total, row_h, Box{
			dir:    .column
			width:  fixed(200)
			height: fixed(400)
		})
		pp.first = vl.first
		pp.count = vl.count
		for k in vl.first .. vl.first + vl.count {
			c.push_id(k)
			c.list_row('row', 'satır', false)
			c.pop_id()
		}
		c.virtual_list_end()
	}
}

// 10.000 satır, 400 px görünüm: yalnız görünen satırlar (tampon dahil) düğüm üretir.
fn test_virtual_list_emits_only_visible_rows() {
	mut atl := Atlas.build(1.0) or { panic(err) }
	mut c := Context.new(&atl, 4096, 8192) or { panic(err) }
	mut p := VlProbe{}
	mut pp := &p
	body := vl_test_body(mut pp, 10000)
	c.begin(Input{}, 400, 900, 1.0)
	body(mut c)
	c.end()
	assert p.first == 0
	assert p.count > 0 && p.count <= 20
	assert c.node_overflow() == 0
	// Kaydırma sonu: son satır listenin sonudur, ofset sınırda kalır.
	c.scroll_to('list', f32(1e9))
	c.begin(Input{}, 400, 900, 1.0)
	body(mut c)
	c.end()
	assert p.first + p.count == 10000
	assert c.node_overflow() == 0
}

// Bir kare: önce reveal_row (kare içinde, begin öncesi), sonra liste. Döner: çizilen aralık.
fn vl_reveal_frame(mut c Context, total int, idx int) VirtualList {
	c.begin(Input{}, 400, 900, 1.0)
	c.reveal_row('list', idx, row_h)
	vl := c.virtual_list_begin('list', total, row_h, Box{
		dir:    .column
		width:  fixed(200)
		height: fixed(400)
	})
	for k in vl.first .. vl.first + vl.count {
		c.push_id(k)
		c.list_row('row', 'satır', false)
		c.pop_id()
	}
	c.virtual_list_end()
	c.end()
	return vl
}

// Satır alttan yukarıdaysa: üst hizalı (ofset = satırın üstü) — kutunun önceki durumu ofseti önce ayarlar.
fn test_reveal_row_above_aligns_top() {
	mut atl := Atlas.build(1.0) or { panic(err) }
	mut c := Context.new(&atl, 4096, 8192) or { panic(err) }
	vl_reveal_frame(mut c, 10000, 0)
	c.scroll_to('list', f32(500) * row_h)
	vl := vl_reveal_frame(mut c, 10000, 10)
	assert c.scroll_offset('list') == f32(10) * row_h
	assert vl.first <= 10 && 10 < vl.first + vl.count
}

// Satır altta: alt hizalı (satırın altı kutunun altına gelir); ofset yalnız gereken kadar artar.
fn test_reveal_row_below_aligns_bottom() {
	mut atl := Atlas.build(1.0) or { panic(err) }
	mut c := Context.new(&atl, 4096, 8192) or { panic(err) }
	vl_reveal_frame(mut c, 10000, 0)
	vl := vl_reveal_frame(mut c, 10000, 100)
	// Satır 100: üst 2600, alt 2626; görünüm 400 → ofset 2226.
	assert c.scroll_offset('list') == f32(101) * row_h - 400
	assert vl.first <= 100 && 100 < vl.first + vl.count
}

// Zaten görünen satır ofseti değiştirmez.
fn test_reveal_row_already_visible_no_change() {
	mut atl := Atlas.build(1.0) or { panic(err) }
	mut c := Context.new(&atl, 4096, 8192) or { panic(err) }
	vl_reveal_frame(mut c, 10000, 0)
	vl_reveal_frame(mut c, 10000, 100)
	before := c.scroll_offset('list')
	vl_reveal_frame(mut c, 10000, 90)
	assert c.scroll_offset('list') == before
}
