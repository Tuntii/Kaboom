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

	s.recorder.start()
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
	assert replay_error(bad_set, &reg) == 'replay ayrıştı: tick ${rec.entries[first_set].tick}'

	// Spawn'ın üreteceği id farklıysa hata: ilk spawn tick 0'da.
	bad_spawn := with_entity(rec, 0, ecs.make_entity(9999, 0))
	assert replay_error(bad_spawn, &reg) == 'replay ayrıştı: tick 0'
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
	assert replay_error(bad_set, &reg) == 'replay ayrıştı: tick 500'

	bad_spawn := with_entity(rec, spawn_idx, ecs.make_entity(9999, 0))
	assert replay_error(bad_spawn, &reg) == 'replay ayrıştı: tick 500'
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
	assert msg.starts_with('replay: bolge ayrilamadi')
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
