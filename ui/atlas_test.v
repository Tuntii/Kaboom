module ui

fn must_atlas(scale f32) Atlas {
	return Atlas.build(scale) or { panic(err) }
}

fn test_stb_fontinfo_fits_opaque_buffer() {
	assert sizeof(C.stbtt_fontinfo) <= stbtt_info_size
}

fn test_atlas_builds_at_scale_1() {
	a := must_atlas(1.0)
	assert a.width() <= 4096
	assert a.height() <= 4096
	assert a.pixels().len == a.width() * a.height()
}

fn test_atlas_builds_at_scale_1_5() {
	a := must_atlas(1.5)
	assert a.width() <= 4096
	assert a.pixels().len == a.width() * a.height()
}

fn test_atlas_builds_at_scale_2() {
	a := must_atlas(2.0)
	assert a.width() <= 4096
	assert a.pixels().len == a.width() * a.height()
}

fn test_turkish_glyphs_present() {
	a := must_atlas(1.0)
	q := a.glyph(.body, u32(0x3F))
	for cp in [u32(0x11F), 0x15F, 0x131, 0x130, 0x11E, 0x15E, 0xE7, 0xF6, 0xFC] {
		g := a.glyph(.body, cp)
		assert g.u0 != q.u0 || g.v0 != q.v0
	}
}

fn test_missing_glyph_falls_back() {
	a := must_atlas(1.0)
	q := a.glyph(.body, u32(0x3F))
	assert a.glyph(.body, u32(0x1F600)) == q
	assert a.glyph(.body, u32(0x4E2D)) == q
	assert a.glyph(.body, u32(0xFFFD)) == q
	assert a.measure('a😀b', .body) > 0
}

fn test_measure_monotonic() {
	a := must_atlas(1.0)
	assert a.measure('Kaydet', .body) > a.measure('Kay', .body)
	assert a.measure('Kay', .body) > 0
	assert a.measure('', .body) == 0
}

fn test_measure_logical_independent_of_scale() {
	a1 := must_atlas(1.0)
	a2 := must_atlas(2.0)
	mut d := a1.measure('Inspector', .body) - a2.measure('Inspector', .body)
	if d < 0 {
		d = -d
	}
	assert d <= 1.0
}

fn test_mono_is_monospace() {
	a := must_atlas(1.0)
	assert a.measure('iiii', .mono) == a.measure('MMMM', .mono)
}

fn test_white_pixel_is_opaque() {
	a := must_atlas(1.0)
	u, v := a.white_uv()
	x := int(u * f32(a.width()))
	y := int(v * f32(a.height()))
	assert a.pixels()[y * a.width() + x] == 255
}

fn test_utf8_next_invalid_byte() {
	cp, next := utf8_next('\xff' + 'a', 0)
	assert cp == 0xFFFD
	assert next == 1
}
