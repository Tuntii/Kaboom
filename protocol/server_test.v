module protocol

import os
import sim
import cmd
import ecs
import memory

fn new_server() Server {
	return Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

// Yanıt satırını Val olarak çözer; yanıt yoksa test düşer. Değer bir sonraki handle çağrısına kadar geçerlidir.
fn call(mut s Server, line string) Val {
	out := s.handle(line) or { panic('yanıt yok: ${line}') }
	return parse(out) or { panic('yanıt JSON degil: ${out}') }
}

// Anahtar yoksa null döner.
fn pick(v Val, key string) Val {
	return v.get(key) or { null_val() }
}

fn at(v Val, key string) Val {
	return pick(v, key)
}

fn has(v Val, key string) bool {
	return v.get(key) != none
}

// Metin değeri; arena sıfırlanınca bozulmaması için kopyalanır.
fn str_of(v Val) string {
	return v.str().clone()
}

// Dizi ya da nesnenin alt düğümleri (dizi öğeleri için).
fn items(v Val) []Val {
	mut out := []Val{}
	mut c := v.first()
	for !c.is_nil() {
		out << c
		c = c.next()
	}
	return out
}

// Hata kodu; yanıt hata içermiyorsa -1.
fn error_code(v Val) int {
	e := v.get('error') or { return -1 }
	return int(pick(e, 'code').f64())
}

fn result_of(v Val) Val {
	return pick(v, 'result')
}

fn test_spawn_with_components_then_get() {
	mut s := new_server()
	defer {
		s.close()
	}
	r := call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1.5},"Body":{"vx":2}}}}')
	assert pick(result_of(r), 'entity').f64() == 0
	g := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":2,"method":"entity.get","params":{"entity":0}}'))
	comps := pick(g, 'components')
	tr := pick(comps, 'Transform')
	assert pick(tr, 'x').f64() == 1.5
	assert pick(tr, 'y').f64() == 0
	assert pick(pick(comps, 'Body'), 'vx').f64() == 2
}

