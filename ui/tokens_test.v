module ui

fn test_contrast_known_values() {
	assert contrast_ratio(0xFFFFFFFF, 0x000000FF) > 20.99
	assert contrast_ratio(0xFFFFFFFF, 0x000000FF) < 21.01
	assert contrast_ratio(text_primary, text_primary) == 1.0
}

fn test_text_contrast_meets_aa() {
	surfaces := [surface_0, surface_1, surface_2, surface_hover]
	for s in surfaces {
		assert contrast_ratio(text_primary, s) >= 4.5
		assert contrast_ratio(text_secondary, s) >= 4.5
		assert contrast_ratio(text_muted, s) >= 3.0
	}
	assert contrast_ratio(accent_text, accent) >= 4.5
}

fn test_text_roles_specs() {
	face, size := TextRole.body.spec()
	assert face == .sans
	assert size == 13
	mface, msize := TextRole.mono.spec()
	assert mface == .mono
	assert msize == 12
}

fn test_drawcmd_size_is_72() {
	assert sizeof(DrawCmd) == 72
}

fn test_drawlist_push_until_full() {
	mut l := DrawList.new(2)
	assert l.push(DrawCmd{}) == true
	assert l.push(DrawCmd{}) == true
	assert l.push(DrawCmd{}) == false
	assert l.dropped() == 1
	assert l.len() == 2
	l.clear()
	assert l.len() == 0
}
