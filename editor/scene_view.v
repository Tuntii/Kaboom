module editor

import ecs
import math
import protocol
import ui

// Sahne görünümü (M4c Görev 6): tıklama ile seçim, taşıma gizmosu, Boşluk/orta tuş pan'i, tekerlek yakınlaştırma.
// Dünyaya yazım yalnız component.set istekleriyle (handle_from, .editor) olur; gizmo sürüklemesi tek geri alma grubudur.

// Gizmo ve seçim ölçüleri (mantıksal px): kol uzunluğu, görünen kalınlık, tutma bandı, orta kare, çerçeve.
const gizmo_len = f32(64)
const gizmo_thick = f32(2)
const gizmo_band = f32(10)
const gizmo_center = f32(10)
const gizmo_tip = f32(8) // eksen ucundaki dolu kare
const outline_w = f32(1)

enum SceneMode {
	idle
	pan
	pending // tutamaç basıldı, sürükleme eşiği henüz aşılmadı
	move // gizmo sürüklemesi: geri alma grubu açık
}

enum Handle {
	center
	arm_x
	arm_y
}

// Transform x/y ve Sprite size alanlarının indisleri; kayıttan bir kez çözülür (render ile aynı alanlar).
struct SceneFields {
	tx u16
	ty u16
	sz u16
}

// Sahne görünümünün durumu: seçim ve sürükleme (basış konumu, başlangıç değeri, pan başlangıç kamerası).
struct SceneState {
mut:
	fields    SceneFields
	fields_ok bool
	sel       ?ecs.EntityID
	mode    SceneMode
	grab    Handle
	btn     int // pan düğmesi: 2 orta, 0 Boşluk + sol
	press_x f32
	press_y f32
	start_x f32
	start_y f32
	cam_cx  f32
	cam_cy  f32
}

fn (s &SceneState) selected() (bool, ecs.EntityID) {
	id := s.sel or { return false, ecs.EntityID(0) }
	return true, id
}

fn resolve_scene_fields(reg &ecs.Registry) !SceneFields {
	t := reg.component(ecs.transform_id) or { return error('Transform bileseni kayitli degil') }
	s := reg.component(ecs.sprite_id) or { return error('Sprite bileseni kayitli degil') }
	return SceneFields{
		tx: t.field_index('x') or { return error('Transform.x yok') }
		ty: t.field_index('y') or { return error('Transform.y yok') }
		sz: s.field_index('size') or { return error('Sprite.size yok') }
	}
}

fn in_rect(r ui.Rect, x f32, y f32) bool {
	return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
}

// Dikdörtgeni kırpma alanına sığdırır; kesişim boşsa sıfır dikdörtgen.
fn clip_rect(r ui.Rect, clip ui.Rect) ui.Rect {
	x0 := if r.x > clip.x { r.x } else { clip.x }
	y0 := if r.y > clip.y { r.y } else { clip.y }
	x1 := if r.x + r.w < clip.x + clip.w { r.x + r.w } else { clip.x + clip.w }
	y1 := if r.y + r.h < clip.y + clip.h { r.y + r.h } else { clip.y + clip.h }
	if x1 <= x0 || y1 <= y0 {
		return ui.Rect{}
	}
	return ui.Rect{
		x: x0
		y: y0
		w: x1 - x0
		h: y1 - y0
	}
}

// Sahne alanına kırpılmış overlay; görünen kısmı yoksa hiçbir şey çizilmez. bg 0 ise yalnız tutma alanı.
fn rect_overlay(mut c ui.Context, label string, r ui.Rect, clip ui.Rect, bg ui.Color) {
	vis := clip_rect(r, clip)
	if vis.w <= 0 || vis.h <= 0 {
		return
	}
	c.overlay(label, vis.x, vis.y, ui.Box{
		width:  ui.fixed(vis.w)
		height: ui.fixed(vis.h)
		bg:     bg
	})
	c.close()
}

// Varlığın alanı (canlıysa ve bileşeni varsa).
fn read_f32(w &ecs.World, e ecs.EntityID, comp u16, field u16) ?f32 {
	if !w.is_alive(e) {
		return none
	}
	st := w.store(comp)
	row := st.row_of(e.index()) or { return none }
	return unsafe { st.column_f32(field)[row] }
}