fn test_errors_are_structured() {
	mut s := new_server()
	defer {
		s.close()
	}
	bad := call(mut s, '{bozuk')
	assert error_code(bad) == -32700
	assert at(bad, 'id').is_null()
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
		'error'), 'data')
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
	assert at(r, 'id').f64() == 5
	assert has(r, 'result')
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
		parse(out) or { panic('yanıt JSON degil: ${out}') }
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
		assert has(r, 'result')
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
	assert has(call(mut s,
		'{"jsonrpc":"2.0","id":2,"method":"entity.spawn","params":{"components":{"Body":{}}}}'), 'result')
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
	ids := items(pick(q, 'entities'))
	assert ids.len == 2
	assert ids[0].f64() == 0
	assert ids[1].f64() == 2
	assert pick(q, 'count').f64() == 2
	lim := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":5,"method":"query.entities","params":{"with":["Body"],"limit":1}}'))
	assert items(pick(lim, 'entities')).len == 1
	assert items(pick(lim, 'entities'))[0].f64() == 0
	assert pick(lim, 'count').f64() == 2
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":6,"method":"query.entities","params":{"with":["Nope"]}}')) == 1002
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":7,"method":"sim.step","params":{"n":0}}')) == -32602
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":8,"method":"sim.step","params":{"n":1000001}}')) == -32602
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":9,"method":"sim.step"}')) == -32602
	t := result_of(call(mut s, '{"jsonrpc":"2.0","id":10,"method":"sim.step","params":{"n":10}}'))
	assert pick(t, 'tick').f64() == 10
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
	assert has(call(mut s, '{"jsonrpc":"2.0","id":5,"method":"record.start"}'), 'result')
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
	// spawn Transform {x} iki prev_* iç yazımı ekler (spawn, add T, set x, set prev_x, set prev_y, add B, set vx, set vx).
	assert pick(stop, 'commands').f64() == 8
	assert pick(stop, 'end_tick').f64() == 100
	stop_hash := str_of(pick(stop, 'hash'))
	live := result_of(call(mut s, '{"jsonrpc":"2.0","id":6,"method":"sim.state_hash"}'))
	live_hash := str_of(pick(live, 'hash'))
	assert stop_hash == live_hash
	replay := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":7,"method":"replay.run","params":{"path":"${path}"}}'))
	assert pick(replay, 'end_tick').f64() == 100
	assert str_of(pick(replay, 'hash')) == live_hash
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
	assert has(call(mut s,
		'{"jsonrpc":"2.0","id":4,"method":"component.add","params":{"entity":0,"component":"Transform","values":{"x":2}}}'), 'result')
	g := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":5,"method":"entity.get","params":{"entity":0}}'))
	assert pick(pick(pick(g, 'components'), 'Transform'), 'x').f64() == 2
	assert has(call(mut s,
		'{"jsonrpc":"2.0","id":6,"method":"component.remove","params":{"entity":0,"component":"Body"}}'), 'result')
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":7,"method":"component.remove","params":{"entity":0,"component":"Body"}}')) == 1005
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":8,"method":"component.set","params":{"entity":0,"component":"Body","field":"vx","value":1}}')) == 1005
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":9,"method":"component.set","params":{"entity":0,"component":"Transform","field":"zz","value":1}}')) == 1003
	assert error_code(call(mut s,
		'{"jsonrpc":"2.0","id":10,"method":"component.set","params":{"entity":0,"component":"Transform","field":"x","value":"a"}}')) == -32602
	assert has(call(mut s,
		'{"jsonrpc":"2.0","id":11,"method":"entity.despawn","params":{"entity":0}}'), 'result')
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
	comps := items(pick(result_of(call(mut s, '{"jsonrpc":"2.0","id":1,"method":"schema.components"}')),
		'components'))
	assert comps.len == 3
	assert str_of(at(comps[0], 'name')) == 'Transform'
	fields := items(at(comps[0], 'fields'))
	assert str_of(at(fields[2], 'name')) == 'prev_x'
	assert at(fields[2], 'readonly').as_bool() == true
	assert str_of(at(fields[0], 'unit')) == 'm'
	cmds := items(pick(result_of(call(mut s, '{"jsonrpc":"2.0","id":2,"method":"schema.commands"}')),
		'commands'))
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
	assert pick(h, 'tick').f64() == 0
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
	tr := pick(pick(g, 'components'), 'Transform')
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
	assert pick(pick(pick(g, 'components'), 'Transform'), 'x').f64() == 2
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
	data := at(at(bad, 'error'), 'data')
	assert str_of(pick(data, 'hint')) == 'Sprite.r must be in [0, 1]'
	assert str_of(pick(data, 'component')) == 'Sprite'
	assert str_of(pick(data, 'field')) == 'r'
	assert has(call(mut s,
		'{"jsonrpc":"2.0","id":3,"method":"component.set","params":{"entity":0,"component":"Sprite","field":"r","value":0.5}}'), 'result')
	g := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":4,"method":"entity.get","params":{"entity":0}}'))
	assert pick(pick(pick(g, 'components'), 'Sprite'), 'r').f64() == 0.5
}

// Spawn'da aralık dışı değer hata döner ve hiçbir varlık oluşmaz.
fn test_range_violation_on_spawn_creates_nothing() {
	mut s := new_server()
	defer {
		s.close()
	}
	bad := call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Sprite":{"size":-1}}}}')
	assert error_code(bad) == -32602
	data := at(at(bad, 'error'), 'data')
	assert str_of(pick(data, 'hint')) == 'Sprite.size must be in [0, 1000]'
	assert str_of(pick(data, 'component')) == 'Sprite'
	assert str_of(pick(data, 'field')) == 'size'
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
	assert at(r, 'id').f64() == 1
	// Surum "1.0": yine calismaz.
	r2 := call(mut s, '{"jsonrpc":"1.0","id":2,"method":"sim.step","params":{"n":1}}')
	assert error_code(r2) == -32600
	assert at(r2, 'id').f64() == 2
	// Bildirim (id yok) ve yanlis surum: yanit yok, yurutulmez.
	assert s.handle('{"method":"sim.step","params":{"n":1}}') == none
	assert s.handle('{"jsonrpc":"1.0","method":"sim.step","params":{"n":1}}') == none
	h := result_of(call(mut s, '{"jsonrpc":"2.0","id":5,"method":"sim.state_hash"}'))
	assert pick(h, 'tick').f64() == 0
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
	assert pick(stop, 'commands').f64() >= 1
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
	assert has(call(mut s, ok), 'result')
}

