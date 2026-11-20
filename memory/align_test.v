module memory

fn test_align_forward_known_values() {
	assert align_forward(0, 64) == 0
	assert align_forward(1, 64) == 64
	assert align_forward(64, 64) == 64
	assert align_forward(65, 64) == 128
	assert pad_for(1, 64) == 63
	assert pad_for(64, 64) == 0
	assert pad_for(100, 16) == 12
}

fn test_align_property() {
	for p in u64(0) .. 1000 {
		for k in [u64(1), 2, 4, 8, 16, 32, 64, 4096] {
			a := align_forward(p, k)
			assert a == p + pad_for(p, k)
			assert a % k == 0
			assert a - p < k
		}
	}
}

fn test_is_pow2() {
	assert is_pow2(1) && is_pow2(64) && is_pow2(4096)
	assert !is_pow2(0) && !is_pow2(3) && !is_pow2(96)
}
