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
