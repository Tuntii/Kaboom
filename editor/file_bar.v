module editor

import ui
import protocol

// Dosya ve geçmiş (M4c Görev 9): geri al/yinele, kaydet/aç yol alanı, kaydedilmemiş değişiklik şeridi,
// durum çubuğunda 4 sn hata iletisi. Dünyaya yazım history.* ve scene.* istekleriyle olur.

const flash_ms = f64(4000) // hata iletisinin görünme süresi (ms)
const field_w = f32(240) // yol alanı genişliği

// Yol alanının modu: kapalı, kayıt (Enter = kaydet) ya da aç (Enter = yükle).
enum FileField {
	idle
	save
	open
}

// Kaydedilmemiş değişiklik şeridinin bekleyen eylemi: aç (target'a) ya da pencereyi kapat.
enum Confirm {
	idle
	open
	close
}

fn (e &Editor) dirty(count u64) bool {
	return count != e.saved_count
}

// Pencere kapatma isteği (cmd_main): kare başında kirlilik sorulur.
pub fn (mut e Editor) request_close() {
	e.close_asked = true
}

// Pencere kapanabilir mi: kaydedildi ya da kaydedilmemiş değişiklik onaylandı.
pub fn (e &Editor) should_close() bool {
	return e.closing
}

// Sürükleme grubu açıkken geri alma ve yineleme istenmez (protokol editor_group_open ile reddeder).
fn (e &Editor) group_open() bool {
	return e.sv.mode == .move || e.ins.grouping
}

// history.undo / history.redo: uygulandıysa seçim remap'e göre yeni id'ye taşınır.
fn (mut e Editor) history_step(mut srv protocol.Server, undo bool) {
	if e.group_open() {
		return
	}
	mut r := ReqBuf{}
	r.begin(if undo { 'history.undo' } else { 'history.redo' })
	resp := editor_request(mut e, mut srv, r.end(), if undo { 'geri alma' } else { 'yineleme' }) or { return }
	has, sel := e.sv.selected()
	if has {
		if n := protocol.response_remap(resp, sel) {
			e.sv.sel = n
		}
	}
}

// Durum çubuğu hata iletisi (4 sn). Metin tampona kopyalanır; tahsis yok.
fn (mut e Editor) flash_error(a string, b string) {
	mut n := put_str(mut e.flash, 0, a)
	n = put_str(mut e.flash, n, b)
	e.flash_len = n
	e.flash_until = e.now_ms + flash_ms
}

// Görünen hata iletisi ya da süresi dolmuş / yok: boş. Tahsissiz görünüm.
fn (e &Editor) flash_text() string {
	if e.flash_len == 0 || e.now_ms >= e.flash_until {
		return ''
	}
	return unsafe { tos(&e.flash[0], e.flash_len) }
}

// scene.save: başarıda yol ve kayıt sayacı güncellenir, yol alanı kapanır. Hata durum çubuğunda görünür.
fn (mut e Editor) save_to(mut srv protocol.Server, path string) bool {
	mut r := ReqBuf{}
	r.begin('scene.save')
	r.param_str('path', path)
	_ = editor_request(mut e, mut srv, r.end(), 'kayıt') or { return false }
	e.path.set(path)
	e.saved_count = srv.change_count()
	e.file_field = .idle
	return true
}

// scene.load: başarıda seçim temizlenir, kamera sıfırlanır, kayıt sayacı eşitlenir. Hata yolu ve dünyayı değiştirmez.
fn (mut e Editor) open_path(mut srv protocol.Server, path string) bool {
	e.close_drag(mut srv)
	mut r := ReqBuf{}
	r.begin('scene.load')
	r.param_str('path', path)
	_ = editor_request(mut e, mut srv, r.end(), 'yükleme') or { return false }
	e.path.set(path)
	e.saved_count = srv.change_count()
	e.loads_seen = srv.load_count()
	e.sv.sel = none
	e.cam.cx = 0
	e.cam.cy = 0
	e.cam.view_h = cam_view_h
	e.fit_pending = true
	e.file_field = .idle
	e.confirm = .idle
	return true
}

