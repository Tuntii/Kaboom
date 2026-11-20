module cmd

import ecs
import memory
import math
import os

fn bits(f f32) u64 {
	return u64(math.f32_bits(f))
}

fn f32_of(b u64) f32 {
	return math.f32_from_bits(u32(b))
}

// Test ortamı: dünya, kuyruk ve kayıt ayni bölgeden kurulur; çağıran bölgeyi serbest bırakır.
fn queue_env(queue_cap u32, rec_cap u32) (&u8, ecs.World, CommandQueue, Recorder) {
	reg := ecs.core_registry() or { panic('registry basarisiz') }
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, 1 << 20)
	w := ecs.World.new(mut a, &reg, 8) or { panic('World.new none') }
	q := CommandQueue.new(mut a, queue_cap) or { panic('CommandQueue.new none') }
	rec := Recorder.new(mut a, rec_cap) or { panic('Recorder.new none') }
	return region, w, q, rec
}

fn test_flush_applies_by_source_class_then_push_order() {
	region, mut w, mut q, mut rec := queue_env(8, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	q.push(Command{ kind: .set_field, source: .agent, entity: e, comp: 0, field: 0, value: bits(3.0) })
	q.push(Command{ kind: .set_field, source: .script, entity: e, comp: 0, field: 0, value: bits(1.0) })
	q.push(Command{ kind: .set_field, source: .editor, entity: e, comp: 0, field: 0, value: bits(2.0) })
	assert q.flush(mut w, 0, mut rec) == 3
	assert f32_of(w.get_field(e, 0, 0) or { panic('get') }) == 3.0 // agent en son uygulanır
	assert q.result(1).status == .ok
	assert q.result(0).status == .ok
	assert q.result(2).status == .ok
}

// Aynı sınıftaki komutlar push sırasıyla uygulanır: son push edilen kazanır.
fn test_flush_push_order_within_class() {
	region, mut w, mut q, mut rec := queue_env(8, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	q.push(Command{ kind: .set_field, source: .editor, entity: e, comp: 0, field: 0, value: bits(5.0) })
	q.push(Command{ kind: .set_field, source: .editor, entity: e, comp: 0, field: 0, value: bits(6.0) })
	assert q.flush(mut w, 0, mut rec) == 2
	assert f32_of(w.get_field(e, 0, 0) or { panic('get') }) == 6.0
}

fn test_flush_records_ok_only_with_spawn_id() {
	region, mut w, mut q, mut rec := queue_env(8, 8)
	defer {
		memory.release(region)
	}
	rec.start()
	q.push(Command{ kind: .spawn, source: .agent })
	q.push(Command{ kind: .despawn, source: .agent, entity: ecs.make_entity(99, 0) }) // dead_entity
	assert q.flush(mut w, 7, mut rec) == 1
	assert rec.len() == 1
	spawned := q.result(0).entity
	assert q.result(1).status == .dead_entity
	path := os.join_path(os.temp_dir(), 'vcore_cmd_flush_ids.vcrc')
	defer {
		os.rm(path) or {}
	}
	rec.save(path, 8, 7) or { panic(err) }
	got := load_recording(path) or { panic(err) }
	assert got.entries.len == 1
	assert got.entries[0].tick == 7
	assert got.entries[0].cmd.kind == .spawn
	assert got.entries[0].cmd.entity == spawned
	assert !spawned.is_null()
}

// Flush iki kez çağrılırsa komutlar yeniden uygulanmaz.
fn test_flush_twice_applies_once() {
	region, mut w, mut q, mut rec := queue_env(8, 8)
	defer {
		memory.release(region)
	}
	q.push(Command{ kind: .spawn, source: .script })
	assert q.flush(mut w, 0, mut rec) == 1
	assert q.flush(mut w, 0, mut rec) == 0
	assert w.alive_count() == 1
}

fn test_push_full_returns_false() {
	region, _, mut q, _ := queue_env(2, 8)
	defer {
		memory.release(region)
	}
	assert q.push(Command{ kind: .spawn, source: .agent })
	assert q.push(Command{ kind: .spawn, source: .agent })
	assert !q.push(Command{ kind: .spawn, source: .agent })
	assert q.len() == 2
}

// Flush'tan sonraki ilk push kuyruğu ve sonuçları temizler.
fn test_push_after_flush_resets_queue() {
	region, mut w, mut q, mut rec := queue_env(2, 8)
	defer {
		memory.release(region)
	}
	q.push(Command{ kind: .spawn, source: .agent })
	q.push(Command{ kind: .spawn, source: .agent })
	assert q.flush(mut w, 0, mut rec) == 2
	assert q.push(Command{ kind: .spawn, source: .agent })
	assert q.len() == 1
	assert q.flush(mut w, 1, mut rec) == 1
	assert w.alive_count() == 3
}
