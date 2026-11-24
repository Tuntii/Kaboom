module editor

import cmd
import ecs
import os
import protocol
import sim
import ui

// Ajan ile editör eşzamanlılığı (M4c Görev 10): aynı anda iki kaynak aynı dünyayı değiştirir.
// Gerçek Server + Context, sentetik kareler; ajan istekleri srv.handle (kaynak agent), editör istekleri
// kendi yollarıyla (handle_from, .editor) gider. GL yok.

fn cc_server() protocol.Server {
	return protocol.Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

fn cc_frame(mut c ui.Context, mut e Editor, mut srv protocol.Server, inp ui.Input) EditorFrame {
	c.begin(inp, 1440, 900, 1.0)
	fr := e.frame(mut c, mut srv)
	c.end()
	return fr
}

// Transform + Sprite'lı varlık; kimlik yanıttan okunur.
fn cc_spawn(mut srv protocol.Server, x f32, y f32, size f32) ecs.EntityID {
	line := '{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":${x},"y":${y}},"Sprite":{"size":${size}}}}}'
	resp := srv.handle(line) or { panic('yanit yok') }
	return protocol.response_entity(resp) or { panic('kimlik yok: ${resp}') }
}

// Ajan isteği (kaynak agent): tek alan yazımı; yanıt başarılı olmalı.
fn cc_agent_set(mut srv protocol.Server, id ecs.EntityID, comp string, field string, v f32) {
	mut r := ReqBuf{}
	r.begin('component.set')
	r.param_entity('entity', id)
	r.param_str('component', comp)
	r.param_str('field', field)
	r.param_f32('value', v)
	resp := srv.handle(r.end()) or { panic('yanit yok') }
	assert protocol.response_ok(resp), 'ajan component.set: ${resp}'
}

fn cc_field(srv &protocol.Server, id ecs.EntityID, comp u16, field string) f32 {
	cs := srv.registry().component(comp) or { panic('bileşen yok') }
	fi := cs.field_index(field) or { panic('alan yok: ${field}') }
	return read_f32(srv.world(), id, comp, fi) or { panic('alan okunamadı') }
}

// Boşta iki kare: sahne dikdörtgeni bir önceki karenin düzeninden okunur.
fn cc_warm(mut c ui.Context, mut e Editor, mut srv protocol.Server) ui.Rect {
	cc_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fr := cc_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	return fr.scene
}

// Üzerine gel, bas, bırak (üç kare).
fn cc_click_at(mut c ui.Context, mut e Editor, mut srv protocol.Server, x f32, y f32) {
	cc_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: x, mouse_y: y })
	mut down := ui.Input{ mouse_x: x, mouse_y: y }
	down.down[0] = true
	down.pressed[0] = true
	cc_frame(mut c, mut e, mut srv, down)
	mut up := ui.Input{ mouse_x: x, mouse_y: y }
	up.released[0] = true
	cc_frame(mut c, mut e, mut srv, up)
}

// Düğme (etiketiyle) tıklaması: konum bir önceki karenin düzeninden okunur.
fn cc_click_label(mut c ui.Context, mut e Editor, mut srv protocol.Server, label string) {
	r := c.last_rect(label) or { panic('düğme yok: ${label}') }
	cc_click_at(mut c, mut e, mut srv, r.x + r.w / 2, r.y + r.h / 2)
}

// Sprite'a tıklayıp seçer (dünya (0,0) kamera merkezinde).
fn cc_select_at_origin(mut c ui.Context, mut e Editor, mut srv protocol.Server, r ui.Rect) {
	sx, sy := e.cam.world_to_screen(r, 0, 0)
	cc_click_at(mut c, mut e, mut srv, sx, sy)
}

// Gizmo x kolunda basılı sürükleme: eşiği aşar (grup açılır), ilk taşıma karesi.
fn cc_gizmo_drag_start(mut c ui.Context, mut e Editor, mut srv protocol.Server, x f32, y f32) {
	cc_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: x, mouse_y: y })
	mut down := ui.Input{ mouse_x: x, mouse_y: y }
	down.down[0] = true
	down.pressed[0] = true
	cc_frame(mut c, mut e, mut srv, down)
	mut drag := ui.Input{ mouse_x: x + 30, mouse_y: y }
	drag.down[0] = true
	cc_frame(mut c, mut e, mut srv, drag)
}

// Basılı fare üzerinde Esc (sürükleme iptali) ve bırakma.
fn cc_gizmo_cancel(mut c ui.Context, mut e Editor, mut srv protocol.Server, x f32, y f32) {
	mut esc := ui.Input{ mouse_x: x + 30, mouse_y: y }
	esc.down[0] = true
	esc.keys[0] = .escape
	esc.key_count = 1
	cc_frame(mut c, mut e, mut srv, esc)
	mut up := ui.Input{ mouse_x: x + 30, mouse_y: y }
	up.released[0] = true
	cc_frame(mut c, mut e, mut srv, up)
}

