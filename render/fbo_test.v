module render

import platform
import ui

// FBO testleri: hidden pencere + GL yoksa test atlanır (ui_renderer_test.v ile aynı desen).
// Her _test.v ayrı derlendiği için yardımcı burada yeniden tanımlanır.
fn fbo_open_gl_window() ?platform.Window {
	mut w := platform.Window.new(platform.WindowConfig{ visible: false, width: 200, height: 150 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return none
	}
	load_gl() or {
		w.close()
		assert false, 'load_gl: ${err}'
		return none
	}
	return w
}

// Ekran arka tamponunu (framebuffer 0) mavi ile temizler: FBO'ya yanlış bağlanma burada görünür.
fn fbo_sentinel() {
	unbind_fbo()
	clear_color(0, 0, 1, 1)
	clear(gl_color_buffer_bit)
	finish()
}

// Okunan tek pikseli (x, y) sol üst köken ile verir; GL'de y çevrilir.
fn fbo_read_px(x int, y int, gh int) (u8, u8, u8) {
	mut px := []u8{len: 4}
	read_pixels(x, gh - 1 - y, 1, 1, gl_rgba, gl_unsigned_byte, px.data)
	return px[0], px[1], px[2]
}

fn test_fbo_complete_and_reads_clear_color() {
	mut w := fbo_open_gl_window() or { return }
	defer { w.close() }
	_, ch := w.size()
	mut f := Fbo.new(64, 48) or {
		assert false, 'Fbo.new: ${err}'
		return
	}
	defer { f.close() }
	fbo_sentinel()
	f.bind()
	viewport(0, 0, 64, 48)
	clear_color(1, 0, 0, 1)
	clear(gl_color_buffer_bit)
	finish()
	fr, fg, fb := fbo_read_px(63, 47, 48)
	assert fr >= 254 && fg <= 1 && fb <= 1, 'FBO kırmızı değil: ${fr} ${fg} ${fb}'
	// Bağlama gerçekten FBO'ya yönlendirmiş olmalı: arka tampon mavi kalmalı.
	unbind_fbo()
	br, bg, bb := fbo_read_px(0, 0, ch)
	assert br <= 1 && bg <= 1 && bb >= 254, 'arka tampon değişti (bind no-op?): ${br} ${bg} ${bb}'
}

fn test_fbo_rejects_empty_size() {
	mut w := fbo_open_gl_window() or { return }
	defer { w.close() }
	if f := Fbo.new(0, 8) {
		mut g := f
		g.close()
		assert false, 'sıfır boyutlu FBO kabul edildi'
	}
}

fn test_fbo_resize() {
	mut w := fbo_open_gl_window() or { return }
	defer { w.close() }
	_, ch := w.size()
	mut f := Fbo{}
	f.resize(64, 48) or {
		assert false, 'resize 64x48: ${err}'
		return
	}
	assert f.w == 64 && f.h == 48
	first := f.fb
	// Aynı boyut yeniden oluşturmaz.
	f.resize(64, 48) or { assert false, 'resize aynı boyut: ${err}' }
	assert f.fb == first
	f.resize(32, 32) or {
		assert false, 'resize 32x32: ${err}'
		return
	}
	assert f.w == 32 && f.h == 32
	fbo_sentinel()
	f.bind()
	viewport(0, 0, 32, 32)
	clear_color(0, 1, 0, 1)
	clear(gl_color_buffer_bit)
	finish()
	fr, fg, fb := fbo_read_px(31, 31, 32)
	assert fr <= 1 && fg >= 254 && fb <= 1, 'yeniden boyutlanan FBO yeşil değil: ${fr} ${fg} ${fb}'
	unbind_fbo()
	br, bg, bb := fbo_read_px(0, 0, ch)
	assert br <= 1 && bg <= 1 && bb >= 254, 'arka tampon değişti (bind no-op?): ${br} ${bg} ${bb}'
	f.close()
	assert f.fb == 0 && f.w == 0
}

// Yarı saydam kenar FBO'da alfa < 255 bırakır; make_opaque sonrası her alfa 255 olmalı.
fn test_fbo_capture_is_opaque_after_make_opaque() {
	mut w := fbo_open_gl_window() or { return }
	defer { w.close() }
	mut f := Fbo.new(64, 48) or {
		assert false, 'Fbo.new: ${err}'
		return
	}
	defer { f.close() }
	f.bind()
	viewport(0, 0, 64, 48)
	clear_color(0, 0, 0, 1)
	clear(gl_color_buffer_bit)
	mut r := UiRenderer.new(4) or {
		assert false, 'UiRenderer.new: ${err}'
		return
	}
	defer { r.close() }
	mut list := ui.DrawList.new(4)
	list.push(ui_cmd_full(0, 0, 64, 48, 0x00FF0080))
	r.draw(&list, 64, 48)
	finish()
	mut px := []u8{len: 64 * 48 * 4}
	read_pixels(0, 0, 64, 48, gl_rgba, gl_unsigned_byte, px.data)
	unbind_fbo()
	mut below := false
	for i := 3; i < px.len; i += 4 {
		if px[i] < 255 {
			below = true
		}
	}
	assert below, 'yarı saydam çizim alfayı düşürmedi; test anlamsız'
	make_opaque(mut px)
	for i := 3; i < px.len; i += 4 {
		assert px[i] == 255, 'alfa 255 değil: ${px[i]} (piksel ${i / 4})'
	}
}

fn test_make_opaque_sets_alpha_only() {
	mut px := [u8(1), 2, 3, 0, 4, 5, 6, 128]
	make_opaque(mut px)
	assert px == [u8(1), 2, 3, 255, 4, 5, 6, 255]
}

// Tam kare komut (UiRenderer için); renk rgba'dır.
fn ui_cmd_full(x f32, y f32, w f32, h f32, color u32) ui.DrawCmd {
	return ui.DrawCmd{
		x:     x
		y:     y
		w:     w
		h:     h
		cx1:   w
		cy1:   h
		color: color
	}
}
