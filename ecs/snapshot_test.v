module ecs

import memory

fn snapshot_world(reg &Registry, capacity u32) World {
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, 1 << 20)
	return World.new(mut a, reg, capacity) or { panic('World.new none') }
}

// Bosluklar, emekli bir slot ve nesli 0'dan buyuk slotlar iceren dunya.
fn busy_world(reg &Registry) World {
	mut w := snapshot_world(reg, 8)
	// Ayni slotu max nesile kadar dondur: son yikim slotu emekli eder.
	for _ in 0 .. 0x10000 {
		e := w.spawn() or { panic('spawn none') }
		assert w.despawn(e)
	}
	mut es := []EntityID{}
	for _ in 0 .. 4 {
		es << w.spawn() or { panic('spawn none') }
	}
	for e in es {
		assert w.add_component(e, transform_id) == .ok
		assert w.set_field(e, transform_id, 0, u64(e.index() + 1)) == .ok
	}
	assert w.add_component(es[2], body_id) == .ok
	assert w.set_field(es[2], body_id, 1, 77) == .ok
	assert w.despawn(es[1])
	assert w.despawn(es[2])
	return w
}

fn restore_fails(mut w World, data []u8) bool {
	w.restore(data) or { return true }
	return false
}

fn test_snapshot_roundtrip_keeps_ids_and_generations() {
	reg := core_registry() or { panic('registry basarisiz') }
	mut src := busy_world(&reg)
	assert src.entities().retired_count() == 1
	data := src.snapshot()
	mut dst := snapshot_world(&reg, 8)
	dst.restore(data) or { panic(err) }
	assert dst.snapshot() == data
	assert dst.alive_count() == src.alive_count()
	assert dst.entities().high_water() == src.entities().high_water()
	// Son yikilan slot (indeks 3) nesil 1 ile bos listenin basinda: iki dunyada ayni id.
	for e in [make_entity(3, 1), make_entity(1, 0)] {
		assert dst.is_alive(e) == src.is_alive(e)
	}
	a := src.spawn() or { panic('spawn none') }
	b := dst.spawn() or { panic('spawn none') }
	assert a == make_entity(3, 1)
	assert a == b
}

fn test_restore_rejects_wrong_capacity_without_touching_world() {
	reg := core_registry() or { panic('registry basarisiz') }
	mut src := busy_world(&reg)
	data := src.snapshot()
	mut dst := snapshot_world(&reg, 16)
	_ = dst.spawn() or { panic('spawn none') }
	before := dst.snapshot()
	assert restore_fails(mut dst, data)
	assert dst.snapshot() == before
}

fn test_restore_rejects_schema_mismatch_without_touching_world() {
	reg := core_registry() or { panic('registry basarisiz') }
	mut src := busy_world(&reg)
	data := src.snapshot()
	mut small := Registry{}
	_ = small.register[Transform]() or { panic('register basarisiz') }
	mut dst := snapshot_world(&small, 8)
	before := dst.snapshot()
	assert restore_fails(mut dst, data)
	assert dst.snapshot() == before
}

fn test_restore_rejects_truncated_and_corrupted_without_touching_world() {
	reg := core_registry() or { panic('registry basarisiz') }
	mut src := busy_world(&reg)
	data := src.snapshot()
	mut dst := snapshot_world(&reg, 8)
	_ = dst.spawn() or { panic('spawn none') }
	before := dst.snapshot()
	assert restore_fails(mut dst, []u8{})
	assert restore_fails(mut dst, data[..data.len - 1])
	assert restore_fails(mut dst, data[..snapshot_header_size])
	mut bad_magic := data.clone()
	bad_magic[0] ^= 1
	assert restore_fails(mut dst, bad_magic)
	mut flipped := data.clone()
	flipped[flipped.len / 2] ^= 0x10
	assert restore_fails(mut dst, flipped)
	mut trailing := data.clone()
	trailing << u8(0)
	assert restore_fails(mut dst, trailing)
	assert dst.snapshot() == before
}

// 0xFFFF yıkım: slot nesil 0xFFFF ile serbest listede kalır, emekli değildir.
fn cycled_world(reg &Registry, n int) World {
	mut w := snapshot_world(reg, 8)
	for _ in 0 .. n {
		e := w.spawn() or { panic('spawn none') }
		assert w.despawn(e)
	}
	return w
}

fn test_snapshot_roundtrip_with_free_slot_at_max_generation() {
	reg := core_registry() or { panic('registry basarisiz') }
	mut src := cycled_world(&reg, 0xFFFF)
	assert src.entities().retired_count() == 0
	data := src.snapshot()
	mut dst := snapshot_world(&reg, 8)
	dst.restore(data) or { panic(err) }
	assert dst.snapshot() == data
	a := src.spawn() or { panic('spawn none') }
	b := dst.spawn() or { panic('spawn none') }
	assert a == make_entity(0, 0xFFFF)
	assert a == b
}

// Dense listesinde tekrarlı satır: sağlama yeniden mühürlenir, yine de reddedilir.
fn test_restore_rejects_duplicate_dense_row() {
	reg := core_registry() or { panic('registry basarisiz') }
	mut src := snapshot_world(&reg, 8)
	e0 := src.spawn() or { panic('spawn none') }
	e1 := src.spawn() or { panic('spawn none') }
	assert src.add_component(e0, transform_id) == .ok
	assert src.add_component(e1, transform_id) == .ok
	mut data := src.snapshot()
	// Başlık 36 + 2 slot × 7 = 50; store 0: alan sayısı 4 + 4 boyut × 4 = 70'te satır sayısı; dense satır 0 = 74, satır 1 = 78.
	assert get_le(data, 70, 4) == 2
	assert data[74] == 0 && data[78] == 1
	for k in 0 .. 4 {
		data[78 + k] = data[74 + k]
	}
	put_le(mut data, 32, u64(snapshot_checksum(data[snapshot_header_size..])), 4)
	mut dst := snapshot_world(&reg, 8)
	before := dst.snapshot()
	assert restore_fails(mut dst, data)
	assert dst.snapshot() == before
}