fn cc_undo_count(srv &protocol.Server) int {
	u, _ := srv.history_lens()
	return u
}

// Alan sürüklenirken ajan başka bir alanı değiştirir; iptal yalnız editörün grubunu geri alır (D1).
fn test_agent_change_to_other_field_survives_drag_cancel() {
	mut srv := cc_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := cc_spawn(mut srv, 0, 0, 4)
	r := cc_warm(mut c, mut e, mut srv)
	cc_select_at_origin(mut c, mut e, mut srv, r)
	has, sel := e.sv.selected()
	assert has && sel == id, 'varlık seçilmeli'
	ox, oy := e.cam.world_to_screen(r, 0, 0)
	undo0 := cc_undo_count(&srv)
	cc_gizmo_drag_start(mut c, mut e, mut srv, ox + 40, oy)
	assert e.sv.mode == .move, 'sürükleme grubu açık olmalı'
	assert cc_field(&srv, id, ecs.transform_id, 'x') > 0, 'editör x alanını sürüklüyor'
	// Ajan sürükleme sırasında başka alanı (Sprite.size) değiştirir.
	cc_agent_set(mut srv, id, 'Sprite', 'size', 9)
	cc_gizmo_cancel(mut c, mut e, mut srv, ox + 40, oy)
	// Editörün sürüklemesi iptal edildi: x başlangıca döndü; ajanın Sprite.size değişikliği kaldı.
	assert cc_field(&srv, id, ecs.transform_id, 'x') == 0, 'iptal x başlangıcına döner'
	assert cc_field(&srv, id, ecs.sprite_id, 'size') == 9, 'ajan değişikliği korunmalı'
	// Yalnız ajan isteği geri alma adımı olarak kaldı.
	assert cc_undo_count(&srv) == undo0 + 1, 'geri alma: ${cc_undo_count(&srv)} ${undo0}'
	assert !e.ins.grouping && e.sv.mode == .idle
}

// Ajan seçili varlığı siler: editör sonraki karede seçimi temizler ve inspektör "Seçim yok" gösterir.
fn test_agent_despawn_clears_selection_next_frame() {
	mut srv := cc_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := cc_spawn(mut srv, 0, 0, 4)
	r := cc_warm(mut c, mut e, mut srv)
	cc_select_at_origin(mut c, mut e, mut srv, r)
	has, _ := e.sv.selected()
	assert has, 'seçim yapılmalı'
	assert !e.inspector_empty(), 'seçim varken inspektör boş olmamalı'
	resp := srv.handle('{"jsonrpc":"2.0","id":2,"method":"entity.despawn","params":{"entity":${u64(id)}}}') or {
		panic('yanit yok')
	}
	assert protocol.response_ok(resp), resp
	cc_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	still, _ := e.sv.selected()
	assert !still, 'silinen varlığın seçimi düşmeli'
	assert e.inspector_empty(), 'inspektör "Seçim yok" göstermeli'
}

// Ajan düzenlenen alanı değiştirir: yazılı metin korunur (sonraki tuşlarla birlikte onaylanır).
fn test_agent_change_keeps_user_typed_text() {
	mut srv := cc_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := cc_spawn(mut srv, 1, 2, 4)
	r := cc_warm(mut c, mut e, mut srv)
	cc_select_at_origin(mut c, mut e, mut srv, r)
	cc_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fr := e.inspector_rect(&c, hit_field, ecs.transform_id, cc_x_index(&srv)) or { panic('x alanı yok') }
	x := fr.x + fr.w / 2
	y := fr.y + fr.h / 2
	cc_click_at(mut c, mut e, mut srv, x, y)
	cc_frame(mut c, mut e, mut srv, cc_text_input(x, y, '2.5'))
	cc_agent_set(mut srv, id, 'Transform', 'x', 7)
	cc_frame(mut c, mut e, mut srv, cc_text_input(x, y, '5'))
	cc_frame(mut c, mut e, mut srv, cc_enter_input(x, y))
	assert cc_field(&srv, id, ecs.transform_id, 'x') == 2.55, 'kullanıcı metni ajan değerinin üstüne yazılmalı'
}