// Açık sürükleme grubunu kapatır: yükleme ve geri alma açık grupla çakışmaz.
fn (mut e Editor) close_drag(mut srv protocol.Server) {
	e.leave_drag(mut srv)
	if e.ins.grouping {
		srv.history_end_group()
		e.ins.grouping = false
	}
}

// Yol alanını açar; odak bir sonraki karede alana verilir.
fn (mut e Editor) show_field(mode FileField) {
	e.file_field = mode
	e.field.set(e.path.str())
	e.focus_next = true
}

// Bekleyen eylem (kayıt ya da şerit kararı sonrası): kapanış ya da yükleme (hedef yoksa yol alanı).
fn (mut e Editor) proceed(mut srv protocol.Server) {
	pending := e.confirm
	e.confirm = .idle
	match pending {
		.close {
			e.closing = true
		}
		.open {
			if e.target.len > 0 {
				e.open_path(mut srv, e.target.str())
			} else {
				e.show_field(.open)
			}
		}
		.idle {}
	}
}

// Kaydet (düğme ya da Ctrl+S): yol varsa kaydeder; yoksa yol alanı kayıt modunda açılır.
fn (mut e Editor) save_click(mut srv protocol.Server) {
	if e.path.len == 0 {
		if e.file_field != .save {
			e.show_field(.save)
		}
		return
	}
	_ = e.save_to(mut srv, e.path.str())
}

// Aç: kirliyse şerit çıkar (Kaydetme sonrası yol alanı açılır), değilse yol alanı açılır.
fn (mut e Editor) open_click(mut srv protocol.Server) {
	if e.dirty(srv.change_count()) {
		e.confirm = .open
		e.target.len = 0
		return
	}
	e.show_field(.open)
}

// Yol alanında Enter: kayıt modunda kaydeder (şerit varsa bekleyen eylem sürer); aç modunda kirliyse şerit, değilse yükler.
fn (mut e Editor) field_commit(mut srv protocol.Server) {
	p := e.field.str()
	if p == '' {
		e.flash_error('yol boş', '')
		return
	}
	if e.file_field == .save {
		if e.save_to(mut srv, p) {
			e.proceed(mut srv)
		}
		return
	}
	if e.dirty(srv.change_count()) {
		e.target.set(p)
		e.file_field = .idle
		e.confirm = .open
		return
	}
	_ = e.open_path(mut srv, p)
}

// Şerit Kaydet: yol varsa kaydeder ve bekleyen eylemi sürdürür; yol yoksa kayıt alanı açılır.
fn (mut e Editor) confirm_save(mut srv protocol.Server) {
	if e.path.len == 0 {
		if e.file_field != .save {
			e.show_field(.save)
		}
		return
	}
	if e.save_to(mut srv, e.path.str()) {
		e.proceed(mut srv)
	}
}

// Şerit Vazgeç: bekleyen eylem ve yol alanı kapanır; pencere açık kalır.
fn (mut e Editor) cancel_confirm() {
	e.confirm = .idle
	e.file_field = .idle
}

// Kapatma isteği ve şerit durumu: kirli değilse bekleyen eylem hemen sürer, kirliyse istek şeride döner.
fn (mut e Editor) settle_confirm(mut srv protocol.Server) {
	if e.close_asked {
		e.close_asked = false
		if e.dirty(srv.change_count()) {
			e.confirm = .close
		} else {
			e.closing = true
		}
	}
	if e.confirm != .idle && !e.dirty(srv.change_count()) {
		e.proceed(mut srv)
	}
}

