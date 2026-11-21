module protocol

import os
import x.json2
import sim
import cmd
import ecs
import memory

fn new_server() Server {
	return Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

// Yanıt satırını JSON olarak çözer; yanıt yoksa test düşer.
fn call(mut s Server, line string) json2.Any {
	out := s.handle(line) or { panic('yanıt yok: ${line}') }
	return json2.decode[json2.Any](out) or { panic(err) }
}

// Anahtar yoksa null döner; sum type indekslemesi için.
fn pick(m map[string]json2.Any, key string) json2.Any {
	return m[key] or { json2.Any(json2.null) }
}

fn at(a json2.Any, key string) json2.Any {
	return pick(a.as_map(), key)
}

// Metin değeri; sayı ya da başka tip gelirse panik (test düşer).
fn str_of(a json2.Any) string {
	return a as string
}

// Hata kodu; yanıt hata içermiyorsa -1.
fn error_code(a json2.Any) int {
	if 'error' !in a.as_map() {
		return -1
	}
	return at(at(a, 'error'), 'code').int()
}

fn result_of(a json2.Any) map[string]json2.Any {
	return at(a, 'result').as_map()
}

fn test_spawn_with_components_then_get() {
	mut s := new_server()
	defer {
		s.close()
	}
	r := call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1.5},"Body":{"vx":2}}}}')
	assert pick(result_of(r), 'entity').u64() == 0
	g := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":2,"method":"entity.get","params":{"entity":0}}'))
	comps := pick(g, 'components').as_map()
	tr := pick(comps, 'Transform').as_map()
	assert pick(tr, 'x').f64() == 1.5
	assert pick(tr, 'y').f64() == 0
	assert pick(pick(comps, 'Body').as_map(), 'vx').f64() == 2
}

fn test_errors_are_structured() {
	mut s := new_server()
	defer {
		s.close()
	}
	bad := call(mut s, '{bozuk')
	assert error_code(bad) == -32700
	assert at(bad, 'id') is json2.Null
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":3,"method":"nope"}')) == -32601
	// Dünya bos: entity 0 henüz yok.
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":4,"method":"component.set","params":{"entity":0,"component":"Transform","field":"x","value":1}}')) == 1001
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":5,"method":"entity.spawn","params":{"components":{"Nope":{}}}}')) == 1002
	assert s.engine.world.alive_count() == 0
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":6,"method":"entity.spawn","params":{"components":{"Transform":{"zz":1}}}}')) == 1003
	assert s.engine.world.alive_count() == 0
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":7,"method":"entity.spawn","params":{"components":{"Transform":{"x":"a"}}}}')) == -32602
	assert s.engine.world.alive_count() == 0
	assert error_code(call(mut s, '[1,2]')) == -32600
	// Gercek bir varlık olustur; readonly kontrolu bu varlık uzerinde.
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":8,"method":"entity.spawn","params":{}}')) == -1
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":9,"method":"component.set","params":{"entity":0,"component":"Transform","field":"prev_x","value":1}}')) == 1009
	// Hata yanıti data alaninda component, field ve hint taşır.
	data := at(at(call(mut s,
		'{"jsonrpc":"2.0","id":10,"method":"component.set","params":{"entity":0,"component":"Transform","field":"prev_x","value":1}}'),
		'error'), 'data').as_map()
	assert str_of(pick(data, 'component')) == 'Transform'
	assert str_of(pick(data, 'field')) == 'prev_x'
	assert str_of(pick(data, 'hint')) != ''
}

fn test_blank_and_crlf_lines() {
	mut s := new_server()
	defer {
		s.close()
	}
	assert s.handle('') == none
	assert s.handle('\r') == none
	r := call(mut s, '{"jsonrpc":"2.0","id":5,"method":"sim.state_hash"}\r')
	assert at(r, 'id').u64() == 5
	assert 'result' in r.as_map()
	// id'siz istek bildirimdir: yanıt yok, ama yürütülür.
	assert s.handle('{"jsonrpc":"2.0","method":"sim.step","params":{"n":1}}') == none
	assert s.engine.tick() == 1
}