// Ajan düzenlenen alanı değiştirir ve kullanıcı Esc'e basar: yeni dünya değeri görünür, yazım gönderilmez.
fn test_agent_change_then_escape_shows_new_value() {
	mut srv := cc_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	id := cc_spawn(mut srv, 1, 2, 4)
	r := cc_warm(mut c, mut e, mut srv)
	cc_select_at_origin(mut c, mut e, mut srv, r)
	cc_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fr := e.inspector_rect(&c, hit_field, ecs.transform_id, cc_x_index(&srv)) or { panic('x alanı yok') }
	x := fr.x + fr.w / 2
	y := fr.y + fr.h / 2
	cc_click_at(mut c, mut e, mut srv, x, y)
	cc_frame(mut c, mut e, mut srv, cc_text_input(x, y, '2.5'))
	undo0 := cc_undo_count(&srv)
	cc_agent_set(mut srv, id, 'Transform', 'x', 7)
	mut esc := ui.Input{ mouse_x: x, mouse_y: y }
	esc.keys[0] = .escape
	esc.key_count = 1
	cc_frame(mut c, mut e, mut srv, esc)
	cc_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert !c.keyboard_captured(), 'Esc yazma kipini kapatır'
	assert e.inspector_shown(ecs.transform_id, cc_x_index(&srv)) or { panic('gösterilen yok') } == 7
	assert cc_field(&srv, id, ecs.transform_id, 'x') == 7
	// Esc yazım göndermez: yalnız ajanın tek geri alma adımı var.
	assert cc_undo_count(&srv) == undo0 + 1, 'Esc geri alma adımı eklememeli'
}

fn cc_x_index(srv &protocol.Server) u16 {
	cs := srv.registry().component(ecs.transform_id) or { panic('Transform yok') }
	return cs.field_index('x') or { panic('x yok') }
}

fn cc_text_input(x f32, y f32, s string) ui.Input {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	for i, ch in s {
		inp.chars[i] = u32(ch)
	}
	inp.char_count = s.len
	return inp
}

fn cc_enter_input(x f32, y f32) ui.Input {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	inp.keys[0] = .enter
	inp.key_count = 1
	return inp
}

// Kayıt açıkken editör eylemleri "editor", ajan eylemleri "agent" kaynağıyla yazılır; yeniden oynatma canlı hash'i verir.
fn test_recording_tags_sources_and_replays_to_live_hash() {
	mut srv := cc_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	cc_warm(mut c, mut e, mut srv)
	path := os.join_path(os.temp_dir(), 'vcore_m4c10_${os.getpid()}.vrec').replace('\\', '/')
	defer {
		os.rm(path) or {}
	}
	started := srv.handle('{"jsonrpc":"2.0","id":1,"method":"record.start"}') or { panic('yanit yok') }
	assert protocol.response_ok(started), started
	// Editör eylemi: "Ekle" düğmesi (entity.spawn, kaynak editor).
	cc_click_label(mut c, mut e, mut srv, 'Ekle')
	id := e.sv.sel or { panic('editör yeni varlığı seçmeli') }
	// Ajan eylemi: aynı varlığın alanı (kaynak agent).
	cc_agent_set(mut srv, id, 'Transform', 'x', 3)
	stopped := srv.handle('{"jsonrpc":"2.0","id":2,"method":"record.stop","params":{"path":"${path}"}}') or {
		panic('yanit yok')
	}
	assert protocol.response_ok(stopped), stopped
	rec := cmd.load_recording(path) or { panic('kayıt okunamadı: ${err}') }
	mut editor_n := 0
	mut agent_n := 0
	for entry in rec.entries {
		match entry.cmd.source {
			.editor { editor_n++ }
			.agent { agent_n++ }
			else {}
		}
	}
	assert editor_n >= 1, 'editör eylemi editor kaynağıyla kaydedilmeli'
	assert agent_n >= 1, 'ajan eylemi agent kaynağıyla kaydedilmeli'
	res := sim.replay(rec, srv.registry()) or { panic('replay: ${err}') }
	assert res.hash == sim.state_hash(srv.world(), srv.tick()), 'replay hash canlıya eşit olmalı'
}

// Tek varlıklı sahne dosyası (x=5, y=5): ajan yüklemesi testleri için. Yazıcı süreci ayrı bir Server'dır.
fn cc_scene_file(tag string) string {
	dir := os.temp_dir().replace('\\', '/')
	path := '${dir}/vcore_m4c_fix_${tag}_${os.getpid()}.vscene'
	mut writer := cc_server()
	writer.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":5,"y":5},"Sprite":{"size":4}}}}') or {
		panic('yanit yok')
	}
	writer.handle('{"jsonrpc":"2.0","id":2,"method":"scene.save","params":{"path":"${path}"}}') or { panic('yanit yok') }
	writer.close()
	return path
}

