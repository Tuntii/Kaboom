module benchkit

import os
import time
import json
import strings

// Bir olcumun ozeti. Tum sureler ornek basina nanosaniye.
pub struct Stats {
pub:
	min_ns    u64
	median_ns u64
	p99_ns    u64
	samples   int
}

// Ornekleri siralar. Medyan alt medyan, p99 nearest-rank. Bos ise none.
pub fn summarize(samples []u64) ?Stats {
	if samples.len == 0 {
		return none
	}
	mut s := samples.clone()
	s.sort()
	n := u64(s.len)
	// ceil(0.99 * n) tam sayi olarak: (99n + 99) / 100
	p99_rank := (99 * n + 99) / 100
	return Stats{
		min_ns:    s[0]
		median_ns: s[(n - 1) / 2]
		p99_ns:    s[p99_rank - 1]
		samples:   s.len
	}
}

// Isinmadan sonra her ornegi tek f cagrisi olarak olcer. Olcum disi tahsisat yok, ornekler onceden ayrilir.
pub fn measure(warmup int, iterations int, f fn ()) Stats {
	for _ in 0 .. warmup {
		f()
	}
	mut samples := []u64{cap: iterations}
	for _ in 0 .. iterations {
		t0 := time.sys_mono_now()
		f()
		samples << time.sys_mono_now() - t0
	}
	return summarize(samples) or { panic('measure: iterations 0 olamaz') }
}

// Sonuclar klasoru. Her program kendi koşusunu bu klasore yazar.
pub fn results_dir() string {
	return os.join_path(@VMODROOT, 'bench', 'results')
}

// Tek bir benchmark sonucu. state_hash M2'ye kadar "". seed: veri uretiminin tohumu (yoksa 0).
pub struct Result {
pub:
	name           string
	entities       u32
	ops_per_sample u32
	stats          Stats
	mem_bytes      u64
	state_hash     string
	seed           u64
}

// Bir kosunun tum sonuclari. date biçimi YYYY-MM-DD-HHMMSS. suite: benchmark programi (m1_memory, m2_tick).
pub struct Report {
pub:
	suite     string
	label     string
	date      string
	v_version string
	results   []Result
}

// dir yoksa olusturur, <dir>/<date>-<suite>-<label>.json yazar ve yolu doner.
pub fn write_report(r Report, dir string) !string {
	os.mkdir_all(dir)!
	path := os.join_path(dir, '${r.date}-${r.suite}-${r.label}.json')
	os.write_file(path, json.encode(r))!
	return path
}

// Ayni suite'li en yeni raporu doner. exclude_path ile verilen dosya atlanir.
// Bozuk JSON ve baska suite'e ait raporlar atlanir, klasor yoksa none.
pub fn latest_report(dir string, suite string, exclude_path string) ?Report {
	files := os.ls(dir) or { return none }
	mut names := files.filter(it.ends_with('.json'))
	names.sort()
	for i := names.len - 1; i >= 0; i-- {
		path := os.join_path(dir, names[i])
		if path == exclude_path {
			continue
		}
		text := os.read_file(path) or { continue }
		r := json.decode(Report, text) or { continue }
		if r.suite == suite {
			return r
		}
	}
	return none
}

// Yuzde degisim. Onceki deger 0 ise 0 doner (bolme yok).
fn pct_change(prev u64, cur u64) f64 {
	if prev == 0 {
		return 0.0
	}
	return (f64(cur) - f64(prev)) / f64(prev) * 100.0
}

// Ayni adli sonuclari karsilastirir. Medyan %10'dan fazla artarsa YAVASLADI, onceki raporda olmayan YENI,
// onceki raporda olup simdikinde olmayan KAYIP.
pub fn compare(prev Report, cur Report) string {
	mut sb := strings.new_builder(256)
	for r in cur.results {
		mut found := false
		for p in prev.results {
			if p.name != r.name {
				continue
			}
			found = true
			med := pct_change(p.stats.median_ns, r.stats.median_ns)
			p99 := pct_change(p.stats.p99_ns, r.stats.p99_ns)
			sb.write_string('${r.name}: medyan ${p.stats.median_ns} -> ${r.stats.median_ns} ns (${med:+.1f}%), p99 ${p.stats.p99_ns} -> ${r.stats.p99_ns} ns (${p99:+.1f}%)')
			if med > 10.0 {
				sb.write_string(' YAVASLADI')
			}
			sb.write_string('\n')
			break
		}
		if !found {
			sb.write_string('${r.name}: YENI\n')
		}
	}
	for p in prev.results {
		if !cur.results.any(it.name == p.name) {
			sb.write_string('${p.name}: KAYIP\n')
		}
	}
	return sb.str()
}
