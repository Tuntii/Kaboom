module protocol

import math
import ecs
import cmd
import memory
import sim

// Entity id JSON'da tamsayıdır ve 2^48 altında kalir (index 32 bit, nesil 16 bit).
const entity_id_limit = 281474976710656.0
const max_f32 = 3.4028234663852886e38

// Doğrulanmış bir bileşen yazımı: alan indeksi ve f32 bit deseni.
struct FieldWrite {
	field u16
	bits  u64
}

// Bir bileşen ve yazimlari; spawn ve component.add bunu kuyruga çevirir.
struct Plan {
	comp u16
mut:
	writes []FieldWrite
}

// schema.commands tablosu: her metot icin params ve result açıklamasi.
struct CommandDoc {
	method string
	params string
	result string
}

const command_docs = [
	CommandDoc{
		method: 'entity.spawn'
		params: '{"components"?: {"<Comp>": {"<field>": number}}}'
		result: '{"entity": id}'
	},
	CommandDoc{
		method: 'entity.despawn'
		params: '{"entity": id}'
		result: '{}'
	},
	CommandDoc{
		method: 'component.add'
		params: '{"entity": id, "component": "<Comp>", "values"?: {"<field>": number}}'
		result: '{}'
	},
	CommandDoc{
		method: 'component.remove'
		params: '{"entity": id, "component": "<Comp>"}'
		result: '{}'
	},
	CommandDoc{
		method: 'component.set'
		params: '{"entity": id, "component": "<Comp>", "field": "<field>", "value": number}'
		result: '{}'
	},
	CommandDoc{
		method: 'entity.get'
		params: '{"entity": id}'
		result: '{"entity": id, "index": n, "generation": n, "components": {"<Comp>": {"<field>": number}}}; sonlu olmayan f32 değerler metin olarak döner: "inf", "-inf", "nan"'
	},
	CommandDoc{
		method: 'query.entities'
		params: '{"with": ["<Comp>", ...], "limit"?: n}'
		result: '{"entities": [id, ...], "count": n}; index artan sırada; count limit oncesi toplam'
	},
	CommandDoc{
		method: 'schema.components'
		params: 'none'
		result: '{"components": [{"id", "name", "fields": [{"name", "type", "unit", "min", "max", "desc", "readonly"}]}]}'
	},
	CommandDoc{
		method: 'schema.commands'
		params: 'none'
		result: '{"commands": [{"method", "params", "result"}]}'
	},
	CommandDoc{
		method: 'sim.step'
		params: '{"n": 1..1000000}'
		result: '{"tick": n}'
	},
	CommandDoc{
		method: 'sim.reset'
		params: 'none'
		result: '{}; dünyayı, kuyruğu, kaydı ve geçmişi sıfırlar'
	},
	CommandDoc{
		method: 'sim.state_hash'
		params: 'none'
		result: '{"tick": n, "hash": "0x<16 hex>"}'
	},
	CommandDoc{
		method: 'sim.pause'
		params: 'none'
		result: '{"paused": true}; ilerleme durur, sim.step çalışmaya devam eder'
	},
	CommandDoc{
		method: 'sim.resume'
		params: 'none'
		result: '{"paused": false}'
	},
	CommandDoc{
		method: 'capture.screenshot'
		params: '{"path": string}'
		result: '{"path", "width", "height"}; yalnız pencereli çalışmada (vcore run); headless modda 1013'
	},
	CommandDoc{
		method: 'history.undo'
		params: 'none'
		result: '{"applied": bool, "commands": n, "failed": n, "remap": [{"old": id, "new": id}]}; uygulanmadıysa applied false ve "reason": "empty" (boş yığın, hata değil) ya da "editor_group_open" (açık editör grubu içinde reddedilir); yalnız reddedilince neden alanı döner'
	},
	CommandDoc{
		method: 'history.redo'
		params: 'none'
		result: '{"applied": bool, "commands": n, "failed": n, "remap": [{"old": id, "new": id}]}; uygulanmadıysa applied false ve "reason": "empty" (boş yığın, hata değil) ya da "editor_group_open" (açık editör grubu içinde reddedilir); yalnız reddedilince neden alanı döner'
	},
	CommandDoc{
		method: 'record.start'
		params: 'none'
		result: '{}; yalnizca tick 0 ve bos dünyada'
	},
	CommandDoc{
		method: 'record.stop'
		params: '{"path": string}'
		result: '{"path", "commands", "end_tick", "hash"}'
	},
	CommandDoc{
		method: 'replay.run'
		params: '{"path": string}'
		result: '{"end_tick", "hash"}'
	},
	CommandDoc{
		method: 'scene.save'
		params: '{"path": string}'
		result: '{"path", "entities": n, "bytes": n}; .vscene metni <path>.tmp üzerinden atomik olarak yazılır; hata io_error (1010) ve eski dosya yerinde kalır'
	},
	CommandDoc{
		method: 'scene.load'
		params: '{"path": string}'
		result: '{"entities": [id, ...]}; dosya tamamen doğrulanır, sonra dünya sıfırlanıp kurulur ve geçmiş temizlenir; hatalar: -32602 (biçim, aralık, sonlu olmayan sayı; varlık ve alan hatalarında data: entity_index, component, field), -32603 (bellek), 1002 bilinmeyen bileşen, 1003 bilinmeyen alan, 1006 kapasite, 1007 kuyruk dolu, 1008 kayıt aktif, 1009 readonly alan, 1010 io_error; doğrulama hataları dünyayı değiştirmez'
	},
]

