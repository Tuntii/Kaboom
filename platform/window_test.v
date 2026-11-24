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
	// Mantıksal boyut DPI ile ölçeklenir (tamsayı formülü: boyut*dpi/96); size() fiziksel piksel döner.
	d := int(w.dpi_scale() * 96 + 0.5)
	cw, ch := w.size()
	assert cw == 200 * d / 96 && ch == 150 * d / 96
}

// dpi_aware false: width/height doğrudan fiziksel piksel, DPI'dan bağımsız.
fn test_size_is_physical_when_not_dpi_aware() {
	mut w := Window.new(WindowConfig{ visible: false, width: 200, height: 150, dpi_aware: false }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	cw, ch := w.size()
	assert cw == 200 && ch == 150
	assert w.dpi_scale() == 1.0
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

// Tekrar (bit 30) düşmez: kare listesine repeat bayrağıyla girer.
fn test_key_repeat_delivered_with_flag() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	C.SendMessageW(w.hwnd, 0x0100, 0x08, 0)
	C.SendMessageW(w.hwnd, 0x0100, 0x08, isize(0x40000000))
	f := w.input()
	assert f.vkey_count == 2
	assert f.vkeys[0] == 0x08 && !f.vkey_repeat[0]
	assert f.vkeys[1] == 0x08 && f.vkey_repeat[1]
}

// Tutulan Boşluk bayrağı bırakma mesajında yenilenir (test ortamında Boşluk basılı değil: GetKeyState 0).
fn test_keyup_refreshes_held_space() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	mut p := C.vcore_in_ptr()
	p.space = 1
	C.SendMessageW(w.hwnd, 0x0101, 0x20, 0)
	assert !w.input().space
}

// Odak kaybında tutulan tuş bayrakları temizlenir: bırakma olayı gelmeyebilir.
fn test_kill_focus_clears_held_keys() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	mut p := C.vcore_in_ptr()
	p.space = 1
	p.ctrl = 1
	C.SendMessageW(w.hwnd, 0x0008, 0, 0)
	f := w.input()
	assert !f.space && !f.ctrl
}

// F10 sistem tuşu olarak kaydedilir ve DefWindowProc'a gitmez; çağrı 0 döner.
fn test_f10_sys_key_consumed_and_recorded() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	assert C.SendMessageW(w.hwnd, 0x0104, 0x79, 0) == 0
	assert C.SendMessageW(w.hwnd, 0x0105, 0x79, 0) == 0
	f := w.input()
	assert f.vkey_count == 1 && f.vkeys[0] == 0x79
}

// Tek Alt'ın bırakılması menü modal döngüsünü açmaz.
fn test_bare_alt_sys_keys_consumed() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	assert C.SendMessageW(w.hwnd, 0x0104, 0x12, 0) == 0
	assert C.SendMessageW(w.hwnd, 0x0105, 0x12, 0) == 0
}

// SC_KEYMENU (0xF100) kendi başına 0 döner; DefWindowProc menü döngüsünü açamaz.
fn test_sc_keymenu_consumed() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	assert C.SendMessageW(w.hwnd, 0x0112, 0xF100, 0) == 0
}

// Küçültülmüş pencere restore ile geri gelir (gizli pencerede de).
fn test_restore_leaves_minimized() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	C.ShowWindow(w.hwnd, 6) // SW_MINIMIZE
	assert w.minimized()
	w.restore()
	assert !w.minimized()
}

// WM_QUIT kapanış bayrağından ayrıdır: poll false döner, quit_requested görür, clear_close onu silmez.
fn test_wm_quit_is_not_close() {
	mut w := Window.new(WindowConfig{ visible: false, width: 64, height: 64 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	C.PostQuitMessage(0)
	assert !w.poll()
	assert w.quit_requested()
	w.clear_close()
	assert w.quit_requested()
}