fn read_pos(w &ecs.World, e ecs.EntityID, f SceneFields) (bool, f32, f32) {
	x := read_f32(w, e, ecs.transform_id, f.tx) or { return false, 0, 0 }
	y := read_f32(w, e, ecs.transform_id, f.ty) or { return false, 0, 0 }
	return true, x, y
}

// Sprite'lı varlıklardan dünya noktasını içereni; sprite satır sırasında en sonuncusu (en üstte çizilen).
// Kapsam render'daki quad ile aynıdır: merkez ± boyut/2 (Transform x/y, interpolasyonsuz).
fn pick_sprite(w &ecs.World, f SceneFields, wx f32, wy f32) ?ecs.EntityID {
	sp := w.store(ecs.sprite_id)
	tf := w.store(ecs.transform_id)
	xs := tf.column_f32(f.tx)
	ys := tf.column_f32(f.ty)
	zs := sp.column_f32(f.sz)
	mut hit := ?ecs.EntityID(none)
	for row in 0 .. sp.len() {
		idx := sp.index_at(row)
		trow := tf.row_of(idx) or { continue }
		half := unsafe { zs[row] } / 2
		x := unsafe { xs[trow] }
		y := unsafe { ys[trow] }
		if wx >= x - half && wx < x + half && wy >= y - half && wy < y + half {
			if id := w.entities().handle_at(idx) {
				hit = id
			}
		}
	}
	return hit
}