fn (mut s Server) entity_spawn(p Val) !Val {
	comps := object_param(p, 'components')!
	plans := s.component_plans(comps, false)!
	defer {
		free_plans(plans)
	}
	e := s.spawn_planned(plans)!
	return kv('entity', num(f64(u64(e))))
}

// Bir varlığın bileşen nesnesinden planları üretir (entity.spawn ve scene.load ortak yolu); dünyaya dokunmaz.
// Yinelenen anahtarda yalnız son değer geçerlidir. scene: .vscene değerleri kabul edilir.
fn (s &Server) component_plans(comps Val, scene bool) ![]Plan {
	mut plans := []Plan{cap: comps.child_count()}
	mut ok := false
	defer {
		if !ok {
			free_plans(plans)
		}
	}
	mut c := comps.first()
	for !c.is_nil() {
		name := c.key()
		if comps.is_last(c) {
			if !c.is_object() {
				d := hint_data('components.${name} must be an object of field values')
				d.set('component', str_val(name))
				return rpc_error(code_invalid_params, 'invalid params', d)
			}
			mut pl := s.plan_component(name, c, scene)!
			s.seed_transform_prev(mut pl)
			plans << pl
		}
		c = c.next()
	}
	s.check_queue_slots(plans)!
	ok = true
	return plans
}

// Spawn bir komut, her bileşen bir add, her alan bir set: hepsi kuyrukta sığmalı.
fn (s &Server) check_queue_slots(plans []Plan) ! {
	mut need := u64(1)
	for pl in plans {
		need += u64(1 + pl.writes.len)
	}
	if need > u64(s.cfg.queue_capacity) {
		return rpc_error(code_queue_full, 'command queue is full', hint_data('spawn needs ${need} queue slots but queue_capacity is ${s.cfg.queue_capacity}; spawn fewer components or start the server with a larger queue_capacity'))
	}
}

// Planları bir varlığa dönüştürür: önce spawn (id'yi alır), sonra her bileşen bir add, her alan bir set.
// Çağıran kuyruk sığmasını check_queue_slots ile önceden denetler.
fn (mut s Server) spawn_planned(plans []Plan) !ecs.EntityID {
	// Spawn ve bileşen yazımları tek geçmiş bloğu: tersi yalnız despawn olur, geri alma bloğu tek parça kalır.
	s.engine.history.begin_block()
	defer {
		s.engine.history.end_block()
	}
	// Tek komut: dizi literali (heap) ayrılmadan commit_one.
	s.commit_one(cmd.Command{
		kind:   .spawn
		source: s.source
	})!
	e := s.engine.queue.result(0).entity
	// Kapasite önceden: büyüyen dizi yeniden ayırır (tahsis sayacı bunu sızıntı sayar).
	mut slots := 0
	for pl in plans {
		slots += 1 + pl.writes.len
	}
	mut cmds := []cmd.Command{cap: slots}
	defer {
		unsafe { cmds.free() }
	}
	for pl in plans {
		cmds << cmd.Command{
			kind:   .add_component
			source: s.source
			entity: e
			comp:   pl.comp
		}
		for w in pl.writes {
			cmds << cmd.Command{
				kind:   .set_field
				source: s.source
				entity: e
				comp:   pl.comp
				field:  w.field
				value:  w.bits
			}
		}
	}
	if cmds.len > 0 {
		s.commit(cmds)!
	}
	return e
}

fn (mut s Server) entity_despawn(p Val) !Val {
	e := entity_param(p)!
	s.commit_one(cmd.Command{
		kind:   .despawn
		source: s.source
		entity: e
	})!
	return empty_object()
}

