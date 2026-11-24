module sim

import os
import ecs
import cmd
import memory
import math

fn replay_test_path(name string) string {
	return os.join_path(os.temp_dir(), 'vcore_sim_${name}.vcrc')
}

// Canlı senaryo: 10 varlık, Transform/Body, 500 adım, 3 set_field + 1 despawn, 500 adım.
// Kaydı dosyaya yazar ve kayıt durdurulduğundaki canlı hash'i döner.
fn record_live_scenario(path string, reg &ecs.Registry) u64 {
	cfg := Config{
		capacity:        64
		queue_capacity:  256
		record_capacity: 4096
	}
	need := cfg.bytes_needed(reg)
	region := memory.reserve(need) or { panic('reserve basarisiz') }
	defer { memory.release(region) }
	mut a := memory.LinearArena.new(region, need)
	mut s := Sim.new(mut a, reg, cfg) or { panic('Sim.new none') }

	s.start_recording()
	for _ in 0 .. 10 {
		s.push(cmd.Command{
			kind:   .spawn
			source: .agent
		})
	}
	_ = s.flush()
	for i in 0 .. 10 {
		e := ecs.make_entity(u32(i), 0)
		assert s.world.is_alive(e)
		s.push(cmd.Command{
			kind:   .add_component
			source: .agent
			comp:   ecs.transform_id
			entity: e
		})
		s.push(cmd.Command{
			kind:   .add_component
			source: .agent
			comp:   ecs.body_id
			entity: e
		})
		s.push(cmd.Command{
			kind:   .set_field
			source: .agent
			comp:   ecs.body_id
			field:  0
			entity: e
			value:  u64(math.f32_bits(f32(1.0)))
		})
	}
	_ = s.flush()
	for _ in 0 .. 500 {
		s.step()
	}
	// Sıfır olmayan tick'te spawn: kayıtlı id'nin ayrışma kontrolü de orada sınanır.
	s.push(cmd.Command{
		kind:   .spawn
		source: .agent
	})
	s.push(cmd.Command{
		kind:   .set_field
		source: .agent
		comp:   ecs.body_id
		field:  1
		entity: ecs.make_entity(2, 0)
		value:  u64(math.f32_bits(f32(-0.5)))
	})
	s.push(cmd.Command{
		kind:   .set_field
		source: .agent
		comp:   ecs.body_id
		field:  0
		entity: ecs.make_entity(4, 0)
		value:  u64(math.f32_bits(f32(2.5)))
	})
	s.push(cmd.Command{
		kind:   .set_field
		source: .agent
		comp:   ecs.transform_id
		field:  0
		entity: ecs.make_entity(6, 0)
		value:  u64(math.f32_bits(f32(7.0)))
	})
	s.push(cmd.Command{
		kind:   .despawn
		source: .agent
		entity: ecs.make_entity(8, 0)
	})
	for _ in 0 .. 500 {
		s.step()
	}
	s.recorder.stop()
	s.recorder.save(path, cfg.capacity, s.tick()) or { panic(err) }
	return s.state_hash()
}

// Kaydı yeniden oynatır ve hata mesajını döner; başarılıysa boş string.
fn replay_error(rec cmd.Recording, reg &ecs.Registry) string {
	_ = replay(rec, reg) or { return err.msg() }
	return ''
}

// Verilen indeksteki girdinin entity alanını değiştirilmiş bir kopya kurar.
fn with_entity(rec cmd.Recording, idx int, e ecs.EntityID) cmd.Recording {
	mut entries := rec.entries.clone()
	mut c := entries[idx].cmd
	c.entity = e
	entries[idx] = cmd.RecordEntry{
		tick: entries[idx].tick
		cmd:  c
	}
	return cmd.Recording{
		capacity: rec.capacity
		end_tick: rec.end_tick
		entries:  entries
	}
}

fn test_record_replay_twice_bit_identical() {
	reg := ecs.core_registry() or { panic(err) }
	path := replay_test_path('bit_identical')
	defer {
		os.rm(path) or {}
	}
	live := record_live_scenario(path, &reg)
	rec := cmd.load_recording(path) or { panic(err) }
	assert rec.end_tick == 1000
	a := replay(rec, &reg) or { panic(err) }
	b := replay(rec, &reg) or { panic(err) }
	assert a.hash == live && b.hash == live && a.end_tick == 1000
}