// Büyük tamsayılar (ör. 2^32) tamsayı olarak yazılmalı; "4.294967296e+09" biçimi kabul edilmez.
fn test_large_integer_ids_print_as_integers() {
	mut s := new_server()
	defer {
		s.close()
	}
	out := s.handle('{"jsonrpc":"2.0","id":1,"method":"entity.get","params":{"entity":4294967296}}') or {
		panic('yanıt yok')
	}
	assert out.contains('"entity":4294967296'), out
	assert !out.contains('e+'), out
}

// Arena dolduğunda yanıt, arenaya ihtiyaç duymayan sabit -32600 satırıdır.
fn test_arena_exhaustion_returns_static_error() {
	mut s := new_server()
	defer {
		s.close()
	}
	mut small := []u8{len: 64}
	arena_set(&u8(small.data), 64)
	out := s.handle('{"jsonrpc":"2.0","id":1,"method":"sim.state_hash"}') or { panic('no response') }
	assert out.contains('request or response too large'), out
	assert out.contains('"code":-32600'), out
	arena_set(s.req_region, request_arena_bytes(s.cfg))
	assert has(call(mut s, '{"jsonrpc":"2.0","id":2,"method":"sim.state_hash"}'), 'result')
}

// Tırnak içi \u0000 kaçışı NUL olarak kabul edilmez: metin strlen ile kesilirdi.
fn test_escaped_nul_is_parse_error() {
	mut s := new_server()
	defer {
		s.close()
	}
	assert error_code(call(mut s, r'{"jsonrpc":"2.0","id":1,"method":"sim.step\u0000x"}')) == -32700
	assert error_code(call(mut s, r'{"jsonrpc":"2.0","id":1,"me\u0000thod":"sim.step"}')) == -32700
}

// Ham NUL baytı satırın herhangi bir yerinde reddedilir.
fn test_raw_nul_byte_is_parse_error() {
	mut s := new_server()
	defer {
		s.close()
	}
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":1,"me\x00thod":"sim.step"}')) == -32700
	assert error_code(call(mut s, '{"jsonrpc":"2.0","id":1,"method":"sim.step"}\x00')) == -32700
}

// Kaçışlı ters eğik çizgiden sonra gelen u0000 metni NUL değildir: istek çalışır.
fn test_escaped_backslash_u0000_is_not_nul() {
	mut s := new_server()
	defer {
		s.close()
	}
	r := call(mut s, r'{"jsonrpc":"2.0","id":2,"method":"sim.state_hash","params":{"x":"\\u0000"}}')
	assert has(r, 'result')
	assert !has(r, 'error')
}

// Kapatılmış sunucu sabit hata yanıtı verir; arenaya dokunmaz.
fn test_request_after_close_reports_closed() {
	mut s := new_server()
	s.close()
	out := s.handle('{"jsonrpc":"2.0","id":1,"method":"sim.state_hash"}') or { panic('no response') }
	assert out.contains('server is closed; create a new server'), out
	assert out.contains('"code":-32603'), out
	assert !out.contains('too large'), out
}

fn test_sim_pause_and_resume() {
	mut s := new_server()
	defer {
		s.close()
	}
	assert !s.paused()
	r := call(mut s, '{"jsonrpc":"2.0","id":1,"method":"sim.pause"}')
	assert pick(result_of(r), 'paused').as_bool() == true
	assert s.paused()
	r2 := call(mut s, '{"jsonrpc":"2.0","id":2,"method":"sim.resume"}')
	assert pick(result_of(r2), 'paused').as_bool() == false
	assert !s.paused()
}

fn test_advance_is_noop_while_paused() {
	mut s := new_server()
	defer {
		s.close()
	}
	s.advance(2)
	assert s.engine.tick() == 2
	call(mut s, '{"jsonrpc":"2.0","id":1,"method":"sim.pause"}')
	s.advance(5)
	assert s.engine.tick() == 2
	// sim.step protokolle duraklatılmışken de çalışır.
	r := call(mut s, '{"jsonrpc":"2.0","id":2,"method":"sim.step","params":{"n":3}}')
	assert pick(result_of(r), 'tick').f64() == 5
}

