module main

import os
import image

// vcore editor: stdin'den üç Transform+Sprite varlığı ve bir component.set gelir, gizli pencerede 5 kare çizilir.
// Sahne alanı ortasındaki piksel kırmızı sprite'ı, ikinci varlık (yeşil) ajan değişikliğiyle sola kaymış olmalı;
// durum çubuğunda metin pikselleri olmalı. GL yoksa süreç çıkış kodu 3 ile biter; test atlanır.

fn edt_scene_pixel(pixels []u8, w int, x int, y int) []u8 {
	o := (y * w + x) * 4
	return pixels[o..o + 3]
}

fn test_editor_scenario_sprite_in_scene_area() {
	tmp := os.join_path(os.temp_dir(), 'vcore_m4c5_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	exe := os.join_path(tmp, 'vcore.exe')
	build := os.execute('"${@VEXE}" -gc none -subsystem console -o "${exe}" "${@VMODROOT}/cmd_main"')
	assert build.exit_code == 0, build.output

	// Kırmızı (0), yeşil (1, sonra x=-2'ye taşınır), mavi (2) sprite'lar; boyut 2 birim ≈ 17 px.
	input := os.join_path(tmp, 'in.jsonl')
	os.write_file(input, [
		'{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":0,"y":0},"Sprite":{"size":2,"r":1,"g":0,"b":0}}}}',
		'{"jsonrpc":"2.0","id":2,"method":"entity.spawn","params":{"components":{"Transform":{"x":-3,"y":0},"Sprite":{"size":2,"r":0,"g":1,"b":0}}}}',
		'{"jsonrpc":"2.0","id":3,"method":"entity.spawn","params":{"components":{"Transform":{"x":3,"y":0},"Sprite":{"size":2,"r":0,"g":0,"b":1}}}}',
		'{"jsonrpc":"2.0","id":4,"method":"component.set","params":{"entity":1,"component":"Transform","field":"x","value":-2}}',
	].join('\n') + '\n') or {
		panic(err)
	}
	shot_path := os.join_path(tmp, 'editor.png')
	old_wd := os.getwd()
	os.chdir(tmp) or { panic(err) }
	defer {
		os.chdir(old_wd) or {}
	}

	run := os.execute('"${exe}" editor --hidden --width 640 --height 400 --scale 1 --frames 5 --screenshot "${shot_path}" < "${input}"')
	if run.exit_code == 3 && run.output.contains('GL yok') {
		eprintln('atlandi: GL yok: ${run.output.trim_space()}')
		return
	}
	assert run.exit_code == 0, run.output
	// Bariyer: ekran görüntüsü stdin EOF'tan sonra alınır; dört istek de yanıtlanmış olmalı (stdout'ta 4 yanıt).
	assert run.output.count('"jsonrpc"') == 4, 'dört yanıt bekleniyor: ${run.output}'

	png := os.read_bytes(shot_path) or { panic('editor.png okunamadi: ${err}') }
	w, h, px := image.decode_png_stored(png) or { panic('PNG cozulemedi: ${err}') }
	assert w == 640 && h == 400, 'PNG boyutu ${w}x${h}'
	// Sahne alanı: x 244..336 (merkez 290), y 41..376 (merkez 208). Kamera 0,0, görünüm yüksekliği 40: 8.375 px/birim.
	c := edt_scene_pixel(px, w, 290, 208)
	assert c[0] > 200 && c[1] < 40 && c[2] < 40, 'sahne merkezi kirmizi olmali: ${c}'
	// Mavi sprite x=3: merkez 315 px.
	b := edt_scene_pixel(px, w, 315, 208)
	assert b[2] > 200 && b[0] < 40 && b[1] < 40, 'mavi sprite x=3 konumunda olmali: ${b}'
	// Yeşil sprite ajan değişikliğiyle x=-2 (merkez 273 px); eski konumu (x=-3, merkez 265 px) artık boş: 258 px yeşil değil.
	g := edt_scene_pixel(px, w, 273, 208)
	assert g[1] > 200 && g[0] < 40 && g[2] < 40, 'yesil sprite ajan set sonrasi x=-2 olmali: ${g}'
	old := edt_scene_pixel(px, w, 258, 208)
	assert !(old[1] > 200 && old[0] < 40), 'yesil sprite eski konumda kalmamali: ${old}'
	// Sol panel kırmızı değil.
	side := edt_scene_pixel(px, w, 100, 208)
	assert !(side[0] > 200 && side[1] < 40), 'sol panel kirmizi olmamali: ${side}'
	// Durum çubuğu: metin pikselleri (parlak) var; yüzey zemininden belirgin.
	mut text_px := 0
	for y in h - 20 .. h - 4 {
		for x in 4 .. 200 {
			p := edt_scene_pixel(px, w, x, y)
			if p[0] > 90 || p[1] > 90 || p[2] > 90 {
				text_px++
			}
		}
	}
	assert text_px > 20, 'durum cubugunda metin pikseli yok: ${text_px}'
}

// --select N, sahnede satır yoksa hata verip 1 ile çıkar (sessiz seçimsiz ekran görüntüsü üretmez).
fn test_editor_select_missing_row_exits_1() {
	tmp := os.join_path(os.temp_dir(), 'vcore_m4c10_sel_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	exe := os.join_path(tmp, 'vcore.exe')
	build := os.execute('"${@VEXE}" -gc none -subsystem console -o "${exe}" "${@VMODROOT}/cmd_main"')
	assert build.exit_code == 0, build.output

	input := os.join_path(tmp, 'in.jsonl')
	os.write_file(input, '{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":0,"y":0},"Sprite":{"size":2}}}}\n') or {
		panic(err)
	}
	shot_path := os.join_path(tmp, 'sel.png')
	old_wd := os.getwd()
	os.chdir(tmp) or { panic(err) }
	defer {
		os.chdir(old_wd) or {}
	}
	run := os.execute('"${exe}" editor --hidden --width 640 --height 400 --scale 1 --select 5 --screenshot "${shot_path}" < "${input}"')
	if run.exit_code == 3 && run.output.contains('GL yok') {
		eprintln('atlandi: GL yok: ${run.output.trim_space()}')
		return
	}
	assert run.exit_code == 1, 'çıkış kodu 1 olmalı: ${run.exit_code} ${run.output}'
	assert run.output.contains('satır yok'), run.output
	assert !os.exists(shot_path), 'hata durumunda ekran görüntüsü yazılmamalı'
}