fn test_replay_detects_divergence() {
	reg := ecs.core_registry() or { panic(err) }
	path := replay_test_path('divergence')
	defer {
		os.rm(path) or {}
	}
	record_live_scenario(path, &reg)
	rec := cmd.load_recording(path) or { panic(err) }

	// Varolmayan bir varlığa set_field: hata, ilk set_field'in tick'ini adlandırmalı.
	mut first_set := -1
	for i, e in rec.entries {
		if e.cmd.kind == .set_field {
			first_set = i
			break
		}
	}
	assert first_set >= 0
	bad_set := with_entity(rec, first_set, ecs.make_entity(9999, 0))
	assert replay_error(bad_set, &reg).starts_with('replay diverged: tick ${rec.entries[first_set].tick} entry ${first_set} ')

	// Spawn'ın üreteceği id farklıysa hata: ilk spawn tick 0'da.
	bad_spawn := with_entity(rec, 0, ecs.make_entity(9999, 0))
	assert replay_error(bad_spawn, &reg).starts_with('replay diverged: tick 0 entry 0 ')
}

// Sıfır olmayan tick'te ayrışma: tick 500'deki ilk set_field ve spawn hata mesajında tick'i adlandırmalı.
fn test_replay_divergence_reports_nonzero_tick() {
	reg := ecs.core_registry() or { panic(err) }
	path := replay_test_path('divergence_500')
	defer {
		os.rm(path) or {}
	}
	record_live_scenario(path, &reg)
	rec := cmd.load_recording(path) or { panic(err) }

	mut set_idx := -1
	mut spawn_idx := -1
	for i, e in rec.entries {
		if e.tick == 500 && e.cmd.kind == .set_field && set_idx < 0 {
			set_idx = i
		}
		if e.tick == 500 && e.cmd.kind == .spawn && spawn_idx < 0 {
			spawn_idx = i
		}
	}
	assert set_idx >= 0 && spawn_idx >= 0

	bad_set := with_entity(rec, set_idx, ecs.make_entity(9999, 0))
	assert replay_error(bad_set, &reg).starts_with('replay diverged: tick 500 ')

	bad_spawn := with_entity(rec, spawn_idx, ecs.make_entity(9999, 0))
	assert replay_error(bad_spawn, &reg).starts_with('replay diverged: tick 500 ')
}

// Kapasitesi ayrılamayacak kadar büyük kayıt: bölge ayrılamaz, hata döner, panic olmaz.
fn test_replay_reservation_failure_returns_error() {
	reg := ecs.core_registry() or { panic(err) }
	rec := cmd.Recording{
		capacity: 0xFFFF_FFF0
		end_tick: 1
		entries:  [
			cmd.RecordEntry{
				tick: 0
				cmd:  cmd.Command{
					kind:   .spawn
					source: .agent
				}
			},
		]
	}
	msg := replay_error(rec, &reg)
	assert msg.starts_with('replay setup failed: ')
}

fn test_replay_rejects_non_monotonic_ticks() {
	reg := ecs.core_registry() or { panic(err) }
	rec := cmd.Recording{
		capacity: 64
		end_tick: 10
		entries:  [
			cmd.RecordEntry{
				tick: 5
				cmd:  cmd.Command{
					kind:   .spawn
					source: .agent
				}
			},
			cmd.RecordEntry{
				tick: 3
				cmd:  cmd.Command{
					kind:   .spawn
					source: .agent
				}
			},
		]
	}
	assert replay_error(rec, &reg) == 'replay ayrıştı: tick 3: kayıt sırası monoton değil (önceki tick 5)'
}

fn test_replay_rejects_end_tick_before_last_entry() {
	reg := ecs.core_registry() or { panic(err) }
	rec := cmd.Recording{
		capacity: 64
		end_tick: 4
		entries:  [
			cmd.RecordEntry{
				tick: 5
				cmd:  cmd.Command{
					kind:   .spawn
					source: .agent
				}
			},
		]
	}
	assert replay_error(rec, &reg) == 'replay ayrıştı: tick 4: bitiş son girdiden (tick 5) önce'
}