fn cc_agent_load(mut srv protocol.Server, path string) {
	resp := srv.handle('{"jsonrpc":"2.0","id":3,"method":"scene.load","params":{"path":"${path}"}}') or {
		panic('yanit yok')
	}
	assert protocol.response_ok(resp), resp
}

fn cc_agent_reset(mut srv protocol.Server) {
	resp := srv.handle('{"jsonrpc":"2.0","id":4,"method":"sim.reset"}') or { panic('yanit yok') }
	assert protocol.response_ok(resp), resp
}

// Yeni dunyanin ilk varligi (sprite sirasinda ilk satir).
fn cc_first_entity(srv &protocol.Server) ecs.EntityID {
	sp := srv.world().store(ecs.sprite_id)
	assert sp.len() > 0, 'yeni dunyada sprite olmali'
	id := srv.world().entities().handle_at(sp.index_at(0)) or { panic('kimlik yok') }
	return id
}

// Surukleme ortasinda ajan yuklemesi/sifirlamasi: editor secimi ve grubu birakir; kalan hareket ve Esc yeni dunyaya yazmaz.
fn test_agent_load_during_gizmo_drag_drops_drag() {
	path := cc_scene_file('gizmo')
	defer {
		os.rm(path) or {}
	}
	mut srv := cc_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	_ = cc_spawn(mut srv, 0, 0, 4)
	r := cc_warm(mut c, mut e, mut srv)
	cc_select_at_origin(mut c, mut e, mut srv, r)
	ox, oy := e.cam.world_to_screen(r, 0, 0)
	cc_gizmo_drag_start(mut c, mut e, mut srv, ox + 40, oy)
	assert e.sv.mode == .move, 'surukleme grubu acik olmali'
	cc_agent_load(mut srv, path)
	// Yukleme karesi: secim ve grup duser; geri alma gecmisi yeni dunyaninkidir (bos).
	cc_frame(mut c, mut e, mut srv, cc_held(ox + 60, oy))
	has, _ := e.sv.selected()
	assert !has, 'yukleme sonrasi secim dusmeli'
	assert e.sv.mode == .idle && !e.ins.grouping, 'surukleme durmali'
	id := cc_first_entity(&srv)
	x0 := cc_field(&srv, id, ecs.transform_id, 'x')
	undo0 := cc_undo_count(&srv)
	// Basili fare yeni konumlara gider, sonra Esc ve birakma: yeni dunyaya hicbir yazim gitmez.
	cc_frame(mut c, mut e, mut srv, cc_held(ox + 90, oy))
	cc_gizmo_cancel(mut c, mut e, mut srv, ox + 90, oy)
	assert cc_field(&srv, id, ecs.transform_id, 'x') == x0, 'yeni dunya degismemeli'
	assert cc_undo_count(&srv) == undo0, 'ek geri alma adimi olusmamali: ${cc_undo_count(&srv)} ${undo0}'
	assert !e.note_text().contains('geri alma'), 'sahte geri alma bildirimi: ${e.note_text()}'
}

// sim.reset secili varlikta: secim duser, geri alma adimi eklenmez, yeni dunyaya yazilmaz.
fn test_agent_reset_with_selection_clears_selection() {
	mut srv := cc_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	_ = cc_spawn(mut srv, 0, 0, 4)
	r := cc_warm(mut c, mut e, mut srv)
	cc_select_at_origin(mut c, mut e, mut srv, r)
	has0, _ := e.sv.selected()
	assert has0, 'secim yapilmali'
	ox, oy := e.cam.world_to_screen(r, 0, 0)
	cc_gizmo_drag_start(mut c, mut e, mut srv, ox + 40, oy)
	cc_agent_reset(mut srv)
	// Ajan sıfırlamadan sonra yeni varlık kurar: kimlik eskisiyle aynı olabilir (seçim yanlışlıkla canlı görünür).
	_ = cc_spawn(mut srv, 7, 7, 4)
	cc_frame(mut c, mut e, mut srv, cc_held(ox + 90, oy))
	has, _ := e.sv.selected()
	assert !has, 'sifirlama sonrasi secim dusmeli'
	assert e.sv.mode == .idle && !e.ins.grouping
	assert cc_undo_count(&srv) == 1, 'sifirlamada yalniz ajanin spawn adimi olmali: ${cc_undo_count(&srv)}'
	assert srv.world().alive_count() == 1, 'yeni dunya yalniz ajanin varligini icermeli'
}

// Basili fare (sol tus) konumu; basis ani degil, suruklemenin ara karesi.
fn cc_held(x f32, y f32) ui.Input {
	mut inp := ui.Input{ mouse_x: x, mouse_y: y }
	inp.down[0] = true
	return inp
}
