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

// scroll_to ile seçili satır (13.000 px ofset = 500. satır) bir sonraki karede görünür.
fn test_scroll_to_makes_row_visible() {
	mut atl := Atlas.build(1.0) or { panic(err) }
	mut c := Context.new(&atl, 4096, 8192) or { panic(err) }
	mut p := VlProbe{}
	mut pp := &p
	body := vl_test_body(mut pp, 10000)
	c.begin(Input{}, 400, 900, 1.0)
	body(mut c)
	c.end()
	c.scroll_to('list', f32(500) * row_h)
	c.begin(Input{}, 400, 900, 1.0)
	body(mut c)
	c.end()
	assert c.scroll_offset('list') == f32(500) * row_h
	assert p.first <= 500 && 500 < p.first + p.count
}
