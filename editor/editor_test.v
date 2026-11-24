module editor

import os
import ui
import ecs
import protocol
import sim

// Her test kendi Server ve Context'ini kurar (dosya başına derleme: yardımcılar bu dosyada).
fn edt_server() protocol.Server {
	return protocol.Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
}

// Bir sentetik kare: düzen kurulur, editör çizer, düzen bir önceki kare olarak saklanır.
fn edt_frame(mut c ui.Context, mut e Editor, mut srv protocol.Server, inp ui.Input) EditorFrame {
	c.begin(inp, 1440, 900, 1.0)
	fr := e.frame(mut c, mut srv)
	c.end()
	return fr
}

// Düğmeye tıklama: üzerine gel, bas, bırak (üç kare). Konum bir önceki karenin düzeninden okunur.
fn edt_click(mut c ui.Context, mut e Editor, mut srv protocol.Server, label string) {
	r := c.last_rect(label) or { panic('düğme yok: ${label}') }
	x := r.x + r.w / 2
	y := r.y + r.h / 2
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: x, mouse_y: y })
	mut down := ui.Input{ mouse_x: x, mouse_y: y }
	down.down[0] = true
	down.pressed[0] = true
	edt_frame(mut c, mut e, mut srv, down)
	mut up := ui.Input{ mouse_x: x, mouse_y: y }
	up.released[0] = true
	edt_frame(mut c, mut e, mut srv, up)
}

fn edt_key(k ui.Key) ui.Input {
	mut inp := ui.Input{ mouse_x: -1, mouse_y: -1 }
	inp.keys[0] = k
	inp.key_count = 1
	return inp
}

fn test_play_pause_step_send_protocol() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert srv.paused(), 'editör açılışta sim.pause gönderir'
	edt_click(mut c, mut e, mut srv, 'Oynat')
	assert !srv.paused(), 'oynat sim.resume gönderir'
	edt_click(mut c, mut e, mut srv, 'Adım')
	assert srv.tick() == 1, 'adım sim.step n=1 gönderir'
	edt_click(mut c, mut e, mut srv, 'Duraklat')
	assert srv.paused(), 'duraklat sim.pause gönderir'
}

fn test_shortcuts_ignored_when_keyboard_captured() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	// Denetim: alan yokken F5 oynatır.
	edt_frame(mut c, mut e, mut srv, edt_key(.f5))
	assert !srv.paused(), 'F5 alan yokken oynatır'
	// Bir metin alanı odaklanır; alan her karede çizilir (düzenin en üstünde, editör düzeninden önce).
	mut buf := ui.TextBuf{}
	c.begin(ui.Input{ mouse_x: -1, mouse_y: -1 }, 1440, 900, 1.0)
	c.text_field('ad', mut buf, 200)
	e.frame(mut c, mut srv)
	c.end()
	r := c.last_rect('ad') or { panic('alan yok') }
	x := r.x + r.w / 2
	y := r.y + r.h / 2
	mut hover := ui.Input{ mouse_x: x, mouse_y: y }
	mut press := ui.Input{ mouse_x: x, mouse_y: y }
	press.down[0] = true
	press.pressed[0] = true
	mut release := ui.Input{ mouse_x: x, mouse_y: y }
	release.released[0] = true
	for inp in [hover, press, release] {
		c.begin(inp, 1440, 900, 1.0)
		c.text_field('ad', mut buf, 200)
		e.frame(mut c, mut srv)
		c.end()
	}
	assert c.keyboard_captured(), 'alan odaklanınca klavye yakalanır'
	// Yakalıyken F5 yok sayılır: duraklatma durumu değişmez.
	before := srv.paused()
	c.begin(edt_key(.f5), 1440, 900, 1.0)
	c.text_field('ad', mut buf, 200)
	e.frame(mut c, mut srv)
	c.end()
	assert srv.paused() == before, 'F5 klavye yakalıyken çalışmamalı'
}

fn test_status_bar_counts() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	srv.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn"}') or { panic('yanıt yok') }
	srv.handle('{"jsonrpc":"2.0","id":2,"method":"entity.spawn"}') or { panic('yanıt yok') }
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	s := e.status_text()
	assert s.contains('2 varlık'), 'durum: ${s}'
	assert s.contains('tick 0 '), 'durum: ${s}'
	assert s.contains('duraklatıldı'), 'durum: ${s}'
}

// Kare zamanından ölçülen fps (EMA) tam sayı olarak görünür: 20 ms kare aralığı → 50 fps.
fn test_fps_measured_from_frame_times() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	for k in 0 .. 6 {
		edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1, time_ms: f64(k) * 20 })
	}
	assert e.status_text().contains('50 fps'), 'durum: ${e.status_text()}'
}

