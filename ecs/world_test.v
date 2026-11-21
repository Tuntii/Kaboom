module ecs

import memory
import math

fn new_world() World {
	reg := core_registry() or { panic('registry basarisiz') }
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, 1 << 20)
	return World.new(mut a, &reg, 8) or { panic('World.new none') }
}

fn test_spawn_add_set_get() {
	mut w := new_world()
	e := w.spawn()?
	assert w.add_component(e, transform_id) == .ok
	assert w.add_component(e, transform_id) == .already_has
	assert w.set_field(e, transform_id, 0, u64(math.f32_bits(4.0))) == .ok
	assert math.f32_from_bits(u32(w.get_field(e, transform_id, 0)?)) == 4.0
	assert w.set_field(e, body_id, 0, 0) == .missing_component
	assert w.set_field(e, transform_id, 9, 0) == .unknown_field
	assert w.add_component(e, 7) == .unknown_component
}

fn test_despawn_clears_stores_and_stale_handle() {
	mut w := new_world()
	e := w.spawn()?
	w.add_component(e, transform_id)
	w.add_component(e, body_id)
	assert w.despawn(e)
	assert w.store(transform_id).len() == 0 && w.store(body_id).len() == 0
	assert w.set_field(e, transform_id, 0, 0) == .dead_entity
	assert w.add_component(EntityID(u64(e) | (u64(1) << 50)), transform_id) == .dead_entity
	assert !w.despawn(e)
}

fn test_capacity_full() {
	mut w := new_world()
	for _ in 0 .. 8 {
		w.spawn()?
	}
	assert w.spawn() == none
}

fn test_remove_component_status() {
	mut w := new_world()
	e := w.spawn()?
	assert w.remove_component(e, transform_id) == .missing_component
	assert w.add_component(e, transform_id) == .ok
	assert w.remove_component(e, transform_id) == .ok
	assert !w.has(e, transform_id)
	assert w.remove_component(e, 7) == .unknown_component
	w.despawn(e)
	assert w.remove_component(e, transform_id) == .dead_entity
}

// Yeniden kullanılan slot eski bileşenini ve eski alan değerini görmemeli.
fn test_reused_slot_starts_clean() {
	mut w := new_world()
	e := w.spawn()?
	w.add_component(e, transform_id)
	w.set_field(e, transform_id, 0, u64(math.f32_bits(9.0)))
	w.despawn(e)
	e2 := w.spawn()?
	assert e2.index() == e.index() && e2 != e
	assert !w.has(e, transform_id)
	assert w.get_field(e, transform_id, 0) == none
	assert w.add_component(e2, transform_id) == .ok
	assert w.get_field(e2, transform_id, 0)? == 0
}

fn test_alive_count_and_entities() {
	mut w := new_world()
	e1 := w.spawn()?
	_ := w.spawn()?
	assert w.alive_count() == 2
	w.despawn(e1)
	assert w.alive_count() == 1
	assert w.is_alive(e1) == false
	assert w.entities().alive_count() == 1
	assert w.store_count() == 3
}

// Kurulum başarısız olursa parent arena başlangıç imlecine dönmeli.
fn test_new_rewinds_parent_on_failure() {
	reg := core_registry() or { panic('registry basarisiz') }
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	// 200 B: EntityAllocator (~136 B) sığar, ilk store sığmaz; hata store aşamasında çıkar.
	mut a := memory.LinearArena.new(region, 200)
	assert World.new(mut a, &reg, 8) == none
	assert a.used() == 0
}