fn test_screenshot_without_hook_is_no_renderer() {
	mut s := new_server()
	defer {
		s.close()
	}
	r := call(mut s, '{"jsonrpc":"2.0","id":1,"method":"capture.screenshot","params":{"path":"a.png"}}')
	assert error_code(r) == 1013
	assert str_of(pick(pick(pick(r, 'error'), 'data'), 'hint')) == 'screenshots need a window: start vcore run'
}

// Adlandırılmış kanca: fonksiyon değişmezi closure üretmez (V closure kodu cJSON makrolarıyla çakışır).
fn hook_disk_full(path string) !(int, int) {
	return error('disk dolu')
}

fn hook_64x32(path string) !(int, int) {
	return 64, 32
}

fn test_screenshot_hook_error_is_io_error() {
	mut s := new_server()
	defer {
		s.close()
	}
	s.set_capture(hook_disk_full)
	r := call(mut s, '{"jsonrpc":"2.0","id":1,"method":"capture.screenshot","params":{"path":"a.png"}}')
	assert error_code(r) == 1010
	assert str_of(pick(pick(pick(r, 'error'), 'data'), 'hint')).contains('disk dolu')
}

fn test_screenshot_hook_result() {
	mut s := new_server()
	defer {
		s.close()
	}
	s.set_capture(hook_64x32)
	r := call(mut s, '{"jsonrpc":"2.0","id":1,"method":"capture.screenshot","params":{"path":"shots/a.png"}}')
	res := result_of(r)
	assert pick(res, 'width').f64() == 64
	assert pick(res, 'height').f64() == 32
	assert str_of(pick(res, 'path')) == 'shots/a.png'
}

// 100k varlık: sorgu yanıtı istek arenasına sığmalı; kullanılan bayt 256 B/varlık bütçesinin altında kalır.
fn test_query_entities_at_100k_scale() {
	mut s := Server.new(sim.Config{ capacity: 100_000 }) or { panic(err) }
	defer {
		s.close()
	}
	for i in 0 .. 100_000 {
		r := call(mut s, '{"jsonrpc":"2.0","id":${i + 1},"method":"entity.spawn","params":{"components":{"Transform":{"x":1}}}}')
		assert has(r, 'result'), 'spawn ${i} basarisiz'
	}
	out := s.handle('{"jsonrpc":"2.0","id":7,"method":"query.entities","params":{"with":["Transform"]}}') or { panic('no response') }
	// Ölçüm ayrıştırmadan önce: yalnız yanıt ağacının kullandığı bayt sayılır.
	used := arena_used()
	assert used <= u64(100_000) * 256, 'sorgu yanıtı ${used} bayt kullandı; bütçe 256 B/varlık'
	r := parse(out) or { panic('yanıt JSON degil') }
	assert !has(r, 'error'), 'sorgu hata dondu'
	res := result_of(r)
	assert pick(res, 'count').f64() == 100_000
	assert items(pick(res, 'entities')).len == 100_000
}

// Yanıt arenaya sığmazsa hata yanıtı gerçek istek id'sini taşır ve sınır ipucunu verir.
fn test_too_large_response_keeps_request_id() {
	mut s := Server.new(sim.Config{ capacity: 256 }) or { panic(err) }
	defer {
		s.close()
	}
	for i in 0 .. 200 {
		_ = call(mut s, '{"jsonrpc":"2.0","id":${i + 1},"method":"entity.spawn","params":{"components":{"Transform":{"x":1}}}}')
	}
	arena_set(s.req_region, 8192)
	out := s.handle('{"jsonrpc":"2.0","id":42,"method":"query.entities","params":{"with":["Transform"]}}') or {
		panic('yanıt yok')
	}
	r := parse(out) or { panic('yanıt JSON degil: ${out}') }
	assert error_code(r) == -32600, out
	assert pick(r, 'id').f64() == 42, out
	assert str_of(at(at(at(r, 'error'), 'data'), 'hint')) == 'response too large; use the limit parameter', out
	arena_set(s.req_region, request_arena_bytes(s.cfg))
}

