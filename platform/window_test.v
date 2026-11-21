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
	cw, ch := w.size()
	assert cw == 200 && ch == 150
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