fn test_malformed_input_never_panics() {
	mut s := new_server()
	defer {
		s.close()
	}
	lines := [
		'{"jsonrpc":"2.0","id":1}',
		'{"jsonrpc":"2.0","id":1,"method":5}',
		'{"jsonrpc":"2.0","id":{},"method":"sim.step"}',
		'{"jsonrpc":"2.0","id":1,"method":"entity.get","params":[1]}',
		'{"jsonrpc":"2.0","id":1,"method":"entity.get","params":{"entity":1e300}}',
		'{"jsonrpc":"2.0","id":1,"method":"entity.get","params":{"entity":true}}',
		'{"jsonrpc":"2.0","id":1,"method":"sim.step","params":{"n":2.5}}',
		'{"jsonrpc":"2.0","id":1,"method":"query.entities","params":{"with":"Transform"}}',
		'{"jsonrpc":"2.0","id":1,"method":"query.entities","params":{"with":[1]}}',
		'{"jsonrpc":"2.0","id":1,"method":"query.entities","params":{"with":[],"limit":-1}}',
		'{"jsonrpc":"2.0","id":1,"method":"record.stop"}',
		'{"jsonrpc":"2.0","id":1,"method":"record.stop","params":{"path":""}}',
		'{"jsonrpc":"2.0","id":1,"method":"replay.run","params":{"path":"no/such/file.vrec"}}',
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":5}}}',
		'{"jsonrpc":"2.0","id":1,"method":"component.set","params":{"entity":0,"component":"Transform","field":"x"}}',
		'5',
		'"x"',
		'null',
		'{"id":1,"method":"entity.get","params":{"entity":18446744073709551615}}',
	]
	for line in lines {
		out := s.handle(line) or { continue }
		json2.decode[json2.Any](out) or { panic('yanıt JSON degil: ${out}') }
	}
}

fn test_string_id_is_echoed() {
	mut s := new_server()
	defer {
		s.close()
	}
	r := call(mut s, '{"jsonrpc":"2.0","id":"abc","method":"sim.state_hash"}')
	assert str_of(at(r, 'id')) == 'abc'
}

fn test_capacity_full_spawn() {
	mut s := new_server()
	defer {
		s.close()
	}
	for i in 0 .. 64 {
		r := call(mut s, '{"jsonrpc":"2.0","id":${i},"method":"entity.spawn"}')
		assert 'result' in r.as_map()
	}
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":99,"method":"entity.spawn"}')) == 1006
	assert s.engine.world.alive_count() == 64
}

fn test_queue_full_spawn_with_components() {
	mut s := Server.new(sim.Config{ capacity: 64, queue_capacity: 2, record_capacity: 64 }) or {
		panic(err)
	}
	defer {
		s.close()
	}
	// 1 spawn + 2 komut (Transform + x) + 2 komut (Body + vx) = 5 > 2.
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1},"Body":{"vx":1}}}}')) == 1007
	assert s.engine.world.alive_count() == 0
	// 1 spawn + 1 komut (Body) = 2 <= 2.
	assert 'result' in call(mut s,
		'{"jsonrpc":"2.0","id":2,"method":"entity.spawn","params":{"components":{"Body":{}}}}').as_map()
}

fn test_query_and_step() {
	mut s := new_server()
	defer {
		s.close()
	}
	_ = call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Body":{}}}}')
	_ = call(mut s, '{"jsonrpc":"2.0","id":2,"method":"entity.spawn"}')
	_ = call(mut s,
		'{"jsonrpc":"2.0","id":3,"method":"entity.spawn","params":{"components":{"Body":{}}}}')
	q := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":4,"method":"query.entities","params":{"with":["Body"]}}'))
	ids := pick(q, 'entities').as_array()
	assert ids.len == 2
	assert ids[0].u64() == 0
	assert ids[1].u64() == 2
	assert pick(q, 'count').int() == 2
	lim := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":5,"method":"query.entities","params":{"with":["Body"],"limit":1}}'))
	assert pick(lim, 'entities').as_array().len == 1
	assert pick(lim, 'entities').as_array()[0].u64() == 0
	assert pick(lim, 'count').int() == 2
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":6,"method":"query.entities","params":{"with":["Nope"]}}')) == 1002
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":7,"method":"sim.step","params":{"n":0}}')) == -32602
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":8,"method":"sim.step","params":{"n":1000001}}')) == -32602
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":9,"method":"sim.step"}')) == -32602
	t := result_of(call(mut s, '{"jsonrpc":"2.0","id":10,"method":"sim.step","params":{"n":10}}'))
	assert pick(t, 'tick').u64() == 10
}

