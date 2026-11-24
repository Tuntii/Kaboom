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

// Araç çubuğu yalnız dosya adını gösterir (yol ipucundadır); ayırıcı / ya da \ olabilir.
fn test_toolbar_shows_basename() {
	assert Editor.new('a/b/c.vscene').file_label() == 'c.vscene'
	assert Editor.new('a\\b\\c.vscene').file_label() == 'c.vscene'
	assert Editor.new('c.vscene').file_label() == 'c.vscene'
	assert Editor.new('').file_label() == 'Yeni sahne'
}

// Sahne yüklenince kamera tüm spriteları %15 kenar boşluğuyla kadrajlar (bir kenar sınıra değer).
fn test_frame_all_on_load() {
	dir := os.temp_dir().replace('\\', '/')
	path := '${dir}/vcore_m4c11_frame_${os.getpid()}.vscene'
	defer {
		os.rm(path) or {}
	}
	mut writer := edt_server()
	for line in edt_sprite_lines() {
		writer.handle(line) or { panic('yanit yok') }
	}
	writer.handle('{"jsonrpc":"2.0","id":9,"method":"scene.save","params":{"path":"${path}"}}') or { panic('yanit yok') }
	writer.close()

	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new(path)
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	fr := edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	assert e.load_error() == '', 'hata olmamali: ${e.load_error()}'
	assert e.cam.view_h < cam_view_h, 'kamera yakinlasmali: ${e.cam.view_h}'
	r := fr.scene
	// Sprite ekran kutuları: dünya merkezi ± boyut/2, kamera ölçeğiyle.
	k := e.cam.px_per_unit(r)
	mut x0 := f32(1e9)
	mut y0 := f32(1e9)
	mut x1 := f32(-1e9)
	mut y1 := f32(-1e9)
	boxes := [[f32(-9), f32(-4), f32(3)], [f32(6), f32(5), f32(2)], [f32(0), f32(0), f32(1)]]
	for s in boxes {
		sx, sy := e.cam.world_to_screen(r, s[0], s[1])
		h := s[2] * k / 2
		x0 = if sx - h < x0 { sx - h } else { x0 }
		x1 = if sx + h > x1 { sx + h } else { x1 }
		y0 = if sy - h < y0 { sy - h } else { y0 }
		y1 = if sy + h > y1 { sy + h } else { y1 }
	}
	m := f32(0.15)
	assert x0 >= r.x + m * r.w - 1e-2 && x1 <= r.x + r.w - m * r.w + 1e-2, 'yatay tasma: ${x0}..${x1} sahne ${r}'
	assert y0 >= r.y + m * r.h - 1e-2 && y1 <= r.y + r.h - m * r.h + 1e-2, 'dikey tasma: ${y0}..${y1} sahne ${r}'
	touch := [x0 - (r.x + m * r.w), r.x + r.w - m * r.w - x1, y0 - (r.y + m * r.h), r.y + r.h - m * r.h - y1]
	mut best := f32(1e9)
	for t in touch {
		if t < best {
			best = t
		}
	}
	assert best < 1.5, 'en az bir kenar %15 sinirinda olmali: ${touch}'
}

// F: seçiliyi (seçim yoksa hepsini) kadrajlar.
fn test_f_frames_selection() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := Editor.new('')
	for line in edt_sprite_lines() {
		srv.handle(line) or { panic('yanit yok') }
	}
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	// Seçim yok: tüm spriteların merkezi (-10.5..7, -5.5..6).
	edt_frame(mut c, mut e, mut srv, edt_key(.f))
	assert edt_close(e.cam.cx, -1.75) && edt_close(e.cam.cy, 0.25), 'hepsi kadrajlanmali: ${e.cam.cx},${e.cam.cy}'
	// Seçim var: yalnız o sprite (merkez -9,-4; boyut 3).
	first := srv.world().store(ecs.sprite_id).index_at(0)
	e.sv.sel = srv.world().entities().handle_at(first)
	edt_frame(mut c, mut e, mut srv, edt_key(.f))
	assert edt_close(e.cam.cx, -9) && edt_close(e.cam.cy, -4), 'secili kadrajlanmali: ${e.cam.cx},${e.cam.cy}'
	assert e.cam.view_h < 6, 'secili sprite yakinlasmali: ${e.cam.view_h}'
}

fn edt_close(a f32, b f32) bool {
	d := if a > b { a - b } else { b - a }
	return d < 1e-3
}

// Üç sprite (Transform + Sprite): (-9,-4,3), (6,5,2), (0,0,1).
fn edt_sprite_lines() []string {
	return [
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":-9,"y":-4},"Sprite":{"size":3}}}}',
		'{"jsonrpc":"2.0","id":2,"method":"entity.spawn","params":{"components":{"Transform":{"x":6,"y":5},"Sprite":{"size":2}}}}',
		'{"jsonrpc":"2.0","id":3,"method":"entity.spawn","params":{"components":{"Transform":{"x":0,"y":0},"Sprite":{"size":1}}}}',
	]
}

// Uzun ad: ad kutusu en çok ui.file_name_max_w genişlikte (sonu … ile kırpılmış) çizilir.
fn test_toolbar_truncates_long_name() {
	mut srv := edt_server()
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	long := 'a'.repeat(160) + '.vscene'
	mut e := Editor.new('docs/' + long)
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	edt_frame(mut c, mut e, mut srv, ui.Input{ mouse_x: -1, mouse_y: -1 })
	r := c.last_rect('file_name') or { panic('ad kutusu yok') }
	assert r.w <= ui.file_name_max_w + 1e-3, 'ad kutusu genisligi: ${r.w}'
	assert r.w > 0
}
