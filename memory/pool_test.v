module memory

fn test_acquire_all_ascending() {
	base := reserve(65536) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 65536)
	mut p := PoolAllocator.new(mut a, 24, 130) or { panic('pool none') }
	for i in 0 .. 130 {
		idx := p.acquire() or { panic('acquire none, i=${i}') }
		assert idx == u32(i)
	}
	if _ := p.acquire() {
		assert false
	}
	assert p.live_count() == 130
}

fn test_release_reuses_lowest() {
	base := reserve(65536) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 65536)
	mut p := PoolAllocator.new(mut a, 24, 130) or { panic('pool none') }
	for _ in 0 .. 130 {
		_ := p.acquire() or { panic('acquire none') }
	}
	assert p.release(5)
	assert p.release(70)
	assert (p.acquire() or { panic('acquire none') }) == 5
	assert (p.acquire() or { panic('acquire none') }) == 70
}

fn test_first_free_hint_tracks_lowest_free_word() {
	base := reserve(65536) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 65536)
	mut p := PoolAllocator.new(mut a, 24, 130) or { panic('pool none') }
	for _ in 0 .. 130 {
		_ := p.acquire() or { panic('acquire none') }
	}
	// Son isabetli kelime 2; bos kelime bulunamayinca ipucu word_count'a cekilir.
	assert p.first_free == 2
	if _ := p.acquire() {
		assert false
	}
	assert p.first_free == p.word_count
	assert p.release(129)
	assert p.first_free == 2
	assert (p.acquire() or { panic('acquire none') }) == 129
	assert p.release(3)
	assert p.release(100)
	assert p.first_free == 0
	assert (p.acquire() or { panic('acquire none') }) == 3
	assert (p.acquire() or { panic('acquire none') }) == 100
	assert p.live_count() == 130
}

fn test_double_and_oob_release() {
	base := reserve(65536) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 65536)
	mut p := PoolAllocator.new(mut a, 24, 130) or { panic('pool none') }
	for _ in 0 .. 10 {
		_ := p.acquire() or { panic('acquire none') }
	}
	assert p.live_count() == 10
	assert p.release(5)
	assert !p.release(5)
	assert !p.release(130)
	assert p.live_count() == 9
}

fn test_word_boundaries() {
	for count in [u32(64), u32(1)] {
		base := reserve(65536) or { panic('reserve basarisiz') }
		mut a := LinearArena.new(base, 65536)
		mut p := PoolAllocator.new(mut a, 16, count) or { panic('pool none') }
		for i in 0 .. count {
			idx := p.acquire() or { panic('acquire none') }
			assert idx == i
		}
		if _ := p.acquire() {
			assert false
		}
		assert p.live_count() == count
		release(base)
	}
}

fn test_slot_ptr_layout() {
	base := reserve(65536) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 65536)
	p := PoolAllocator.new(mut a, 24, 8) or { panic('pool none') }
	assert p.stride == 32
	for i in 0 .. 7 {
		p0 := u64(p.slot_ptr(i))
		p1 := u64(p.slot_ptr(i + 1))
		assert p0 % 16 == 0
		assert p1 - p0 == 32
	}
}

fn test_new_parent_too_small_is_none() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 256)
	if _ := PoolAllocator.new(mut a, 24, 130) {
		assert false
	}
}

// Slot blogu sigar, bitmap sigmaz: parent geri sarilmali.
fn test_new_rolls_back_on_bitmap_failure() {
	base := reserve(65536) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut a := LinearArena.new(base, 4240)
	// Offset 8: slotlar 64..4224'e sigar, bitmap 4224..4248'e sigmaz.
	a.alloc_aligned(8, 1) or { panic('prealloc none') }
	before := a.used()
	if _ := PoolAllocator.new(mut a, 24, 130) {
		assert false, 'bitmap sigmiyor, none donmeli'
	}
	assert a.used() == before
}
