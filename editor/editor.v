module editor

import ui
import protocol

// vcore editor iskeleti (M4c Görev 5): araç çubuğu, paneller, durum çubuğu, oynat/duraklat/adım.
// Dünyaya yazmak yalnız handle_from(..., .editor) ile olur; dünyayı okumak srv.world() ile serbesttir.

const panel_left_w = f32(240)
const panel_right_w = f32(300)
const cam_view_h = f32(40)
// Kare süresi EMA'sı: yeni kare payı; 0.1 ≈ son ~10 karenin ortalaması.
const fps_alpha = f32(0.1)
const status_cap = 160

// Bir karenin sonucu: cmd_main sahne quad'larını bu kamerayla ve bu dikdörtgende çizer.
pub struct EditorFrame {
pub:
	scene      ui.Rect
	cam_cx     f32
	cam_cy     f32
	cam_view_h f32
	cursor     ui.CursorHint
}

pub struct Editor {
mut:
	left_w     f32
	right_w    f32
	cam        EditorCamera
	sv         SceneState
	path       ui.TextBuf
	started    bool
	timed      bool
	last_ms    f64
	fps        f32
	status     [status_cap]u8
	status_len int
	err        [status_cap]u8
	err_len    int
}

// Yeni editör: panel genişlikleri 240/300, kamera 0,0 görünüm yüksekliği 40, seçim yok.
// shortcut: yol 256 baytlık TextBuf'a sığmazsa kod noktası sınırında kırpılır; kırpılmış yol yüklenirken dosya bulunamaz hatası görünür. upgrade: Görev 9 yol ayrı tutulunca.
pub fn Editor.new(scene_path string) Editor {
	mut e := Editor{
		left_w:  panel_left_w
		right_w: panel_right_w
		cam:     EditorCamera{
			view_h: cam_view_h
		}
	}
	e.path.set(scene_path)
	return e
}

// Sahne yükleme hatası metni; hata yoksa boş. Tahsissiz görünüm.
pub fn (e &Editor) load_error() string {
	return unsafe { tos(&e.err[0], e.err_len) }
}

// scene.load isteği. Başarısızlık (boş istek, yanıt yok, error üyesi) durum çubuğunda gösterilir ve
// gösterilen dosya adı temizlenir; ilk karede tek sefer çağrılır.
fn (mut e Editor) load_scene(mut srv protocol.Server) {
	mut r := ReqBuf{}
	r.begin('scene.load')
	r.param_str('path', e.path.str())
	line := r.end()
	if line == '' {
		e.set_load_error('istek kurulamadı: yol çok uzun')
		return
	}
	resp := srv.handle_from(line, .editor) or {
		e.set_load_error('yanıt yok')
		return
	}
	if !protocol.response_ok(resp) {
		e.set_load_error(protocol.response_error_message(resp))
	}
}

fn (mut e Editor) set_load_error(msg string) {
	mut n := put_str(mut e.err, 0, 'sahne yüklenemedi: ')
	n = put_str(mut e.err, n, msg)
	e.err_len = n
	e.path.len = 0
}

// Son karede hazırlanan durum metni (tahsissiz görünüm; bir sonraki kareye kadar geçerli).
pub fn (e &Editor) status_text() string {
	return unsafe { tos(&e.status[0], e.status_len) }
}

// Bir kare: düzeni kurar, gerekli istekleri gönderir. Çağıran ui.Context.begin/end çevresini sağlar.
pub fn (mut e Editor) frame(mut c ui.Context, mut srv protocol.Server) EditorFrame {
	if !e.started {
		e.started = true
		// Açılışta duraklatılır: oynat/adım düğmeleri ilerlemeyi açıkça yönetir.
		send_plain(mut srv, 'sim.pause')
		e.sv.fields = resolve_scene_fields(srv.registry()) or { panic(err) }
		if e.path.len > 0 {
			e.load_scene(mut srv)
		}
	}
	e.measure(c.input().time_ms)
	e.toolbar(mut c, mut srv)
	e.body(mut c)
	// Sahne görünümü: önceki karenin sahne dikdörtgeni (düzen bir kare geriden; ilk karede sıfır, işlem yok).
	scene := c.prev_rect(c.id('scene')) or { ui.Rect{} }
	e.scene_view(mut c, mut srv, scene)
	// Kısayollar alanlar çizildikten sonra: klavye bir alandaysa (ui.Context.shortcut) atlanır.
	if c.shortcut(.f5) {
		if srv.paused() {
			send_plain(mut srv, 'sim.resume')
		} else {
			send_plain(mut srv, 'sim.pause')
		}
	}
	if c.shortcut(.f6) {
		send_plain(mut srv, 'sim.pause')
	}
	if c.shortcut(.f10) {
		e.step(mut srv)
	}
	e.format_status(srv)
	c.statusbar_begin()
	if e.err_len > 0 {
		c.text(e.load_error(), .caption, ui.danger)
	} else {
		c.statusbar_text(e.status_text())
	}
	c.statusbar_end()
	return EditorFrame{
		scene:      scene
		cam_cx:     e.cam.cx
		cam_cy:     e.cam.cy
		cam_view_h: e.cam.view_h
		cursor:     c.cursor_hint()
	}
}

