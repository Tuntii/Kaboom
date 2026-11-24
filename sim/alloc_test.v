module sim

import ecs
import cmd
import memory

// Test için bellek ayırır ve Sim kurar; bölge çağıran tarafından serbest bırakılır.
fn open_sim(cfg Config) (Sim, &u8) {
	reg := ecs.core_registry() or { panic(err) }
	need := cfg.bytes_needed(&reg)
	region := memory.reserve(need) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, need)
	s := Sim.new(mut a, &reg, cfg) or { panic('Sim.new none') }
	return s, region
}

// -d track_heap ile çalıştırıldığında tick yolunun sıfır heap tahsisi yaptığını kanıtlar.
fn test_tick_has_zero_heap_allocs() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap ile calistir')
		return
	}
	// Kanca gerçekten sayıyor mu?
	x := 'canli mi'.repeat(3)
	before0 := memory.heap_alloc_count()
	_ = x + '!'
	assert memory.heap_alloc_count() > before0

	cfg := Config{
		capacity:        1024
		queue_capacity:  1024
		record_capacity: 200_000
	}
	mut s, region := open_sim(cfg)
	defer { memory.release(region) }
	for _ in 0 .. 1000 {
		e := s.world.spawn() or { panic('spawn none') }
		s.world.add_component(e, ecs.transform_id)
		s.world.add_component(e, ecs.body_id)
	}
	s.start_recording()
	before := memory.heap_alloc_count()
	for _ in 0 .. 100 {
		for i in 0 .. 1000 {
			s.push(cmd.Command{
				kind:   .set_field
				source: .agent
				comp:   ecs.body_id
				field:  0
				entity: ecs.make_entity(u32(i), 0)
				value:  0
			})
		}
		s.step()
	}
	assert memory.heap_alloc_count() == before
	// Geçmiş gerçekten yakalıyor olmalı; aksi halde sıfır tahsis kanıtı geçmişi kapsamaz.
	assert s.history.undo_len() > 0

	// Yapısal komutlar (add, remove, despawn, spawn) da geçmişe yazılır; ölçülen tick'lerde tahsissiz olmalı.
	e0 := s.world.spawn() or { panic('spawn none') }
	assert s.world.add_component(e0, ecs.body_id) == .ok
	mut e1 := s.world.spawn() or { panic('spawn none') }
	before2 := memory.heap_alloc_count()
	for _ in 0 .. 100 {
		s.push(cmd.Command{ kind: .add_component, source: .agent, comp: ecs.transform_id, entity: e1 })
		s.push(cmd.Command{ kind: .remove_component, source: .agent, comp: ecs.body_id, entity: e0 })
		s.push(cmd.Command{ kind: .add_component, source: .agent, comp: ecs.body_id, entity: e0 })
		s.push(cmd.Command{ kind: .despawn, source: .agent, entity: e1 })
		s.push(cmd.Command{ kind: .spawn, source: .agent })
		s.step()
		// Her yapısal komut gerçekten uygulanmış olmalı; yoksa test boş yere geçer.
		assert s.queue.result(0).status == .ok && s.queue.result(1).status == .ok
		assert s.queue.result(2).status == .ok && s.queue.result(3).status == .ok
		// Son komut (spawn) dönen yeni id'yi sonraki tick'in e1'i yapar.
		e1 = s.queue.result(4).entity
	}
	assert memory.heap_alloc_count() == before2
}
