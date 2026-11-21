module memory

fn test_alloc_is_aligned_and_disjoint() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 4096)
	p1 := a.alloc_aligned(10, 64) or { panic('p1 none') }
	p2 := a.alloc_aligned(10, 64) or { panic('p2 none') }
	assert u64(p1) % 64 == 0
	assert u64(p2) % 64 == 0
	assert u64(p2) >= u64(p1) + 10
}

fn test_unaligned_base() {
	raw := reserve(8192) or { panic('reserve basarisiz') }
	defer { release(raw) }
	base := unsafe { raw + 1 }
	mut a := LinearArena.new(base, 4095)
	p := a.alloc_aligned(8, 64) or { panic('alloc none') }
	pad := pad_for(u64(base), 64)
	assert u64(p) % 64 == 0
	assert a.used() == pad + 8
}

fn test_overflow_returns_none() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 128)
	_ := a.alloc_aligned(128, 1) or { panic('ilk alloc none') }
	if _ := a.alloc_aligned(1, 1) {
		assert false
	}
	assert a.used() == 128
	assert a.failed_allocs() == 1
}

fn test_size_wraparound_is_none() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 4096)
	if _ := a.alloc_aligned(u64(-1), 1) {
		assert false
	}
	assert a.offset == 0
	assert a.failed_allocs() == 1
}

fn test_non_pow2_alignment_is_none() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 4096)
	if _ := a.alloc_aligned(8, 3) {
		assert false, '2^n olmayan hizalama none donmeli'
	}
	assert a.used() == 0
	assert a.failed_allocs() == 1
}

fn test_early_padding_overflow_is_none() {
	raw := reserve(8192) or { panic('reserve basarisiz') }
	defer { release(raw) }
	base := unsafe { raw + 1 }
	// Ilk kontrol (padding > capacity - offset) dolmadan once tetiklenmeli.
	mut a := LinearArena.new(base, 8)
	if _ := a.alloc_aligned(0, 64) {
		assert false, 'padding kapasiteyi asiyor, none donmeli'
	}
	assert a.used() == 0
	assert a.failed_allocs() == 1
}

fn test_reset() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 4096)
	_ := a.alloc_aligned(100, 16) or { panic('alloc none') }
	a.reset()
	assert a.used() == 0
	p := a.alloc_aligned(1, 1) or { panic('sonrasi alloc none') }
	assert p == base
}

fn test_mark_rewind() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 1024)
	a.alloc_aligned(100, 1) or { panic('alloc1 none') }
	m := a.mark()
	assert m == 100
	a.alloc_aligned(200, 1) or { panic('alloc2 none') }
	a.rewind(m)
	assert a.used() == 100
	// Ileri sarma yok sayilir.
	a.rewind(900)
	assert a.used() == 100
}
