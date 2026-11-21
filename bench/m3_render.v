module main

import os
import time
import math
import memory
import ecs
import cmd
import sim
import platform
import render
import bench.benchkit

// M3 render benchmark: 100k quad, gizli 1280x720 pencerede. Olcum: yalnizca prepare, draw + glFinish, prepare + draw + glFinish.
// Veri splitmix64 ile tohumdan uretilir; render simulasyondan ayri raporlanir (spec §7.14).
const suite_name = 'm3_render'
const seed = u64(0x5EED)
const entity_count = u32(100_000)
const queue_capacity = u32(131_072)
// Kurulumda bir partide kac varlik: 10 komut/varlik * 10k = 100k, kuyruk kapasitesinin altinda kalir.
const setup_chunk = 10_000
const warmup = 10
const iterations = 200
const view_h = f32(220)
const alpha = f32(0.5)

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

// Olcum icin tum durum tek heap nesnesinde; closure'lar pointer tasir (M2 ile ayni desen).
struct Bench {
mut:
	world &ecs.World
	f     render.QuadFields
	n     u32
	cw    int
	ch    int
	r     render.Renderer
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

fn add_cmd(comp u16, e ecs.EntityID) cmd.Command {
	return cmd.Command{
		kind:   .add_component
		source: .editor
		comp:   comp
		entity: e
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

// Kurulum: varlik ac (spawn sonuclarindan id oku), sonra Transform + Sprite ve alanlari parti parti yaz.
// Konum [-100, 100), boyut [0.2, 1.0), renk [0, 1). prev_* konuma esitlenir: ilk karede ziplama olmaz.
fn setup(mut s sim.Sim, mut rng Rng, f render.QuadFields) []ecs.EntityID {
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

	for base := 0; base < ids.len; base += setup_chunk {
		end := if base + setup_chunk < ids.len { base + setup_chunk } else { ids.len }
		mut cmds := []cmd.Command{cap: (end - base) * 10}
		for e in ids[base..end] {
			cmds << add_cmd(ecs.transform_id, e)
			cmds << add_cmd(ecs.sprite_id, e)
			x := rng.f32_in(-100.0, 100.0)
			y := rng.f32_in(-100.0, 100.0)
			cmds << set_cmd(ecs.transform_id, f.x, e, x)
			cmds << set_cmd(ecs.transform_id, f.y, e, y)
			cmds << set_cmd(ecs.transform_id, f.prev_x, e, x)
			cmds << set_cmd(ecs.transform_id, f.prev_y, e, y)
			cmds << set_cmd(ecs.sprite_id, f.size, e, rng.f32_in(0.2, 1.0))
			cmds << set_cmd(ecs.sprite_id, f.r, e, rng.f32_in(0.0, 1.0))
			cmds << set_cmd(ecs.sprite_id, f.g, e, rng.f32_in(0.0, 1.0))
			cmds << set_cmd(ecs.sprite_id, f.b, e, rng.f32_in(0.0, 1.0))
		}
		push_batched(mut s, cmds)
	}
	return ids
}

// Olcumu calistirir. Her f cagrisi (warmup + iterations) kez koşar; draw_calls artisi beklenenle esit olmali.
fn measure_checked(b &Bench, name string, expected_draws u64, f fn ()) benchkit.Stats {
	before := b.r.draw_calls()
	st := benchkit.measure(warmup, iterations, f)
	grown := b.r.draw_calls() - before
	if grown != expected_draws {
		panic('${name}: draw_calls ${grown} artti, beklenen ${expected_draws}')
	}
	return st
}

@[console]
fn main() {
	label := if os.args.len > 1 { os.args[1] } else { 'local' }
	reg := ecs.core_registry() or { panic('registry kurulamadi') }
	f := render.resolve_quad_fields(&reg) or { panic('alan indisleri cozulemedi: ${err}') }

	// Pencere ve GL once kurulur; basarisizlikta acik mesajla cikilir.
	mut w := platform.Window.new(platform.WindowConfig{ visible: false, width: 1280, height: 720 }) or {
		eprintln('m3_render: pencere acilamadi (GL yok olabilir): ${err}')
		exit(3)
	}
	render.load_gl() or {
		eprintln('m3_render: GL fonksiyonlari yuklenemedi: ${err}')
		w.close()
		exit(3)
	}
	r := render.Renderer.new(entity_count) or {
		eprintln('m3_render: Renderer kurulamadi: ${err}')
		w.close()
		exit(3)
	}
	cw, ch := w.size()

	region_size := config().bytes_needed(&reg)
	region := memory.reserve(region_size) or { panic('bolge ayrilamadi') }
	mut arena := memory.LinearArena.new(region, region_size)
	mut s := sim.Sim.new(mut arena, &reg, config()) or { panic('sim kurulamadi') }
	mut rng := Rng{
		state: seed
	}
	setup(mut s, mut rng, f)
	// Kurulum sonrası dünya özeti (m2 ile aynı 0x%016x biçimi); ölçümler dünyayı değiştirmez.
	scene_hash := '0x${s.state_hash():016x}'
	mem := arena.used()

	mut b := &Bench{
		world: &s.world
		f:     f
		cw:    cw
		ch:    ch
		r:     r
	}
	// Renderer'in kendi tamponu: draw yalnizca bunu yukler. Ayri bir dizi kullanilirsa cizim sifir ornekle yapilir.
	mut out := b.r.payload()
	n0, skipped0 := render.prepare(b.world, b.f, alpha, mut out)
	if skipped0 != 0 || n0 != entity_count {
		panic('kurulum: ${n0} yazildi, ${skipped0} atlandi, beklenen ${entity_count}')
	}
	if out[0].size <= 0 {
		panic('kurulum: payload[0].size ${out[0].size} (sifir ornek)')
	}
	b.n = n0

	bp := b
	f_prepare := fn [bp] () {
		mut m := unsafe { bp }
		mut o := m.r.payload()
		_, skipped := render.prepare(m.world, m.f, alpha, mut o)
		if skipped != 0 {
			panic('prepare: kapasite asildi')
		}
	}
	f_draw := fn [bp] () {
		mut m := unsafe { bp }
		m.r.draw(render.Camera{ view_h: view_h }, m.cw, m.ch, m.n)
		render.finish()
	}
	f_frame := fn [bp] () {
		mut m := unsafe { bp }
		mut o := m.r.payload()
		n, skipped := render.prepare(m.world, m.f, alpha, mut o)
		if skipped != 0 {
			panic('frame: kapasite asildi')
		}
		m.r.draw(render.Camera{ view_h: view_h }, m.cw, m.ch, n)
		render.finish()
	}

	// Yalnizca prepare: cizim cagrisi olmamali.
	prepare_stats := measure_checked(bp, 'render_prepare_100k', 0, f_prepare)
	// draw ve frame: her olcum (warmup + iterations) kare, her kare tam bir cizim cagrisi.
	frames := u64(warmup + iterations)
	draw_stats := measure_checked(bp, 'render_draw_100k', frames, f_draw)
	frame_stats := measure_checked(bp, 'render_frame_100k', frames, f_frame)

	results := [
		benchkit.Result{
			name:           'render_prepare_100k'
			entities:       entity_count
			ops_per_sample: 1
			stats:          prepare_stats
			mem_bytes:      mem
			state_hash:     scene_hash
			seed:           seed
		},
		benchkit.Result{
			name:           'render_draw_100k'
			entities:       entity_count
			ops_per_sample: 1
			stats:          draw_stats
			mem_bytes:      mem
			state_hash:     scene_hash
			seed:           seed
		},
		benchkit.Result{
			name:           'render_frame_100k'
			entities:       entity_count
			ops_per_sample: 1
			stats:          frame_stats
			mem_bytes:      mem
			state_hash:     scene_hash
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

	b.r.close()
	w.close()
	memory.release(region)
}

fn print_table(r benchkit.Report) {
	println('ad                       varlik   ops/ornek  medyan(ns/ornek)  p99(ns/ornek)   bellek(B)')
	for res in r.results {
		println('${res.name:-24} ${res.entities:6}   ${res.ops_per_sample:8}  ${res.stats.median_ns:16}  ${res.stats.p99_ns:14}   ${res.mem_bytes:9}')
	}
}
