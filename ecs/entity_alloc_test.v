module ecs

import memory

fn test_create_sequential() {
	base := memory.reserve(65536) or { panic('reserve basarisiz') }
	defer { memory.release(base) }
	mut arena := memory.LinearArena.new(base, 65536)
	mut ea := EntityAllocator.new(mut arena, 8) or { panic('new none') }
	for i in 0 .. 3 {
		e := ea.create() or { panic('create none, i=${i}') }
		assert e.index() == u32(i)
		assert e.generation() == 0
	}
	assert ea.alive_count() == 3
}

fn test_reuse_bumps_generation() {
	base := memory.reserve(65536) or { panic('reserve basarisiz') }
	defer { memory.release(base) }
	mut arena := memory.LinearArena.new(base, 65536)
	mut ea := EntityAllocator.new(mut arena, 8) or { panic('new none') }
	mut ids := []EntityID{}
	for _ in 0 .. 3 {
		ids << (ea.create() or { panic('create none') })
	}
	b := ids[1]
	assert ea.destroy(b)
	e := ea.create() or { panic('create none') }
	assert e.index() == 1
	assert e.generation() == 1
	assert !ea.is_alive(b)
	assert ea.is_alive(e)
}

fn test_untrusted_handles() {
	base := memory.reserve(65536) or { panic('reserve basarisiz') }
	defer { memory.release(base) }
	mut arena := memory.LinearArena.new(base, 65536)
	mut ea := EntityAllocator.new(mut arena, 8) or { panic('new none') }
	mut ids := []EntityID{}
	for _ in 0 .. 3 {
		ids << (ea.create() or { panic('create none') })
	}
	b := ids[1]
	assert ea.destroy(b)
	// Slot 1 bos, nesli 1: alive biti 0 oldugu icin bu handle canli sayilmamali.
	assert !ea.is_alive(make_entity(1, 1))
	assert !ea.destroy(make_entity(1, 1))
	assert !ea.destroy(b)
	assert !ea.is_alive(make_entity(1, 2))
	assert !ea.is_alive(make_entity(5, 0))
	assert !ea.is_alive(null_entity)
	assert !ea.destroy(make_entity(7, 0))
	// Canli handle'a bit 48..63 eklenmis sahte kopya: kanonik degil, reddedilmeli.
	live := ids[0]
	forged := EntityID(u64(live) | (u64(1) << 60))
	assert !ea.is_alive(forged)
	assert !ea.destroy(forged)
	assert ea.is_alive(live)
	assert ea.alive_count() == 2
}

fn test_capacity_exhausted() {
	base := memory.reserve(65536) or { panic('reserve basarisiz') }
	defer { memory.release(base) }
	mut arena := memory.LinearArena.new(base, 65536)
	mut ea := EntityAllocator.new(mut arena, 2) or { panic('new none') }
	ea.create() or { panic('create none') }
	ea.create() or { panic('create none') }
	if _ := ea.create() {
		assert false
	}
}

fn test_new_rejects_null_index_capacity() {
	base := memory.reserve(65536) or { panic('reserve basarisiz') }
	defer { memory.release(base) }
	mut arena := memory.LinearArena.new(base, 65536)
	if _ := EntityAllocator.new(mut arena, null_index) {
		assert false
	}
}

fn test_generation_retire() {
	base := memory.reserve(65536) or { panic('reserve basarisiz') }
	defer { memory.release(base) }
	mut arena := memory.LinearArena.new(base, 65536)
	mut ea := EntityAllocator.new(mut arena, 2) or { panic('new none') }
	mut e := ea.create() or { panic('create none') }
	for _ in 0 .. int(max_generation) {
		assert ea.destroy(e)
		e = ea.create() or { panic('create none') }
	}
	assert e.index() == 0
	assert e.generation() == max_generation
	assert ea.destroy(e)
	assert ea.retired_count() == 1
	// Emekli slot: alive biti 0, nesil max_generation; bu handle hicbir sekilde canli olmamali.
	assert !ea.is_alive(make_entity(0, max_generation))
	assert !ea.destroy(make_entity(0, max_generation))
	f := ea.create() or { panic('create none after retire') }
	assert f.index() == 1
	assert f.generation() == 0
	if _ := ea.create() {
		assert false
	}
}