fn (mut s Server) component_add(p Val) !Val {
	e := entity_param(p)!
	name := string_param(p, 'component')!
	values := object_param(p, 'values')!
	plan := s.plan_component(name, values, false)!
	defer {
		unsafe { plan.writes.free() }
	}
	// Mevcut bileşeni ya da olmayan varlığı, sets'in yanlis satıra dokunmasını olmadan reddet.
	if !s.engine.world.is_alive(e) {
		return s.cmd_error(.dead_entity, cmd.Command{
			kind:   .add_component
			entity: e
			comp:   plan.comp
		})
	}
	if s.engine.world.has(e, plan.comp) {
		return s.cmd_error(.already_has, cmd.Command{
			kind:   .add_component
			entity: e
			comp:   plan.comp
		})
	}
	// Ekleme ve değer yazımları tek geçmiş bloğu: tersi yalnız remove_component olur.
	s.engine.history.begin_block()
	defer {
		s.engine.history.end_block()
	}
	mut cmds := [
		cmd.Command{
			kind:   .add_component
			source: s.source
			entity: e
			comp:   plan.comp
		},
	]
	defer {
		unsafe { cmds.free() }
	}
	for w in plan.writes {
		cmds << cmd.Command{
			kind:   .set_field
			source: s.source
			entity: e
			comp:   plan.comp
			field:  w.field
			value:  w.bits
		}
	}
	s.commit(cmds)!
	return empty_object()
}

fn (mut s Server) component_remove(p Val) !Val {
	e := entity_param(p)!
	name := string_param(p, 'component')!
	comp := s.component_id(name)!
	s.commit_one(cmd.Command{
		kind:   .remove_component
		source: s.source
		entity: e
		comp:   comp
	})!
	return empty_object()
}

fn (mut s Server) component_set(p Val) !Val {
	e := entity_param(p)!
	name := string_param(p, 'component')!
	fname := string_param(p, 'field')!
	v := p.get('value') or { return invalid_params('value is required: a number') }
	comp := s.component_id(name)!
	schema := s.reg.component(comp) or {
		return status_error(.unknown_component, kv('component', str_val(name)))
	}
	w := s.field_write(name, schema, fname, v, false)!
	s.commit_one(cmd.Command{
		kind:   .set_field
		source: s.source
		entity: e
		comp:   comp
		field:  w.field
		value:  w.bits
	})!
	return empty_object()
}

fn (s &Server) entity_get(p Val) !Val {
	e := entity_param(p)!
	w := &s.engine.world
	if !w.is_alive(e) {
		return status_error(.dead_entity, kv('entity', num(f64(u64(e)))))
	}
	comps := obj()
	for id in u16(0) .. s.reg.count() {
		if !w.has(e, id) {
			continue
		}
		schema := s.reg.component(id) or { continue }
		fields := obj()
		for fi, f in schema.fields {
			// shortcut: yalnız f32 alanlar JSON'a çevrilir; i32/bool/entity M6'da
			if f.typ != .f32_ {
				continue
			}
			bits := w.get_field(e, id, u16(fi)) or { continue }
			fields.set(f.name, f32_json(bits))
		}
		comps.set(schema.name, fields)
	}
	out := obj()
	out.set('entity', num(f64(u64(e))))
	out.set('index', num(f64(e.index())))
	out.set('generation', num(f64(e.generation())))
	out.set('components', comps)
	return out
}

fn (s &Server) query_entities(p Val) !Val {
	wv := p.get('with') or { return invalid_params('with is required: an array of component names') }
	if !wv.is_array() {
		return invalid_params('with must be an array of component names')
	}
	mut ids := []u16{}
	defer {
		unsafe { ids.free() }
	}
	mut nc := wv.first()
	for !nc.is_nil() {
		if !nc.is_string() {
			return invalid_params('with must be an array of component names')
		}
		ids << s.component_id(nc.str())!
		nc = nc.next()
	}
	mut limit := max_int
	if _ := p.get('limit') {
		limit = int_param(p, 'limit', 0, max_int)!
	}
	w := &s.engine.world
	alloc := w.entities()
	out := arr()
	mut out_n := 0
	mut total := 0
	for i in 0 .. alloc.high_water() {
		e := alloc.handle_at(i) or { continue }
		mut all := true
		for cid in ids {
			if !w.has(e, cid) {
				all = false
				break
			}
		}
		if !all {
			continue
		}
		total++
		if out_n < limit {
			out.push(num(f64(u64(e))))
			out_n++
		}
	}
	res := obj()
	res.set('entities', out)
	res.set('count', num(f64(total)))
	return res
}

fn (s &Server) schema_components() !Val {
	list := arr()
	for id in u16(0) .. s.reg.count() {
		c := s.reg.component(id) or { continue }
		fields := arr()
		for f in c.fields {
			fo := obj()
			fo.set('name', str_val(f.name))
			fo.set('type', str_val(f.typ.name()))
			fo.set('unit', str_val(f.unit))
			fo.set('min', num(f.min))
			fo.set('max', num(f.max))
			fo.set('desc', str_val(f.desc))
			fo.set('readonly', bool_val(f.readonly))
			fields.push(fo)
		}
		co := obj()
		co.set('id', num(f64(int(c.id))))
		co.set('name', str_val(c.name))
		co.set('fields', fields)
		list.push(co)
	}
	res := obj()
	res.set('components', list)
	return res
}

