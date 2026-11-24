module platform

fn test_hidden_window_gets_core_33() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	assert w.gl_version().starts_with('3.3')
	cw, ch := w.size()
	assert cw > 0 && ch > 0
	assert w.poll()
}

// width/height istemci alanıdır; dış boyut AdjustWindowRect ile hesaplanır.
// 64 px genişlik sistem minimumunun (SM_CXMIN, dış ~136 px) altında kalır ve pencere genişletilir,
// bu yüzden exact boyut testi minimumun üstünde yapılır.
fn test_size_is_client_area() {
	mut w := Window.new(WindowConfig{ visible: false, width: 200, height: 150 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	// Mantıksal boyut DPI ile ölçeklenir; size() fiziksel piksel döner.
	s := w.dpi_scale()
	cw, ch := w.size()
	assert cw == int(200 * s + 0.5) && ch == int(150 * s + 0.5)
}

fn C.SendMessageW(hwnd voidptr, msg u32, wp usize, lp isize) isize

fn mouse_lp(x int, y int) isize {
	return isize(y) * 65536 + isize(x & 0xFFFF)
}

fn test_mouse_move_and_click() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	C.SendMessageW(w.hwnd, 0x0200, 0, mouse_lp(10, 20))
	C.SendMessageW(w.hwnd, 0x0201, 0, mouse_lp(10, 20))
	C.SendMessageW(w.hwnd, 0x0202, 0, mouse_lp(10, 20))
	f := w.input()
	assert f.mouse_x == 10
	assert f.pressed[0] && f.released[0]
	assert !f.down[0]
	assert !w.input().pressed[0]
}

fn test_wheel_notches() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	C.SendMessageW(w.hwnd, 0x020A, usize(120) << 16, 0)
	assert w.input().wheel == 1.0
}

fn test_char_utf16_pair() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	C.SendMessageW(w.hwnd, 0x0102, 0xD83D, 0)
	C.SendMessageW(w.hwnd, 0x0102, 0xDE00, 0)
	f := w.input()
	assert f.char_count == 1
	assert f.chars[0] == 0x1F600
}

fn test_kill_focus_releases_buttons() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	C.SendMessageW(w.hwnd, 0x0007, 0, 0)
	C.SendMessageW(w.hwnd, 0x0201, 0, 0)
	C.SendMessageW(w.hwnd, 0x0008, 0, 0)
	f := w.input()
	assert !f.down[0]
	assert f.released[0]
	assert !f.focused
}

fn test_dpi_scale_positive() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	assert w.dpi_scale() >= 1.0
}

fn test_close_twice_is_safe() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	w.close()
	w.close()
}

// WM_CLOSE pencereyi yok etmez, yalnız bayrağı kaldırır; poll false döner.
fn test_wm_close_stops_poll() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	assert wnd_proc(w.hwnd, 0x0010, 0, 0) == 0
	assert !w.poll()
}

fn test_gl_proc_null_for_unknown_name() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	assert gl_proc(c'vcore_yok_boyle_bir_fonksiyon') == unsafe { nil }
}
