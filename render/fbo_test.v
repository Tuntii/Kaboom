module render

import platform

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

fn test_fbo_complete_and_reads_clear_color() {
	mut w := fbo_open_gl_window() or { return }
	defer { w.close() }
	mut f := Fbo.new(64, 48) or {
		assert false, 'Fbo.new: ${err}'
		return
	}
	defer { f.close() }
	f.bind()
	viewport(0, 0, 64, 48)
	clear_color(1, 0, 0, 1)
	clear(gl_color_buffer_bit)
	finish()
	mut px := []u8{len: 4}
	read_pixels(63, 47, 1, 1, gl_rgba, gl_unsigned_byte, px.data)
	unbind_fbo()
	assert px[0] >= 254 && px[1] <= 1 && px[2] <= 1, 'FBO kırmızı değil: ${px}'
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
	f.bind()
	viewport(0, 0, 32, 32)
	clear_color(0, 1, 0, 1)
	clear(gl_color_buffer_bit)
	finish()
	mut px := []u8{len: 4}
	read_pixels(31, 31, 1, 1, gl_rgba, gl_unsigned_byte, px.data)
	unbind_fbo()
	f.close()
	assert f.fb == 0 && f.w == 0
	assert px[0] <= 1 && px[1] >= 254 && px[2] <= 1, 'yeniden boyutlanan FBO yeşil değil: ${px}'
}