fn schema_commands() Val {
	list := arr()
	for d in command_docs {
		o := obj()
		o.set('method', str_val(d.method))
		o.set('params', str_val(d.params))
		o.set('result', str_val(d.result))
		list.push(o)
	}
	res := obj()
	res.set('commands', list)
	return res
}

fn (mut s Server) sim_step(p Val) !Val {
	n := int_param(p, 'n', 1, 1_000_000)!
	for _ in 0 .. n {
		s.engine.step()
	}
	return kv('tick', num(f64(u64(s.engine.tick()))))
}

// Bölgeyi serbest birakip tazesini ayırır. Yeniden ayırma başarısızsa sunucu kapalı kalır.
fn (mut s Server) sim_reset() !Val {
	s.engine.free()
	_ = memory.release(s.region)
	s.region = unsafe { nil }
	need := s.cfg.bytes_needed(&s.reg)
	region := memory.reserve(need) or {
		return internal_error('sim.reset could not reserve ${need} bytes; restart the server')
	}
	mut a := memory.LinearArena.new(region, need)
	engine := sim.Sim.new(mut a, &s.reg, s.cfg) or {
		_ = memory.release(region)
		return internal_error('sim.reset could not build the simulation; restart the server')
	}
	s.region = region
	s.engine = engine
	// Yeni motorun geçmişi boş ve derinliği 0: açık editör grubu da artık yok.
	s.editor_depth = 0
	return empty_object()
}

fn (mut s Server) sim_pause() Val {
	s.is_paused = true
	return kv('paused', bool_val(true))
}

fn (mut s Server) sim_resume() Val {
	s.is_paused = false
	return kv('paused', bool_val(false))
}

// Kanca pencereden gelir; headless modda yoktur ve 1013 döner.
fn (s &Server) capture_screenshot(p Val) !Val {
	path := string_param(p, 'path')!
	hook := s.capture or {
		return rpc_error(code_no_renderer, 'no renderer', hint_data('screenshots need a window: start vcore run'))
	}
	w, h := hook(path) or { return io_error(path, err.msg()) }
	res := obj()
	res.set('path', str_val(path))
	res.set('width', num(f64(w)))
	res.set('height', num(f64(h)))
	return res
}

fn (s &Server) sim_state_hash() Val {
	res := obj()
	res.set('tick', num(f64(u64(s.engine.tick()))))
	res.set('hash', hash_val(s.engine.state_hash()))
	return res
}

fn (mut s Server) record_start() !Val {
	if s.engine.recorder.is_active() {
		return record_error('a recording is already active; call record.stop first')
	}
	if s.engine.tick() != 0 || s.engine.world.entities().high_water() != 0 {
		return record_error('recording starts only on a pristine world (tick 0, no entities); call sim.pause, then sim.reset, then record.start')
	}
	s.engine.recorder.start()
	return empty_object()
}

fn (mut s Server) record_stop(p Val) !Val {
	path := string_param(p, 'path')!
	if !s.engine.recorder.is_active() {
		return record_error('no recording is active; call record.start first')
	}
	tick := s.engine.tick()
	// Taşmış kayıt yazılmaz; kayıt yine de durdurulur ki bir sonraki record.start çalışabilsin.
	if s.engine.recorder.overflowed() {
		s.engine.recorder.stop()
		return io_error(path, 'recording buffer overflowed; restart with a larger record capacity')
	}
	// Kayıt, yazma başarılı olmadan durdurulmaz: I/O hatasında kayıt aktif kalır ve tekrar denenebilir.
	s.engine.recorder.save(path, s.cfg.capacity, tick) or {
		return io_error(path, 'could not write file; retry record.stop with another path')
	}
	s.engine.recorder.stop()
	res := obj()
	res.set('path', str_val(path))
	res.set('commands', num(f64(s.engine.recorder.len())))
	res.set('end_tick', num(f64(u64(tick))))
	res.set('hash', hash_val(s.engine.state_hash()))
	return res
}

