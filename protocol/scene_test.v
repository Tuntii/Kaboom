module protocol

import os
import math
import sim

// Bu dosya kendi yardımcılarını taşır (server_test.v'deki yardımcılar görünmez).
fn pick(v Val, key string) Val {
	return v.get(key) or { null_val() }
}

fn error_code(v Val) int {
	e := v.get('error') or { return -1 }
	return int(pick(e, 'code').f64())
}

// Bit-eşitlik: f32 metninin geri okunuşu girdiyle aynı bit desenini vermeli.
fn round_trips(v f32, text string) bool {
	return math.f32_bits(C.strtof(&char(text.str), unsafe { nil })) == math.f32_bits(v)
}

fn test_f32_text_cases() {
	assert f32_text(f32(0.1)) == '0.1'
	assert f32_text(f32(1)) == '1'
	assert f32_text(f32(-3)) == '-3'
	assert f32_text(f32(100)) == '100'
	neg_zero := math.f32_from_bits(u32(0x80000000))
	assert f32_text(neg_zero) == '-0'
	// Kural R5: |v| < 1e7 tamsayısı düz yazılır; diğerleri en kısa %g metni.
	assert f32_text(f32(9999999)) == '9999999'
	assert f32_text(f32(1e7)) == '1e+07'
	max := f32(3.4028235e38)
	assert f32_text(max) == '3.4028235e+38'
	assert round_trips(max, f32_text(max))
	denorm := math.f32_from_bits(u32(1))
	assert round_trips(denorm, f32_text(denorm))
	third := f32(1.0) / f32(3.0)
	third_text := f32_text(third)
	assert third_text == '0.33333334'
	assert round_trips(third, third_text)
	assert third_text.replace('-', '').replace('.', '').trim_left('0').len <= 9
	assert f32_text(f32(math.nan())) == 'nan'
	assert f32_text(f32(math.inf(1))) == 'inf'
	assert f32_text(f32(math.inf(-1))) == '-inf'
}

fn new_scene_server() Server {
	return Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

fn test_scene_text_golden() {
	mut s := new_scene_server()
	defer {
		s.close()
	}
	s.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1,"y":2},"Sprite":{"size":1,"r":1,"g":0,"b":0}}}}') or { panic('yanıt yok') }
	s.handle('{"jsonrpc":"2.0","id":2,"method":"entity.spawn","params":{"components":{"Transform":{"x":0.5,"y":-3}}}}') or { panic('yanıt yok') }
	want := '{"format":"vscene","version":1,"capacity":64,"entities":[
{"components":{"Transform":{"x":1,"y":2},"Sprite":{"size":1,"r":1,"g":0,"b":0}}},
{"components":{"Transform":{"x":0.5,"y":-3}}}
]}
'
	assert scene_text(s.world(), s.registry()) == want
}

fn test_scene_text_empty_world() {
	mut s := new_scene_server()
	defer {
		s.close()
	}
	assert scene_text(s.world(), s.registry()) == '{"format":"vscene","version":1,"capacity":64,"entities":[\n]}\n'
}

fn test_scene_text_skips_readonly_and_holes() {
	mut s := new_scene_server()
	defer {
		s.close()
	}
	s.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1,"y":2}}}}') or { panic('yanıt yok') }
	s.handle('{"jsonrpc":"2.0","id":2,"method":"entity.spawn","params":{"components":{"Transform":{"x":5,"y":6}}}}') or { panic('yanıt yok') }
	s.handle('{"jsonrpc":"2.0","id":3,"method":"entity.despawn","params":{"entity":0}}') or { panic('yanıt yok') }
	text := scene_text(s.world(), s.registry())
	assert !text.contains('prev_')
	assert !text.contains('"x":1,')
	assert text.contains('{"components":{"Transform":{"x":5,"y":6}}}')
	assert text.count('"components"') == 1
}

