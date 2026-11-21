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

fn test_hash_known_vector() {
	cfg := Config{
		capacity:        16
		queue_capacity:  64
		record_capacity: 64
	}
	s, region := open_sim(cfg)
	defer { memory.release(region) }
	// Boş dünya, tick 0: 8 sıfır baytın FNV-1a 64 özeti.
	assert state_hash(&s.world, 0) == u64(0xa8c7f832281a39c5)
}

// Aynı komut dizisi ayrı iki Sim'de aynı hash'i üretir; alan ya da tick değişince hash değişir.
fn run_scenario(x f32) (Sim, &u8) {
	cfg := Config{
		capacity:        16
		queue_capacity:  64
		record_capacity: 64
	}
	mut s, region := open_sim(cfg)
	e := s.world.spawn() or { panic('spawn none') }
	s.world.add_component(e, ecs.transform_id)
	s.world.add_component(e, ecs.body_id)
	s.push(cmd.Command{
		kind:   .set_field
		source: .agent
		comp:   ecs.transform_id
		field:  0
		entity: e
		value:  u64(math.f32_bits(x))
	})
	s.step()
	s.step()
	return s, region
}

fn test_hash_sensitive_and_stable() {
	a, ra := run_scenario(f32(3.0))
	defer { memory.release(ra) }
	b, rb := run_scenario(f32(3.0))
	defer { memory.release(rb) }
	c, rc := run_scenario(f32(4.0))
	defer { memory.release(rc) }
	assert a.state_hash() == b.state_hash()
	assert a.state_hash() != c.state_hash()
	assert state_hash(&a.world, 2) != state_hash(&a.world, 3)
}

// Dolu dünyanın altın vektörü: id 0 varlık, Transform.x=1.0, Transform.y=2.0, Body.vx=3.0 (diğer alanlar 0).
fn test_hash_golden_vector_non_empty_world() {
	reg := ecs.core_registry() or { panic(err) }
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	defer { memory.release(region) }
	mut a := memory.LinearArena.new(region, 1 << 20)
	mut w := ecs.World.new(mut a, &reg, 8) or { panic('World.new none') }
	e := w.spawn() or { panic('spawn none') }
	assert u64(e) == 0
	assert w.add_component(e, ecs.transform_id) == .ok
	assert w.add_component(e, ecs.body_id) == .ok
	assert w.set_field(e, ecs.transform_id, 0, u64(math.f32_bits(f32(1.0)))) == .ok
	assert w.set_field(e, ecs.transform_id, 1, u64(math.f32_bits(f32(2.0)))) == .ok
	assert w.set_field(e, ecs.body_id, 0, u64(math.f32_bits(f32(3.0)))) == .ok
	assert state_hash(&w, 0) == u64(0x776b582d1e09bfd9)
}