fn (s &Server) replay_run(p Val) !Val {
	path := string_param(p, 'path')!
	rec := cmd.load_recording(path) or {
		return io_error(path, 'recording could not be read or is malformed; record it again with record.start and record.stop')
	}
	if rec.capacity > s.cfg.capacity {
		return io_error(path, 'recording needs capacity ${rec.capacity}; start vcore with --capacity >= ${rec.capacity}')
	}
	res := sim.replay(rec, &s.reg) or {
		msg := err.msg()
		// Yalnızca "replay diverged: " önekli hatalar kaydın ayrıştığını gösterir; diğerleri sunucu içi hatadır.
		if msg.starts_with('replay diverged: ') {
			d := obj()
			d.set('path', str_val(path))
			d.set('hint', str_val(msg))
			return rpc_error(code_replay_diverged, 'replay diverged', d)
		}
		return internal_error(msg)
	}
	out := obj()
	out.set('end_tick', num(f64(u64(res.end_tick))))
	out.set('hash', hash_val(res.hash))
	return out
}

// Dünyayı .vscene metni olarak yazar; yazım atomiktir (scene.v). Sim durumuna dokunmaz, tick dışındadır.
fn (s &Server) scene_save(p Val) !Val {
	path := string_param(p, 'path')!
	text := scene_text(s.world(), s.registry())
	defer {
		unsafe { text.free() }
	}
	save_scene_atomic(path, text) or {
		return io_error(path, 'could not write file; check that the folder exists and is writable, then retry scene.save')
	}
	res := obj()
	res.set('path', str_val(path))
	res.set('entities', num(f64(s.world().alive_count())))
	res.set('bytes', num(f64(text.len)))
	return res
}

// .vscene dosyasını yükler: önce tamamen doğrular, sonra dünyayı sıfırlayıp komutlarla kurar.
// Ayrıştırma ve doğrulama dosya boyutuna göre ayrılan kendi arenasında yapılır; istek arenası sonuç dizisini tutar.
// Sonuç dizisi dünya sıfırlanmadan önce kurulur: sıfırlamadan sonra yetmezlik olmaz.
fn (mut s Server) scene_load(p Val) !Val {
	path := string_param(p, 'path')!
	text := load_scene_text(path) or {
		return io_error(path, 'could not read file; check that the path exists and is readable, then retry scene.load')
	}
	defer {
		unsafe { text.free() }
	}
	req_off := arena_used()
	need := scene_arena_bytes(text.len)
	region := memory.reserve(need) or {
		return internal_error('scene.load could not reserve ${need} bytes for parsing; free memory and retry')
	}
	defer {
		_ = memory.release(region)
	}
	_ = arena_switch(region, need, 0)
	ents := s.scene_parse(text) or {
		_ = arena_switch(s.req_region, request_arena_bytes(s.cfg), req_off)
		return rehome(err)
	}
	// Bundan sonra istek arenası etkin; ayrıştırma bölgesi yalnız okunur (release'e kadar yaşar).
	_ = arena_switch(s.req_region, request_arena_bytes(s.cfg), req_off)
	n := ents.len()
	out := arr()
	for _ in 0 .. n {
		out.push(num(0))
	}
	if exhausted() {
		return invalid_params('scene has ${n} entities and the response does not fit the request arena; start the server with a larger capacity')
	}
	if s.engine.recorder.is_active() {
		return record_error('a recording is active; call record.stop before scene.load')
	}
	// Dünya sıfırlanır: tick 0, boş geçmiş ve editor_depth 0 (sim.reset ile aynı iç yol).
	_ = s.sim_reset()!
	// Sıfırlama yeni motor (derinlik 0) kurar: kurulum bir grup içinde yazılır, geçmişi sonunda temizlenir.
	s.engine.history.begin_group()
	defer {
		s.engine.history.end_group()
	}
	mut node := out.first()
	for i in 0 .. n {
		ent := ents.at(i) or { break }
		plans := s.scene_entity_plans(ent, i)!
		e := s.spawn_planned(plans) or {
			free_plans(plans)
			return err
		}
		free_plans(plans)
		// Yer tutucu düğüm değerini yerinde değiştirir: bellek ayırmaz, yani yanıt arenası yetmezliği olmaz.
		node.set_num(f64(u64(e)))
		node = node.next()
	}
	// Kurulum komutları geçmişe yazılmış olabilir: yüklenen sahne tek geri alma adımı değildir.
	s.engine.history.clear()
	res := obj()
	res.set('entities', out)
	return res
}

// Ayrıştırma bölgesi boyutu: cJSON düğümleri ve anahtarları metinden birkaç kat büyüktür; 32 kat ve 1 MiB taban yeter.
fn scene_arena_bytes(text_len int) u64 {
	return u64(text_len) * 32 + u64(1) << 20
}

// Metni ayrıştırır ve tamamen doğrular; dünyaya dokunmaz. Döner: varlık dizisi (ayrıştırma bölgesinde).
fn (s &Server) scene_parse(text string) !Val {
	doc := parse(text) or {
		if exhausted() {
			return invalid_params('scene file is too large to parse; split it or start the server with a larger capacity')
		}
		return invalid_params('file is not valid JSON; check the file or save it again with scene.save')
	}
	return s.scene_validate(doc)
}

