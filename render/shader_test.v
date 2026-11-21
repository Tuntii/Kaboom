module render

import platform

const vs_ok = '#version 330 core
layout(location = 0) in vec2 pos;
void main() { gl_Position = vec4(pos, 0.0, 1.0); }
'

const fs_ok = '#version 330 core
out vec4 color;
void main() { color = vec4(1.0); }
'

// x tanimsiz; derleyici hata verir.
const fs_bad = '#version 330 core
out vec4 color;
void main() { x = 1; }
'

fn test_load_gl_ok() {
	mut w := platform.Window.new(platform.WindowConfig{ visible: false, width: 200, height: 150 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	load_gl() or { assert false, 'load_gl: ${err}' }
}

fn test_compile_valid_program() {
	mut w := platform.Window.new(platform.WindowConfig{ visible: false, width: 200, height: 150 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	load_gl() or { assert false, 'load_gl: ${err}' }
	prog := compile_program(vs_ok, fs_ok) or {
		assert false, 'gecerli shader reddedildi: ${err}'
		return
	}
	assert prog > 0
	delete_program(prog)
}

// Hata mesajı GL info log'unu taşır; sonundaki satır sonu ve NUL kırpılmış olmalı.
fn test_compile_broken_fragment_reports_log() {
	mut w := platform.Window.new(platform.WindowConfig{ visible: false, width: 200, height: 150 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	load_gl() or { assert false, 'load_gl: ${err}' }
	_ = compile_program(vs_ok, fs_bad) or {
		msg := err.msg()
		assert msg.len > 0
		assert !msg.ends_with('\n')
		assert !msg.contains('\x00')
		return
	}
	assert false, 'bozuk fragment shader kabul edildi'
}

// Pencere yokken context yoktur; wglGetProcAddress NULL döner, hazır bayrağı kalkık kalır.
fn test_gl_not_ready_without_context() {
	load_gl() or {
		assert !gl_ready()
		assert err.msg().contains('glCreateShader')
		assert err.msg().contains('glDrawArraysInstanced')
		return
	}
	assert false, 'context yokken load_gl basarili dondu'
}

fn test_gl_ready_after_load() {
	mut w := platform.Window.new(platform.WindowConfig{ visible: false, width: 200, height: 150 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	load_gl() or { assert false, 'load_gl: ${err}' }
	assert gl_ready()
}

// Hata yolu: iki sahte isim tek hatada listelenir, hazır bayrağı kalkar ve yuvalar sıfırlanır.
fn test_load_names_reports_all_missing_and_clears() {
	mut w := platform.Window.new(platform.WindowConfig{ visible: false, width: 200, height: 150 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	load_gl() or { assert false, 'load_gl: ${err}' }
	load_names(['glNope1', 'glCreateShader', 'glNope2']) or {
		assert err.msg().contains('glNope1')
		assert err.msg().contains('glNope2')
		assert !err.msg().contains('glCreateShader')
		assert !gl_ready()
		// Sonraki testler yüklü durumla çalışsın diye yeniden yükle.
		load_gl() or { assert false, 'yeniden load_gl: ${err}' }
		return
	}
	assert false, 'sahte isimler kabul edildi'
}