// Metin id'si 64 bayttan uzunsa dönüş yanıtında kırpılır; bellek güvenliği için yeterli, id kaybolmaz.
fn test_too_large_response_truncates_long_string_id() {
	mut s := Server.new(sim.Config{ capacity: 256 }) or { panic(err) }
	defer {
		s.close()
	}
	for i in 0 .. 200 {
		_ = call(mut s, '{"jsonrpc":"2.0","id":${i + 1},"method":"entity.spawn","params":{"components":{"Transform":{"x":1}}}}')
	}
	arena_set(s.req_region, 8192)
	long_id := 'x'.repeat(80)
	out := s.handle('{"jsonrpc":"2.0","id":"${long_id}","method":"query.entities","params":{"with":["Transform"]}}') or {
		panic('yanıt yok')
	}
	r := parse(out) or { panic('yanıt JSON degil: ${out}') }
	assert error_code(r) == -32600, out
	assert str_of(pick(r, 'id')) == 'x'.repeat(64), out
	arena_set(s.req_region, request_arena_bytes(s.cfg))
}

// Yanıt istek satırına referans tutmaz: satır serbest bırakılıp üzerine yazıldıktan sonra da yanıt doğrudur.
fn test_response_does_not_reference_request_line() {
	mut s := new_server()
	defer {
		s.close()
	}
	line := '{"jsonrpc":"2.0","id":"req-1","method":"sim.state_hash"}'.clone()
	out := s.handle(line) or { panic('no response') }
	unsafe { line.free() }
	mut junk := []u8{len: 64, init: u8(0x41)}
	assert junk.len == 64
	r := parse(out) or { panic('yanıt JSON degil: ${out}') }
	assert str_of(pick(r, 'id')) == 'req-1', out
	assert has(r, 'result')
}

// Kaynak parametresi kayda yazılır: handle_from(.editor) girdileri editor olarak kaydeder.
fn test_handle_from_editor_source_recorded() {
	mut s := new_server()
	defer {
		s.close()
	}
	path := os.join_path(os.temp_dir(), 'vcore_src_editor_${os.getpid()}.vrec').replace('\\', '/')
	defer {
		os.rm(path) or {}
	}
	_ = call(mut s, '{"jsonrpc":"2.0","id":1,"method":"record.start"}')
	_ = s.handle_from('{"jsonrpc":"2.0","id":2,"method":"entity.spawn"}', .editor) or { panic('no response') }
	_ = call(mut s, '{"jsonrpc":"2.0","id":3,"method":"record.stop","params":{"path":"${path}"}}')
	rec := cmd.load_recording(path) or { panic('recording unreadable') }
	assert rec.entries.len > 0
	for e in rec.entries {
		assert e.cmd.source == .editor
	}
}

fn test_handle_defaults_to_agent() {
	mut s := new_server()
	defer {
		s.close()
	}
	path := os.join_path(os.temp_dir(), 'vcore_src_agent_${os.getpid()}.vrec').replace('\\', '/')
	defer {
		os.rm(path) or {}
	}
	_ = call(mut s, '{"jsonrpc":"2.0","id":1,"method":"record.start"}')
	_ = call(mut s, '{"jsonrpc":"2.0","id":2,"method":"entity.spawn"}')
	_ = call(mut s, '{"jsonrpc":"2.0","id":3,"method":"record.stop","params":{"path":"${path}"}}')
	rec := cmd.load_recording(path) or { panic('recording unreadable') }
	assert rec.entries.len > 0
	for e in rec.entries {
		assert e.cmd.source == .agent
	}
}

// entity.spawn Transform {x, y} verince prev_x/prev_y aynı değerlerle tohumlanır.
fn test_spawn_seeds_prev() {
	mut s := new_server()
	defer {
		s.close()
	}
	sp := result_of(call(mut s,
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":3,"y":4}}}}'))
	id := u64(pick(sp, 'entity').f64())
	got := result_of(call(mut s, '{"jsonrpc":"2.0","id":2,"method":"entity.get","params":{"entity":${id}}}'))
	tr := pick(pick(got, 'components'), 'Transform')
	assert pick(tr, 'prev_x').f64() == 3
	assert pick(tr, 'prev_y').f64() == 4
}

fn test_record_start_hint_mentions_pause_reset() {
	mut s := new_server()
	defer {
		s.close()
	}
	_ = call(mut s, '{"jsonrpc":"2.0","id":1,"method":"entity.spawn"}')
	e := call(mut s, '{"jsonrpc":"2.0","id":2,"method":"record.start"}')
	hint := str_of(pick(pick(pick(e, 'error'), 'data'), 'hint'))
	assert hint.contains('call sim.pause, then sim.reset, then record.start'), hint
}
