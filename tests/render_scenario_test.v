module main

import os
import x.json2
import image

// Uçtan uca pencereli senaryo: vcore run --hidden --paused ikilisi derlenir, senaryo stdin'den beslenir,
// ekran görüntüsü PNG olarak çözülür ve bilinen varlıkların merkez pikselleri denetlenir.
// GL yoksa süreç çıkış kodu 3 ile biter; bu durumda test atlanır.

fn render_be32(b []u8, p int) u32 {
	return u32(b[p]) << 24 | u32(b[p + 1]) << 16 | u32(b[p + 2]) << 8 | u32(b[p + 3])
}

// Yalnızca bu projenin ürettiği stored deflate RGBA PNG'lerini çözer. CRC ve Adler-32 doğrulanır.
fn render_decode_png(png []u8) !(int, int, []u8) {
	if png.len < 8 || png[..8] != [u8(0x89), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
		return error('imza yok')
	}
	mut pos := 8
	mut w := 0
	mut h := 0
	mut idat := []u8{}
	for pos + 12 <= png.len {
		n := int(render_be32(png, pos))
		typ := png[pos + 4..pos + 8].bytestr()
		ds := pos + 8
		de := ds + n
		if de + 4 > png.len {
			return error('chunk tasiyor')
		}
		if render_be32(png, de) != image.crc32(png[pos + 4..de]) {
			return error('chunk CRC hatali')
		}
		match typ {
			'IHDR' {
				w = int(render_be32(png, ds))
				h = int(render_be32(png, ds + 4))
			}
			'IDAT' {
				idat << png[ds..de]
			}
			else {}
		}
		pos = de + 4
		if typ == 'IEND' {
			break
		}
	}
	// zlib başlığı 2 bayt; ardından stored bloklar; sonda Adler-32.
	if idat.len < 6 || idat[0] != 0x78 || idat[1] != 0x01 {
		return error('zlib basligi hatali')
	}
	mut raw := []u8{}
	mut p := 2
	for {
		hdr := idat[p]
		if hdr & 0x06 != 0 {
			return error('stored olmayan blok')
		}
		len := int(u32(idat[p + 1]) | u32(idat[p + 2]) << 8)
		p += 5
		raw << idat[p..p + len]
		p += len
		if hdr & 1 == 1 {
			break
		}
	}
	if render_be32(idat, p) != image.adler32(raw) {
		return error('Adler-32 hatali')
	}
	row := w * 4
	mut pixels := []u8{cap: row * h}
	for r in 0 .. h {
		base := r * (row + 1)
		if raw[base] != 0 {
			return error('filtre bayti 0 degil')
		}
		pixels << raw[base + 1..base + 1 + row]
	}
	return w, h, pixels
}

fn render_pixel(pixels []u8, w int, x int, y int) []u8 {
	o := (y * w + x) * 4
	return pixels[o..o + 3]
}

fn assert_rgb_near(got []u8, want []u8, what string) {
	for c in 0 .. 3 {
		d := int(got[c]) - int(want[c])
		assert d >= -2 && d <= 2, '${what}: kanal ${c} ${got} beklenen ${want}'
	}
}