fn test_save_atomic_preserves_old_file_on_failure() {
	dir := os.join_path(os.temp_dir(), 'vcore_scene_atomic_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'scene.vscene')
	os.write_file(path, 'OLD') or { panic(err) }
	// Tmp yolu bir klasör: tmp açılamaz, taşıma hiç denenmez ve eski dosya yerinde kalır.
	tmp_dir := path + '.tmp'
	os.mkdir(tmp_dir) or { panic(err) }
	mut s := new_scene_server()
	defer {
		s.close()
	}
	jpath := path.replace('\\', '/')
	res := s.handle('{"jsonrpc":"2.0","id":1,"method":"scene.save","params":{"path":"${jpath}"}}') or { panic('yanıt yok') }
	assert error_code(parse(res) or { panic('JSON degil') }) == code_io_error
	assert (os.read_file(path) or { panic(err) }) == 'OLD'
	assert os.is_dir(tmp_dir)
}

fn test_save_unicode_path() {
	dir := os.join_path(os.temp_dir(), 'vcore_scene_unicode_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'sahne_ğüş.vscene')
	mut s := new_scene_server()
	defer {
		s.close()
	}
	s.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":2}}}}') or { panic('yanıt yok') }
	jpath := path.replace('\\', '/')
	res := s.handle('{"jsonrpc":"2.0","id":2,"method":"scene.save","params":{"path":"${jpath}"}}') or { panic('yanıt yok') }
	out := parse(res) or { panic('JSON degil') }
	result := pick(out, 'result')
	assert pick(result, 'entities').f64() == 1
	content := scene_text(s.world(), s.registry())
	assert pick(result, 'bytes').f64() == f64(content.len)
	assert (os.read_file(path) or { panic(err) }) == content
	assert !os.exists(path + '.tmp')
}

fn scene_load_dir() string {
	return os.join_path(os.temp_dir(), 'vcore_scene_load_test')
}

// Test dosyasını yazar; yol JSON metni için ileri eğik çizgilidir.
fn write_scene_file(name string, content string) string {
	dir := scene_load_dir()
	os.mkdir_all(dir) or { panic(err) }
	path := os.join_path(dir, name)
	os.write_file(path, content) or { panic(err) }
	return path.replace('\\', '/')
}

fn load_reply(mut s Server, path string) Val {
	return scene_call(mut s, '{"jsonrpc":"2.0","id":9,"method":"scene.load","params":{"path":"${path}"}}')
}

fn spawn_one(mut s Server) {
	s.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":7,"y":8}}}}') or { panic('yanıt yok') }
}

fn test_save_load_save_byte_equal() {
	dir := scene_load_dir()
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	mut s := new_scene_server()
	defer {
		s.close()
	}
	s.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1,"y":2},"Sprite":{"size":1,"r":0.5,"g":0,"b":1}}}}') or { panic('yanıt yok') }
	spawn_one(mut s)
	path_a := write_scene_file('a.vscene', scene_text(s.world(), s.registry()))
	path_b := os.join_path(dir, 'b.vscene').replace('\\', '/')
	s.handle('{"jsonrpc":"2.0","id":2,"method":"scene.save","params":{"path":"${path_a}"}}') or { panic('yanıt yok') }
	load_reply(mut s, path_a)
	s.handle('{"jsonrpc":"2.0","id":3,"method":"scene.save","params":{"path":"${path_b}"}}') or { panic('yanıt yok') }
	assert (os.read_file(path_a) or { panic(err) }) == (os.read_file(path_b) or { panic(err) })
}

fn test_load_twice_same_hash() {
	dir := scene_load_dir()
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	mut s := new_scene_server()
	defer {
		s.close()
	}
	spawn_one(mut s)
	path := write_scene_file('twice.vscene', scene_text(s.world(), s.registry()))
	load_reply(mut s, path)
	h1 := s.engine.state_hash()
	load_reply(mut s, path)
	assert s.engine.state_hash() == h1
}

fn test_dense_world_roundtrip_same_hash() {
	dir := scene_load_dir()
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	mut s := new_scene_server()
	defer {
		s.close()
	}
	for i in 0 .. 5 {
		s.handle('{"jsonrpc":"2.0","id":${i},"method":"entity.spawn","params":{"components":{"Transform":{"x":${i}.5,"y":-${i}},"Body":{"vx":1,"vy":0.25}}}}') or { panic('yanıt yok') }
	}
	before := s.engine.state_hash()
	path := write_scene_file('dense.vscene', scene_text(s.world(), s.registry()))
	reply := load_reply(mut s, path)
	assert pick(scene_result(reply), 'entities').len() == 5
	assert s.engine.state_hash() == before
}

fn test_holey_world_roundtrip_values() {
	dir := scene_load_dir()
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	mut s := new_scene_server()
	defer {
		s.close()
	}
	s.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1,"y":2}}}}') or { panic('yanıt yok') }
	s.handle('{"jsonrpc":"2.0","id":2,"method":"entity.spawn","params":{"components":{"Transform":{"x":5,"y":6}}}}') or { panic('yanıt yok') }
	s.handle('{"jsonrpc":"2.0","id":3,"method":"entity.spawn","params":{"components":{"Transform":{"x":9,"y":10}}}}') or { panic('yanıt yok') }
	s.handle('{"jsonrpc":"2.0","id":4,"method":"entity.despawn","params":{"entity":1}}') or { panic('yanıt yok') }
	saved := scene_text(s.world(), s.registry())
	path := write_scene_file('holey.vscene', saved)
	reply := load_reply(mut s, path)
	assert pick(scene_result(reply), 'entities').len() == 2
	assert scene_text(s.world(), s.registry()) == saved
}

