module memory

fn test_reserve_release() {
	p := reserve(1 << 20) or { panic('reserve basarisiz') }
	assert u64(p) & 0xFFF == 0
	unsafe {
		p[0] = 7
		p[(1 << 20) - 1] = 9
		assert p[0] == 7 && p[(1 << 20) - 1] == 9
	}
	assert release(p)
}

fn test_reserve_zero_is_none() {
	if _ := reserve(0) {
		assert false
	}
}