// Hatayı istek arenasına taşır: ayrıştırma bölgesi serbest bırakılınca eski düğümler geçersiz olur.
// Çağıran istek arenasını etkinleştirmiş olmalıdır.
fn rehome(err IError) IError {
	if err is RpcError {
		return rpc_error(err.err_code, err.message, dup(err.data))
	}
	return err
}

// Belgeyi doğrular ve varlık dizisini döner; dünyaya dokunmaz.
fn (s &Server) scene_validate(doc Val) !Val {
	if !doc.is_object() {
		return invalid_params('scene must be a JSON object')
	}
	format := doc.get('format') or { null_val() }
	if !format.is_string() || format.str() != 'vscene' {
		return invalid_params('format must be "vscene"')
	}
	version := doc.get('version') or { null_val() }
	if !version.is_number() || version.f64() != 1 {
		return invalid_params('version must be 1')
	}
	ents := doc.get('entities') or { null_val() }
	if !ents.is_array() {
		return invalid_params('entities must be an array of entity objects')
	}
	if u64(ents.len()) > u64(s.cfg.capacity) {
		return rpc_error(code_capacity_full, 'world capacity is full', hint_data('scene has ${ents.len()} entities but world capacity is ${s.cfg.capacity}; start the server with a larger capacity'))
	}
	for i in 0 .. ents.len() {
		ent := ents.at(i) or { break }
		plans := s.scene_entity_plans(ent, i)!
		free_plans(plans)
	}
	return ents
}

// Tek varlığın planları; dünyaya dokunmaz. Hata, varlık indeksini taşır.
fn (s &Server) scene_entity_plans(ent Val, index int) ![]Plan {
	comps := ent.get('components') or {
		return scene_error(index, invalid_params('components is required: an object of component values'))
	}
	if !comps.is_object() {
		return scene_error(index, invalid_params('components must be an object of component values'))
	}
	return s.component_plans(comps, true) or { return scene_error(index, err) }
}

// Varlık indeksini hata verisine ekler.
fn scene_error(index int, err IError) IError {
	if err is RpcError {
		d := err.data
		d.set('entity_index', num(f64(index)))
		return rpc_error(err.err_code, err.message, d)
	}
	return err
}

// Bileşen adini kayit id'sine çevirir; yoksa 1002.
fn (s &Server) component_id(name string) !u16 {
	return s.reg.find(name) or { return status_error(.unknown_component, kv('component', str_val(name))) }
}

// Değerleri doğrular ve dünyaya dokunmadan bir Plan uretir. Sıra: ad, alan adı, readonly, tip, değer.
// Yinelenen anahtarda yalnız son değer alınır. scene_values: .vscene değerleri ("nan" gibi metinler) kabul edilir.
fn (s &Server) plan_component(name string, values Val, scene_values bool) !Plan {
	id := s.component_id(name)!
	schema := s.reg.component(id) or {
		return status_error(.unknown_component, kv('component', str_val(name)))
	}
	// +2: Transform'un prev_x/prev_y tohumu (seed_transform_prev) en fazla iki yazım ekler.
	mut writes := []FieldWrite{cap: values.child_count() + 2}
	mut ok := false
	defer {
		if !ok {
			unsafe { writes.free() }
		}
	}
	mut c := values.first()
	for !c.is_nil() {
		if values.is_last(c) {
			writes << s.field_write(name, schema, c.key(), c, scene_values)!
		}
		c = c.next()
	}
	ok = true
	return Plan{
		comp:   id
		writes: writes
	}
}

// Transform verilen spawn'da prev_x/prev_y'yi x/y ile tohumlar: ilk karede interpolasyon sıçramaz.
// İç yazım: prev alanları protokol girişinde readonly, ama bu yol field_write'dan geçmez.
fn (s &Server) seed_transform_prev(mut pl Plan) {
	if pl.comp != ecs.transform_id {
		return
	}
	schema := s.reg.component(pl.comp) or { return }
	xi := schema.field_index('x') or { return }
	yi := schema.field_index('y') or { return }
	pxi := schema.field_index('prev_x') or { return }
	pyi := schema.field_index('prev_y') or { return }
	// Verilmeyen x/y 0 kalır: bileşen varsayılanı da 0 bitidir.
	mut xb := u64(0)
	mut yb := u64(0)
	for w in pl.writes {
		if w.field == xi {
			xb = w.bits
		} else if w.field == yi {
			yb = w.bits
		}
	}
	pl.writes << FieldWrite{ field: pxi, bits: xb }
	pl.writes << FieldWrite{ field: pyi, bits: yb }
}

