module protocol

import os
import sim
import cmd
import ecs

// Bu dosya kendi yardımcılarını taşır: her _test.v ayrı derlenir (server_test.v'deki yardımcılar görünmez).
fn hist_server() Server {
	return Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

fn hcall(mut s Server, line string) Val {
	out := s.handle(line) or { panic('yanit yok: ${line}') }
	return parse(out) or { panic('yanit JSON degil: ${out}') }
}

fn hpick(v Val, key string) Val {
	return v.get(key) or { null_val() }
}

fn hresult(v Val) Val {
	return hpick(v, 'result')
}

fn herror(v Val) int {
	e := v.get('error') or { return -1 }
	return int(hpick(e, 'code').f64())
}

fn hstr(v Val) string {
	return v.str().clone()
}

fn hitems(v Val) []Val {
	mut out := []Val{}
	mut c := v.first()
	for !c.is_nil() {
		out << c
		c = c.next()
	}
	return out
}

// Rastgele test için büyük dünya: 256 varlık, 1000 komut.
fn new_history_server(capacity u32) Server {
	return Server.new(sim.Config{ capacity: capacity, queue_capacity: 64, record_capacity: 4096 }) or {
		panic(err)
	}
}

fn rq(id int, body string) string {
	return '{"jsonrpc":"2.0","id":${id},${body}}'
}

// Transform.x değeri; varlık yoksa hata yanıtı olduğundan 0 döner.
// Varlık yoksa (hata yanıtı) test düşer: 0 varsayılanı eksik varlığı gizlemesin.
fn tr_x(mut s Server, e u64) f64 {
	resp := hcall(mut s, rq(1, '"method":"entity.get","params":{"entity":${e}}'))
	assert herror(resp) == -1, 'entity ${e} is not alive'
	return hpick(hpick(hpick(hresult(resp), 'components'), 'Transform'), 'x').f64()
}

fn live_count(mut s Server) int {
	r := hresult(hcall(mut s, rq(1, '"method":"query.entities","params":{"with":["Transform"]}')))
	return int(hpick(r, 'count').f64())
}

fn spawn_at(mut s Server, x f64) u64 {
	r := hresult(hcall(mut s, rq(1, '"method":"entity.spawn","params":{"components":{"Transform":{"x":${x}}}}')))
	return u64(hpick(r, 'entity').f64())
}

// Editör kaynaklı istekler handle_from ile gider; diğerleri handle ile (agent).
fn set_x(mut s Server, e u64, x f64, src cmd.Source) {
	line := rq(1, '"method":"component.set","params":{"entity":${e},"component":"Transform","field":"x","value":${x}}')
	if src == .editor {
		_ = s.handle_from(line, .editor)
		return
	}
	_ = hcall(mut s, line)
}

fn history_op(mut s Server, method string) Val {
	return hresult(hcall(mut s, rq(1, '"method":"${method}"')))
}

fn test_undo_redo_set() {
	mut s := hist_server()
	defer {
		s.close()
	}
	e := spawn_at(mut s, 1)
	set_x(mut s, e, 5, .agent)
	set_x(mut s, e, 7, .agent)
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert tr_x(mut s, e) == 5
	assert hpick(history_op(mut s, 'history.redo'), 'applied').as_bool()
	assert tr_x(mut s, e) == 7
}

fn test_undo_spawn_and_despawn_remaps() {
	mut s := hist_server()
	defer {
		s.close()
	}
	old := spawn_at(mut s, 3)
	_ = hcall(mut s, rq(2, '"method":"component.add","params":{"entity":${old},"component":"Sprite","values":{"size":2}}'))
	_ = hcall(mut s, rq(3, '"method":"entity.despawn","params":{"entity":${old}}'))
	assert live_count(mut s) == 0
	u1 := history_op(mut s, 'history.undo')
	assert hpick(u1, 'applied').as_bool()
	remap := hitems(hpick(u1, 'remap'))
	assert remap.len == 1
	new_id := u64(hpick(remap[0], 'new').f64())
	assert u64(hpick(remap[0], 'old').f64()) == old
	assert new_id != old
	assert tr_x(mut s, new_id) == 3
	assert s.engine.world.has(ecs.EntityID(new_id), ecs.sprite_id)
	assert live_count(mut s) == 1
	// Grup sırası: spawn, add Sprite, despawn (ilk geri alma yukarıda). Sprite ekleme, sonra spawn geri alınır.
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert !s.engine.world.has(ecs.EntityID(new_id), ecs.sprite_id)
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert live_count(mut s) == 0
	assert !hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert hpick(history_op(mut s, 'history.redo'), 'applied').as_bool()
	assert live_count(mut s) == 1
	assert hpick(history_op(mut s, 'history.redo'), 'applied').as_bool()
	assert hpick(history_op(mut s, 'history.redo'), 'applied').as_bool()
	assert live_count(mut s) == 0
	assert hpick(history_op(mut s, 'history.redo'), 'applied').as_bool() == false
	assert live_count(mut s) == 0
}

fn test_undo_interleaved_sources() {
	mut s := hist_server()
	defer {
		s.close()
	}
	e := spawn_at(mut s, 0)
	set_x(mut s, e, 1, .agent)
	set_x(mut s, e, 2, .editor)
	set_x(mut s, e, 3, .agent)
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert tr_x(mut s, e) == 2
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert tr_x(mut s, e) == 1
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert tr_x(mut s, e) == 0
	assert hpick(history_op(mut s, 'history.redo'), 'applied').as_bool()
	assert tr_x(mut s, e) == 1
}

fn test_undo_after_script_despawn_reports_failure() {
	mut s := hist_server()
	defer {
		s.close()
	}
	e := spawn_at(mut s, 0)
	// Script kaynaklı yıkım geçmişe girmez; spawn'ın ters işlemi artık ölü bir varlığa işaret eder.
	assert s.engine.push(cmd.Command{ kind: .despawn, source: .script, entity: ecs.EntityID(e) })
	_ = s.engine.flush()
	u := history_op(mut s, 'history.undo')
	assert hpick(u, 'applied').as_bool()
	assert int(hpick(u, 'failed').f64()) >= 1
	assert int(hpick(u, 'commands').f64()) == 0
}

fn test_editor_group_spans_requests() {
	mut s := hist_server()
	defer {
		s.close()
	}
	e := spawn_at(mut s, 0)
	s.history_begin_group()
	for i in 1 .. 11 {
		set_x(mut s, e, f64(i), .editor)
	}
	s.history_end_group()
	assert s.engine.history.undo_len() == 2
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert tr_x(mut s, e) == 0
	assert s.engine.history.undo_len() == 1
}

fn test_cancel_group_restores_and_leaves_no_trace() {
	mut s := hist_server()
	defer {
		s.close()
	}
	e := spawn_at(mut s, 0)
	s.history_begin_group()
	set_x(mut s, e, 1, .editor)
	set_x(mut s, e, 2, .editor)
	set_x(mut s, e, 3, .editor)
	s.history_cancel_group() or { panic(err) }
	assert tr_x(mut s, e) == 0
	assert s.engine.history.undo_len() == 1
	assert s.engine.history.redo_len() == 0
	// İptal edilen grup hiçbir yığında yok; geri al önceki gruba (spawn) gider.
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert live_count(mut s) == 0
}

fn test_new_command_clears_redo() {
	mut s := hist_server()
	defer {
		s.close()
	}
	e := spawn_at(mut s, 1)
	set_x(mut s, e, 5, .agent)
	set_x(mut s, e, 7, .agent)
	_ = history_op(mut s, 'history.undo')
	assert s.engine.history.redo_len() == 1
	set_x(mut s, e, 9, .agent)
	assert s.engine.history.redo_len() == 0
	assert !hpick(history_op(mut s, 'history.redo'), 'applied').as_bool()
}

fn test_empty_stack_is_not_an_error() {
	mut s := hist_server()
	defer {
		s.close()
	}
	r := history_op(mut s, 'history.undo')
	assert !hpick(r, 'applied').as_bool()
	assert hpick(r, 'commands').f64() == 0
	assert hpick(r, 'failed').f64() == 0
}

fn test_undo_redo_recorded_and_replay_matches() {
	mut s := hist_server()
	defer {
		s.close()
	}
	path := os.join_path(os.temp_dir(), 'vcore_hist_${os.getpid()}.vrec').replace('\\', '/')
	defer {
		os.rm(path) or {}
	}
	_ = hcall(mut s, rq(1, '"method":"record.start"'))
	e := spawn_at(mut s, 1)
	set_x(mut s, e, 5, .agent)
	_ = history_op(mut s, 'history.undo')
	_ = history_op(mut s, 'history.redo')
	_ = history_op(mut s, 'history.undo')
	stop := hresult(hcall(mut s, rq(2, '"method":"record.stop","params":{"path":"${path}"}')))
	live := hstr(hpick(hresult(hcall(mut s, rq(3, '"method":"sim.state_hash"'))), 'hash'))
	assert hstr(hpick(stop, 'hash')) == live
	replay := hresult(hcall(mut s, rq(4, '"method":"replay.run","params":{"path":"${path}"}')))
	assert hstr(hpick(replay, 'hash')) == live
}

// Kimlikten bağımsız içerik: canlı varlıkların bileşen id'si ve alan bitlerinin sıralı listesi.
fn content_snapshot(s &Server) string {
	w := &s.engine.world
	alloc := w.entities()
	mut rows := []string{}
	for i in 0 .. alloc.high_water() {
		e := alloc.handle_at(i) or { continue }
		if !w.is_alive(e) {
			continue
		}
		mut row := ''
		for comp in u16(0) .. w.store_count() {
			if !w.has(e, comp) {
				continue
			}
			row += 'c${comp}['
			for f in 0 .. w.store(comp).field_count() {
				bits := w.get_field(e, comp, f) or { 0 }
				row += '${bits},'
			}
			row += ']'
		}
		rows << row
	}
	rows.sort()
	return rows.join('|')
}

// Deterministik sözde rastgele sayı (xorshift64); test tohumu sabittir.
struct Rng {
mut:
	state u64
}

fn (mut r Rng) next(n int) int {
	r.state ^= r.state << 13
	r.state ^= r.state >> 7
	r.state ^= r.state << 17
	return int(r.state % u64(n))
}

fn test_random_1000_undo_redo_content() {
	mut s := new_history_server(256)
	defer {
		s.close()
	}
	mut rng := Rng{
		state: 0x9E3779B97F4A7C15
	}
	for k in 0 .. 1000 {
		w := &s.engine.world
		alloc := w.entities()
		mut live := []ecs.EntityID{}
		for i in 0 .. alloc.high_water() {
			e := alloc.handle_at(i) or { continue }
			if w.is_alive(e) {
				live << e
			}
		}
		// Geçerli komutlar üretilir: her biri tek grup olarak geçmişe girer.
		op := if live.len == 0 || (live.len < 150 && rng.next(5) == 0) { 0 } else { rng.next(4) + 1 }
		mut line := ''
		if op == 0 {
			x := rng.next(201) - 100
			line = rq(k + 10, '"method":"entity.spawn","params":{"components":{"Transform":{"x":${x}}}}')
		} else {
			e := u64(live[rng.next(live.len)])
			match op {
				1 {
					line = rq(k + 10, '"method":"entity.despawn","params":{"entity":${e}}')
				}
				2 {
					if w.has(ecs.EntityID(e), ecs.sprite_id) {
						line = rq(k + 10, '"method":"component.remove","params":{"entity":${e},"component":"Sprite"}')
					} else {
						line = rq(k + 10, '"method":"component.add","params":{"entity":${e},"component":"Sprite","values":{"size":${rng.next(100) + 1}}}')
					}
				}
				else {
					line = rq(k + 10, '"method":"component.set","params":{"entity":${e},"component":"Transform","field":"x","value":${rng.next(201) - 100}}')
				}
			}
		}
		r := hcall(mut s, line)
		assert herror(r) == -1
	}
	snapshot := content_snapshot(&s)
	assert snapshot != ''
	mut undone := 0
	for hpick(history_op(mut s, 'history.undo'), 'applied').as_bool() {
		undone++
	}
	assert undone == 1000
	assert content_snapshot(&s) == ''
	mut redone := 0
	for hpick(history_op(mut s, 'history.redo'), 'applied').as_bool() {
		redone++
	}
	assert redone == 1000
	assert content_snapshot(&s) == snapshot
}

fn test_stale_handle_mutators_after_slot_reuse() {
	mut s := hist_server()
	defer {
		s.close()
	}
	old := spawn_at(mut s, 0)
	_ = hcall(mut s, rq(2, '"method":"entity.despawn","params":{"entity":${old}}'))
	fresh := spawn_at(mut s, 0)
	assert ecs.EntityID(fresh).index() == ecs.EntityID(old).index()
	assert fresh != old
	assert herror(hcall(mut s, rq(3, '"method":"component.add","params":{"entity":${old},"component":"Body"}'))) == 1001
	assert herror(hcall(mut s, rq(4, '"method":"component.set","params":{"entity":${old},"component":"Transform","field":"x","value":1}'))) == 1001
	assert herror(hcall(mut s, rq(5, '"method":"component.remove","params":{"entity":${old},"component":"Transform"}'))) == 1001
	assert herror(hcall(mut s, rq(6, '"method":"entity.despawn","params":{"entity":${old}}'))) == 1001
}

// Açık editör grubunda geri alma, hazırlama alanı boşken bile reddedilir; grup kapanınca çalışır.
fn test_undo_refused_while_editor_group_open() {
	mut s := hist_server()
	defer {
		s.close()
	}
	e := spawn_at(mut s, 0)
	set_x(mut s, e, 1, .agent)
	s.history_begin_group()
	assert !hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert s.engine.history.undo_len() == 2
	assert s.engine.history.redo_len() == 0
	assert tr_x(mut s, e) == 1
	set_x(mut s, e, 2, .editor)
	assert !hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert s.engine.history.undo_len() == 2
	s.history_end_group()
	// Grup kapandı: önce editörün yazımı geri alınır (x = 1), sonra agent yazımı.
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert tr_x(mut s, e) == 1
}

// Hazırlama alanı taşmış grupta iptal hiçbir şey uygulamaz, hata döner ve grup açık kalır.
fn test_cancel_refuses_overflowed_group() {
	mut s := Server.new(sim.Config{
		capacity:         64
		queue_capacity:   64
		record_capacity:  1024
		history_capacity: 4
		history_groups:   8
	}) or { panic(err) }
	defer {
		s.close()
	}
	e := spawn_at(mut s, 0)
	s.history_begin_group()
	for i in 1 .. 7 {
		set_x(mut s, e, f64(i), .editor)
	}
	assert s.engine.history.stage_overflowed()
	mut refused := false
	s.history_cancel_group() or { refused = true }
	assert refused
	// Kısmi geri alma yok: değer son yazılan değerde kalır.
	assert tr_x(mut s, e) == 6
	s.history_end_group()
	assert s.engine.history.dropped_groups() >= 1
}

// Geri alma komutları, isteği yapanın kaynağını taşır: kayıtta editör olarak görünmeli.
fn test_undo_records_requester_source() {
	mut s := hist_server()
	defer {
		s.close()
	}
	path := os.join_path(os.temp_dir(), 'vcore_hist_src_${os.getpid()}.vrec').replace('\\', '/')
	defer {
		os.rm(path) or {}
	}
	_ = hcall(mut s, rq(1, '"method":"record.start"'))
	e := spawn_at(mut s, 1)
	// Geri alınan yazım agent kaynaklı; geri almayı editör istiyor. Ters yazım editör olmalı.
	set_x(mut s, e, 5, .agent)
	set_x(mut s, e, 7, .agent)
	_ = s.handle_from(rq(2, '"method":"history.undo"'), .editor)
	_ = hcall(mut s, rq(3, '"method":"record.stop","params":{"path":"${path}"}'))
	rec := cmd.load_recording(path) or { panic(err) }
	n := rec.entries.len
	assert rec.entries[n - 1].cmd.source == .editor
	assert rec.entries[n - 1].cmd.kind == .set_field
	assert rec.entries[n - 2].cmd.source == .agent
}

// İç içe editör grupları: iç end sayacı sıfırlamaz; yalnız son end geri almayı yeniden açar.
fn test_undo_refused_under_nested_editor_groups() {
	mut s := hist_server()
	defer {
		s.close()
	}
	e := spawn_at(mut s, 0)
	set_x(mut s, e, 1, .agent)
	s.history_begin_group()
	s.history_begin_group()
	s.history_end_group()
	assert !hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert s.engine.history.undo_len() == 2
	assert tr_x(mut s, e) == 1
	s.history_end_group()
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert tr_x(mut s, e) == 0
}

// sim.reset açık grubu da bitirir: sonrasında agent geri almaları reddedilmez.
fn test_sim_reset_clears_open_editor_group() {
	mut s := hist_server()
	defer {
		s.close()
	}
	s.history_begin_group()
	_ = hcall(mut s, rq(1, '"method":"sim.reset"'))
	f := spawn_at(mut s, 3)
	set_x(mut s, f, 9, .agent)
	// Yazım sonrası geri alma uygulanmalı (applied true): yığın boş olduğu için değil, koruma yüzünden reddedilmiyor.
	assert hpick(history_op(mut s, 'history.undo'), 'applied').as_bool()
	assert tr_x(mut s, f) == 3
}
