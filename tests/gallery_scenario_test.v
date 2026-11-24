module main

import os
import image

// vcore gallery: pencereli vitrin derlenir, tek kare ekran görüntüsü alınır ve pikseller denetlenir.
// GL yoksa süreç çıkış kodu 3 ile biter; bu durumda test atlanır.
// PNG çözücü tests/render_scenario_test.v'deki kopyadır: her _test.v dosyası ayrı derlenir (render/alloc_test.v deseni).

fn gal_be32(b []u8, p int) u32 {
	return u32(b[p]) << 24 | u32(b[p + 1]) << 16 | u32(b[p + 2]) << 8 | u32(b[p + 3])
}

// Yalnızca bu projenin ürettiği stored deflate RGBA PNG'lerini çözer. CRC ve Adler-32 doğrulanır.
fn gal_decode_png(png []u8) !(int, int, []u8) {
	if png.len < 8 || png[..8] != [u8(0x89), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
		return error('imza yok')
	}
	mut pos := 8
	mut w := 0
	mut h := 0
	mut idat := []u8{}
	for pos + 12 <= png.len {
		n := int(gal_be32(png, pos))
		typ := png[pos + 4..pos + 8].bytestr()
		ds := pos + 8
		de := ds + n
		if de + 4 > png.len {
			return error('chunk tasiyor')
		}
		if gal_be32(png, de) != image.crc32(png[pos + 4..de]) {
			return error('chunk CRC hatali')
		}
		match typ {
			'IHDR' {
				w = int(gal_be32(png, ds))
				h = int(gal_be32(png, ds + 4))
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
	if gal_be32(idat, p) != image.adler32(raw) {
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

fn gal_pixel(pixels []u8, w int, x int, y int) []u8 {
	o := (y * w + x) * 4
	return pixels[o..o + 3]
}

fn gal_assert_rgb_near(got []u8, want []u8, what string) {
	for c in 0 .. 3 {
		d := int(got[c]) - int(want[c])
		assert d >= -2 && d <= 2, '${what}: kanal ${c} ${got} beklenen ${want}'
	}
}

fn test_gallery_screenshot() {
	tmp := os.join_path(os.temp_dir(), 'vcore_m4a_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	exe := os.join_path(tmp, 'vcore.exe')
	build := os.execute('"${@VEXE}" -gc none -subsystem console -o "${exe}" "${@VMODROOT}/cmd_main"')
	assert build.exit_code == 0, build.output

	shot_path := os.join_path(tmp, 'gallery.png')
	old_wd := os.getwd()
	os.chdir(tmp) or { panic(err) }
	defer {
		os.chdir(old_wd) or {}
	}

	run := os.execute('"${exe}" gallery --hidden --width 1280 --height 800 --scale 1 --screenshot "${shot_path}"')
	if run.exit_code == 3 && run.output.contains('GL yok') {
		eprintln('atlandi: GL yok: ${run.output.trim_space()}')
		return
	}
	assert run.exit_code == 0, run.output

	png := os.read_bytes(shot_path) or { panic('gallery.png okunamadi: ${err}') }
	w, h, px := gal_decode_png(png) or { panic('PNG cozulemedi: ${err}') }
	assert w == 1280 && h == 800, 'PNG boyutu ${w}x${h}'

	surface_0 := [u8(0x11), 0x12, 0x14]
	surface_1 := [u8(0x17), 0x18, 0x1B]
	// Araç çubuğu zemini (sol üst köşe, düğmelerin dışı).
	gal_assert_rgb_near(gal_pixel(px, w, 4, 4), surface_1, 'arac cubugu zemini')
	// Durum çubuğu (en alt satır) yüzey renklerinden birinde.
	status := gal_pixel(px, w, 4, h - 4)
	near_1 := status[0] >= surface_1[0] - 2 && status[0] <= surface_1[0] + 2
	near_0 := status[0] >= surface_0[0] - 2 && status[0] <= surface_0[0] + 2
	assert near_1 || near_0, 'durum cubugu piksel ${status}'

	// Sahne ortasında quad'lar: yüzey dışı en az bir piksel.
	mut quad_seen := false
	for y in h / 2 - 50 .. h / 2 + 50 {
		for x in w / 2 - 50 .. w / 2 + 50 {
			p := gal_pixel(px, w, x, y)
			if p[0] != surface_0[0] || p[1] != surface_0[1] || p[2] != surface_0[2] {
				quad_seen = true
			}
		}
	}
	assert quad_seen, 'sahne ortasinda quad piksel yok'
}