// Tek bir alan yazımını doğrular: alan adı, readonly, tip, aralık.
// scene: .vscene değerleri. Metin olarak yazılan "inf", "-inf", "nan" yalnız varsayılan aralıklı alanda kabul edilir;
// açık aralıklı alanda sonlu olmayan her değer reddedilir (NaN karşılaştırmaları aralığı geçtiği için ayrıca denetlenir).
fn (s &Server) field_write(name string, schema ecs.ComponentSchema, fname string, v Val, scene bool) !FieldWrite {
	fi := schema.field_index(fname) or {
		return status_error(.unknown_field, component_field_ref(name, fname))
	}
	f := schema.fields[fi]
	if f.readonly {
		d := component_field_ref(name, fname)
		d.set('hint', str_val('${name}.${fname} is maintained by the system and cannot be set'))
		return rpc_error(code_readonly_field, 'readonly field', d)
	}
	// shortcut: yalnız f32 JSON donusumu; i32/bool/entity M6'da
	if f.typ != .f32_ {
		return invalid_params('field ${name}.${fname} has type ${f.typ.name()}, only f32 is supported over JSON')
	}
	if scene && v.is_string() {
		special := scene_nonfinite(v) or { return finite_error(name, fname) }
		if f.ranged {
			return range_error(name, fname, f)
		}
		return FieldWrite{
			field: u16(fi)
			bits:  u64(math.f32_bits(f32(special)))
		}
	}
	bits := f32_bits(v) or { return finite_error(name, fname) }
	x := v.f64()
	if f.ranged && x != x {
		return range_error(name, fname, f)
	}
	if x < f.min || x > f.max {
		return range_error(name, fname, f)
	}
	return FieldWrite{
		field: u16(fi)
		bits:  bits
	}
}

// Sonlu olmayan ya da sayı olmayan değer: -32602, bileşen ve alan adıyla (scene yolunda varlık indeksi scene_error ile eklenir).
fn finite_error(name string, fname string) RpcError {
	d := component_field_ref(name, fname)
	d.set('hint', str_val('${name}.${fname} must be a finite number'))
	return rpc_error(code_invalid_params, 'invalid params', d)
}

fn range_error(name string, fname string, f ecs.FieldSchema) RpcError {
	d := component_field_ref(name, fname)
	d.set('hint', str_val('${name}.${fname} must be in [${range_text(f.min)}, ${range_text(f.max)}]'))
	return rpc_error(code_invalid_params, 'invalid params', d)
}

// .vscene'de sonsuz ve NaN değerler metin olarak yazılır; üç bilinen metin f64'e çevrilir.
fn scene_nonfinite(v Val) ?f64 {
	if !v.is_string() {
		return none
	}
	if v.str() == 'nan' {
		return math.nan()
	}
	if v.str() == 'inf' {
		return math.inf(1)
	}
	if v.str() == '-inf' {
		return math.inf(-1)
	}
	return none
}

// Komutları kuyruğa koyar ve tek flush ile uygular. Sonuçların ilk ok olmayanı hata olur.
// Kapasite komutlardan önce denetlenir: yarım kalmış bir kuyruk sonraki isteğe sızmaz.
fn (mut s Server) commit(cmds []cmd.Command) ! {
	if cmds.len > int(s.cfg.queue_capacity) {
		return rpc_error(code_queue_full, 'command queue is full', hint_data('request needs ${cmds.len} queue slots but queue_capacity is ${s.cfg.queue_capacity}'))
	}
	for c in cmds {
		if !s.engine.push(c) {
			return rpc_error(code_queue_full, 'command queue is full', hint_data('command queue rejected a command; retry the request'))
		}
	}
	_ = s.engine.flush()
	for i, c in cmds {
		r := s.engine.queue.result(u32(i))
		if r.status != .ok {
			return s.cmd_error(r.status, c)
		}
	}
}

// commit'in tek komutluk hali: dizi tahsisi yapmaz, denetimler commit ile aynıdır.
fn (mut s Server) commit_one(c cmd.Command) ! {
	if 1 > int(s.cfg.queue_capacity) {
		return rpc_error(code_queue_full, 'command queue is full', hint_data('request needs 1 queue slots but queue_capacity is ${s.cfg.queue_capacity}'))
	}
	if !s.engine.push(c) {
		return rpc_error(code_queue_full, 'command queue is full', hint_data('command queue rejected a command; retry the request'))
	}
	_ = s.engine.flush()
	r := s.engine.queue.result(0)
	if r.status != .ok {
		return s.cmd_error(r.status, c)
	}
}

