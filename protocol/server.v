module protocol

import x.json2
import sim
import ecs
import memory

// JSON-RPC sunucusu: bir sim.Sim ve onun bellek bölgesini sahiplenir. İstekler tek tek işlenir;
// her istekten sonra kuyruk boşalmış olur.
pub struct Server {
mut:
	cfg    sim.Config
	reg    ecs.Registry
	region &u8
	engine sim.Sim
}

// Bölgeyi cfg.bytes_needed kadar rezerve eder ve Sim'i kurar.
pub fn Server.new(cfg sim.Config) !Server {
	reg := ecs.core_registry()!
	need := cfg.bytes_needed(&reg)
	region := memory.reserve(need) or { return error('protocol: bölge ayrilamadi (${need} bayt)') }
	mut a := memory.LinearArena.new(region, need)
	engine := sim.Sim.new(mut a, &reg, cfg) or {
		_ = memory.release(region)
		return error('protocol: Sim kurulamadi')
	}
	return Server{
		cfg:    cfg
		reg:    reg
		region: region
		engine: engine
	}
}

// Bölgeyi serbest birakir. Sonrasindaki istekler yapilandirilmis hata döner.
pub fn (mut s Server) close() {
	if s.region != unsafe { nil } {
		_ = memory.release(s.region)
		s.region = unsafe { nil }
	}
}

// Tek satır istek alir; yanıt satırını ya da none döner (bildirim ve bos satır).
// Hiçbir girdi panik yaratmaz: ayrıştırma ve yürütme hatalari yapilandirilmis yanıta dönüşür.
pub fn (mut s Server) handle(line string) ?string {
	text := line.trim_space()
	if text == '' {
		return none
	}
	// json2 özyinelemelidir: derin satır yığını taşırmadan decode'a girmeden reddedilir.
	if json_nesting_too_deep(text) {
		return error_line(null_value(), rpc_error(code_parse, 'parse error', {
			'hint': json2.Any('JSON nesting deeper than 64')
		}))
	}
	req := json2.decode[json2.Any](text) or {
		return error_line(null_value(), rpc_error(code_parse, 'parse error', {
			'hint': json2.Any('request line is not valid JSON')
		}))
	}
	if req !is map[string]json2.Any {
		return error_line(null_value(),
			invalid_request('request must be a single JSON object; batches are not supported'))
	}
	m := req as map[string]json2.Any
	// id alani yoksa istek bildirimdir: yürütülür ama yanıt yazilmaz.
	has_id := 'id' in m
	id := m['id'] or { null_value() }
	if has_id && !is_valid_id(id) {
		return error_line(null_value(), invalid_request('id must be a number, a string or null'))
	}
	// Surum uyesi yoksa ya da "2.0" degilse istek yurutulmez; bildirimse yanit da yazilmaz.
	if !is_jsonrpc_20(m) {
		if !has_id {
			return none
		}
		return error_line(id, invalid_request('jsonrpc member must be "2.0"'))
	}
	result := s.invoke(m) or {
		if !has_id {
			return none
		}
		return error_line(id, err)
	}
	if !has_id {
		return none
	}
	return success_line(id, result)
}

// Yöntemi ve parametreleri doğrular, ilgili işleyiciye yönlendirir.
fn (mut s Server) invoke(m map[string]json2.Any) !json2.Any {
	if s.region == unsafe { nil } {
		return internal_error('server is closed; create a new server')
	}
	method_v := m['method'] or { null_value() }
	if method_v !is string {
		return invalid_request('method must be a string')
	}
	mut p := map[string]json2.Any{}
	if 'params' in m {
		pv := m['params'] or { null_value() }
		if pv !is map[string]json2.Any {
			return invalid_params('params must be an object')
		}
		p = pv as map[string]json2.Any
	}
	return s.dispatch(method_v as string, p)
}

fn (mut s Server) dispatch(method string, p map[string]json2.Any) !json2.Any {
	match method {
		'entity.spawn' { return s.entity_spawn(p) }
		'entity.despawn' { return s.entity_despawn(p) }
		'component.add' { return s.component_add(p) }
		'component.remove' { return s.component_remove(p) }
		'component.set' { return s.component_set(p) }
		'entity.get' { return s.entity_get(p) }
		'query.entities' { return s.query_entities(p) }
		'schema.components' { return s.schema_components() }
		'schema.commands' { return schema_commands() }
		'sim.step' { return s.sim_step(p) }
		'sim.reset' { return s.sim_reset() }
		'sim.state_hash' { return s.sim_state_hash() }
		'record.start' { return s.record_start() }
		'record.stop' { return s.record_stop(p) }
		'replay.run' { return s.replay_run(p) }
		else {}
	}

	return rpc_error(code_method_not_found, 'method not found', {
		'hint': json2.Any('unknown method "${method}"; see schema.commands')
	})
}

// [ ve { derinliği JSON metinlerinde (tırnak içi hariç) 64'ü aşarsa true.
fn json_nesting_too_deep(text string) bool {
	mut depth := 0
	mut in_str := false
	mut i := 0
	for i < text.len {
		c := text[i]
		if in_str {
			if c == `\\` {
				i += 2
				continue
			}
			if c == `"` {
				in_str = false
			}
		} else if c == `"` {
			in_str = true
		} else if c == `[` || c == `{` {
			depth++
			if depth > 64 {
				return true
			}
		} else if c == `]` || c == `}` {
			depth--
		}
		i++
	}
	return false
}

fn is_jsonrpc_20(m map[string]json2.Any) bool {
	v := m['jsonrpc'] or { return false }
	return v is string && (v as string) == '2.0'
}

fn is_valid_id(id json2.Any) bool {
	return id is f64 || id is string || id is json2.Null
}

fn null_value() json2.Any {
	return json2.Any(json2.null)
}

fn success_line(id json2.Any, result json2.Any) string {
	mut m := map[string]json2.Any{}
	m['jsonrpc'] = json2.Any('2.0')
	m['id'] = id
	m['result'] = result
	return json2.encode(m)
}

// Hata yanıti; IError RpcError degilse sunucu içi hata olarak raporlanır.
// Alanlar smartcast ile okunur: `as` ile deger çevrimi V 0.5.2'de C derlemesini bozuyor.
fn error_line(id json2.Any, err IError) string {
	mut code := code_internal
	mut message := 'internal error'
	mut data := map[string]json2.Any{}
	data['hint'] = json2.Any('unexpected error')
	if err is RpcError {
		code = err.err_code
		message = err.message
		data = err.data.clone()
	}
	mut obj := map[string]json2.Any{}
	obj['code'] = json2.Any(code)
	obj['message'] = json2.Any(message)
	obj['data'] = json2.Any(data)
	mut m := map[string]json2.Any{}
	m['jsonrpc'] = json2.Any('2.0')
	m['id'] = id
	m['error'] = json2.Any(obj)
	return json2.encode(m)
}