// Sahne görünümünün bir karesi. r: sahne dikdörtgeni (önceki kare); ilk karede sıfırdır ve iş yapılmaz.
pub fn (mut e Editor) scene_view(mut c ui.Context, mut srv protocol.Server, r ui.Rect) {
	w := srv.world()
	// Seçili varlık öldüyse (ör. yükleme) seçim düşer; sürükleniyorsa grup kapanır.
	alive_sel, dead_check := e.sv.selected()
	if alive_sel && !w.is_alive(dead_check) {
		e.sv.sel = none
		e.leave_drag(mut srv)
	}
	// Sahne daraldıysa (ya da alan çözülemediyse) sürükleme kapanır: açık grup kalmaz.
	if r.w <= 0 || r.h <= 0 || !e.sv.fields_ok {
		e.leave_drag(mut srv)
		return
	}
	// Yükleme sonrası kadraj: sahne dikdörtgeni bilindiği ilk karede bir kez.
	if e.fit_pending {
		e.fit_pending = false
		e.frame_all(w, r)
	}
	has_sel, sel_id := e.sv.selected()
	mut has_tf := false
	mut tx := f32(0)
	mut ty := f32(0)
	if has_sel {
		has_tf, tx, ty = read_pos(w, sel_id, e.sv.fields)
	}
	ox, oy := e.cam.world_to_screen(r, tx, ty)

	// Tutamaçlar: etkileşim durumu bu karede okunur; konum önceki karenin isabet kutularından gelir.
	it_c := if has_tf { c.interact(c.id('gz_c'), false) } else { ui.Interaction{} }
	it_x := if has_tf { c.interact(c.id('gz_x'), false) } else { ui.Interaction{} }
	it_y := if has_tf { c.interact(c.id('gz_y'), false) } else { ui.Interaction{} }

	inp := c.input()
	mx := inp.mouse_x
	my := inp.mouse_y
	in_scene := in_rect(r, mx, my)
	mut grab := Handle.center
	mut on_handle := false
	if has_tf && inp.pressed[0] {
		if it_c.pressed {
			grab = .center
			on_handle = true
		} else if it_x.pressed {
			grab = .arm_x
			on_handle = true
		} else if it_y.pressed {
			grab = .arm_y
			on_handle = true
		}
	}

	// Esc: sürüklemeyi iptal eder. Grup geri alınır (yığınlara girmez); değer başlangıca döner.
	// Taşma: iptal grubu geri alamaz; grup hâlâ açıkken değer başlangıca yazılır ve grup normal kapanır
	// (taşan grup yığına girmez). Bildirim durum çubuğunda gösterilir: sessiz kayıp olmaz.
	mut cancelled := false
	if e.sv.mode == .move && c.shortcut(.escape) {
		e.sv.mode = .idle
		cancelled = true
		srv.history_cancel_group() or {
			e.restore_start(mut srv)
			srv.history_end_group()
			e.set_note('geri alma geçmişi doldu; değer geri yüklendi')
		}
	}

	match e.sv.mode {
		.move {
			if !cancelled {
				if inp.down[0] {
					e.move_to(mut srv, r, mx, my)
				} else {
					srv.history_end_group()
					e.sv.mode = .idle
				}
			}
		}
		.pending {
			if !inp.down[0] {
				e.sv.mode = .idle
			} else if math.abs(mx - e.sv.press_x) >= ui.drag_threshold || math.abs(my - e.sv.press_y) >= ui.drag_threshold {
				// Eşik aşıldı: tek geri alma grubu başlar; bu karenin taşıması da gruba girer.
				srv.history_begin_group()
				e.sv.mode = .move
				e.move_to(mut srv, r, mx, my)
			}
		}
		.pan {
			if inp.down[e.sv.btn] {
				e.pan_to(r, mx, my)
			} else {
				e.sv.mode = .idle
			}
		}
		.idle {
			space := inp.space
			if in_scene && (inp.pressed[2] || (inp.pressed[0] && space)) {
				e.sv.mode = .pan
				e.sv.btn = if inp.pressed[2] { 2 } else { 0 }
				e.sv.press_x = mx
				e.sv.press_y = my
				e.sv.cam_cx = e.cam.cx
				e.sv.cam_cy = e.cam.cy
			} else if on_handle {
				e.sv.mode = .pending
				e.note_len = 0
				e.sv.grab = grab
				e.sv.press_x = mx
				e.sv.press_y = my
				e.sv.start_x = tx
				e.sv.start_y = ty
			} else if in_scene && inp.pressed[0] && !space {
				wx, wy := e.cam.screen_to_world(r, mx, my)
				e.sv.sel = pick_sprite(w, e.sv.fields, wx, wy)
			}
			if in_scene && inp.wheel_y != 0 {
				e.cam.zoom_at(r, mx, my, f32(math.pow(cam_zoom_notch, f64(inp.wheel_y))))
			}
		}
	}
	if e.sv.mode == .pan || (in_scene && inp.space) {
		c.set_cursor_hint(.hand)
	}

	// Çizim: seçim çerçevesi, sonra gizmo (üstte). Her kenar sahne dikdörtgenine kırpılır.
	if has_tf {
		if sz := read_f32(w, sel_id, ecs.sprite_id, e.sv.fields.sz) {
			e.outline_overlays(mut c, r, ox, oy, sz)
		}
		e.gizmo_overlays(mut c, r, ox, oy, it_x.hovered, it_y.hovered, it_c.hovered)
	}
}

// Tüm sprite'ların dünya kutusu (merkez ± boyut/2); sprite yoksa ok false. Yalnız okuma.
fn sprite_box(w &ecs.World, f SceneFields) (bool, f32, f32, f32, f32) {
	sp := w.store(ecs.sprite_id)
	tf := w.store(ecs.transform_id)
	xs := tf.column_f32(f.tx)
	ys := tf.column_f32(f.ty)
	zs := sp.column_f32(f.sz)
	mut ok := false
	mut x0 := f32(0)
	mut y0 := f32(0)
	mut x1 := f32(0)
	mut y1 := f32(0)
	for row in 0 .. sp.len() {
		idx := sp.index_at(row)
		trow := tf.row_of(idx) or { continue }
		half := unsafe { zs[row] } / 2
		x := unsafe { xs[trow] }
		y := unsafe { ys[trow] }
		if !ok {
			x0 = x - half
			x1 = x + half
			y0 = y - half
			y1 = y + half
			ok = true
		} else {
			x0 = if x - half < x0 { x - half } else { x0 }
			x1 = if x + half > x1 { x + half } else { x1 }
			y0 = if y - half < y0 { y - half } else { y0 }
			y1 = if y + half > y1 { y + half } else { y1 }
		}
	}
	return ok, x0, y0, x1, y1
}