// Düzen: sahne alanı sıfır olmayan dikdörtgen; kamera 0,0 ve görünüm yüksekliği 40.
fn test_frame_reports_scene_rect_and_camera() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fr := edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert fr.scene.w > 0 && fr.scene.h > 0, 'sahne alanı: ${fr.scene}'
	assert fr.cam_cx == 0 && fr.cam_cy == 0 && fr.cam_view_h == 40
}

// İstek kurucu: metin değerleri JSON'da kaçışlanır, sayılar işaretli yazılır, taşan satır boş döner.
fn test_req_buf_escapes_and_bounds() {
	mut r := ReqBuf{}
	r.begin('scene.load')
	r.param_str('path', 'C:\\a"b')
	r.param_int('n', -12)
	assert r.end() == '{"jsonrpc":"2.0","id":1,"method":"scene.load","params":{"path":"C:\\\\a\\"b","n":-12}}'

	mut long := ReqBuf{}
	long.begin('scene.load')
	long.param_str('path', 'a'.repeat(1100))
	assert long.end() == ''
}

// INT_MIN: negatif işaret taşmadan yazilir.
fn test_req_buf_int_min() {
	mut r := ReqBuf{}
	r.begin('sim.step')
	r.param_int('n', -2147483648)
	assert r.end() == '{"jsonrpc":"2.0","id":1,"method":"sim.step","params":{"n":-2147483648}}'
}

// Eksik sahne dosyasi: ilk karede yükleme hatasi görünür, dosya adi temizlenir.
fn test_missing_scene_shows_load_error() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('yok_dosya_m4c5.vscene')
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert e.load_error().contains('sahne yüklenemedi'), 'hata: ${e.load_error()}'
	assert e.load_error().contains('could not read file'), 'hata: ${e.load_error()}'
	assert e.file_label() == 'Yeni sahne', 'dosya adi temizlenmeli: ${e.file_label()}'
}

// Geçerli sahne: yükleme hatasi yok ve dünya sahnedeki varlikla kurulur.
fn test_valid_scene_loads_without_error() {
	dir := os.temp_dir().replace('\\', '/')
	path := '${dir}/vcore_m4c5_ok_${os.getpid()}.vscene'
	defer {
		os.rm(path) or {}
	}
	mut writer := edt_server()
	call_spawn := writer.handle('{"jsonrpc":"2.0","id":1,"method":"entity.spawn"}') or { panic('yanit yok') }
	assert call_spawn.contains('"entity"')
	writer.handle('{"jsonrpc":"2.0","id":2,"method":"scene.save","params":{"path":"${path}"}}') or { panic('yanit yok') }
	writer.close()

	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new(path)
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert e.load_error() == '', 'hata olmamali: ${e.load_error()}'
	assert srv.world().alive_count() == 1
}

// f32 metni: %.9g; tam sayı ondalıksız, ondalık ve üçte bir bit-eşit (9 basamak); sonlu olmayan istek kurmaz.
fn test_req_buf_f32_and_entity_text() {
	mut r := ReqBuf{}
	r.begin('component.set')
	r.param_entity('entity', ecs.make_entity(7, 2))
	r.param_f32('a', 100)
	r.param_f32('b', 0.1)
	r.param_f32('c', f32(1) / f32(3))
	r.param_f32('d', -2.5)
	assert r.end() == '{"jsonrpc":"2.0","id":1,"method":"component.set","params":{"entity":8589934599,"a":100,"b":0.1,"c":0.33333334,"d":-2.5}}'
	assert f32(0.33333334) == f32(1) / f32(3), 'kısa metin f32 değerini geri okutur'
	// Protokolün f32_text'iyle aynı biçim (aynı değerler, aynı metin).
	for v in [f32(0.1), f32(1) / f32(3), f32(12345.678), f32(1e-7), f32(-2.5), f32(3e38), f32(100), f32(-7), f32(0)] {
		mut q := ReqBuf{}
		q.begin('component.set')
		q.param_f32('v', v)
		assert q.end().contains('"v":${protocol.f32_text(v)}}'), 'biçim: ${protocol.f32_text(v)}'
	}

	mut bad := ReqBuf{}
	bad.begin('component.set')
	zero := f32(0)
	bad.param_f32('v', zero / zero)
	assert bad.end() == '', 'NaN istek kurmaz'
}

// Durum metni kesimi UTF-8 kod noktası sınırında: çok baytlı harf ortadan bölünmez.
fn test_put_str_respects_utf8_boundary() {
	mut buf := [status_cap]u8{}
	s := 'a'.repeat(159) + 'ş' // ş iki bayt: 159 + 2 = 161 > 160
	n := put_str(mut buf, 0, s)
	assert n == 159, 'sınır geri çekilmeli: ${n}'
	assert buf[158] == `a`
}