fn new_replay_sim(reg &ecs.Registry, cfg Config) (Sim, &u8) {
	need := cfg.bytes_needed(reg)
	region := memory.reserve(need) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, need)
	s := Sim.new(mut a, reg, cfg) or { panic('Sim.new none') }
	return s, region
}

// Dünya görüntüsü: boşluklu, emekli slotlu ve nesli > 0 bir dünya geri yüklenince hash ve sonraki id aynıdır.
fn test_snapshot_restore_matches_hash_and_next_id() {
	reg := ecs.core_registry() or { panic('registry basarisiz') }
	cfg := Config{
		capacity:        16
		queue_capacity:  64
		record_capacity: 64
	}
	need := cfg.bytes_needed(&reg)
	region_a := memory.reserve(need) or { panic('reserve basarisiz') }
	defer { memory.release(region_a) }
	mut a := memory.LinearArena.new(region_a, need)
	mut src := Sim.new(mut a, &reg, cfg) or { panic('Sim.new none') }
	region_b := memory.reserve(need) or { panic('reserve basarisiz') }
	defer { memory.release(region_b) }
	mut b := memory.LinearArena.new(region_b, need)
	mut dst := Sim.new(mut b, &reg, cfg) or { panic('Sim.new none') }

	for _ in 0 .. 3 {
		e := src.world.spawn() or { panic('spawn none') }
		assert src.world.despawn(e)
	}
	mut es := []ecs.EntityID{}
	for _ in 0 .. 5 {
		es << src.world.spawn() or { panic('spawn none') }
	}
	for e in es {
		_ = src.world.add_component(e, ecs.transform_id)
		_ = src.world.add_component(e, ecs.body_id)
		_ = src.world.set_field(e, ecs.body_id, 0, u64(math.f32_bits(f32(e.index()) + 0.5)))
	}
	assert src.world.despawn(es[1])
	assert src.world.despawn(es[3])
	for _ in 0 .. 25 {
		src.step()
	}
	dst.world.restore(src.world.snapshot()) or { panic(err) }
	dst.set_tick(src.tick())
	assert dst.state_hash() == src.state_hash()
	for _ in 0 .. 10 {
		src.step()
		dst.step()
	}
	assert dst.state_hash() == src.state_hash()
	ea := src.world.spawn() or { panic('spawn none') }
	eb := dst.world.spawn() or { panic('spawn none') }
	assert ea == eb
	assert dst.state_hash() == src.state_hash()
}

// Sürüm 1 kaydı (boş dünya, tick 0, görüntü yok) hâlâ oynatılır ve canlı durumla aynı hash'i verir.
fn test_v1_recording_still_replays() {
	reg := ecs.core_registry() or { panic('registry basarisiz') }
	e := ecs.make_entity(0, 0)
	value := u64(math.f32_bits(f32(2.5)))
	rec := cmd.Recording{
		capacity:   16
		start_tick: 0
		end_tick:   4
		snapshot:   []u8{}
		entries:    [
			cmd.RecordEntry{
				tick: 0
				cmd:  cmd.Command{ kind: .spawn, source: .agent, entity: e }
			},
			cmd.RecordEntry{
				tick: 0
				cmd:  cmd.Command{ kind: .add_component, source: .agent, entity: e, comp: ecs.transform_id }
			},
			cmd.RecordEntry{
				tick: 1
				cmd:  cmd.Command{ kind: .set_field, source: .agent, entity: e, comp: ecs.transform_id, field: 0, value: value }
			},
		]
	}
	res := replay(rec, &reg) or { panic(err) }
	mut live, region := new_replay_sim(&reg, Config{ capacity: 16, queue_capacity: 64, record_capacity: 64 })
	defer { memory.release(region) }
	_ = cmd.apply(mut live.world, rec.entries[0].cmd)
	_ = cmd.apply(mut live.world, rec.entries[1].cmd)
	live.step()
	_ = cmd.apply(mut live.world, rec.entries[2].cmd)
	for _ in 0 .. 3 {
		live.step()
	}
	assert res.end_tick == 4
	assert res.hash == live.state_hash()
}