fn test_record_start_requires_pristine_world() {
	mut s := new_server()
	defer {
		s.close()
	}
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"record.stop","params":{"path":"x.vrec"}}')) == 1008
	_ = call(mut s, '{"jsonrpc":"2.0","id":2,"method":"entity.spawn"}')
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":3,"method":"record.start"}')) == 1008
	_ = call(mut s, '{"jsonrpc":"2.0","id":4,"method":"sim.reset"}')
	assert 'result' in call(mut s, '{"jsonrpc":"2.0","id":5,"method":"record.start"}').as_map()
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":6,"method":"record.start"}')) == 1008
}

fn test_record_roundtrip_and_replay_run() {
	mut s := new_server()
	defer {
		s.close()
	}
	// JSON metninde ters eğik çizgi kaçış ister; yol ileri eğik çizgiyle verilir.
	path := os.join_path(os.temp_dir(), 'vcore_protocol_${os.getpid()}.vrec').replace('\\', '/')
	defer {
		os.rm(path) or {}
	}
	_ = call(mut s, '{"jsonrpc":"2.0","id":1,"method":"record.start"}')
	_ = call(mut s,
		'{"jsonrpc":"2.0","id":2,"method":"entity.spawn","params":{"components":{"Transform":{"x":1},"Body":{"vx":3}}}}')
	_ = call(mut s,
		'{"jsonrpc":"2.0","id":3,"method":"component.set","params":{"entity":0,"component":"Body","field":"vx","value":5}}')
	_ = call(mut s, '{"jsonrpc":"2.0","id":4,"method":"sim.step","params":{"n":100}}')
	stop := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":5,"method":"record.stop","params":{"path":"${path}"}}'))
	assert pick(stop, 'commands').int() == 6
	assert pick(stop, 'end_tick').u64() == 100
	live := result_of(call(mut s, '{"jsonrpc":"2.0","id":6,"method":"sim.state_hash"}'))
	assert str_of(pick(stop, 'hash')) == str_of(pick(live, 'hash'))
	replay := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":7,"method":"replay.run","params":{"path":"${path}"}}'))
	assert pick(replay, 'end_tick').u64() == 100
	assert str_of(pick(replay, 'hash')) == str_of(pick(live, 'hash'))
}

fn test_io_errors_map_to_1010() {
	mut s := new_server()
	defer {
		s.close()
	}
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"replay.run","params":{"path":"no/such/file.vrec"}}')) == 1010
	_ = call(mut s, '{"jsonrpc":"2.0","id":2,"method":"record.start"}')
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":3,"method":"record.stop","params":{"path":"no_such_dir_vcore/x.vrec"}}')) == 1010
}

fn test_component_add_remove_set() {
	mut s := new_server()
	defer {
		s.close()
	}
	_ = call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Body":{}}}}')
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":2,"method":"component.add","params":{"entity":0,"component":"Body"}}')) == 1004
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":3,"method":"component.add","params":{"entity":0,"component":"Nope"}}')) == 1002
	assert 'result' in call(mut s,
		'{"jsonrpc":"2.0","id":4,"method":"component.add","params":{"entity":0,"component":"Transform","values":{"x":2}}}').as_map()
	g := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":5,"method":"entity.get","params":{"entity":0}}'))
	assert pick(pick(pick(g, 'components').as_map(), 'Transform').as_map(), 'x').f64() == 2
	assert 'result' in call(mut s,
		'{"jsonrpc":"2.0","id":6,"method":"component.remove","params":{"entity":0,"component":"Body"}}').as_map()
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":7,"method":"component.remove","params":{"entity":0,"component":"Body"}}')) == 1005
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":8,"method":"component.set","params":{"entity":0,"component":"Body","field":"vx","value":1}}')) == 1005
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":9,"method":"component.set","params":{"entity":0,"component":"Transform","field":"zz","value":1}}')) == 1003
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":10,"method":"component.set","params":{"entity":0,"component":"Transform","field":"x","value":"a"}}')) == -32602
	assert 'result' in call(mut s,
		'{"jsonrpc":"2.0","id":11,"method":"entity.despawn","params":{"entity":0}}').as_map()
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":12,"method":"entity.despawn","params":{"entity":0}}')) == 1001
}

fn test_entity_ids_must_be_non_negative_integers() {
	mut s := new_server()
	defer {
		s.close()
	}
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.get","params":{"entity":-1}}')) == -32602
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":2,"method":"entity.get","params":{"entity":1.5}}')) == -32602
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":3,"method":"entity.get","params":{"entity":"0"}}')) == -32602
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":4,"method":"entity.get","params":{"entity":0}}')) == 1001
}

