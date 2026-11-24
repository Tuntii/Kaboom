module cmd

import ecs
import math
import memory

// Test ortamı: dünya ve geçmiş aynı bölgeden kurulur; çağıran bölgeyi serbest bırakır.
fn hist_env(cap u32, groups u32) (&u8, ecs.World, History) {
	reg := ecs.core_registry() or { panic('registry basarisiz') }
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, 1 << 20)
	w := ecs.World.new(mut a, &reg, 16) or { panic('World.new none') }
	h := History.new(mut a, &reg, cap, groups) or { panic('History.new none') }
	return region, w, h
}

// flush'un tek komut eşdeğeri: yakala, uygula, kaydet.
fn hist_step(mut h History, mut w ecs.World, c Command) ApplyResult {
	h.capture_before(&w, c)
	r := apply(mut w, c)
	h.commit_capture(r)
	return r
}

fn set_cmd(e ecs.EntityID, field u16, v f32) Command {
	return Command{
		kind:   .set_field
		source: .agent
		comp:   ecs.transform_id
		field:  field
		entity: e
		value:  hist_bits(v)
	}
}

fn test_set_field_inverse_restores_old_value() {
	region, mut w, mut h := hist_env(16, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	assert w.set_field(e, ecs.transform_id, 0, hist_bits(1.0)) == .ok
	assert hist_step(mut h, mut w, set_cmd(e, 0, 7.0)).status == .ok
	assert h.undo_len() == 1
	g := h.pop_undo() or { panic('pop') }
	b := g.block(0)
	assert b.len == 1
	assert b[0].kind == .set_field
	assert b[0].value == hist_bits(1.0)
	for c in b {
		apply(mut w, c)
	}
	assert hist_f32(w.get_field(e, ecs.transform_id, 0) or { panic('get') }) == 1.0
}

fn test_add_inverse_is_remove() {
	region, mut w, mut h := hist_env(16, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	r := hist_step(mut h, mut w, Command{
		kind:   .add_component
		source: .agent
		comp:   ecs.sprite_id
		entity: e
	})
	assert r.status == .ok
	g := h.pop_undo() or { panic('pop') }
	b := g.block(0)
	assert b.len == 1
	assert b[0].kind == .remove_component
	assert b[0].comp == ecs.sprite_id
	assert b[0].entity == e
}

fn test_remove_inverse_restores_fields() {
	region, mut w, mut h := hist_env(16, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.sprite_id) == .ok
	assert w.set_field(e, ecs.sprite_id, 0, hist_bits(2.0)) == .ok
	assert w.set_field(e, ecs.sprite_id, 1, hist_bits(0.25)) == .ok
	r := hist_step(mut h, mut w, Command{
		kind:   .remove_component
		source: .agent
		comp:   ecs.sprite_id
		entity: e
	})
	assert r.status == .ok
	assert !w.has(e, ecs.sprite_id)
	g := h.pop_undo() or { panic('pop') }
	b := g.block(0)
	// add + Sprite'ın 4 alanı için set.
	assert b.len == 5
	for c in b {
		apply(mut w, c)
	}
	assert w.has(e, ecs.sprite_id)
	assert hist_f32(w.get_field(e, ecs.sprite_id, 0) or { panic('get') }) == 2.0
	assert hist_f32(w.get_field(e, ecs.sprite_id, 1) or { panic('get') }) == 0.25
}

fn test_spawn_inverse_is_despawn_of_new_id() {
	region, mut w, mut h := hist_env(16, 8)
	defer {
		memory.release(region)
	}
	r := hist_step(mut h, mut w, Command{
		kind:   .spawn
		source: .agent
	})
	assert r.status == .ok
	g := h.pop_undo() or { panic('pop') }
	b := g.block(0)
	assert b.len == 1
	assert b[0].kind == .despawn
	assert b[0].entity == r.entity
}

// Despawn'ın ters bloğu: spawn (eski id), her bileşen için add ve her alan için eski değerli set.
fn test_despawn_inverse_block_restores_all_components() {
	region, mut w, mut h := hist_env(32, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	assert w.add_component(e, ecs.sprite_id) == .ok
	assert w.set_field(e, ecs.transform_id, 0, hist_bits(3.5)) == .ok
	assert w.set_field(e, ecs.sprite_id, 0, hist_bits(2.0)) == .ok
	r := hist_step(mut h, mut w, Command{
		kind:   .despawn
		source: .agent
		entity: e
	})
	assert r.status == .ok
	g := h.pop_undo() or { panic('pop') }
	b := g.block(0)
	assert b.len == 11
	assert b[0].kind == .spawn
	assert b[0].entity == e
	assert b[1].kind == .add_component
	assert b[1].comp == ecs.transform_id
	assert b[1].entity == e
	assert b[2].kind == .set_field
	assert b[2].field == 0
	assert b[2].value == hist_bits(3.5)
	assert b[6].kind == .add_component
	assert b[6].comp == ecs.sprite_id
	assert b[7].kind == .set_field
	assert b[7].value == hist_bits(2.0)
	for c in b {
		assert c.entity == e || c.kind == .spawn
	}
}

fn test_failed_command_not_captured() {
	region, mut w, mut h := hist_env(16, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	assert w.despawn(e)
	assert h.undo_len() == 0
	r := hist_step(mut h, mut w, set_cmd(e, 0, 1.0))
	assert r.status == .dead_entity
	assert h.undo_len() == 0
}

fn test_script_not_captured() {
	region, mut w, mut h := hist_env(16, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	mut c := set_cmd(e, 0, 1.0)
	c.source = .script
	assert hist_step(mut h, mut w, c).status == .ok
	assert h.undo_len() == 0
}

fn test_groups_and_reverse_block_order() {
	region, mut w, mut h := hist_env(16, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	h.begin_group()
	assert hist_step(mut h, mut w, set_cmd(e, 0, 1.0)).status == .ok
	assert hist_step(mut h, mut w, set_cmd(e, 0, 2.0)).status == .ok
	assert hist_step(mut h, mut w, set_cmd(e, 0, 3.0)).status == .ok
	h.end_group()
	assert h.undo_len() == 1
	g := h.pop_undo() or { panic('pop') }
	assert g.block_count() == 3
	// Blok 0 son komutun ters işlemidir: x 2.0'dan 3.0'a geçti, eski değer 2.0.
	assert g.block(0)[0].value == hist_bits(2.0)
	assert g.block(1)[0].value == hist_bits(1.0)
	assert g.block(2)[0].value == hist_bits(0.0)
}

fn test_new_group_clears_redo() {
	region, mut w, mut h := hist_env(16, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	assert hist_step(mut h, mut w, set_cmd(e, 0, 5.0)).status == .ok
	g := h.pop_undo() or { panic('pop') }
	h.set_mode(.undoing)
	for c in g.block(0) {
		hist_step(mut h, mut w, c)
	}
	h.set_mode(.normal)
	assert h.redo_len() == 1
	assert h.undo_len() == 0
	assert hist_step(mut h, mut w, set_cmd(e, 0, 9.0)).status == .ok
	assert h.redo_len() == 0
	assert h.undo_len() == 1
}

// Halka 8 komut tutar; 12 tek komutlu grupta en eski 4 grup düşer.
fn test_ring_drops_oldest_group() {
	region, mut w, mut h := hist_env(8, 64)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	for i in 1 .. 13 {
		assert hist_step(mut h, mut w, set_cmd(e, 0, f32(i))).status == .ok
	}
	assert h.undo_len() == 8
	assert h.dropped_groups() == 4
	g := h.pop_undo() or { panic('pop') }
	// En yeni grup 12'ye yazdı; eski değer 11.
	assert g.block(0)[0].value == hist_bits(11.0)
}

fn test_group_larger_than_capacity_dropped() {
	region, mut w, mut h := hist_env(8, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	h.begin_group()
	for i in 1 .. 21 {
		hist_step(mut h, mut w, set_cmd(e, 0, f32(i)))
	}
	h.end_group()
	assert h.undo_len() == 0
	assert h.dropped_groups() == 1
	// Taşmadan sonra sıradaki küçük grup normal çalışır.
	assert hist_step(mut h, mut w, set_cmd(e, 0, 99.0)).status == .ok
	assert h.undo_len() == 1
}

// Çok komutlu bloklar halka sonunda sarmaz: pad ile bitişik yerleşir ve dilim doğru içeriği verir.
fn test_block_contents_after_wrap() {
	region, mut w, mut h := hist_env(8, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	assert w.add_component(e, ecs.sprite_id) == .ok
	assert w.set_field(e, ecs.sprite_id, 0, hist_bits(2.0)) == .ok
	// Transform kaldırma: 5 komut (add + 4 set), Sprite kaldırma: 5 komut. İkincisi sarar.
	assert hist_step(mut h, mut w, Command{
		kind:   .remove_component
		source: .agent
		comp:   ecs.transform_id
		entity: e
	}).status == .ok
	assert hist_step(mut h, mut w, Command{
		kind:   .remove_component
		source: .agent
		comp:   ecs.sprite_id
		entity: e
	}).status == .ok
	assert h.undo_len() == 1
	assert h.dropped_groups() == 1
	g := h.pop_undo() or { panic('pop') }
	b := g.block(0)
	assert b.len == 5
	assert b[0].kind == .add_component
	assert b[0].comp == ecs.sprite_id
	assert b[1].kind == .set_field
	assert b[1].value == hist_bits(2.0)
}

fn test_remap_rewrites_both_stacks() {
	region, mut w, mut h := hist_env(32, 8)
	defer {
		memory.release(region)
	}
	r1 := hist_step(mut h, mut w, Command{ kind: .spawn, source: .agent })
	r2 := hist_step(mut h, mut w, Command{ kind: .spawn, source: .agent })
	// Son spawn'ın ters işlemini geri al: redo'da r2 id'li spawn birikir.
	g := h.pop_undo() or { panic('pop') }
	h.set_mode(.undoing)
	for c in g.block(0) {
		hist_step(mut h, mut w, c)
	}
	h.set_mode(.normal)
	new_id := ecs.make_entity(77, 0)
	h.remap(r2.entity, new_id)
	rg := h.pop_redo() or { panic('redo pop') }
	assert rg.block(0)[0].entity == new_id
	ug := h.pop_undo() or { panic('undo pop') }
	assert ug.block(0)[0].entity == r1.entity
}

fn test_clear_empties_both_stacks() {
	region, mut w, mut h := hist_env(16, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	assert hist_step(mut h, mut w, set_cmd(e, 0, 4.0)).status == .ok
	h.clear()
	assert h.undo_len() == 0
	assert h.redo_len() == 0
}

fn hist_bits(f f32) u64 {
	return u64(math.f32_bits(f))
}

fn hist_f32(b u64) f32 {
	return math.f32_from_bits(u32(b))
}

// Büyük açık grup, önceki tamamlanmış grubu silmemeli: G0 sağ kalır ve geri alınabilir.
fn test_oversized_group_keeps_older_group() {
	region, mut w, mut h := hist_env(8, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	assert hist_step(mut h, mut w, set_cmd(e, 0, 1.0)).status == .ok
	h.begin_group()
	for i in 2 .. 22 {
		hist_step(mut h, mut w, set_cmd(e, 0, f32(i)))
	}
	h.end_group()
	assert h.undo_len() == 1
	assert h.dropped_groups() == 1
	g := h.pop_undo() or { panic('pop') }
	// G0 yalnızca tek set'ti: eski değer 0.0.
	assert g.block_count() == 1
	assert g.block(0)[0].value == hist_bits(0.0)
}

fn test_staged_group_readable_and_abandon() {
	region, mut w, mut h := hist_env(16, 8)
	defer {
		memory.release(region)
	}
	e := w.spawn() or { panic('spawn') }
	assert w.add_component(e, ecs.transform_id) == .ok
	h.begin_group()
	assert hist_step(mut h, mut w, set_cmd(e, 0, 4.0)).status == .ok
	assert hist_step(mut h, mut w, set_cmd(e, 0, 5.0)).status == .ok
	// Açık grup okunabilir: block(0) en son blok (eski değer 4.0), block(1) ilki (eski değer 0.0).
	st := h.staged()
	assert st.block_count() == 2
	assert st.block(0)[0].value == hist_bits(4.0)
	assert st.block(1)[0].value == hist_bits(0.0)
	assert !h.stage_overflowed()
	// Atılan grup hiçbir yığına girmez ve derinlik sıfırlanır.
	h.abandon_group()
	assert h.undo_len() == 0
	assert h.redo_len() == 0
	assert h.staged().block_count() == 0
	h.end_group()
	// Yakalama kapalıyken (off) komutlar geçmişe girmez.
	h.set_mode(.off)
	assert hist_step(mut h, mut w, set_cmd(e, 0, 6.0)).status == .ok
	h.set_mode(.normal)
	assert h.undo_len() == 0
	assert h.staged().block_count() == 0
}
