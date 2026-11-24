module editor

import ecs
import protocol
import ui

// Hiyerarşi paneli (M4c Görev 7): canlı varlıklar index sırasıyla sanal listede; satır "#index" ve sağda bileşen
// rozetleri. Seçim sahne görünümüyle ortak (e.sv.sel). Dünyaya yazım yalnız entity.spawn / entity.despawn ile.
// Satır metinleri kare boyunca yaşayan sabit tamponlarda kurulur (kare başına tahsis yok).

// shortcut: görünür satır tamponu 128 satır (~3300 px görünür yükseklik); daha fazlası çizilmez, upgrade: gerekirse büyütülür.
const hier_max_rows = 128
const hier_label_cap = 16 // '#' ve en fazla 10 basamak
const hier_badge_cap = 2 * ecs.max_components // harf ve boşluk çifti
const spawn_size_div = f32(20) // yeni Sprite boyutu = görünüm yüksekliği / 20
const spawn_r = f32(0.8)
const spawn_b = f32(0.85)

struct Hierarchy {
mut:
	letters   [ecs.max_components]u8 // bileşen kayıt sırasıyla rozet harfleri (init'te bir kez)
	nletters  int
	nrows     int // bu karede çizilen satır sayısı
	ids       [hier_max_rows]ecs.EntityID
	labels    [hier_max_rows][hier_label_cap]u8
	label_len [hier_max_rows]int
	badges    [hier_max_rows][hier_badge_cap]u8
	badge_len [hier_max_rows]int
	first     int // ilk çizilen satır (tampon dahil); liste kaydırmasının sonucu
	shown     bool // son hizalanan seçim var mı
	shown_id  ecs.EntityID
}

fn (mut h Hierarchy) init(reg &ecs.Registry) {
	for id in u16(0) .. reg.count() {
		schema := reg.component(id) or { continue }
		h.letters[h.nletters] = if schema.name.len > 0 { schema.name[0] } else { `?` }
		h.nletters++
	}
}

pub fn (h &Hierarchy) label(j int) string {
	return unsafe { tos(&h.labels[j][0], h.label_len[j]) }
}

pub fn (h &Hierarchy) badge(j int) string {
	return unsafe { tos(&h.badges[j][0], h.badge_len[j]) }
}

fn (mut h Hierarchy) fill_label(row int, idx u32) {
	h.labels[row][0] = `#`
	mut digits := [10]u8{}
	mut k := 0
	mut x := idx
	for {
		digits[k] = u8(48 + x % 10)
		k++
		x /= 10
		if x == 0 {
			break
		}
	}
	mut n := 1
	for k > 0 {
		k--
		h.labels[row][n] = digits[k]
		n++
	}
	h.label_len[row] = n
}

// Varlığın sahip olduğu bileşenlerin harfleri, kayıt sırasıyla, boşlukla ayrılmış.
fn (mut h Hierarchy) fill_badge(row int, w &ecs.World, id ecs.EntityID) {
	mut m := 0
	for k in 0 .. h.nletters {
		if !w.has(id, u16(k)) {
			continue
		}
		if m > 0 {
			h.badges[row][m] = ` `
			m++
		}
		h.badges[row][m] = h.letters[k]
		m++
	}
	h.badge_len[row] = m
}

// Görünen satırların kimlikleri: canlıların index sırasındaki [first, first+n) dilimi. Tek geçiş, tahsissiz.
fn fill_rows(w &ecs.World, first int, n int, mut ids [hier_max_rows]ecs.EntityID) int {
	a := w.entities()
	mut rank := 0
	mut got := 0
	for i in u32(0) .. a.high_water() {
		id := a.handle_at(i) or { continue }
		if rank >= first && got < n {
			ids[got] = id
			got++
		}
		rank++
		if got >= n {
			break
		}
	}
	return got
}

// Canlı varlığın satırı (canlıların index sırasındaki sırası); canlı değilse none.
fn row_of(w &ecs.World, id ecs.EntityID) ?int {
	if !w.is_alive(id) {
		return none
	}
	a := w.entities()
	mut row := 0
	for i in u32(0) .. id.index() {
		_ = a.handle_at(i) or { continue }
		row++
	}
	return row
}