// Kadraj (F tuşu ve yükleme): tüm sprite'lar. Sprite yoksa kamera değişmez.
fn (mut e Editor) frame_all(w &ecs.World, r ui.Rect) {
	if !e.sv.fields_ok {
		return
	}
	ok, x0, y0, x1, y1 := sprite_box(w, e.sv.fields)
	if ok {
		e.cam.frame_box(r, x0, y0, x1, y1)
	}
}

// Kadraj (F tuşu): seçili varlığın sprite kutusu (sprite yoksa konumu). Seçim yoksa false: çağıran tümünü kadrajlar.
fn (mut e Editor) frame_selected(w &ecs.World, r ui.Rect) bool {
	if !e.sv.fields_ok {
		return false
	}
	has, id := e.sv.selected()
	if !has {
		return false
	}
	ok, x, y := read_pos(w, id, e.sv.fields)
	if !ok {
		return false
	}
	half := (read_f32(w, id, ecs.sprite_id, e.sv.fields.sz) or { f32(0) }) / 2
	e.cam.frame_box(r, x - half, y - half, x + half, y + half)
	return true
}

// Taşıma (gizmo): başlangıç değeri + basış konumundan dünya deltası; yalnız tutulan eksenler yazılır.
fn (mut e Editor) move_to(mut srv protocol.Server, r ui.Rect, mx f32, my f32) {
	k := e.cam.px_per_unit(r)
	if k <= 0 {
		return
	}
	if e.sv.grab != .arm_y {
		e.set_transform(mut srv, 'x', e.sv.start_x + (mx - e.sv.press_x) / k)
	}
	if e.sv.grab != .arm_x {
		e.set_transform(mut srv, 'y', e.sv.start_y - (my - e.sv.press_y) / k)
	}
}

// Sürüklemeden önceki değerleri yazar (tutulan eksenler). Çağrı açık editör grubunun içinde olmalı.
fn (mut e Editor) restore_start(mut srv protocol.Server) {
	if e.sv.grab != .arm_y {
		e.set_transform(mut srv, 'x', e.sv.start_x)
	}
	if e.sv.grab != .arm_x {
		e.set_transform(mut srv, 'y', e.sv.start_y)
	}
}

// Tek alan yazımı: component.set (Transform), editör kaynağıyla.
fn (mut e Editor) set_transform(mut srv protocol.Server, field string, v f32) {
	_, id := e.sv.selected()
	mut r := ReqBuf{}
	r.begin('component.set')
	r.param_entity('entity', id)
	r.param_str('component', 'Transform')
	r.param_str('field', field)
	r.param_f32('value', v)
	_ = srv.handle_from(r.end(), .editor)
}

// Pan: basış anındaki kamera + fare farkı (birikmeden; sürüklemenin sonu tam konumu verir).
fn (mut e Editor) pan_to(r ui.Rect, mx f32, my f32) {
	k := e.cam.px_per_unit(r)
	if k <= 0 {
		return
	}
	e.cam.cx = e.sv.cam_cx - (mx - e.sv.press_x) / k
	e.cam.cy = e.sv.cam_cy + (my - e.sv.press_y) / k
}

// Sürükleme durur (seçim düşünce): grup açıksa kapanır.
fn (mut e Editor) leave_drag(mut srv protocol.Server) {
	if e.sv.mode == .move {
		srv.history_end_group()
	}
	e.sv.mode = .idle
}

