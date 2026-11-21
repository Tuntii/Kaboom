module benchkit

import os
import time
import json

// Test icin ortak rapor kurucu. Sonuc tek satirlik, sadece alanlari dolu.
fn sample_report(suite string, date string, label string) Report {
	return Report{
		suite:     suite
		label:     label
		date:      date
		v_version: 'V 0.5.2 test'
		results:   [
			Result{
				name:            'arena_alloc_64b'
				entities:        0
				ops_per_sample:  100000
				stats:           Stats{
					min_ns:    10
					median_ns: 100
					p99_ns:    200
					samples:   200
				}
				mem_bytes:       6400000
				state_hash:      ''
			},
		]
	}
}

fn test_summarize() {
	mut s := []u64{}
	for i in 1 .. 101 {
		s << u64(i)
	}
	st := summarize(s) or { panic('1..100 icin Stats bekleniyordu') }
	assert st.min_ns == 1
	assert st.median_ns == 50
	assert st.p99_ns == 99
	assert st.samples == 100
}

fn test_summarize_single() {
	st := summarize([u64(7)]) or { panic('tek ornek icin Stats bekleniyordu') }
	assert st.min_ns == 7
	assert st.median_ns == 7
	assert st.p99_ns == 7
	assert st.samples == 1
}

fn test_summarize_empty() {
	summarize([]u64{}) or { return }
	assert false, 'bos ornekte none bekleniyordu'
}

fn test_write_and_read_report() {
	base := os.join_path(os.temp_dir(), 'benchkit_test_${time.sys_mono_now()}')
	defer {
		os.rmdir_all(base) or {}
	}
	// Olmayan alt klasor: write_report onu olusturmali.
	dir := os.join_path(base, 'x', 'y')

	r1 := sample_report('x', '2026-11-20-100000', 'm1')
	p1 := write_report(r1, dir) or { panic('write_report basarisiz: ${err}') }
	assert os.exists(p1)

	text := os.read_file(p1) or { panic('okunamadi: ${err}') }
	got := json.decode(Report, text) or { panic('decode basarisiz: ${err}') }
	assert json.encode(got) == json.encode(r1)

	r2 := sample_report('x', '2026-11-20-100001', 'm1')
	p2 := write_report(r2, dir) or { panic('ikinci write_report basarisiz: ${err}') }

	newest := latest_report(dir, 'x', '') or { panic('latest_report none dondu') }
	assert newest.date == '2026-11-20-100001'

	prev := latest_report(dir, 'x', p2) or { panic('exclude ile latest_report none dondu') }
	assert prev.date == '2026-11-20-100000'
}

fn test_latest_report_skips_other_suite() {
	base := os.join_path(os.temp_dir(), 'benchkit_suite_${time.sys_mono_now()}')
	defer {
		os.rmdir_all(base) or {}
	}
	old := sample_report('x', '2026-11-20-100000', 'm1')
	os.mkdir_all(base) or { panic('klasor olusturulamadi: ${err}') }
	write_report(old, base) or { panic('write_report basarisiz: ${err}') }
	// Daha yeni ama farkli suite'li rapor atlanmali.
	newer := sample_report('y', '2026-11-20-100001', 'm1')
	write_report(newer, base) or { panic('write_report basarisiz: ${err}') }

	got := latest_report(base, 'x', '') or { panic('suite x icin rapor none dondu') }
	assert got.suite == 'x'
	assert got.date == '2026-11-20-100000'
}

fn test_write_report_filename_has_suite() {
	base := os.join_path(os.temp_dir(), 'benchkit_name_${time.sys_mono_now()}')
	defer {
		os.rmdir_all(base) or {}
	}
	r := sample_report('m2_tick', '2026-11-20-100000', 'm2')
	p := write_report(r, base) or { panic('write_report basarisiz: ${err}') }
	assert p.ends_with('-m2_tick-m2.json')
}

fn test_compare() {
	prev := Report{
		label:   'm1'
		date:    '2026-11-20-100000'
		results: [
			Result{
				name:  'arena_alloc_64b'
				stats: Stats{
					median_ns: 100
					p99_ns:    200
				}
			},
			Result{
				name:  'b'
				stats: Stats{
					median_ns: 10
					p99_ns:    20
				}
			},
		]
	}
	cur := Report{
		label:   'm1'
		date:    '2026-11-20-100001'
		results: [
			Result{
				name:  'arena_alloc_64b'
				stats: Stats{
					median_ns: 120
					p99_ns:    200
				}
			},
			Result{
				name:  'pool_acquire_release'
				stats: Stats{
					median_ns: 50
					p99_ns:    60
				}
			},
		]
	}
	out := compare(prev, cur)
	assert out.contains('arena_alloc_64b')
	assert out.contains('+20.0%')
	assert out.contains('YAVASLADI')
	assert out.contains('pool_acquire_release')
	assert out.contains('YENI')
	assert out.contains('b: KAYIP')
}

fn test_compare_small_change_not_slower() {
	prev := Report{
		results: [
			Result{
				name:  'arena_alloc_64b'
				stats: Stats{
					median_ns: 100
					p99_ns:    200
				}
			},
		]
	}
	cur := Report{
		results: [
			Result{
				name:  'arena_alloc_64b'
				stats: Stats{
					median_ns: 105
					p99_ns:    200
				}
			},
		]
	}
	out := compare(prev, cur)
	assert out.contains('+5.0%')
	assert !out.contains('YAVASLADI')
	assert !out.contains('YENI')
	assert !out.contains('KAYIP')
}