fn test_load_errors_leave_world_untouched() {
	dir := scene_load_dir()
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	mut s := new_scene_server()
	defer {
		s.close()
	}
	spawn_one(mut s)
	before := s.engine.state_hash()
	mut many := []string{}
	for _ in 0 .. 65 {
		many << '{"components":{}}'
	}
	cases := [
		// bozuk JSON
		['broken.vscene', '{"format":"vscene","version":1,"entities":[', '-32602'],
		// yanlış format ve sürüm
		['format.vscene', '{"format":"json","version":1,"entities":[]}', '-32602'],
		['version.vscene', '{"format":"vscene","version":2,"entities":[]}', '-32602'],
		// bilinmeyen bileşen
		['unknown.vscene', '{"format":"vscene","version":1,"entities":[{"components":{"Nope":{}}}]}', '1002'],
		// readonly alan (prev_x)
		['readonly.vscene', '{"format":"vscene","version":1,"entities":[{"components":{"Transform":{"x":1,"prev_x":0}}}]}', '1009'],
		// aralık dışı (Sprite.r ∈ [0,1])
		['range.vscene', '{"format":"vscene","version":1,"entities":[{"components":{"Sprite":{"r":2}}}]}', '-32602'],
		// dünya kapasitesi (test: 64)
		['many.vscene', '{"format":"vscene","version":1,"entities":[${many.join(',')}]}', '1006'],
	]
	for c in cases {
		path := write_scene_file(c[0], c[1])
		reply := load_reply(mut s, path)
		assert error_code(reply).str() == c[2], 'kod ${c[0]}: ${error_code(reply)}'
		assert s.engine.state_hash() == before, 'dünya değişti: ${c[0]}'
	}
}

fn test_load_error_data_names_entity_component_field() {
	dir := scene_load_dir()
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	mut s := new_scene_server()
	defer {
		s.close()
	}
	path := write_scene_file('ro.vscene', '{"format":"vscene","version":1,"entities":[{"components":{"Transform":{"x":1}}},{"components":{"Transform":{"x":1,"prev_y":0}}}]}')
	data := pick(pick(load_reply(mut s, path), 'error'), 'data')
	assert pick(data, 'entity_index').f64() == 1
	assert pick(data, 'component').str() == 'Transform'
	assert pick(data, 'field').str() == 'prev_y'
}

fn test_load_refused_while_recording() {
	dir := scene_load_dir()
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	mut s := new_scene_server()
	defer {
		s.close()
	}
	path := write_scene_file('rec.vscene', '{"format":"vscene","version":1,"entities":[]}')
	scene_call(mut s, '{"jsonrpc":"2.0","id":1,"method":"record.start"}')
	assert error_code(load_reply(mut s, path)) == code_record_state
}

fn test_load_clears_history() {
	dir := scene_load_dir()
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	mut s := new_scene_server()
	defer {
		s.close()
	}
	spawn_one(mut s)
	path := write_scene_file('hist.vscene', '{"format":"vscene","version":1,"entities":[{"components":{"Transform":{"x":3}}}]}')
	load_reply(mut s, path)
	undo := scene_call(mut s, '{"jsonrpc":"2.0","id":5,"method":"history.undo"}')
	assert pick(scene_result(undo), 'applied').as_bool() == false
	assert s.engine.world.entities().high_water() == 1
}

fn test_load_accepts_bom_and_crlf() {
	dir := scene_load_dir()
	os.rmdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	mut s := new_scene_server()
	defer {
		s.close()
	}
	body := '{\r\n"format":"vscene",\r\n"version":1,\r\n"entities":[\r\n{"components":{"Transform":{"x":2,"y":"nan"}}}\r\n]\r\n}\r\n'
	path := write_scene_file('bom.vscene', '\xef\xbb\xbf' + body)
	reply := load_reply(mut s, path)
	assert pick(scene_result(reply), 'entities').len() == 1
	assert scene_text(s.world(), s.registry()).contains('"x":2')
}

// server_test.v'deki yardımcılar bu dosyada görünmez: aynı işi burada yapar.
fn scene_call(mut s Server, line string) Val {
	out := s.handle(line) or { panic('yanıt yok: ${line}') }
	return parse(out) or { panic('yanıt JSON degil: ${out}') }
}

fn scene_result(v Val) Val {
	return pick(v, 'result')
}