// Seçim çerçevesi: sprite'ın hemen dışında 1 px koyu (surface_0) hale, onun dışında 1 px accent halkası. Hale accent'i
// aynı renkli sprite'tan ayırır; accent halkası koyu zeminde her sprite renginin çevresinde görünür. Kırpılan kısım sahneye taşmaz.
fn (e &Editor) outline_overlays(mut c ui.Context, r ui.Rect, ox f32, oy f32, sz f32) {
	k := e.cam.px_per_unit(r)
	side := sz * k
	left := ox - side / 2
	top := oy - side / 2
	// Hale: sprite kutusunun 1 px dışı.
	rect_overlay(mut c, 'sel_h_t', ui.Rect{ x: left - outline_w, y: top - outline_w, w: side + 2 * outline_w, h: outline_w }, r, ui.surface_0)
	rect_overlay(mut c, 'sel_h_b', ui.Rect{ x: left - outline_w, y: top + side, w: side + 2 * outline_w, h: outline_w }, r, ui.surface_0)
	rect_overlay(mut c, 'sel_h_l', ui.Rect{ x: left - outline_w, y: top, w: outline_w, h: side }, r, ui.surface_0)
	rect_overlay(mut c, 'sel_h_r', ui.Rect{ x: left + side, y: top, w: outline_w, h: side }, r, ui.surface_0)
	// Accent halkası: halenin 1 px dışı.
	ax := left - 2 * outline_w
	ay := top - 2 * outline_w
	aw := side + 4 * outline_w
	rect_overlay(mut c, 'sel_t', ui.Rect{ x: ax, y: ay, w: aw, h: outline_w }, r, ui.accent)
	rect_overlay(mut c, 'sel_b', ui.Rect{ x: ax, y: ay + aw - outline_w, w: aw, h: outline_w }, r, ui.accent)
	rect_overlay(mut c, 'sel_l', ui.Rect{ x: ax, y: ay, w: outline_w, h: aw }, r, ui.accent)
	rect_overlay(mut c, 'sel_r', ui.Rect{ x: ax + aw - outline_w, y: ay, w: outline_w, h: aw }, r, ui.accent)
}

// Gizmo: X kolu sağa, Y kolu yukarı (ekran y aşağı). Eksen çizgisi 2 px, ucunda 8 px dolu kare (eksen rengi, hover'da
// açılır); ortada 10 px kare (yüzey dolgusu, 1 px text_primary kenar). Tutma bandı görünen kolun üstünde.
fn (e &Editor) gizmo_overlays(mut c ui.Context, r ui.Rect, ox f32, oy f32, hx bool, hy bool, hc bool) {
	half := gizmo_center / 2
	tip := gizmo_tip / 2
	rect_overlay(mut c, 'gz_x_vis', ui.Rect{ x: ox + half, y: oy - gizmo_thick / 2, w: gizmo_len - half, h: gizmo_thick }, r, ui.axis_x)
	rect_overlay(mut c, 'gz_x_tip', ui.Rect{ x: ox + gizmo_len - tip, y: oy - tip, w: gizmo_tip, h: gizmo_tip }, r, if hx { ui.axis_x_hover } else { ui.axis_x })
	rect_overlay(mut c, 'gz_x', ui.Rect{ x: ox + half, y: oy - gizmo_band / 2, w: gizmo_len - half + tip, h: gizmo_band }, r, ui.Color(0))
	rect_overlay(mut c, 'gz_y_vis', ui.Rect{ x: ox - gizmo_thick / 2, y: oy - gizmo_len, w: gizmo_thick, h: gizmo_len - half }, r, ui.axis_y)
	rect_overlay(mut c, 'gz_y_tip', ui.Rect{ x: ox - tip, y: oy - gizmo_len - tip, w: gizmo_tip, h: gizmo_tip }, r, if hy { ui.axis_y_hover } else { ui.axis_y })
	rect_overlay(mut c, 'gz_y', ui.Rect{ x: ox - gizmo_band / 2, y: oy - gizmo_len - tip, w: gizmo_band, h: gizmo_len - half + tip }, r, ui.Color(0))
	rect_overlay(mut c, 'gz_c', ui.Rect{ x: ox - half, y: oy - half, w: gizmo_center, h: gizmo_center }, r, if hc { ui.surface_hover } else { ui.surface_2 })
	rect_overlay(mut c, 'gz_c_t', ui.Rect{ x: ox - half, y: oy - half, w: gizmo_center, h: outline_w }, r, ui.text_primary)
	rect_overlay(mut c, 'gz_c_b', ui.Rect{ x: ox - half, y: oy + half - outline_w, w: gizmo_center, h: outline_w }, r, ui.text_primary)
	rect_overlay(mut c, 'gz_c_l', ui.Rect{ x: ox - half, y: oy - half, w: outline_w, h: gizmo_center }, r, ui.text_primary)
	rect_overlay(mut c, 'gz_c_r', ui.Rect{ x: ox + half - outline_w, y: oy - half, w: outline_w, h: gizmo_center }, r, ui.text_primary)
}
