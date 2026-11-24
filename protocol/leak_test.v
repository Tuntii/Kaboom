module protocol

import os
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

// Geri alma, yineleme, kaydetme ve yükleme de istek başına V heap tahsisi bırakmamalı: M4c Ctrl+Z/Ctrl+S'i saatlerce çağıracak.
fn test_history_and_scene_do_not_grow_live_heap() {
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
	// JSON metninde ters eğik çizgi kaçışı geçersizdir: yol ileri eğik çizgiyle yazılır (Windows).
	path := os.join_path(os.temp_dir(), 'vcore_leak_scene_test.vscene').replace('\\', '/')
	defer {
		os.rm(path) or {}
	}
	_ = s.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1.5},"Body":{"vx":2}}}}') or { panic('yanıt yok') }
	set_line := '{"jsonrpc":"2.0","id":2,"method":"component.set","params":{"entity":0,"component":"Transform","field":"x","value":3}}'
	undo_line := '{"jsonrpc":"2.0","id":3,"method":"history.undo"}'
	redo_line := '{"jsonrpc":"2.0","id":4,"method":"history.redo"}'
	save_line := '{"jsonrpc":"2.0","id":5,"method":"scene.save","params":{"path":"${path}"}}'
	load_line := '{"jsonrpc":"2.0","id":6,"method":"scene.load","params":{"path":"${path}"}}'
	// Kaydedilecek sahne dosyası: yükleme, dosyadaki varlıkları yeniden kurar.
	first_save := s.handle(save_line) or { panic('yanıt yok') }
	// Ölçüm başarılı yolu kapsamalı: hata yanıtı (ör. geçersiz JSON yolu) ölçümü yanlış kılar.
	assert first_save.contains('"result"'), 'scene.save başarısız: ${first_save}'
	// Isınma: ilk isteklerin bir kerelik tahsisleri ölçümden önce yapılır.
	for _ in 0 .. 10 {
		_ = s.handle(set_line) or { panic('yanıt yok') }
		_ = s.handle(undo_line) or { panic('yanıt yok') }
		_ = s.handle(redo_line) or { panic('yanıt yok') }
		_ = s.handle(save_line) or { panic('yanıt yok') }
		_ = s.handle(load_line) or { panic('yanıt yok') }
	}
	before_hist := memory.heap_live_count()
	for _ in 0 .. 1000 {
		_ = s.handle(set_line) or { panic('yanıt yok') }
		_ = s.handle(undo_line) or { panic('yanıt yok') }
		_ = s.handle(redo_line) or { panic('yanıt yok') }
	}
	growth_hist := memory.heap_live_count() - before_hist
	assert growth_hist <= 16, 'undo/redo canli tahsis artisi: ${growth_hist}'
	before_save := memory.heap_live_count()
	for _ in 0 .. 1000 {
		_ = s.handle(save_line) or { panic('yanıt yok') }
	}
	growth_save := memory.heap_live_count() - before_save
	assert growth_save <= 16, 'scene.save canli tahsis artisi: ${growth_save}'
	before_load := memory.heap_live_count()
	for _ in 0 .. 1000 {
		_ = s.handle(load_line) or { panic('yanıt yok') }
	}
	growth_load := memory.heap_live_count() - before_load
	assert growth_load <= 16, 'scene.load canli tahsis artisi: ${growth_load}'
}

// Transform+Body spawn'ının geri al/yinele döngüsü: her adım bir blok dizisi kopyalar, bu dizilerin sızmaması gerekir.
fn test_spawn_undo_redo_cycles_do_not_grow_live_heap() {
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
	_ = s.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1.5},"Body":{"vx":2}}}}') or { panic('yanit yok') }
	undo_line := '{"jsonrpc":"2.0","id":3,"method":"history.undo"}'
	redo_line := '{"jsonrpc":"2.0","id":4,"method":"history.redo"}'
	for _ in 0 .. 10 {
		_ = s.handle(undo_line) or { panic('yanit yok') }
		_ = s.handle(redo_line) or { panic('yanit yok') }
	}
	before := memory.heap_live_count()
	for _ in 0 .. 1000 {
		_ = s.handle(undo_line) or { panic('yanit yok') }
		_ = s.handle(redo_line) or { panic('yanit yok') }
	}
	growth := memory.heap_live_count() - before
	assert growth <= 16, 'spawn geri al/yinele canli tahsis artisi: ${growth}'
}

// Tek editör grubunda üç silme: geri alma üç blok ve üç eşleşme üretir; dizi kapasiteleri sızıntıyı önler.
fn test_editor_group_undo_redo_does_not_grow_live_heap() {
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
	for i in 0 .. 3 {
		_ = s.handle('{"jsonrpc":"2.0","id":${i + 1},"method":"entity.spawn","params":{"components":{"Transform":{"x":1.5},"Body":{"vx":2}}}}') or { panic('yanit yok') }
	}
	s.history_begin_group()
	for i in 0 .. 3 {
		_ = s.handle_from('{"jsonrpc":"2.0","id":${i + 10},"method":"entity.despawn","params":{"entity":${i}}}', .editor) or { panic('yanit yok') }
	}
	s.history_end_group()
	undo_line := '{"jsonrpc":"2.0","id":3,"method":"history.undo"}'
	redo_line := '{"jsonrpc":"2.0","id":4,"method":"history.redo"}'
	for _ in 0 .. 10 {
		_ = s.handle(undo_line) or { panic('yanit yok') }
		_ = s.handle(redo_line) or { panic('yanit yok') }
	}
	before := memory.heap_live_count()
	for _ in 0 .. 1000 {
		_ = s.handle(undo_line) or { panic('yanit yok') }
		_ = s.handle(redo_line) or { panic('yanit yok') }
	}
	growth := memory.heap_live_count() - before
	assert growth <= 16, 'editor grubu geri al/yinele canli tahsis artisi: ${growth}'
}
