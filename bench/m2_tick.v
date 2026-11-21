module main

import os
import time
import math
import memory
import ecs
import cmd
import sim
import bench.benchkit

// M2 benchmark: 100k varlik uzerinde tick, komut flush ve durum hash'i. Veri splitmix64 ile tohumdan uretilir.
const suite_name = 'm2_tick'
const seed = u64(0x5EED)
const entity_count = u32(100_000)
const queue_capacity = u32(131_072)
const warmup = 10
const iterations = 200
// Determinizm kontrolunde her Sim'in kac adim kosacagi.
const det_steps = 1000
const fld_x = u16(0)
const fld_y = u16(1)
const fld_vx = u16(0)
const fld_vy = u16(1)

// Splitmix64 durumu. Ayni tohum ayni diziyi uretir.
struct Rng {
mut:
	state u64
}

fn (mut r Rng) next() u64 {
	r.state += u64(0x9E3779B97F4A7C15)
	mut z := r.state
	z = (z ^ (z >> 30)) * u64(0xBF58476D1CE4E5B9)
	z = (z ^ (z >> 27)) * u64(0x94D049BB133111EB)
	return z ^ (z >> 31)
}

// [lo, hi) araliginda f32. Ust 24 bit kullanilir; bolen 2^24 oldugu icin kesin.
fn (mut r Rng) f32_in(lo f32, hi f32) f32 {
	x := r.next()
	return lo + (hi - lo) * f32(u32(x >> 40)) / f32(1 << 24)
}

fn config() sim.Config {
	return sim.Config{
		capacity:        entity_count
		queue_capacity:  queue_capacity
		record_capacity: 1
	}
}

fn set_cmd(comp u16, field u16, e ecs.EntityID, v f32) cmd.Command {
	return cmd.Command{
		kind:   .set_field
		source: .editor
		comp:   comp
		field:  field
		entity: e
		value:  u64(math.f32_bits(v))
	}
}

// Komutlari kuyruk kapasitesi kadar parcalar halinde iter: push, flush. Her batch tamamen ok olmali.
fn push_batched(mut s sim.Sim, cmds []cmd.Command) {
	for start := 0; start < cmds.len; start += int(queue_capacity) {
		end := if start + int(queue_capacity) < cmds.len { start + int(queue_capacity) } else { cmds.len }
		for i in start .. end {
			if !s.push(cmds[i]) {
				panic('komut kuyruga sigmadi')
			}
		}
		if s.flush() != u32(end - start) {
			panic('komut batch: beklenenden az ok')
		}
	}
}

// Kurulum: varlik ac (spawn sonuclarindan id oku), sonra Transform + Body ve alanlari yaz.
fn setup(mut s sim.Sim, mut rng Rng) []ecs.EntityID {
	mut ids := []ecs.EntityID{len: int(entity_count)}
	for base := 0; base < int(entity_count); base += int(queue_capacity) {
		end := if base + int(queue_capacity) < int(entity_count) {
			base + int(queue_capacity)
		} else {
			int(entity_count)
		}
		for _ in base .. end {
			if !s.push(cmd.Command{ kind: .spawn, source: .editor }) {
				panic('spawn kuyruga sigmadi')
			}
		}
		if s.flush() != u32(end - base) {
			panic('spawn: beklenenden az ok')
		}
		for i in base .. end {
			r := s.queue.result(u32(i - base))
			if r.status != .ok {
				panic('spawn basarisiz')
			}
			ids[i] = r.entity
		}
	}

	mut cmds := []cmd.Command{cap: int(entity_count) * 6}
	for e in ids {
		cmds << cmd.Command{
			kind:   .add_component
			source: .editor
			comp:   ecs.transform_id
			entity: e
		}
		cmds << cmd.Command{
			kind:   .add_component
			source: .editor
			comp:   ecs.body_id
			entity: e
		}
		cmds << set_cmd(ecs.transform_id, fld_x, e, rng.f32_in(-100.0, 100.0))
		cmds << set_cmd(ecs.transform_id, fld_y, e, rng.f32_in(-100.0, 100.0))
		cmds << set_cmd(ecs.body_id, fld_vx, e, rng.f32_in(-10.0, 10.0))
		cmds << set_cmd(ecs.body_id, fld_vy, e, rng.f32_in(-10.0, 10.0))
	}
	push_batched(mut s, cmds)
	return ids
}

// Ayni tohumla bir Sim kurar, det_steps adim kosar ve durum hash'ini doner. Bellek kosu sonunda birakilir.
fn determinism_run(reg &ecs.Registry) u64 {
	region_size := config().bytes_needed(reg)
	region := memory.reserve(region_size) or { panic('determinizm: bolge ayrilamadi') }
	defer {
		memory.release(region)
	}
	mut arena := memory.LinearArena.new(region, region_size)
	mut s := sim.Sim.new(mut arena, reg, config()) or { panic('determinizm: sim kurulamadi') }
	mut rng := Rng{
		state: seed
	}
	setup(mut s, mut rng)
	for _ in 0 .. det_steps {
		s.step()
	}
	return s.state_hash()
}

