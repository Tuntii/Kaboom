module protocol

import math
import x.json2
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
	comp   u16
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
		result: '{"entity": id, "index": n, "generation": n, "components": {"<Comp>": {"<field>": number}}}'
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
		result: '{}; dünyayı, kuyruğu ve kaydı sıfırlar'
	},
	CommandDoc{
		method: 'sim.state_hash'
		params: 'none'
		result: '{"tick": n, "hash": "0x<16 hex>"}'
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
]

fn (mut s Server) entity_spawn(p map[string]json2.Any) !json2.Any {
	comps := object_param(p, 'components')!
	mut plans := []Plan{}
	for name, v in comps {
		if v !is map[string]json2.Any {
			return invalid_params('components.${name} must be an object of field values')
		}
		plans << s.plan_component(name, v as map[string]json2.Any)!
	}
	// Spawn bir komut, her bileşen bir add, her alan bir set: hepsi kuyrukta sığmalı.
	mut need := u64(1)
	for pl in plans {
		need += u64(1 + pl.writes.len)
	}
	if need > u64(s.cfg.queue_capacity) {
		return rpc_error(code_queue_full, 'command queue is full', {
			'hint': json2.Any('spawn needs ${need} queue slots but queue_capacity is ${s.cfg.queue_capacity}; spawn fewer components or start the server with a larger queue_capacity')
		})
	}
	s.commit([cmd.Command{
		kind:   .spawn
		source: .agent
	}])!
	e := s.engine.queue.result(0).entity
	mut cmds := []cmd.Command{}
	for pl in plans {
		cmds << cmd.Command{
			kind:   .add_component
			source: .agent
			entity: e
			comp:   pl.comp
		}
		for w in pl.writes {
			cmds << cmd.Command{
				kind:   .set_field
				source: .agent
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
	return json2.Any({
		'entity': json2.Any(u64(e))
	})
}

fn (mut s Server) entity_despawn(p map[string]json2.Any) !json2.Any {
	e := entity_param(p)!
	s.commit([cmd.Command{
		kind:   .despawn
		source: .agent
		entity: e
	}])!
	return empty_object()
}

fn (mut s Server) component_add(p map[string]json2.Any) !json2.Any {
	e := entity_param(p)!
	name := string_param(p, 'component')!
	values := object_param(p, 'values')!
	plan := s.plan_component(name, values)!
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
	mut cmds := [
		cmd.Command{
			kind:   .add_component
			source: .agent
			entity: e
			comp:   plan.comp
		},
	]
	for w in plan.writes {
		cmds << cmd.Command{
			kind:   .set_field
			source: .agent
			entity: e
			comp:   plan.comp
			field:  w.field
			value:  w.bits
		}
	}
	s.commit(cmds)!
	return empty_object()
}

fn (mut s Server) component_remove(p map[string]json2.Any) !json2.Any {
	e := entity_param(p)!
	name := string_param(p, 'component')!
	comp := s.component_id(name)!
	s.commit([
		cmd.Command{
			kind:   .remove_component
			source: .agent
			entity: e
			comp:   comp
		},
	])!
	return empty_object()
}

fn (mut s Server) component_set(p map[string]json2.Any) !json2.Any {
	e := entity_param(p)!
	name := string_param(p, 'component')!
	fname := string_param(p, 'field')!
	v := p['value'] or { return invalid_params('value is required: a number') }
	plan := s.plan_component(name, {
		fname: v
	})!
	w := plan.writes[0]
	s.commit([
		cmd.Command{
			kind:   .set_field
			source: .agent
			entity: e
			comp:   plan.comp
			field:  w.field
			value:  w.bits
		},
	])!
	return empty_object()
}

fn (s &Server) entity_get(p map[string]json2.Any) !json2.Any {
	e := entity_param(p)!
	w := &s.engine.world
	if !w.is_alive(e) {
		return status_error(.dead_entity, {
			'entity': json2.Any(u64(e))
		})
	}
	mut comps := map[string]json2.Any{}
	for id in u16(0) .. s.reg.count() {
		if !w.has(e, id) {
			continue
		}
		schema := s.reg.component(id) or { continue }
		mut fields := map[string]json2.Any{}
		for fi, f in schema.fields {
			// shortcut: yalnız f32 alanlar JSON'a çevrilir; i32/bool/entity M6'da
			if f.typ != .f32_ {
				continue
			}
			bits := w.get_field(e, id, u16(fi)) or { continue }
			fields[f.name] = f32_json(bits)
		}
		comps[schema.name] = json2.Any(fields)
	}
	return json2.Any({
		'entity':     json2.Any(u64(e))
		'index':      json2.Any(int(e.index()))
		'generation': json2.Any(int(e.generation()))
		'components': json2.Any(comps)
	})
}

fn (s &Server) query_entities(p map[string]json2.Any) !json2.Any {
	wv := p['with'] or { return invalid_params('with is required: an array of component names') }
	if wv !is []json2.Any {
		return invalid_params('with must be an array of component names')
	}
	names := wv as []json2.Any
	mut ids := []u16{}
	for n in names {
		if n !is string {
			return invalid_params('with must be an array of component names')
		}
		ids << s.component_id(n as string)!
	}
	mut limit := max_int
	if 'limit' in p {
		limit = int_param(p, 'limit', 0, max_int)!
	}
	w := &s.engine.world
	alloc := w.entities()
	mut out := []json2.Any{}
	mut total := 0
	for i in 0 .. alloc.high_water() {
		e := alloc.handle_at(i) or { continue }
		mut all := true
		for c in ids {
			if !w.has(e, c) {
				all = false
				break
			}
		}
		if !all {
			continue
		}
		total++
		if out.len < limit {
			out << json2.Any(u64(e))
		}
	}
	return json2.Any({
		'entities': json2.Any(out)
		'count':    json2.Any(total)
	})
}

fn (s &Server) schema_components() !json2.Any {
	mut list := []json2.Any{}
	for id in u16(0) .. s.reg.count() {
		c := s.reg.component(id) or { continue }
		mut fields := []json2.Any{}
		for f in c.fields {
			fields << json2.Any({
				'name':     json2.Any(f.name)
				'type':     json2.Any(f.typ.name())
				'unit':     json2.Any(f.unit)
				'min':      json2.Any(f.min)
				'max':      json2.Any(f.max)
				'desc':     json2.Any(f.desc)
				'readonly': json2.Any(f.readonly)
			})
		}
		list << json2.Any({
			'id':     json2.Any(int(c.id))
			'name':   json2.Any(c.name)
			'fields': json2.Any(fields)
		})
	}
	return json2.Any({
		'components': json2.Any(list)
	})
}

fn schema_commands() json2.Any {
	mut list := []json2.Any{}
	for d in command_docs {
		list << json2.Any({
			'method': json2.Any(d.method)
			'params': json2.Any(d.params)
			'result': json2.Any(d.result)
		})
	}
	return json2.Any({
		'commands': json2.Any(list)
	})
}

fn (mut s Server) sim_step(p map[string]json2.Any) !json2.Any {
	n := int_param(p, 'n', 1, 1_000_000)!
	for _ in 0 .. n {
		s.engine.step()
	}
	return json2.Any({
		'tick': json2.Any(u64(s.engine.tick()))
	})
}

// Bölgeyi serbest birakip tazesini ayırır. Yeniden ayırma başarısızsa sunucu kapalı kalır.
fn (mut s Server) sim_reset() !json2.Any {
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
	return empty_object()
}

fn (s &Server) sim_state_hash() json2.Any {
	return json2.Any({
		'tick': json2.Any(u64(s.engine.tick()))
		'hash': json2.Any(hash_hex(s.engine.state_hash()))
	})
}

fn (mut s Server) record_start() !json2.Any {
	if s.engine.recorder.is_active() {
		return record_error('a recording is already active; call record.stop first')
	}
	if s.engine.tick() != 0 || s.engine.world.entities().high_water() != 0 {
		return record_error('recording starts only on a pristine world (tick 0, no entities); call sim.reset first')
	}
	s.engine.recorder.start()
	return empty_object()
}

fn (mut s Server) record_stop(p map[string]json2.Any) !json2.Any {
	path := string_param(p, 'path')!
	if !s.engine.recorder.is_active() {
		return record_error('no recording is active; call record.start first')
	}
	s.engine.recorder.stop()
	tick := s.engine.tick()
	s.engine.recorder.save(path, s.cfg.capacity, tick) or {
		return rpc_error(code_io_error, 'io error', {
			'path': json2.Any(path)
			'hint': json2.Any('recording was not saved: the file could not be written or the record buffer overflowed (raise record_capacity)')
		})
	}
	return json2.Any({
		'path':     json2.Any(path)
		'commands': json2.Any(int(s.engine.recorder.len()))
		'end_tick': json2.Any(u64(tick))
		'hash':     json2.Any(hash_hex(s.engine.state_hash()))
	})
}

fn (s &Server) replay_run(p map[string]json2.Any) !json2.Any {
	path := string_param(p, 'path')!
	rec := cmd.load_recording(path) or {
		return rpc_error(code_io_error, 'io error', {
			'path': json2.Any(path)
			'hint': json2.Any('recording could not be read or is malformed; record it again with record.start and record.stop')
		})
	}
	res := sim.replay(rec, &s.reg) or {
		return rpc_error(code_replay_diverged, 'replay diverged', {
			'path': json2.Any(path)
			'hint': json2.Any(err.msg())
		})
	}
	return json2.Any({
		'end_tick': json2.Any(u64(res.end_tick))
		'hash':     json2.Any(hash_hex(res.hash))
	})
}

// Bileşen adini kayit id'sine çevirir; yoksa 1002.
fn (s &Server) component_id(name string) !u16 {
	return s.reg.find(name) or {
		return status_error(.unknown_component, {
			'component': json2.Any(name)
		})
	}
}

// Değerleri doğrular ve dünyaya dokunmadan bir Plan uretir. Sıra: ad, readonly, tip, değer.
fn (s &Server) plan_component(name string, values map[string]json2.Any) !Plan {
	id := s.component_id(name)!
	schema := s.reg.component(id) or {
		return status_error(.unknown_component, {
			'component': json2.Any(name)
		})
	}
	mut writes := []FieldWrite{}
	for fname, v in values {
		fi := schema.field_index(fname) or {
			return status_error(.unknown_field, {
				'component': json2.Any(name)
				'field':     json2.Any(fname)
			})
		}
		f := schema.fields[fi]
		if f.readonly {
			return rpc_error(code_readonly_field, 'readonly field', {
				'component': json2.Any(name)
				'field':     json2.Any(fname)
				'hint':      json2.Any('${name}.${fname} is maintained by the system and cannot be set')
			})
		}
		// shortcut: yalnız f32 JSON donusumu; i32/bool/entity M6'da
		if f.typ != .f32_ {
			return invalid_params('field ${name}.${fname} has type ${f.typ.name()}, only f32 is supported over JSON')
		}
		bits := f32_bits(v) or { return invalid_params('${name}.${fname} must be a finite number') }
		writes << FieldWrite{
			field: u16(fi)
			bits:  bits
		}
	}
	return Plan{
		comp:   id
		writes: writes
	}
}

// Komutları kuyruğa koyar ve tek flush ile uygular. Sonuçların ilk ok olmayanı hata olur.
// Kapasite komutlardan önce denetlenir: yarım kalmış bir kuyruk sonraki isteğe sızmaz.
fn (mut s Server) commit(cmds []cmd.Command) ! {
	if cmds.len > int(s.cfg.queue_capacity) {
		return rpc_error(code_queue_full, 'command queue is full', {
			'hint': json2.Any('request needs ${cmds.len} queue slots but queue_capacity is ${s.cfg.queue_capacity}')
		})
	}
	for c in cmds {
		if !s.engine.push(c) {
			return rpc_error(code_queue_full, 'command queue is full', {
				'hint': json2.Any('command queue rejected a command; retry the request')
			})
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

// Komut hatasını entity, component ve field bağlamıyla kodlar.
fn (s &Server) cmd_error(st ecs.Status, c cmd.Command) RpcError {
	mut refs := map[string]json2.Any{}
	if c.kind != .spawn {
		refs['entity'] = json2.Any(u64(c.entity))
	}
	if c.kind in [.add_component, .remove_component, .set_field] {
		if schema := s.reg.component(c.comp) {
			refs['component'] = json2.Any(schema.name)
			if c.kind == .set_field && int(c.field) < schema.fields.len {
				refs['field'] = json2.Any(schema.fields[c.field].name)
			}
		}
	}
	return status_error(st, refs)
}

// Nesne tipindeki parametre; yoksa boş nesne. Tip yanlışsa -32602.
fn object_param(p map[string]json2.Any, key string) !map[string]json2.Any {
	if key !in p {
		return map[string]json2.Any{}
	}
	v := p[key] or { null_value() }
	if v !is map[string]json2.Any {
		return invalid_params('${key} must be an object')
	}
	return v as map[string]json2.Any
}

fn string_param(p map[string]json2.Any, key string) !string {
	v := p[key] or { return invalid_params('${key} is required') }
	if v !is string {
		return invalid_params('${key} must be a string')
	}
	return v as string
}

// Entity id: JSON tamsayısı, 0 <= x < 2^48.
fn entity_param(p map[string]json2.Any) !ecs.EntityID {
	v := p['entity'] or { return invalid_params('entity is required: a non-negative integer id') }
	if v !is f64 {
		return invalid_params('entity must be a non-negative integer id')
	}
	x := v as f64
	if x < 0 || x >= entity_id_limit || x != math.floor(x) {
		return invalid_params('entity must be a non-negative integer id below 2^48')
	}
	return ecs.EntityID(u64(x))
}

// Tamsayı parametresi; [lo, hi] aralığında olmali.
fn int_param(p map[string]json2.Any, key string, lo int, hi int) !int {
	v := p[key] or { return invalid_params('${key} is required') }
	if v !is f64 {
		return invalid_params('${key} must be an integer')
	}
	x := v as f64
	if x != math.floor(x) || x < f64(lo) || x > f64(hi) {
		return invalid_params('${key} must be an integer from ${lo} to ${hi}')
	}
	return int(x)
}

// JSON sayısı f32 aralığındaysa ve sonluysa bit desenini döner.
fn f32_bits(v json2.Any) ?u64 {
	if v !is f64 {
		return none
	}
	x := v as f64
	if x > max_f32 || x < -max_f32 {
		return none
	}
	return u64(math.f32_bits(f32(x)))
}

// f32 bit deseni JSON degeri: sonlu sayi sayi olarak, sonsuz ve NaN metin olarak ("inf", "-inf", "nan").
// JSON'da inf/NaN yoktur; alan tasmasi (ornegin hareket sonrasi) bu yoldan cikar.
fn f32_json(bits u64) json2.Any {
	x := f64(math.f32_from_bits(u32(bits)))
	if x != x {
		return json2.Any('nan')
	}
	if x > max_f32 {
		return json2.Any('inf')
	}
	if x < -max_f32 {
		return json2.Any('-inf')
	}
	return json2.Any(x)
}

fn hash_hex(h u64) string {
	return '0x${h:016x}'
}

fn empty_object() json2.Any {
	return json2.Any(map[string]json2.Any{})
}

fn record_error(hint string) RpcError {
	return rpc_error(code_record_state, 'record state', {
		'hint': json2.Any(hint)
	})
}