// Rozet için kalan genişlik: önceki karedeki satır kutusu eksi etiket, aralık ve kenar boşlukları.
fn badge_room(c &ui.Context, row string, label_w f32) f32 {
	r := c.prev_rect(c.id(row)) or { return f32(1e9) }
	return r.w - 2 * ui.space_3 - ui.space_2 - label_w
}

// Liste: seçim değiştiyse satır begin'den önce görünür kılınır; sonra yalnız görünen satırlar.
// Delete (klavye yakalanmamışken) seçili varlığı siler.
fn (mut e Editor) hier_list(mut c ui.Context, mut srv protocol.Server) {
	w := srv.world()
	has, sel := e.sv.selected()
	if has != e.hier.shown || (has && sel != e.hier.shown_id) {
		e.hier.shown = has
		e.hier.shown_id = sel
		if has {
			if r := row_of(w, sel) {
				c.reveal_row('hier_list', r, ui.row_h)
			}
		}
	}
	vl := c.virtual_list_begin('hier_list', int(w.alive_count()), ui.row_h, ui.Box{
		dir:    .column
		width:  ui.grow()
		height: ui.grow()
	})
	n := if vl.count < hier_max_rows { vl.count } else { hier_max_rows }
	e.hier.first = vl.first
	e.hier.nrows = fill_rows(w, vl.first, n, mut e.hier.ids)
	for j in 0 .. e.hier.nrows {
		id := e.hier.ids[j]
		e.hier.fill_label(j, id.index())
		e.hier.fill_badge(j, w, id)
		lbl := e.hier.label(j)
		it := c.list_row_begin(lbl, has && sel == id)
		if it.clicked {
			e.sv.sel = id
		}
		c.text(lbl, .body, ui.text_primary)
		c.spacer()
		if e.hier.badge_len[j] > 0 {
			label_w := c.atlas().measure(lbl, .body)
			c.text_trunc(e.hier.badge(j), .caption, ui.text_muted, badge_room(c, lbl, label_w))
		}
		c.list_row_end()
	}
	c.virtual_list_end()
	if c.shortcut(.delete) {
		e.delete_selected(mut srv)
	}
}

// + düğmesi: kameranın merkezinde yeni varlık (Transform + Sprite); yeni varlık seçilir (satırı liste hizalar).
fn (mut e Editor) spawn_at_camera(mut srv protocol.Server) {
	mut r := ReqBuf{}
	r.begin('entity.spawn')
	r.obj_begin('components')
	r.obj_begin('Transform')
	r.param_f32('x', e.cam.cx)
	r.param_f32('y', e.cam.cy)
	r.obj_end()
	r.obj_begin('Sprite')
	r.param_f32('size', e.cam.view_h / spawn_size_div)
	r.param_f32('r', spawn_r)
	r.param_f32('g', spawn_r)
	r.param_f32('b', spawn_b)
	r.obj_end()
	r.obj_end()
	resp := editor_request(mut e, mut srv, r.end()) or { return }
	id := protocol.response_entity(resp) or { return }
	e.sv.sel = id
}

// Seçili varlığı siler. Gizmo sürüklemesi açıksa grup kapanır, sonra silinir: yazım silinen varlığa gitmez.
fn (mut e Editor) delete_selected(mut srv protocol.Server) {
	has, id := e.sv.selected()
	if !has {
		return
	}
	e.leave_drag(mut srv)
	e.sv.mode = .idle
	mut r := ReqBuf{}
	r.begin('entity.despawn')
	r.param_entity('entity', id)
	_ = editor_request(mut e, mut srv, r.end()) or { return }
	e.sv.sel = none
}

// Editör isteği: kurulamayan, yanıtsız ya da hatalı istek durum çubuğuna bildirilir; başarıda yanıt ve bildirim temizliği.
fn editor_request(mut e Editor, mut srv protocol.Server, line string) ?string {
	if line == '' {
		e.set_note('istek kurulamadı: değer sınır dışı')
		return none
	}
	resp := srv.handle_from(line, .editor) or {
		e.set_note('yanıt yok')
		return none
	}
	if !protocol.response_ok(resp) {
		e.set_note(protocol.response_error_message(resp))
		return none
	}
	e.note_len = 0
	return resp
}
