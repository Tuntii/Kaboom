module main

import os
import time
import memory
import ui
import bench.benchkit

// M4a UI benchmark: vitrin iki sayfasının bir karesi (begin → showcase → end). Pencere ve GL gerekmez;
// girdi sabittir, durum kare kare aynı kalır. Ölçüm dışında tahsis sayımı yalnızca -d track_heap ile anlamlıdır.
const suite_name = 'm4_ui'
const warmup = 100
const iterations = 1000
const alloc_frames = 100
const frame_w = f32(1440)
const frame_h = f32(900)
const ui_scale = f32(1)
const cmd_cap = u32(8192)
const node_cap = u32(2048)

// Atlas ve Context aynı heap nesnesinde: Context atlas'a işaretçi tutar, nesne hareket etmemeli.
struct UiBench {
mut:
	atlas &ui.Atlas
	ctx   ui.Context
	st    ui.ShowcaseState
	inp   ui.Input
}

// Bir kare: düzen, çizim listesi ve sayfa içeriği. Dönüş: komut sayısı.
fn frame(mut b UiBench, page ui.ShowcasePage) u32 {
	b.ctx.begin(b.inp, frame_w, frame_h, ui_scale)
	_ = ui.showcase(mut b.ctx, mut b.st, page)
	list := b.ctx.end()
	if list.dropped() != 0 || b.ctx.node_overflow() != 0 {
		panic('kare kapasite asti: komut ${list.dropped()}, dugum ${b.ctx.node_overflow()}')
	}
	return list.len()
}

// Kare başına tahsis ortalaması; -d track_heap yoksa -1.
fn allocs_per_frame(mut b UiBench, page ui.ShowcasePage) i64 {
	if !memory.heap_tracking_enabled() {
		return -1
	}
	before := memory.heap_alloc_count()
	for _ in 0 .. alloc_frames {
		_ = frame(mut b, page)
	}
	return i64(memory.heap_alloc_count() - before) / i64(alloc_frames)
}

@[console]
fn main() {
	label := if os.args.len > 1 { os.args[1] } else { 'local' }
	// Atlas heap'te: Context ona işaretçi tutar ve ikisi de UiBench ile birlikte yaşar.
	atl := &ui.Atlas{}
	built := ui.Atlas.build(ui_scale) or { panic('atlas kurulamadi: ${err}') }
	unsafe {
		*atl = built
	}
	ctx := ui.Context.new(atl, node_cap, cmd_cap) or { panic('context kurulamadi: ${err}') }
	mut b := &UiBench{
		atlas: atl
		ctx:   ctx
		st:    ui.ShowcaseState.new()
		inp:   ui.Input{
			mouse_x: 300
			mouse_y: 200
		}
	}

	// Her sayfa için kurulum karesi: komut ve düğüm sayıları ölçümden önce alınır.
	cmds_e := frame(mut b, .editor)
	nodes_e := b.ctx.node_count()
	allocs_e := allocs_per_frame(mut b, .editor)
	cmds_w := frame(mut b, .widgets)
	nodes_w := b.ctx.node_count()
	allocs_w := allocs_per_frame(mut b, .widgets)

	bp := b
	f_editor := fn [bp] () {
		mut m := unsafe { bp }
		_ = frame(mut m, .editor)
	}
	f_widgets := fn [bp] () {
		mut m := unsafe { bp }
		_ = frame(mut m, .widgets)
	}
	st_e := benchkit.measure(warmup, iterations, f_editor)
	st_w := benchkit.measure(warmup, iterations, f_widgets)

	results := [
		benchkit.Result{
			name:             'ui_frame_editor'
			ops_per_sample:   1
			stats:            st_e
			draw_cmds:        cmds_e
			nodes:            nodes_e
			allocs_per_frame: allocs_e
		},
		benchkit.Result{
			name:             'ui_frame_widgets'
			ops_per_sample:   1
			stats:            st_w
			draw_cmds:        cmds_w
			nodes:            nodes_w
			allocs_per_frame: allocs_w
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
}

fn print_table(r benchkit.Report) {
	println('ad                       ops/ornek  medyan(ns)  p99(ns)  min(ns)  komut  dugum  tahsis/kare')
	for res in r.results {
		println('${res.name:-24} ${res.ops_per_sample:8}  ${res.stats.median_ns:10}  ${res.stats.p99_ns:7}  ${res.stats.min_ns:7}  ${res.draw_cmds:5}  ${res.nodes:5}  ${res.allocs_per_frame:11}')
	}
}
