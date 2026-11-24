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
const shown_cap = 256 // yol alanıyla aynı boyut (ui.TextBuf)

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
	hier       Hierarchy
	ins        Inspector
	path       ui.TextBuf
	started    bool
	timed      bool
	last_ms    f64
	fps        f32
	status     [status_cap]u8
	status_len int
	err        [status_cap]u8
	err_len    int
	note       [status_cap]u8 // durum çubuğu bildirimi (ör. taşmada Esc); bir sonraki sürüklemede temizlenir
	note_len   int
	file_field FileField  // yol alanı: kapalı, kayıt ya da aç
	field      ui.TextBuf // yol alanının metni
	target     ui.TextBuf // şerit onayından sonra yüklenecek yol
	confirm    Confirm    // kaydedilmemiş değişiklik şeridi (idle: gizli)
	focus_next bool       // yol alanı yeni açıldı: bu karede odak verilir
	saved_count u64       // son kayıt ya da yüklemedeki değişiklik sayacı (change_count)
	close_asked bool      // pencere kapatma isteği (request_close), bu karede işlenir
	closing     bool      // kapanış onaylandı: cmd_main döngüyü bitirir
	now_ms     f64        // son karenin girdi zamanı (hata iletisi süresi)
	flash      [status_cap]u8
	flash_len  int
	flash_until f64
	fit_pending bool // yükleme sonrası: sahne dikdörtgeni bilindiğinde tüm sprite'lar kadrajlanır
	loads_seen  u64       // son görülen başarılı scene.load sayısı (editör ya da ajan yüklemesi)
	shown       [shown_cap]u8 // ad ve ipucu için yol kopyası: yalnız yol değişince yenilenir (kare içinde tutarlı ölçü)
	shown_len   int
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
		return
	}
	e.saved_count = srv.change_count()
}

// Hata satırı (kırmızı durum metni): yüklemeden bağımsız kurulum hataları da buradan gösterilir.
fn (mut e Editor) set_error(msg string) {
	e.err_len = put_str(mut e.err, 0, msg)
}

// Bildirim: durum çubuğunda hata yoksa sayaç metni yerine gösterilir.
fn (mut e Editor) set_note(msg string) {
	e.note_len = put_str(mut e.note, 0, msg)
}

// Son bildirim; yoksa boş. Tahsissiz görünüm.
pub fn (e &Editor) note_text() string {
	return unsafe { tos(&e.note[0], e.note_len) }
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
		if f := resolve_scene_fields(srv.registry()) {
			e.sv.fields = f
			e.sv.fields_ok = true
		} else {
			e.set_error('sahne alanları çözülemedi: Transform/Sprite kayıtlı değil')
		}
		e.hier.init(srv.registry())
		if e.path.len > 0 {
			e.load_scene(mut srv)
		}
	}
	// Her başarılı scene.load (editör, ajan ya da açılış) bir kez kadrajlanır.
	n := srv.load_count()
	if n != e.loads_seen {
		e.loads_seen = n
		e.fit_pending = true
	}
	e.measure(c.input().time_ms)
	e.now_ms = c.input().time_ms
	// Araç çubuğu (geri al/yinele, dosya alanı) gövdeden önce: geri alma seçimi, ölü seçim düşmeden remap eder.
	e.toolbar(mut c, mut srv)
	e.file_shortcuts(mut c, mut srv)
	e.settle_confirm(mut srv)
	if e.confirm != .idle {
		e.confirm_strip(mut c, mut srv)
	}
	e.body(mut c, mut srv)
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
	// F: seçiliyi kadrajlar; seçim yoksa hepsini.
	if e.sv.fields_ok && scene.w > 0 && scene.h > 0 && c.shortcut(.f) {
		if !e.frame_selected(srv.world(), scene) {
			e.frame_all(srv.world(), scene)
		}
	}
	e.format_status(srv)
	c.statusbar_begin()
	flash := e.flash_text()
	if flash != '' {
		c.text(flash, .caption, ui.danger)
	} else if e.err_len > 0 {
		c.text(e.load_error(), .caption, ui.danger)
	} else if e.note_len > 0 {
		c.statusbar_text(e.note_text())
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
	// Geri al / yinele: yığın doluysa ve sürükleme grubu kapalıysa etkin.
	undo_n, redo_n := srv.history_lens()
	can_hist := !e.group_open()
	if c.icon_button_ex('Geri al', .undo, false, can_hist && undo_n > 0) {
		e.history_step(mut srv, true)
	}
	if c.icon_button_ex('Yinele', .redo, false, can_hist && redo_n > 0) {
		e.history_step(mut srv, false)
	}
	c.spacer()
	e.file_bar(mut c, mut srv)
	c.toolbar_end()
}

// Araç çubuğunda görünen ad (yol değişince kopya yenilenir, bkz. sync_shown).
fn (e &Editor) file_label() string {
	return label_of(e.path.str())
}

// Ad: yolun son bileşeni (ayırıcı / ya da \ sonrası); boş yolda "Yeni sahne". Tahsissiz görünüm.
fn label_of(p string) string {
	if p.len == 0 {
		return 'Yeni sahne'
	}
	mut at := 0
	for i in 0 .. p.len {
		if p[i] == `/` || p[i] == `\\` {
			at = i + 1
		}
	}
	return unsafe { tos(p.str + at, p.len - at) }
}

// Çizimde kullanılan yol kopyası (ad ve tam yol ipucu). Yol değişmişse yeniden kopyalanır; tahsis yok.
fn (mut e Editor) sync_shown() {
	p := e.path.str()
	if p == e.shown_str() {
		return
	}
	for i in 0 .. p.len {
		e.shown[i] = p[i]
	}
	e.shown_len = p.len
}

// Kopyalanmış yol; boş ya da henüz eşitlenmemişse "".
fn (e &Editor) shown_str() string {
	return unsafe { tos(&e.shown[0], e.shown_len) }
}

// Gövde: sol panel, sahne alanı ve sağ panel; ayırıcılar genişlikleri değiştirir.
fn (mut e Editor) body(mut c ui.Context, mut srv protocol.Server) {
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
	c.spacer()
	if c.icon_button('Ekle', .plus, false) {
		e.spawn_at_camera(mut srv)
	}
	c.tooltip('Kameranın ortasında yeni varlık')
	c.close()
	e.hier_list(mut c, mut srv)
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
	e.inspector(mut c, mut srv)
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
