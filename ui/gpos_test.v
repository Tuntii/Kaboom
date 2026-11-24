module ui

fn test_gpos_garbage_no_panic() {
	mut garbage := []u8{len: 512}
	for i in 0 .. garbage.len {
		garbage[i] = u8(0xFF - (i % 7))
	}
	assert gpos_lookup_list(garbage) < 0
	assert gpos_pair_units(garbage, 0, 3, 7) == 0
	assert gpos_kern_table(garbage, [1, 2, 3]).len == 0
}

fn test_gpos_truncated_font_no_panic() {
	mut f := $embed_file('../assets/fonts/Inter-Regular.ttf')
	full := unsafe { (&u8(f.data())).vbytes(f.len) }
	for cut in [12, 100, 1000, full.len / 2] {
		short := full[..cut].clone()
		// Kesik tabloda değerler geçerli olabilir; burada yalnızca panik olmadığı doğrulanır.
		ll := gpos_lookup_list(short)
		if ll >= 0 {
			_ = gpos_pair_units(short, ll, 3, 7)
		}
		_ = gpos_kern_table(short, [1, 2, 3])
	}
}