// Komut hatasını entity, component ve field bağlamıyla kodlar.
fn (s &Server) cmd_error(st ecs.Status, c cmd.Command) RpcError {
	refs := obj()
	if c.kind != .spawn {
		refs.set('entity', num(f64(u64(c.entity))))
	}
	if c.kind in [.add_component, .remove_component, .set_field] {
		if schema := s.reg.component(c.comp) {
			refs.set('component', str_val(schema.name))
			if c.kind == .set_field && int(c.field) < schema.fields.len {
				refs.set('field', str_val(schema.fields[c.field].name))
			}
		}
	}
	return status_error(st, refs)
}

// Nesne tipindeki parametre; yoksa nil (boş nesne gibi okunur). Tip yanlışsa -32602.
fn object_param(p Val, key string) !Val {
	v := p.get(key) or { return Val{} }
	if !v.is_object() {
		return invalid_params('${key} must be an object')
	}
	return v
}

fn string_param(p Val, key string) !string {
	v := p.get(key) or { return invalid_params('${key} is required') }
	if !v.is_string() {
		return invalid_params('${key} must be a string')
	}
	return v.str()
}

// Entity id: JSON tamsayısı, 0 <= x < 2^48.
fn entity_param(p Val) !ecs.EntityID {
	v := p.get('entity') or { return invalid_params('entity is required: a non-negative integer id') }
	if !v.is_number() {
		return invalid_params('entity must be a non-negative integer id')
	}
	x := v.f64()
	if x < 0 || x >= entity_id_limit || x != math.floor(x) {
		return invalid_params('entity must be a non-negative integer id below 2^48')
	}
	return ecs.EntityID(u64(x))
}

// Tamsayı parametresi; [lo, hi] aralığında olmali.
fn int_param(p Val, key string, lo int, hi int) !int {
	v := p.get(key) or { return invalid_params('${key} is required') }
	if !v.is_number() {
		return invalid_params('${key} must be an integer')
	}
	x := v.f64()
	if x != math.floor(x) || x < f64(lo) || x > f64(hi) {
		return invalid_params('${key} must be an integer from ${lo} to ${hi}')
	}
	return int(x)
}

// JSON sayısı f32 aralığındaysa ve sonluysa bit desenini döner.
fn f32_bits(v Val) ?u64 {
	if !v.is_number() {
		return none
	}
	x := v.f64()
	if x > max_f32 || x < -max_f32 {
		return none
	}
	return u64(math.f32_bits(f32(x)))
}

// f32 bit deseni JSON degeri: sonlu sayi sayi olarak, sonsuz ve NaN metin olarak ("inf", "-inf", "nan").
// JSON'da inf/NaN yoktur; alan tasmasi (ornegin hareket sonrasi) bu yoldan cikar.
fn f32_json(bits u64) Val {
	x := f64(math.f32_from_bits(u32(bits)))
	if x != x {
		return str_val('nan')
	}
	if x > max_f32 {
		return str_val('inf')
	}
	if x < -max_f32 {
		return str_val('-inf')
	}
	return num(x)
}

// Tam sayı sınırları "0" biçiminde, ondalıklılar olduğu gibi yazılır.
fn range_text(x f64) string {
	if x == math.floor(x) {
		return '${i64(x)}'
	}
	return '${x}'
}

// "0x" + 16 hex: tampon yığında kurulur ve arenaya kopyalanır (string interpolation tahsis eder).
fn hash_val(h u64) Val {
	mut buf := [19]u8{}
	digits := '0123456789abcdef'
	buf[0] = `0`
	buf[1] = `x`
	for i in 0 .. 16 {
		buf[2 + i] = digits[int((h >> u64(60 - 4 * i)) & 0xf)]
	}
	// buf[18] NUL kalır: cJSON_CreateString uzunluğu strlen ile bulur.
	return str_val(unsafe { tos(&u8(&buf[0]), 18) })
}

fn empty_object() Val {
	return obj()
}

// Tek anahtarlı nesne; hata bağlamı (entity, component ...) için.
fn kv(key string, x Val) Val {
	o := obj()
	o.set(key, x)
	return o
}

fn component_field_ref(name string, fname string) Val {
	o := obj()
	o.set('component', str_val(name))
	o.set('field', str_val(fname))
	return o
}

fn record_error(hint string) RpcError {
	return rpc_error(code_record_state, 'record state', hint_data(hint))
}

// Dosya hatası: path ve bir hint.
fn io_error(path string, hint string) RpcError {
	d := obj()
	d.set('path', str_val(path))
	d.set('hint', str_val(hint))
	return rpc_error(code_io_error, 'io error', d)
}

// Ayrılmış planların dizilerini serbest bırakır (istek sonunda çağrılır).
fn free_plans(plans []Plan) {
	for pl in plans {
		unsafe { pl.writes.free() }
	}
	unsafe { plans.free() }
}
