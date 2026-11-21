module protocol

import memory
import sim

// Yanıtlar istek arenasında üretilir ve test tarafından serbest bırakılmaz. İstek satırları sabit
// literaldir, böylece döngünün kendisi V heap'inde iz bırakmaz; ölçülen artış protokolün kendisine aittir.
fn test_requests_do_not_grow_live_heap() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap yok; sızıntı testi koşmadı')
		return
	}
	mut s := Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
	defer {
		s.close()
	}
	spawn_line := '{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1.5},"Body":{"vx":2}}}}'
	_ = s.handle(spawn_line) or { panic('yanıt yok') }
	get_line := '{"jsonrpc":"2.0","id":2,"method":"entity.get","params":{"entity":0}}'
	set_line := '{"jsonrpc":"2.0","id":3,"method":"component.set","params":{"entity":0,"component":"Transform","field":"x","value":1}}'
	step_line := '{"jsonrpc":"2.0","id":4,"method":"sim.step","params":{"n":1}}'
	schema_line := '{"jsonrpc":"2.0","id":5,"method":"schema.components"}'
	// Isınma: ilk isteklerin bir kerelik tahsisleri (sayaç kayıtları vb.) ölçümden önce yapılır.
	for _ in 0 .. 10 {
		_ = s.handle(get_line) or { panic('yanıt yok') }
		_ = s.handle(set_line) or { panic('yanıt yok') }
		_ = s.handle(step_line) or { panic('yanıt yok') }
		_ = s.handle(schema_line) or { panic('yanıt yok') }
	}
	before := memory.heap_live_count()
	for _ in 0 .. 1000 {
		_ = s.handle(get_line) or { panic('yanıt yok') }
		_ = s.handle(set_line) or { panic('yanıt yok') }
		_ = s.handle(step_line) or { panic('yanıt yok') }
		_ = s.handle(schema_line) or { panic('yanıt yok') }
	}
	growth := memory.heap_live_count() - before
	assert growth <= 16, 'canli tahsis artisi: ${growth}'
}