fn main() {
	label := if os.args.len > 1 { os.args[1] } else { 'local' }
	reg := ecs.core_registry() or { panic('registry kurulamadi') }

	// Iki ayri Sim, ayni tohum: hash'ler esit olmali.
	h1 := determinism_run(&reg)
	h2 := determinism_run(&reg)
	if h1 != h2 {
		panic('determinizm: ayni tohum farkli hash (0x${h1:016x} != 0x${h2:016x})')
	}
	println('determinizm: ok, ${det_steps} adim, hash 0x${h1:016x}')

	region_size := config().bytes_needed(&reg)
	region := memory.reserve(region_size) or { panic('bolge ayrilamadi') }
	mut arena := memory.LinearArena.new(region, region_size)
	mut s := sim.Sim.new(mut arena, &reg, config()) or { panic('sim kurulamadi') }
	mut rng := Rng{
		state: seed
	}
	ids := setup(mut s, mut rng)
	mem := arena.used()

	// Komut flush olcumu icin 100k set_field, kurulum disinda hazirlanir.
	mut flush_cmds := []cmd.Command{len: int(entity_count)}
	for i, e in ids {
		flush_cmds[i] = set_cmd(ecs.transform_id, fld_x, e, rng.f32_in(-100.0, 100.0))
	}

	sp := &s
	f_tick := fn [sp] () {
		mut m := unsafe { sp }
		m.step()
	}
	tick_stats := benchkit.measure(warmup, iterations, f_tick)
	tick_hash := s.state_hash()

	fp := &flush_cmds
	f_flush := fn [sp, fp] () {
		mut m := unsafe { sp }
		cs := unsafe { fp }
		for i in 0 .. cs.len {
			if !m.push(unsafe { cs[i] }) {
				panic('cmd_flush: push basarisiz')
			}
		}
		if m.flush() != entity_count {
			panic('cmd_flush: ok sayisi beklenenden az')
		}
	}
	flush_stats := benchkit.measure(warmup, iterations, f_flush)

	// Hash'in optimizasyonla silinmemesi icin sonuc bir hedefe yazilir.
	mut sink := u64(0)
	kp := &sink
	f_hash := fn [sp, kp] () {
		m := unsafe { sp }
		h := m.state_hash()
		unsafe {
			*kp = *kp ^ h
		}
	}
	hash_stats := benchkit.measure(warmup, iterations, f_hash)

	results := [
		// Warmup + iterations adimdan sonraki hash; 1000 adimlik determinizm hash'i degildir.
		benchkit.Result{
			name:           'tick_motion_100k'
			entities:       entity_count
			ops_per_sample: 1
			stats:          tick_stats
			mem_bytes:      mem
			state_hash:     '0x${tick_hash:016x}'
			seed:           seed
		},
		benchkit.Result{
			name:           'cmd_flush_set_100k'
			entities:       entity_count
			ops_per_sample: entity_count
			stats:          flush_stats
			mem_bytes:      mem
			seed:           seed
		},
		benchkit.Result{
			name:           'state_hash_100k'
			entities:       entity_count
			ops_per_sample: 1
			stats:          hash_stats
			mem_bytes:      mem
			seed:           seed
		},
	]
	date := time.now().custom_format('YYYY-MM-DD-HHmmss')
	report := benchkit.Report{
		suite:     suite_name
		label:     label
		date:      date
		v_version: 'V 0.5.2 ' + @VHASH
		results:   results
	}
	dir := benchkit.results_dir()
	path := benchkit.write_report(report, dir) or { panic('rapor yazilamadi: ${err}') }

	print_table(report)
	println('rapor: ${path}')
	if prev := benchkit.latest_report(dir, suite_name, path) {
		println('')
		println('onceki rapora gore (${prev.date}):')
		print(benchkit.compare(prev, report))
	}
	memory.release(region)
}

fn print_table(r benchkit.Report) {
	println('ad                       varlik   ops/ornek  medyan(ns/ornek)  p99(ns/ornek)   bellek(B)')
	for res in r.results {
		println('${res.name:-24} ${res.entities:6}   ${res.ops_per_sample:8}  ${res.stats.median_ns:16}  ${res.stats.p99_ns:14}   ${res.mem_bytes:9}')
	}
	for res in r.results {
		if res.state_hash != '' {
			println('state_hash (${res.name}): ${res.state_hash}')
		}
	}
}