fn test_render_scenario_screenshot() {
	tmp := os.join_path(os.temp_dir(), 'vcore_m3_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	exe := os.join_path(tmp, 'vcore.exe')
	build := os.execute('"${@VEXE}" -gc none -subsystem console -o "${exe}" "${@VMODROOT}/cmd_main"')
	assert build.exit_code == 0, build.output

	scenario := os.join_path(@VMODROOT, 'tests', 'scenarios', 'm3_screenshot.jsonl')
	old_wd := os.getwd()
	os.chdir(tmp) or { panic(err) }
	defer {
		os.chdir(old_wd) or {}
	}

	run := os.execute('"${exe}" run --hidden --paused --width 320 --height 180 < "${scenario}"')
	if run.exit_code == 3 && run.output.contains('GL yok') {
		eprintln('atlandi: GL yok: ${run.output.trim_space()}')
		return
	}
	assert run.exit_code == 0, run.output

	mut by_id := map[int]map[string]json2.Any{}
	for line in run.output.split_into_lines() {
		if line.trim_space() == '' {
			continue
		}
		m := json2.decode[json2.Any](line) or { panic('gecersiz JSON yanit: ${line}') }
		obj := m.as_map()
		id := (obj['id'] or { panic('id yok: ${line}') }).int()
		by_id[id] = obj.clone()
	}
	assert by_id.len == 7, 'yanit sayisi 7 olmaliydi, ${by_id.len} geldi: ${run.output}'

	// Adım 5: ekran görüntüsü boyutları.
	shot := by_id[5]['result'] or { panic('screenshot sonucu yok: ${run.output}') }.as_map()
	w := shot['width'] or { panic('width yok') }.int()
	h := shot['height'] or { panic('height yok') }.int()
	assert w == 320, 'width=${w}'
	assert h == 180, 'height=${h}'

	// Adım 6: yazılamayan yol G/Ç hatası.
	err6 := by_id[6]['error'] or { panic('bozuk yol hata donmeliydi') }.as_map()
	assert err6['code'] or { panic('') }.int() == 1010

	// PNG çözülür; piksel konumu formülü: kamera view_h 220, cx = cy = 0.
	png := os.read_bytes(os.join_path(tmp, 'm3.png')) or { panic('m3.png okunamadi: ${err}') }
	pw, ph, pixels := render_decode_png(png) or { panic('PNG cozulemedi: ${err}') }
	assert pw == w && ph == h, 'PNG boyutu ${pw}x${ph}, yanit ${w}x${h}'

	view_w := f32(220) * f32(w) / f32(h)
	red_x := int((f32(-50) + view_w / 2) / view_w * f32(w))
	blue_x := int((f32(50) + view_w / 2) / view_w * f32(w))
	mid_y := h / 2
	assert red_x >= 115 && red_x <= 123, 'kirmizi x=${red_x}'
	assert blue_x >= 197 && blue_x <= 205, 'mavi x=${blue_x}'

	assert_rgb_near(render_pixel(pixels, pw, red_x, mid_y), [u8(255), 0, 0], 'kirmizi merkez')
	assert_rgb_near(render_pixel(pixels, pw, blue_x, mid_y), [u8(0), 0, 255], 'mavi merkez')
	// Temizleme rengi: Renderer.new koyu gri (0.08, 0.08, 0.10) ayarlar; 0.08*255 ~ 20, 0.10*255 ~ 26.
	assert_rgb_near(render_pixel(pixels, pw, 0, 0), [u8(20), 20, 26], 'kose')

	// Adım 7: 120 adım * 1/120 sn = 1 sn, yeşil varlık vx=10 ile x≈10.
	e2 := by_id[7]['result'] or { panic('entity.get sonucu yok') }.as_map()
	tr := (e2['components'] or { panic('components yok') }.as_map())['Transform'] or {
		panic('Transform yok')
	}.as_map()
	x := tr['x'] or { panic('x yok') }.f64()
	assert x > 10.0 - 1e-3 && x < 10.0 + 1e-3, 'x=${x} beklenen 10'
}

// Çalışan (duraklatılmamış) modda ekran görüntüsü mevcut tick'i gösterir: yeni varlık ne önceki konumda
// (başlangıç noktası) ne de interpolasyon ara konumunda çizilir. Canlı saat kaç adım koşarsa koşsun
// varlık Body taşımadığı için x=-100'de kalır.
fn test_render_live_screenshot_uses_current_tick() {
	tmp := os.join_path(os.temp_dir(), 'vcore_m3_live_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	exe := os.join_path(tmp, 'vcore.exe')
	build := os.execute('"${@VEXE}" -gc none -subsystem console -o "${exe}" "${@VMODROOT}/cmd_main"')
	assert build.exit_code == 0, build.output

	scenario := os.join_path(@VMODROOT, 'tests', 'scenarios', 'm3_live_screenshot.jsonl')
	old_wd := os.getwd()
	os.chdir(tmp) or { panic(err) }
	defer {
		os.chdir(old_wd) or {}
	}

	run := os.execute('"${exe}" run --hidden --width 320 --height 180 < "${scenario}"')
	if run.exit_code == 3 && run.output.contains('GL yok') {
		eprintln('atlandi: GL yok: ${run.output.trim_space()}')
		return
	}
	assert run.exit_code == 0, run.output

	mut by_id := map[int]map[string]json2.Any{}
	for line in run.output.split_into_lines() {
		if line.trim_space() == '' {
			continue
		}
		m := json2.decode[json2.Any](line) or { panic('gecersiz JSON yanit: ${line}') }
		obj := m.as_map()
		id := (obj['id'] or { panic('id yok: ${line}') }).int()
		by_id[id] = obj.clone()
	}
	assert by_id.len == 2, 'yanit sayisi 2 olmaliydi: ${run.output}'
	shot := by_id[2]['result'] or { panic('screenshot sonucu yok: ${run.output}') }.as_map()
	w := shot['width'] or { panic('width yok') }.int()
	h := shot['height'] or { panic('height yok') }.int()

	png := os.read_bytes(os.join_path(tmp, 'live.png')) or { panic('live.png okunamadi: ${err}') }
	pw, _, pixels := render_decode_png(png) or { panic('PNG cozulemedi: ${err}') }
	assert pw == w, 'PNG genisligi ${pw}, yanit ${w}'

	// Kamera view_h 220, cx = cy = 0: x=-100 merkezi ve x=0 merkezi (başlangıç noktası) piksel konumları.
	view_w := f32(220) * f32(w) / f32(h)
	red_x := int((f32(-100) + view_w / 2) / view_w * f32(w))
	origin_x := int((f32(0) + view_w / 2) / view_w * f32(w))
	mid_y := h / 2
	assert_rgb_near(render_pixel(pixels, pw, red_x, mid_y), [u8(255), 0, 0], 'kirmizi x=-100')
	assert render_pixel(pixels, pw, origin_x, mid_y)[0] < 128, 'kirmizi varlik baslangic noktasinda cizildi'
}