fn (mut e Editor) toolbar(mut c ui.Context, mut srv protocol.Server) {
	c.toolbar_begin()
	if c.icon_button('Oynat', .play, !srv.paused()) {
		send_plain(mut srv, 'sim.resume')
	}
	c.tooltip('Oynat')
	if c.icon_button('Duraklat', .pause, srv.paused()) {
		send_plain(mut srv, 'sim.pause')
	}
	if c.icon_button('Adım', .step, false) {
		e.step(mut srv)
	}
	// Geri al ve yinele 9. görevde (undo/redo) etkinleşir.
	c.icon_button_ex('Geri al', .undo, false, false)
	c.icon_button_ex('Yinele', .redo, false, false)
	c.spacer()
	c.text(e.file_label(), .body_strong, ui.text_primary)
	c.spacer()
	// Aç ve Kaydet 9. görevde etkinleşir.
	c.button_ex('Aç', .secondary, false)
	c.button_ex('Kaydet', .primary, false)
	c.toolbar_end()
}

fn (e &Editor) file_label() string {
	if e.path.len == 0 {
		return 'Yeni sahne'
	}
	return e.path.str()
}

// Gövde: sol panel, sahne alanı ve sağ panel; ayırıcılar genişlikleri değiştirir.
fn (mut e Editor) body(mut c ui.Context) {
	c.open('body', ui.Box{
		dir:    .row
		width:  ui.grow()
		height: ui.grow()
	})
	c.open('hier', ui.Box{
		dir:    .column
		width:  ui.fixed(e.left_w)
		height: ui.grow()
		bg:     ui.surface_1
	})
	c.open('hier_head', ui.Box{
		dir:         .row
		width:       ui.grow()
		height:      ui.fixed(ui.toolbar_h)
		padding:     ui.pad_xy(ui.space_3, 0)
		gap:         ui.space_1
		align_cross: .center
	})
	c.text('Hiyerarşi', .body_strong, ui.text_primary)
	c.close()
	c.close()
	c.splitter('split_l', mut &e.left_w, 160, 420, true)

	c.open('scene', ui.Box{
		width:  ui.grow()
		height: ui.grow()
	})
	c.close()

	c.splitter('split_r', mut &e.right_w, 240, 420, false)
	c.open('inspector', ui.Box{
		dir:     .column
		width:   ui.fixed(e.right_w)
		height:  ui.grow()
		padding: ui.pad_all(ui.space_3)
		gap:     ui.space_2
		bg:      ui.surface_1
	})
	c.text('Inspector', .title, ui.text_primary)
	c.close()
	c.close()
}

fn (mut e Editor) step(mut srv protocol.Server) {
	mut r := ReqBuf{}
	r.begin('sim.step')
	r.param_int('n', 1)
	_ = srv.handle_from(r.end(), .editor)
}

// Parametresiz istek (sim.pause/resume): yanıt yok sayılır, bu komutlar yalnız geçiş yapar.
fn send_plain(mut srv protocol.Server, method string) {
	mut r := ReqBuf{}
	r.begin(method)
	_ = srv.handle_from(r.end(), .editor)
}

// Kare zamanından EMA fps: ilk karede süre yoktur, sonraki karelerde örnek alınır.
fn (mut e Editor) measure(now_ms f64) {
	if e.timed && now_ms > e.last_ms {
		inst := f32(1000.0 / (now_ms - e.last_ms))
		e.fps = if e.fps == 0 { inst } else { e.fps + (inst - e.fps) * fps_alpha }
	}
	e.timed = true
	e.last_ms = now_ms
}

// "tick N · K varlık · duraklatıldı|çalışıyor · F fps" tamponu doldurulur; tahsis yok.
fn (mut e Editor) format_status(srv &protocol.Server) {
	mut n := 0
	n = put_str(mut e.status, n, 'tick ')
	n = put_uint(mut e.status, n, srv.tick())
	n = put_str(mut e.status, n, ' · ')
	n = put_uint(mut e.status, n, u64(srv.world().alive_count()))
	n = put_str(mut e.status, n, ' varlık · ')
	n = put_str(mut e.status, n, if srv.paused() { 'duraklatıldı' } else { 'çalışıyor' })
	n = put_str(mut e.status, n, ' · ')
	n = put_uint(mut e.status, n, u64(int(e.fps + 0.5)))
	n = put_str(mut e.status, n, ' fps')
	e.status_len = n
}

// Sığmayan bayt kesilir (en fazla status_cap bayt); kesim UTF-8 kod noktası sınırına geri çekilir (ui.TextBuf.set gibi).
// Dönen değer yeni uzunluktur.
fn put_str(mut out [status_cap]u8, at int, s string) int {
	mut take := s.len
	if at + take > status_cap {
		take = status_cap - at
	}
	for take > 0 && take < s.len && (s[take] & 0xC0) == 0x80 {
		take--
	}
	mut n := at
	for i in 0 .. take {
		out[n] = s[i]
		n++
	}
	return n
}

fn put_uint(mut out [status_cap]u8, at int, v u64) int {
	mut digits := [20]u8{}
	mut k := 0
	mut x := v
	for {
		digits[k] = u8(48 + x % 10)
		k++
		x /= 10
		if x == 0 {
			break
		}
	}
	mut n := at
	for k > 0 {
		k--
		if n >= status_cap {
			break
		}
		out[n] = digits[k]
		n++
	}
	return n
}
