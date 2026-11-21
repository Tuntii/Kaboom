module main

import os
import time
import memory
import ecs
import bench.benchkit

// Tum bellek benchmark'lari bu 256 MiB bolgeden pay alir. Kurulum parent'tan, olcum kendi alt bolgesinden yapilir.
const region_size = u64(256) * 1024 * 1024
const arena_bench_size = u64(128) * 1024 * 1024
// Bir ornekteki islem sayisi.
const ops = u32(100000)
const warmup = 10
const iterations = 200

fn main() {
	label := if os.args.len > 1 { os.args[1] } else { 'local' }
	region := memory.reserve(region_size) or { panic('256 MiB rezerve edilemedi') }
	mut root := memory.LinearArena.new(region, region_size)

	results := [
		bench_arena_alloc(mut root),
		bench_pool(mut root),
		bench_entity(mut root),
		bench_epoch(mut root),
	]
	date := time.now().custom_format('YYYY-MM-DD-HHmmss')
	report := benchkit.Report{
		suite:     'm1_memory'
		label:     label
		date:      date
		v_version: 'V 0.5.2 ' + @VHASH
		results:   results
	}
	path := benchkit.write_report(report, benchkit.results_dir()) or { panic('rapor yazilamadi: ${err}') }

	print_table(report)
	println('rapor: ${path}')
	if prev := benchkit.latest_report(benchkit.results_dir(), 'm1_memory', path) {
		println('')
		println('onceki rapora gore (${prev.date}):')
		print(benchkit.compare(prev, report))
	}
	memory.release(region)
}

fn print_table(r benchkit.Report) {
	println('ad                       varlik   medyan(ns/ornek)  p99(ns/ornek)   bellek(B)')
	for res in r.results {
		println('${res.name:-24} ${res.entities:6}   ${res.stats.median_ns:16}  ${res.stats.p99_ns:14}   ${res.mem_bytes:9}')
	}
}

// 100k x alloc_aligned(64, 64) + reset. mem_bytes: bir kosunun arenada kullandigi bayt.
fn bench_arena_alloc(mut root memory.LinearArena) benchkit.Result {
	base := root.alloc_aligned(arena_bench_size, 64) or { panic('arena bolgesi ayrilamadi') }
	mut arena := memory.LinearArena.new(base, arena_bench_size)
	for _ in 0 .. ops {
		arena.alloc_aligned(64, 64) or { panic('arena tukendi') }
	}
	mem := arena.used()
	arena.reset()

	ap := &arena
	f := fn [ap] () {
		mut a := unsafe { ap }
		for _ in 0 .. ops {
			a.alloc_aligned(64, 64) or { panic('arena tukendi') }
		}
		a.reset()
	}
	stats := benchkit.measure(warmup, iterations, f)
	return benchkit.Result{
		name:           'arena_alloc_64b'
		ops_per_sample: ops
		stats:          stats
		mem_bytes:      mem
	}
}

// 100k slot (32 B) hepsini al, hepsini birak. Arena baytlari kurulum farkindan olculur.
fn bench_pool(mut root memory.LinearArena) benchkit.Result {
	before := root.used()
	mut pool := memory.PoolAllocator.new(mut root, 32, ops) or { panic('havuz kurulamadi') }
	mem := root.used() - before

	pp := &pool
	f := fn [pp] () {
		mut p := unsafe { pp }
		for _ in 0 .. ops {
			p.acquire() or { panic('havuz doldu') }
		}
		// En dusuk bos slot once verildigi icin indeksler 0..ops-1 sirasiyla gelir.
		for i in 0 .. ops {
			if !p.release(i) {
				panic('slot birakilamadi')
			}
		}
	}
	stats := benchkit.measure(warmup, iterations, f)
	return benchkit.Result{
		name:           'pool_acquire_release'
		ops_per_sample: ops
		stats:          stats
		mem_bytes:      mem
	}
}

// cap 100k: 100k create, sonra 100k destroy. Tutamaclar onceden ayrilir, olcum icinde tahsisat yok.
fn bench_entity(mut root memory.LinearArena) benchkit.Result {
	before := root.used()
	mut ea := ecs.EntityAllocator.new(mut root, ops) or { panic('varlik tahsisatcisi kurulamadi') }
	mem := root.used() - before

	mut handles := []ecs.EntityID{len: int(ops)}
	ep := &ea
	hp := &handles
	f := fn [ep, hp] () {
		mut e := unsafe { ep }
		h := unsafe { hp }
		for i in 0 .. h.len {
			created := e.create() or { panic('varlik tukendi') }
			unsafe {
				h[i] = created
			}
		}
		for i in 0 .. h.len {
			if !e.destroy(unsafe { h[i] }) {
				panic('varlik yok edilemedi')
			}
		}
	}
	stats := benchkit.measure(warmup, iterations, f)
	return benchkit.Result{
		name:           'entity_create_destroy'
		entities:       ops
		ops_per_sample: ops
		stats:          stats
		mem_bytes:      mem
	}
}

// 100k x alloc(32, 16); her 1000 tahsisatta bir advance. Yarım kapasite 64 KiB, bir kare 32 KB kullanir.
fn bench_epoch(mut root memory.LinearArena) benchkit.Result {
	before := root.used()
	mut ea := memory.EpochArena.new(mut root, u64(64) * 1024) or { panic('epoch kurulamadi') }
	mem := root.used() - before

	ep := &ea
	f := fn [ep] () {
		mut e := unsafe { ep }
		for i in 0 .. ops {
			e.alloc(32, 16) or { panic('epoch tukendi') }
			if (i + 1) % 1000 == 0 {
				e.advance()
			}
		}
	}
	stats := benchkit.measure(warmup, iterations, f)
	return benchkit.Result{
		name:           'epoch_advance'
		ops_per_sample: ops
		stats:          stats
		mem_bytes:      mem
	}
}