// Kaydedilmemiş değişiklik şeridi: ince uyarı kenarı, Kaydet / Kaydetme / Vazgeç.
fn (mut e Editor) confirm_strip(mut c ui.Context, mut srv protocol.Server) {
	c.open('confirm', ui.Box{
		dir:    .row
		width:  ui.grow()
		height: ui.fixed(ui.toolbar_h)
		bg:     ui.surface_2
	})
	c.open('confirm_edge', ui.Box{
		width:  ui.fixed(ui.notice_edge_w)
		height: ui.grow()
		bg:     ui.warning
	})
	c.close()
	c.open('confirm_row', ui.Box{
		dir:         .row
		width:       ui.grow()
		height:      ui.grow()
		padding:     ui.pad_xy(ui.space_3, 0)
		gap:         ui.space_2
		align_cross: .center
	})
	c.text('Kaydedilmemiş değişiklikler', .body_strong, ui.text_primary)
	c.spacer()
	// Şerit düğmeleri araç çubuğu düğmeleriyle aynı etiketi taşır: ayrı kimlik yığını.
	c.push_id(1)
	if c.button_ex('Kaydet', .primary, true) {
		e.confirm_save(mut srv)
	}
	if c.button_ex('Kaydetme', .secondary, true) {
		e.proceed(mut srv)
	}
	if c.button_ex('Vazgeç', .ghost, true) {
		e.cancel_confirm()
	}
	c.pop_id()
	c.close()
	c.close()
}

// Araç çubuğunun dosya bölümü: kirlilik noktası, etiket, yol alanı (açıkken), Aç ve Kaydet.
fn (mut e Editor) file_bar(mut c ui.Context, mut srv protocol.Server) {
	if e.dirty(srv.change_count()) {
		c.text('•', .body_strong, ui.warning)
	}
	// Ad kutusu: uzun ad … ile kırpılır; tam yol ipucunda (ad kutusunun üstünde bekleyince). Ad ve ipucu aynı kopyadan
	// okunur: kare içinde yol sonradan değişse de çizilen metin ile ölçüsü eşleşir.
	e.sync_shown()
	c.open('file_name', ui.Box{
		width:  ui.fit()
		height: ui.fit()
	})
	c.text_trunc(label_of(e.shown_str()), .body_strong, ui.text_primary, ui.file_name_max_w)
	c.close()
	if e.shown_len > 0 {
		c.tooltip(e.shown_str())
	}
	if e.file_field != .idle {
		if e.focus_next {
			c.focus_label('Yol')
			e.focus_next = false
		}
		enter := c.text_field('Yol', mut e.field, field_w)
		if enter {
			e.field_commit(mut srv)
		}
	}
	c.spacer()
	if c.button_ex('Aç', .secondary, true) {
		e.open_click(mut srv)
	}
	if c.button_ex('Kaydet', .primary, true) {
		e.save_click(mut srv)
	}
}

// Ctrl+Z geri al; Ctrl+Y ve Ctrl+Shift+Z yineler; Ctrl+S kaydeder. c.shortcut klavye bir alandayken atlar.
fn (mut e Editor) file_shortcuts(mut c ui.Context, mut srv protocol.Server) {
	// Esc: açık yol alanını ya da bekleyen şeridi kapatır; alan Esc'i yutsa da burada görülür.
	if !c.menu_open() && key_hit(c.input(), .escape) && (e.file_field != .idle || e.confirm != .idle) {
		e.cancel_confirm()
	}
	if !c.input().ctrl {
		return
	}
	if c.shortcut(.z) {
		e.history_step(mut srv, !c.input().shift)
	}
	if c.shortcut(.y) {
		e.history_step(mut srv, false)
	}
	if c.shortcut(.s) {
		e.save_click(mut srv)
	}
}

// Bu karede tuş basıldı mı (otomatik tekrar sayılmaz).
fn key_hit(inp &ui.Input, k ui.Key) bool {
	for i in 0 .. inp.key_count {
		if inp.keys[i] == k && !inp.key_repeat[i] {
			return true
		}
	}
	return false
}

// Kapatma isteğini kare çizmeden işler (küçültülmüş pencere): temiz değişiklik hemen kapanır, kirli olan şeride döner.
pub fn (mut e Editor) poll_close(mut srv protocol.Server) {
	e.settle_confirm(mut srv)
}

// Kaydedilmemiş değişiklik şeridi bekliyor mu (küçültülmüş pencere bunu görmek için geri yüklenir).
pub fn (e &Editor) confirm_pending() bool {
	return e.confirm != .idle
}
