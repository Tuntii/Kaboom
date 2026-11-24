module main

import os
import image

// vcore editor: stdin'den Transform+Sprite varlığı gelir, gizli pencerede 5 kare çizilir ve sahne alanı
// ortasındaki piksel kırmızı sprite'ı gösterir. GL yoksa süreç çıkış kodu 3 ile biter; test atlanır.

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

	input := os.join_path(tmp, 'in.jsonl')
	os.write_file(input, '{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":0,"y":0},"Sprite":{"size":10,"r":1,"g":0,"b":0}}}}\n') or {
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

	png := os.read_bytes(shot_path) or { panic('editor.png okunamadi: ${err}') }
	w, h, px := image.decode_png_stored(png) or { panic('PNG cozulemedi: ${err}') }
	assert w == 640 && h == 400, 'PNG boyutu ${w}x${h}'
	// Sahne alanı: x 244..336 (merkez 290), y 41..376 (merkez 208). Kamera 0,0: sprite merkezde.
	c := edt_scene_pixel(px, w, 290, 208)
	assert c[0] > 200 && c[1] < 40 && c[2] < 40, 'sahne merkezi kirmizi olmali: ${c}'
	// Sahne dışı (sol panel) kırmızı değil.
	side := edt_scene_pixel(px, w, 100, 208)
	assert !(side[0] > 200 && side[1] < 40), 'sol panel kirmizi olmamali: ${side}'
}