fn test_schema_components_and_commands() {
	mut s := new_server()
	defer {
		s.close()
	}
	comps := pick(result_of(call(mut s, '{"jsonrpc":"2.0","id":1,"method":"schema.components"}')),
		'components').as_array()
	assert comps.len == 3
	assert str_of(at(comps[0], 'name')) == 'Transform'
	fields := at(comps[0], 'fields').as_array()
	assert str_of(at(fields[2], 'name')) == 'prev_x'
	assert at(fields[2], 'readonly').bool() == true
	assert str_of(at(fields[0], 'unit')) == 'm'
	cmds := pick(result_of(call(mut s, '{"jsonrpc":"2.0","id":2,"method":"schema.commands"}')),
		'commands').as_array()
	assert cmds.len >= 13
}

fn test_sim_reset_clears_world() {
	mut s := new_server()
	defer {
		s.close()
	}
	_ = call(mut s, '{"jsonrpc":"2.0","id":1,"method":"entity.spawn"}')
	_ = call(mut s, '{"jsonrpc":"2.0","id":2,"method":"sim.step","params":{"n":5}}')
	_ = call(mut s, '{"jsonrpc":"2.0","id":3,"method":"sim.reset"}')
	assert s.engine.world.alive_count() == 0
	h := result_of(call(mut s, '{"jsonrpc":"2.0","id":4,"method":"sim.state_hash"}'))
	assert pick(h, 'tick').u64() == 0
	assert str_of(pick(h, 'hash')).len == 18
	assert str_of(pick(h, 'hash')).starts_with('0x')
}

fn test_f32_overflow_is_emitted_as_string_not_inf() {
	mut s := new_server()
	defer {
		s.close()
	}
	_ = call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":3.4028234663852886e38},"Body":{"vx":3.4028234663852886e38}}}}')
	_ = call(mut s, '{"jsonrpc":"2.0","id":2,"method":"sim.step","params":{"n":1}}')
	// Hareket x'i tasirir; cikti gecerli JSON kalmali ve inf metin olmali.
	g := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":3,"method":"entity.get","params":{"entity":0}}'))
	tr := pick(pick(g, 'components').as_map(), 'Transform').as_map()
	assert str_of(pick(tr, 'x')) == 'inf'
	assert pick(tr, 'y').f64() == 0
}

fn test_f32_input_out_of_range_is_rejected_unchanged() {
	mut s := new_server()
	defer {
		s.close()
	}
	_ = call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":2}}}}')
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":2,"method":"component.set","params":{"entity":0,"component":"Transform","field":"x","value":1e39}}')) == -32602
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":3,"method":"component.set","params":{"entity":0,"component":"Transform","field":"x","value":-1e39}}')) == -32602
	g := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":4,"method":"entity.get","params":{"entity":0}}'))
	assert pick(pick(pick(g, 'components').as_map(), 'Transform').as_map(), 'x').f64() == 2
}

// Sprite.r [0, 1] dışındayken set reddedilir, değer değişmez; içindeyken kabul edilir.
fn test_range_violation_on_set_is_rejected_unchanged() {
	mut s := new_server()
	defer {
		s.close()
	}
	_ = call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Sprite":{"r":0.25}}}}')
	bad := call(mut s,
		'{"jsonrpc":"2.0","id":2,"method":"component.set","params":{"entity":0,"component":"Sprite","field":"r","value":1.5}}')
	assert error_code(bad) == -32602
	assert str_of(at(at(at(bad, 'error'), 'data'), 'hint')) == 'value must be in [0, 1]'
	assert 'result' in call(mut s,
		'{"jsonrpc":"2.0","id":3,"method":"component.set","params":{"entity":0,"component":"Sprite","field":"r","value":0.5}}').as_map()
	g := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":4,"method":"entity.get","params":{"entity":0}}'))
	assert pick(pick(pick(g, 'components').as_map(), 'Sprite').as_map(), 'r').f64() == 0.5
}

// Spawn'da aralık dışı değer hata döner ve hiçbir varlık oluşmaz.
fn test_range_violation_on_spawn_creates_nothing() {
	mut s := new_server()
	defer {
		s.close()
	}
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Sprite":{"size":-1}}}}')) == -32602
	assert s.engine.world.alive_count() == 0
}

