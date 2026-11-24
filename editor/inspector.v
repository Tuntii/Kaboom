module editor

import ecs
import math
import protocol
import ui

// Inspektör (M4c Görev 8): seçili varlığın bileşen bölümleri ve f32 alan satırları. Alan değeri her karede dünyadan
// okunur. Sürükleme tek geri alma grubudur (scene_view ile aynı yol); yazılı onay tek component.set'tir. Aralık dışı
// yazılı değer gönderilmez: alt satırda protokol ipucu metni görünür (Sprite.r must be in [0, 1]).

const ins_err_slots = 8
// shortcut: en çok 96 widget kaydı (kare başına); fazlası testte bulunamaz, upgrade: gerekirse büyütülür.
const ins_hit_cap = 96

// Widget türleri (InsHit.kind): test ve tanı için kare kayıtları.
const hit_field = u8(0)
const hit_section = u8(1)
const hit_add = u8(2)

struct InsHit {
	kind  u8
	comp  u16
	field u16
	id    u32
	val   f32 // alan satırında gösterilen değer (sayı alanına verilen, çizimden önce)
}

// Aralık hatası: varlık + bileşen + alan anahtarıyla; metin sabit tampon (tahsissiz).
struct InsErr {
mut:
	used  bool
	id    ecs.EntityID
	comp  u16
	field u16
	text  [status_cap]u8
	len   int
}

struct Inspector {
mut:
	title      [status_cap]u8
	title_len  int
	hits       [ins_hit_cap]InsHit
	nhits      int
	errs       [ins_err_slots]InsErr
	err_next   int
	grouping   bool // sürükleme grubu açık (geri alma grubu, history_begin_group)
	group_id   ecs.EntityID
	group_comp u16
	empty      bool // son karede "Seçim yok" gösterildi (inspector_empty)
}

fn (mut i Inspector) hit(kind u8, comp u16, field u16, id u32, val f32) {
	if i.nhits >= ins_hit_cap {
		return
	}
	i.hits[i.nhits] = InsHit{
		kind:  kind
		comp:  comp
		field: field
		id:    id
		val:   val
	}
	i.nhits++
}

fn (i &Inspector) err_slot(id ecs.EntityID, comp u16, field u16) int {
	for k in 0 .. ins_err_slots {
		if i.errs[k].used && i.errs[k].id == id && i.errs[k].comp == comp && i.errs[k].field == field {
			return k
		}
	}
	return -1
}

fn (i &Inspector) err_text(id ecs.EntityID, comp u16, field u16) string {
	k := i.err_slot(id, comp, field)
	if k < 0 {
		return ''
	}
	return unsafe { tos(&i.errs[k].text[0], i.errs[k].len) }
}

fn (mut i Inspector) clear_err(id ecs.EntityID, comp u16, field u16) {
	k := i.err_slot(id, comp, field)
	if k >= 0 {
		i.errs[k].used = false
	}
}

// Aralık hatası: mevcut yuva ya da sıradaki boş (yoksa dönüşlü) yuvaya yazılır.
fn (mut i Inspector) set_range_err(id ecs.EntityID, comp u16, field u16, cname string, f ecs.FieldSchema) {
	mut k := i.err_slot(id, comp, field)
	if k < 0 {
		k = i.err_next
		i.err_next = (i.err_next + 1) % ins_err_slots
	}
	i.errs[k].used = true
	i.errs[k].id = id
	i.errs[k].comp = comp
	i.errs[k].field = field
	mut n := put_str(mut i.errs[k].text, 0, cname)
	n = put_str(mut i.errs[k].text, n, '.')
	n = put_str(mut i.errs[k].text, n, f.name)
	n = put_str(mut i.errs[k].text, n, ' must be in [')
	n = put_bound(mut i.errs[k].text, n, f.min)
	n = put_str(mut i.errs[k].text, n, ', ')
	n = put_bound(mut i.errs[k].text, n, f.max)
	n = put_str(mut i.errs[k].text, n, ']')
	i.errs[k].len = n
}

// Aralık sınırı metni, protocol.range_text ile aynı biçim: tam sayı ondalıksız, değilse kısa ondalık. Tahsissiz.
// shortcut: ondalık sınırlar %.9g ile yazılır; protokolün ${x} biçimiyle her değerde aynı olmayabilir, upgrade: ortak biçimlendirici.
fn put_bound(mut out [status_cap]u8, at int, x f64) int {
	if x == math.floor(x) && math.abs(x) < 1e15 {
		mut n := at
		if x < 0 {
			n = put_str(mut out, n, '-')
		}
		return put_uint(mut out, n, u64(math.abs(x)))
	}
	mut buf := [32]u8{}
	mut blen := 0
	unsafe {
		blen = C.snprintf(&char(&buf[0]), 32, &char('%.9g'.str), x)
	}
	return put_str(mut out, at, unsafe { tos(&buf[0], blen) })
}

