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
	max := f32(3.4028235e38)
	assert round_trips(max, f32_text(max))
	denorm := math.f32_from_bits(u32(1))
	assert round_trips(denorm, f32_text(denorm))
	third := f32(1.0) / f32(3.0)
	third_text := f32_text(third)
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