fn test_jsonrpc_member_must_be_2_0() {
	mut s := new_server()
	defer {
		s.close()
	}
	// Surum uyesi yok: istek calismaz, id yansitilir.
	r := call(mut s, '{"id":1,"method":"sim.step","params":{"n":1}}')
	assert error_code(r) == -32600
	assert at(r, 'id').u64() == 1
	// Surum "1.0": yine calismaz.
	r2 := call(mut s, '{"jsonrpc":"1.0","id":2,"method":"sim.step","params":{"n":1}}')
	assert error_code(r2) == -32600
	assert at(r2, 'id').u64() == 2
	// Bildirim (id yok) ve yanlis surum: yanit yok, yurutulmez.
	assert s.handle('{"method":"sim.step","params":{"n":1}}') == none
	assert s.handle('{"jsonrpc":"1.0","method":"sim.step","params":{"n":1}}') == none
	h := result_of(call(mut s, '{"jsonrpc":"2.0","id":5,"method":"sim.state_hash"}'))
	assert pick(h, 'tick').u64() == 0
}

// Kayıt dosyasını doğrudan yazar; girdiler sunucu üzerinden üretilemeyen bozuk kayıtlar için kullanılır.
fn write_recording(path string, entity ecs.EntityID, world_capacity u32) {
	region := memory.reserve(1 << 16) or { panic('reserve basarisiz') }
	defer {
		memory.release(region)
	}
	mut a := memory.LinearArena.new(region, 1 << 16)
	mut rec := cmd.Recorder.new(mut a, 4) or { panic('Recorder.new none') }
	rec.start()
	rec.append(0, cmd.Command{ kind: .set_field, source: .agent, entity: entity, comp: 0, field: 0, value: 0 })
	rec.save(path, world_capacity, 1) or { panic(err) }
}

fn test_record_stop_io_failure_keeps_recording() {
	mut s := new_server()
	defer {
		s.close()
	}
	_ = call(mut s, '{"jsonrpc":"2.0","id":1,"method":"record.start"}')
	_ = call(mut s, '{"jsonrpc":"2.0","id":2,"method":"entity.spawn"}')
	bad := os.join_path(os.temp_dir(), 'vcore_no_such_dir', 'x.vcrec').replace('\\', '/')
	failed := call(mut s, '{"jsonrpc":"2.0","id":3,"method":"record.stop","params":{"path":"${bad}"}}')
	assert error_code(failed) == 1010
	assert str_of(at(at(at(failed, 'error'), 'data'), 'hint')).contains('retry record.stop')
	path := os.join_path(os.temp_dir(), 'vcore_protocol_keep_${os.getpid()}.vcrec').replace('\\', '/')
	defer {
		os.rm(path) or {}
	}
	stop := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":4,"method":"record.stop","params":{"path":"${path}"}}'))
	assert pick(stop, 'commands').int() >= 1
}

fn test_replay_divergence_maps_to_1011() {
	mut s := new_server()
	defer {
		s.close()
	}
	path := os.join_path(os.temp_dir(), 'vcore_protocol_diverge_${os.getpid()}.vrec').replace('\\', '/')
	defer {
		os.rm(path) or {}
	}
	// Hiç doğmamış bir varlığa set_field: yükleme geçer, replay ayrışır.
	write_recording(path, ecs.make_entity(9999, 0), 64)
	bad := call(mut s, '{"jsonrpc":"2.0","id":1,"method":"replay.run","params":{"path":"${path}"}}')
	assert error_code(bad) == 1011
	assert str_of(at(at(at(bad, 'error'), 'data'), 'hint')).starts_with('replay diverged: tick 0 entry 0 ')
}

fn test_replay_capacity_too_large_is_1010() {
	mut s := new_server()
	defer {
		s.close()
	}
	path := os.join_path(os.temp_dir(), 'vcore_protocol_capacity_${os.getpid()}.vrec').replace('\\', '/')
	defer {
		os.rm(path) or {}
	}
	write_recording(path, ecs.make_entity(0, 0), 128) // sunucu kapasitesi 64
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":1,"method":"replay.run","params":{"path":"${path}"}}')) == 1010
}

fn test_deep_nesting_is_rejected_without_crash() {
	mut s := new_server()
	defer {
		s.close()
	}
	deep := '['.repeat(10000) + ']'.repeat(10000)
	assert error_code(call(mut s, deep)) == -32700
	// 10 derinlik sınırın altındadır ve çalışmaya devam eder.
	ok := '{"jsonrpc":"2.0","id":1,"method":"sim.state_hash","params":{"x":' + '['.repeat(10) + ']'.repeat(10) + '}}'
	assert 'result' in call(mut s, ok).as_map()
}