// Son karede çizilen bir inspektör widget'ının dikdörtgeni; yoksa none (testler ve tanı için).
pub fn (e &Editor) inspector_rect(c &ui.Context, kind u8, comp u16, field u16) ?ui.Rect {
	for k in 0 .. e.ins.nhits {
		h := e.ins.hits[k]
		if h.kind == kind && h.comp == comp && h.field == field {
			return c.last_rect_id(h.id)
		}
	}
	return none
}

// Alan satırının sayı kutusu (son kare); senaryo girdisi için tıklama hedefi.
pub fn (e &Editor) field_rect(c &ui.Context, comp u16, field u16) ?ui.Rect {
	return e.inspector_rect(c, hit_field, comp, field)
}

// "Bileşen ekle" düğmesinin dikdörtgeni (son kare); bileşen kimliği varlık kimliğiyle kapsamlı olduğundan düz etiketle bulunmaz.
pub fn (e &Editor) add_component_rect(c &ui.Context) ?ui.Rect {
	for k in 0 .. e.ins.nhits {
		h := e.ins.hits[k]
		if h.kind == hit_add {
			return c.last_rect_id(h.id)
		}
	}
	return none
}

// Seçili varlığın inspektörü: başlık #index, bileşen bölümleri, altta "Bileşen ekle". Seçim yoksa sönük metin.
pub fn (mut e Editor) inspector(mut c ui.Context, mut srv protocol.Server) {
	w := srv.world()
	reg := srv.registry()
	has, id := e.sv.selected()
	alive := has && w.is_alive(id)
	e.ins.nhits = 0
	// Sürükleme grubu açıkken seçim değişti ya da bileşen dışarıdan kaldırıldı: grup kapanır (geri alma kilitlenmez).
	if e.ins.grouping && (!alive || id != e.ins.group_id || !w.has(id, e.ins.group_comp)) {
		srv.history_end_group()
		e.ins.grouping = false
	}
	e.ins.empty = !alive
	if !alive {
		c.text('Inspector', .title, ui.text_primary)
		c.text('Seçim yok', .body, ui.text_muted)
		return
	}
	mut n := put_str(mut e.ins.title, 0, '#')
	n = put_uint(mut e.ins.title, n, u64(id.index()))
	e.ins.title_len = n
	c.text(unsafe { tos(&e.ins.title[0], e.ins.title_len) }, .title, ui.text_primary)
	c.push_id(int(id.index()))
	for comp in u16(0) .. reg.count() {
		if !w.has(id, comp) {
			continue
		}
		cs := reg.component(comp) or { continue }
		c.push_id(int(comp))
		e.ins.hit(hit_section, comp, 0, c.id(cs.name), 0)
		res := c.section_ex(cs.name, cs.name, ui.SectionOpts{
			trailing_icon: ui.Icon.trash
			trailing_tip:  'Bileşeni çıkar'
		})
		if res.trailing_clicked {
			e.comp_request(mut srv, 'component.remove', id, cs.name)
		} else if res.open {
			for fi, f in cs.fields {
				// shortcut: yalnız f32 alanlar (protokol JSON'da yalnız f32'yi taşır); bool/i32/entity satırı yok, upgrade: M6.
				if f.typ == .f32_ {
					e.field_row(mut c, mut srv, w, id, comp, cs.name, u16(fi), f)
				}
			}
		}
		c.pop_id()
	}
	c.open('add_row', ui.Box{
		width:   ui.grow()
		height:  ui.fit()
		padding: ui.pad_xy(0, ui.space_2)
	})
	e.ins.hit(hit_add, 0, 0, c.id('add_component'), 0)
	if c.menu_button_ex('add_component', 'Bileşen ekle', ui.grow(), ui.Icon.plus) {
		for comp in u16(0) .. reg.count() {
			if w.has(id, comp) {
				continue
			}
			cs := reg.component(comp) or { continue }
			if c.menu_item(cs.name) {
				e.comp_request(mut srv, 'component.add', id, cs.name)
			}
		}
		c.menu_end()
	}
	c.close()
	c.open('fill_v', ui.Box{
		width:  ui.grow()
		height: ui.grow()
	})
	c.close()
	c.pop_id()
}

