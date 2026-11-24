module sim

import ecs
import cmd
import memory
import math

// Test için bellek ayırır ve Sim kurar; bölge çağıran tarafından serbest bırakılır.
fn open_sim(cfg Config) (Sim, &u8) {
	reg := ecs.core_registry() or { panic(err) }
	need := cfg.bytes_needed(&reg)
	region := memory.reserve(need) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, need)
	s := Sim.new(mut a, &reg, cfg) or { panic('Sim.new none') }
	return s, region
}

// Sim.flush dış komutları geçmişe yazar: spawn'ın ters işlemi tek bir undo grubudur.
fn test_sim_flush_records_history() {
	cfg := Config{
		capacity:        16
		queue_capacity:  64
		record_capacity: 64
	}
	mut s, region := open_sim(cfg)
	defer { memory.release(region) }
	s.push(cmd.Command{
		kind:   .spawn
		source: .agent
	})
	assert s.flush() == 1
	assert s.history.undo_len() == 1
}

fn read_f32(s &Sim, e ecs.EntityID, comp u16, field u16) f32 {
	bits := s.world.get_field(e, comp, field) or { panic('get_field none') }
	return math.f32_from_bits(u32(bits))
}

fn test_step_order_and_motion() {
	cfg := Config{
		capacity:        16
		queue_capacity:  64
		record_capacity: 64
	}
	mut s, region := open_sim(cfg)
	defer { memory.release(region) }
	e := s.world.spawn() or { panic('spawn none') }
	s.world.add_component(e, ecs.transform_id)
	s.world.add_component(e, ecs.body_id)
	s.world.set_field(e, ecs.body_id, 0, u64(math.f32_bits(f32(1.0))))
	s.step()
	assert read_f32(&s, e, ecs.transform_id, 2) == 0 // prev_x
	assert read_f32(&s, e, ecs.transform_id, 0) == dt // x
	assert s.tick() == 1

	// Yalnız Transform: komutla yapılan ışınlanma süzülmez, prev_x de yeni konumu alır.
	e2 := s.world.spawn() or { panic('spawn none') }
	s.world.add_component(e2, ecs.transform_id)
	s.push(cmd.Command{
		kind:   .set_field
		source: .agent
		comp:   ecs.transform_id
		field:  0
		entity: e2
		value:  u64(math.f32_bits(f32(9.0)))
	})
	s.step()
	assert read_f32(&s, e2, ecs.transform_id, 2) == 9
	assert read_f32(&s, e2, ecs.transform_id, 0) == 9
}

fn test_thousand_steps() {
	cfg := Config{
		capacity:        16
		queue_capacity:  64
		record_capacity: 64
	}
	mut s, region := open_sim(cfg)
	defer { memory.release(region) }
	e := s.world.spawn() or { panic('spawn none') }
	s.world.add_component(e, ecs.transform_id)
	s.world.add_component(e, ecs.body_id)
	s.world.set_field(e, ecs.body_id, 0, u64(math.f32_bits(f32(1.0))))
	mut want := f32(0.0)
	for _ in 0 .. 1000 {
		s.step()
		want += f32(1.0) * dt
	}
	assert read_f32(&s, e, ecs.transform_id, 0) == want
}

fn test_bytes_needed_is_enough() {
	reg := ecs.core_registry() or { panic(err) }
	cfg := Config{
		capacity:        1000
		queue_capacity:  1024
		record_capacity: 1024
	}
	need := cfg.bytes_needed(&reg)
	region := memory.reserve(need) or { panic('reserve basarisiz') }
	defer { memory.release(region) }
	mut a := memory.LinearArena.new(region, need)
	_ = Sim.new(mut a, &reg, cfg) or { panic('Sim.new tam bytes_needed ile basarisiz') }
}

// Transform/Body yoksa Sim kurulmaz ve parent bellek ayrılmaz.
fn test_new_none_without_transform_or_body() {
	reg := ecs.Registry{}
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	defer { memory.release(region) }
	mut a := memory.LinearArena.new(region, 1 << 20)
	if _ := Sim.new(mut a, &reg, Config{ capacity: 16, queue_capacity: 16, record_capacity: 16 }) {
		assert false
	}
	assert a.used() == 0
}

fn test_new_failure_rewinds_parent() {
	reg := ecs.core_registry() or { panic(err) }
	cfg := Config{
		capacity:        1000
		queue_capacity:  1024
		record_capacity: 1024
	}
	need := cfg.bytes_needed(&reg)
	region := memory.reserve(need) or { panic('reserve basarisiz') }
	defer { memory.release(region) }
	mut a := memory.LinearArena.new(region, need / 2)
	if _ := Sim.new(mut a, &reg, cfg) {
		assert false
	}
	assert a.used() == 0
}
