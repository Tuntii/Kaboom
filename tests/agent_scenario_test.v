module main

import os
import x.json2
import math
import sim

// Ajan senaryosu: vcore headless ikilisi derlenir, senaryo stdin'den beslenir ve yanıtlar id'ye göre denetlenir.

// Yolu tırnakla; tüm komutu ek tırnağa almak Windows cmd.exe'de yolu bozar.
fn run_cmd(exe string, args string) os.Result {
	return os.execute('"${exe}" ${args}')
}

fn test_agent_scenario_over_stdio() {
	tmp := os.join_path(os.temp_dir(), 'vcore_m2_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	exe := os.join_path(tmp, 'vcore.exe')
	build := os.execute('"${@VEXE}" -gc none -o "${exe}" "${@VMODROOT}/cmd_main"')
	assert build.exit_code == 0, build.output

	scenario := os.join_path(@VMODROOT, 'tests', 'scenarios', 'm2_agent.jsonl')
	old_wd := os.getwd()
	os.chdir(tmp) or { panic(err) }
	defer {
		os.chdir(old_wd) or {}
	}

	run := run_cmd(exe, 'headless < "${scenario}"')
	assert run.exit_code == 0, run.output

	mut by_id := map[int]map[string]json2.Any{}
	for line in run.output.split_into_lines() {
		if line.trim_space() == '' {
			continue
		}
		m := json2.decode[json2.Any](line) or { panic('gecersiz JSON yanit: ${line}') }
		obj := m.as_map()
		id := (obj['id'] or { panic('id yok: ${line}') }).int()
		by_id[id] = obj.clone()
	}
	assert by_id.len == 15, 'yanit sayisi 15 olmaliydi, ${by_id.len} geldi: ${run.output}'

	// Spawn id'leri sırasıyla 0, 1, 2.
	assert by_id[3]['result'] or { panic('spawn 3 sonucu yok') }.as_map()['entity'] or { panic('') }.int() == 0
	assert by_id[4]['result'] or { panic('') }.as_map()['entity'] or { panic('') }.int() == 1
	assert by_id[5]['result'] or { panic('') }.as_map()['entity'] or { panic('') }.int() == 2

	// Adım 1000 tick ilerler: x = 1000*dt, y = 500*dt (f32 dt, f64 olarak karşılaştirilir).
	dt := f64(sim.dt)
	e0 := by_id[7]['result'] or { panic('entity.get sonucu yok') }.as_map()
	comps := e0['components'] or { panic('components yok') }.as_map()
	tr := comps['Transform'] or { panic('Transform yok') }.as_map()
	x := tr['x'] or { panic('x yok') }.f64()
	y := tr['y'] or { panic('y yok') }.f64()
	assert math.abs(x - 1000.0 * dt) < 1e-3, 'x=${x} beklenen ${1000.0 * dt}'
	assert math.abs(y - 500.0 * dt) < 1e-3, 'y=${y} beklenen ${500.0 * dt}'

	assert ids_of(by_id[8]) == [0, 2], 'query Body: ${ids_of(by_id[8])}'
	assert ids_of(by_id[10]) == [0, 1], 'query Transform: ${ids_of(by_id[10])}'

	err := by_id[11]['error'] or { panic('component.set hata donmeliydi') }.as_map()
	assert err['code'] or { panic('') }.int() == 1001

	h :=
		by_id[12]['result'] or { panic('state_hash sonucu yok') }.as_map()['hash'] or { panic('') }.str()
	assert by_id[13]['result'] or { panic('') }.as_map()['hash'] or { panic('') }.str() == h
	assert by_id[14]['result'] or { panic('') }.as_map()['hash'] or { panic('') }.str() == h
	assert by_id[15]['result'] or { panic('') }.as_map()['hash'] or { panic('') }.str() == h

	replay_end := by_id[14]['result'] or { panic('') }.as_map()['end_tick'] or { panic('') }.int()
	assert replay_end == 1000, 'end_tick=${replay_end}'
}

fn test_unknown_mode_exits_with_usage_code() {
	tmp := os.join_path(os.temp_dir(), 'vcore_m2_usage_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	exe := os.join_path(tmp, 'vcore.exe')
	build := os.execute('"${@VEXE}" -gc none -o "${exe}" "${@VMODROOT}/cmd_main"')
	assert build.exit_code == 0, build.output
	assert run_cmd(exe, 'nope').exit_code == 2
	assert run_cmd(exe, 'headless --capacity 0').exit_code == 2
	assert run_cmd(exe, 'headless --capacity x').exit_code == 2
}

fn ids_of(obj map[string]json2.Any) []int {
	arr := (obj['result'] or { panic('sonuc yok') }).as_map()['entities'] or {
		panic('entities yok')
	}.as_array()
	mut out := []int{}
	for v in arr {
		out << v.int()
	}
	return out
}