// Bir alan satırı: sayı alanı, sürükleme grubu, yazılı onay ve aralık denetimi.
fn (mut e Editor) field_row(mut c ui.Context, mut srv protocol.Server, w &ecs.World, id ecs.EntityID, comp u16, cname string, fi u16, f ecs.FieldSchema) {
	cur := read_f32(w, id, comp, fi) or { return }
	mut v := cur
	c.property_row_begin(f.name)
	// Aralıklı alan: yazılı değer [min, max] dışındaysa reddedilir (alan düzenlemede kalır).
	lo := if f.ranged { f32(f.min) } else { f32(0) }
	hi := if f.ranged { f32(f.max) } else { f32(0) }
	res := c.number_field_ex(f.name, mut &v, ui.NumberFieldOpts{
		unit:     f.unit
		decimals: 2
		step:     if f.unit == 'm' { f32(0.1) } else { f32(0.01) }
		readonly:   f.readonly
		error:      if f.readonly { '' } else { e.ins.err_text(id, comp, fi) }
		drag_clamp: f.ranged
		drag_min:   f32(f.min)
		drag_max:   f32(f.max)
		min:        lo
		max:        hi
		reject:     f.ranged
	})
	c.property_row_end()
	e.ins.hit(hit_field, comp, fi, c.id(f.name), v)
	if res.rejected {
		e.ins.set_range_err(id, comp, fi, cname, f)
	} else if res.escaped {
		e.ins.clear_err(id, comp, fi)
	}
	if res.drag_started {
		srv.history_begin_group()
		e.ins.grouping = true
		e.ins.group_id = id
		e.ins.group_comp = comp
		e.note_len = 0
	}
	if res.drag_cancelled {
		e.cancel_drag(mut srv, id, cname, f, v)
	} else if res.changed || res.committed {
		e.commit_field(mut srv, id, comp, cname, fi, f, cur, v)
	}
	if res.drag_ended && e.ins.grouping {
		srv.history_end_group()
		e.ins.grouping = false
	}
}

// Yazım: sürüklemede değer kenara kıstırılır (yazılı değer widget'ta reddedilir, buraya aralık dışı gelmez).
// Başarılı yazımda alanın hatası temizlenir.
fn (mut e Editor) commit_field(mut srv protocol.Server, id ecs.EntityID, comp u16, cname string, fi u16, f ecs.FieldSchema, cur f32, v f32) {
	mut out := v
	if f.ranged {
		lo := f32(f.min)
		hi := f32(f.max)
		if out < lo || out > hi {
			out = if out < lo { lo } else { hi }
		}
	}
	if out != cur {
		field_request(mut srv, id, cname, f.name, out)
	}
	e.ins.clear_err(id, comp, fi)
}

// Sürükleme iptali (Esc): grup geri alınır, yığına girmez. Taşmada değer başlangıca yazılır ve grup normal kapanır.
// v, iptal anındaki başlangıç değeridir (sayı alanı Esc'te onu döndürür).
fn (mut e Editor) cancel_drag(mut srv protocol.Server, id ecs.EntityID, cname string, f ecs.FieldSchema, v f32) {
	if !e.ins.grouping {
		return
	}
	e.ins.grouping = false
	srv.history_cancel_group() or {
		field_request(mut srv, id, cname, f.name, v)
		srv.history_end_group()
		e.set_note('geri alma geçmişi doldu; değer geri yüklendi')
	}
}

// component.set (tek alan) editör kaynağıyla.
fn field_request(mut srv protocol.Server, id ecs.EntityID, cname string, fname string, v f32) {
	mut r := ReqBuf{}
	r.begin('component.set')
	r.param_entity('entity', id)
	r.param_str('component', cname)
	r.param_str('field', fname)
	r.param_f32('value', v)
	_ = srv.handle_from(r.end(), .editor)
}

// component.add / component.remove (bileşen adıyla, değersiz).
fn (mut e Editor) comp_request(mut srv protocol.Server, method string, id ecs.EntityID, cname string) {
	mut r := ReqBuf{}
	r.begin(method)
	r.param_entity('entity', id)
	r.param_str('component', cname)
	_ = srv.handle_from(r.end(), .editor)
}

// Son karede inspektör "Seçim yok" gösterdi mi (okuma; testler için).
pub fn (e &Editor) inspector_empty() bool {
	return e.ins.empty
}

// Son karede bir alan satırında gösterilen değer (sayı alanının çizdiği değerle aynı); yoksa none (testler için).
pub fn (e &Editor) inspector_shown(comp u16, field u16) ?f32 {
	for k in 0 .. e.ins.nhits {
		h := e.ins.hits[k]
		if h.kind == hit_field && h.comp == comp && h.field == field {
			return h.val
		}
	}
	return none
}
