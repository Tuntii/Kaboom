module memory

fn test_epoch_double_buffer() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut parent := LinearArena.new(base, 4096)
	mut e := EpochArena.new(mut parent, 64) or { panic('epoch new none') }

	// frame 0: yazma arenasi arenas[0]
	p := e.alloc(8, 8) or { panic('frame0 alloc none') }
	unsafe {
		*(&u64(p)) = 42
	}
	e.advance()
	assert e.read_base() == p
	assert unsafe { *(&u64(e.read_base())) } == 42
	assert e.read_used() == 8
	assert e.arenas[e.frame & 1].used() == 0

	// frame 1: yazma arenasi arenas[1]
	q := e.alloc(8, 8) or { panic('frame1 alloc none') }
	unsafe {
		*(&u64(q)) = 43
	}
	e.advance()
	// frame 2: yazma arenasi frame 0'inki (arenas[0]) ve sifirlanmis olmali
	assert e.arenas[0].used() == 0
	assert e.read_base() == q
	assert unsafe { *(&u64(e.read_base())) } == 43
	assert e.read_used() == 8
}

fn test_epoch_read_used_zero_at_frame_zero() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut parent := LinearArena.new(base, 4096)
	e := EpochArena.new(mut parent, 64) or { panic('epoch new none') }
	assert e.frame == 0
	assert e.read_used() == 0
}

fn test_epoch_overflow() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut parent := LinearArena.new(base, 4096)
	mut e := EpochArena.new(mut parent, 64) or { panic('epoch new none') }
	if _ := e.alloc(65, 1) {
		assert false, 'half kapasitesini asan tahsis none donmeli'
	}
}

fn test_epoch_parent_too_small() {
	base := reserve(4096) or { panic('reserve basarisiz') }
	defer { release(base) }
	mut parent := LinearArena.new(base, 100)
	if _ := EpochArena.new(mut parent, 64) {
		assert false, 'parent 2 yariyi tasiyamiyor, none donmeli'
	}
}
