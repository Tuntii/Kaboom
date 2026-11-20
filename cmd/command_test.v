module cmd

import ecs
import memory
import math

// Test dünyası: bölge ve dünya birlikte döner; çağıran bölgeyi defer ile serbest bırakır.
fn new_world(capacity u32) (&u8, ecs.World) {
	reg := ecs.core_registry() or { panic('registry basarisiz') }
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, 1 << 20)
	w := ecs.World.new(mut a, &reg, capacity) or { panic('World.new none') }
	return region, w
}

fn test_command_is_24_bytes() {
	assert sizeof(Command) == 24
	assert sizeof(CommandKind) == 1
	assert sizeof(Source) == 1
}

fn test_source_order_is_application_order() {
	assert u8(Source.script) < u8(Source.editor)
	assert u8(Source.editor) < u8(Source.agent)
}

fn test_apply_each_kind() {
	region, mut w := new_world(8)
	defer {
		memory.release(region)
	}
	sp := apply(mut w, Command{ kind: .spawn, source: .agent })
	assert sp.status == .ok
	e := sp.entity
	assert !e.is_null()
	assert apply(mut w, Command{ kind: .add_component, entity: e, comp: ecs.body_id }).status == .ok
	assert apply(mut w, Command{
		kind:   .set_field
		entity: e
		comp:   ecs.body_id
		field:  1
		value:  u64(math.f32_bits(3.0))
	}).status == .ok
	assert apply(mut w, Command{ kind: .remove_component, entity: e, comp: ecs.body_id }).status == .ok
	assert apply(mut w, Command{ kind: .despawn, entity: e }).status == .ok
	assert apply(mut w, Command{ kind: .despawn, entity: e }).status == .dead_entity
}

fn test_apply_result_entity_is_command_entity() {
	region, mut w := new_world(8)
	defer {
		memory.release(region)
	}
	sp := apply(mut w, Command{ kind: .spawn, source: .script })
	e := sp.entity
	assert apply(mut w, Command{ kind: .remove_component, entity: e, comp: ecs.body_id }).entity == e
	assert apply(mut w, Command{ kind: .despawn, entity: e }).entity == e
}

fn test_remove_missing_component() {
	region, mut w := new_world(8)
	defer {
		memory.release(region)
	}
	e := apply(mut w, Command{ kind: .spawn }).entity
	assert apply(mut w, Command{ kind: .remove_component, entity: e, comp: ecs.body_id }).status == .missing_component
}

fn test_spawn_capacity_full() {
	region, mut w := new_world(2)
	defer {
		memory.release(region)
	}
	assert apply(mut w, Command{ kind: .spawn }).status == .ok
	assert apply(mut w, Command{ kind: .spawn }).status == .ok
	third := apply(mut w, Command{ kind: .spawn })
	assert third.status == .capacity_full
	assert third.entity == ecs.null_entity
}
