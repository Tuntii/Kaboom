module platform

#flag -lgdi32 -luser32 -lopengl32
#include <windows.h>
#include <GL/gl.h>
#include "@VMODROOT/platform/win_state.h"

@[typedef]
struct C.WNDCLASSEXW {
mut:
	cbSize        u32
	style         u32
	lpfnWndProc   voidptr
	cbClsExtra    int
	cbWndExtra    int
	hInstance     voidptr
	hIcon         voidptr
	hCursor       voidptr
	hbrBackground voidptr
	lpszMenuName  &u16
	lpszClassName &u16
	hIconSm       voidptr
}

@[typedef]
struct C.PIXELFORMATDESCRIPTOR {
mut:
	nSize        u16
	nVersion     u16
	dwFlags      u32
	iPixelType   u8
	cColorBits   u8
	cDepthBits   u8
	cStencilBits u8
}

@[typedef]
struct C.POINT {
mut:
	x int
	y int
}

// Alan adları windows.h ile aynı olmalı: V sıfır literalini bu adlarla üretir.
@[typedef]
struct C.MSG {
mut:
	hwnd    voidptr
	message u32
	wParam  usize
	lParam  isize
	time    u32
	pt      C.POINT
}

type FnCreateCtx = fn (voidptr, voidptr, &int) voidptr

fn C.GetModuleHandleW(name voidptr) voidptr
fn C.RegisterClassExW(wc &C.WNDCLASSEXW) u16
fn C.DefWindowProcW(hwnd voidptr, msg u32, wp usize, lp isize) isize
fn C.CreateWindowExW(ex u32, cls &u16, title &u16, style u32, x int, y int, w int, h int, parent voidptr, menu voidptr, inst voidptr, param voidptr) voidptr
fn C.ShowWindow(hwnd voidptr, cmd int) int
fn C.DestroyWindow(hwnd voidptr) int
fn C.GetClientRect(hwnd voidptr, rect &int) int
fn C.GetDC(hwnd voidptr) voidptr
fn C.ReleaseDC(hwnd voidptr, hdc voidptr) int
fn C.ChoosePixelFormat(hdc voidptr, ppfd &C.PIXELFORMATDESCRIPTOR) int
fn C.SetPixelFormat(hdc voidptr, format int, ppfd &C.PIXELFORMATDESCRIPTOR) int
fn C.SwapBuffers(hdc voidptr) int
fn C.PeekMessageW(msg &C.MSG, hwnd voidptr, min u32, max u32, remove u32) int
fn C.TranslateMessage(msg &C.MSG) int
fn C.DispatchMessageW(msg &C.MSG) isize
fn C.wglCreateContext(hdc voidptr) voidptr
fn C.wglMakeCurrent(hdc voidptr, ctx voidptr) int
fn C.wglDeleteContext(ctx voidptr) int
fn C.wglGetProcAddress(name &char) voidptr
fn C.glGetString(name u32) &u8
fn C.vcore_win_reset()
fn C.vcore_win_mark_closed()
fn C.vcore_win_closed() int
fn C.vcore_in_ptr() &C.VcoreInput
fn C.vcore_pending_get() u16
fn C.vcore_pending_set(v u16)
fn C.vcore_dpi_get() int
fn C.vcore_dpi_set(d int)
fn C.vcore_cursor_set(idc int)
fn C.vcore_cursor_load() voidptr
fn C.vcore_set_dpi_aware()
fn C.vcore_system_dpi() int
fn C.vcore_dpi_for_window(hwnd voidptr) int
fn C.vcore_adjust_rect(rect &int, style u32, dpi int)
fn C.vcore_on_dpi_changed(hwnd voidptr, wp usize, lp isize)
fn C.SetCapture(hwnd voidptr) voidptr
fn C.ReleaseCapture() int
fn C.GetKeyState(vk int) i16
fn C.SetCursor(c voidptr) voidptr

// win_state.h'deki VcoreInput ile aynı düzen; alanlar yalnızca bu dosyada okunur/yazılır.
@[typedef]
struct C.VcoreInput {
mut:
	mouse_x    int
	mouse_y    int
	down       [3]int
	pressed    [3]int
	released   [3]int
	wheel      f32
	vkeys      [16]u16
	vkey_count int
	vkey_repeat [16]int
	chars      [32]u32
	char_count int
	ctrl       int
	shift      int
	alt        int
	space      int
	focused    int
}

const wm_close = 0x0010
const wm_setcursor = 0x0020
const wm_dpichanged = 0x02E0
const cw_usedefault = -2147483648
const ws_overlappedwindow = 0x00CF0000
const class_name = 'VCorePlatformWindow'

// Süreç başına bir pencere. Tutamaçlar nil ise ilgili kaynak yoktur; close her durumda güvenlidir.
pub struct Window {
mut:
	hwnd  voidptr
	hdc   voidptr
	hglrc voidptr
}

// WNDPROC. WM_CLOSE pencereyi yok etmez; çağıran close() ile kapatır, poll bayrağı görür.
fn wnd_proc(hwnd voidptr, msg u32, wp usize, lp isize) isize {
	if msg == wm_close {
		C.vcore_win_mark_closed()
		return 0
	}
	if msg == wm_dpichanged {
		C.vcore_on_dpi_changed(hwnd, wp, lp)
		return 0
	}
	if msg == wm_setcursor && (lp & 0xFFFF) == 1 { // HTCLIENT
		C.SetCursor(C.vcore_cursor_load())
		return 1
	}
	// F10 ve tek Alt: DefWindowProc menü modal döngüsünü (SC_KEYMENU) açar ve kare döngüsü donar.
	if (msg == 0x0104 || msg == 0x0105) && (wp == 0x79 || wp == 0x12) {
		record_input(hwnd, msg, wp, lp)
		return 0
	}
	if msg == 0x0112 && (wp & 0xFFF0) == 0xF100 { // WM_SYSCOMMAND SC_KEYMENU
		return 0
	}
	record_input(hwnd, msg, wp, lp)
	return C.DefWindowProcW(hwnd, msg, wp, lp)
}

fn key_down(vk int) int {
	return if C.GetKeyState(vk) < 0 { 1 } else { 0 }
}

// Düğme durumu; ilk basışta yakalama, son bırakışta serbest bırakma.
fn set_button(hwnd voidptr, b int, is_down bool) {
	mut p := C.vcore_in_ptr()
	if is_down {
		p.down[b] = 1
		p.pressed[b] = 1
		C.SetCapture(hwnd)
	} else {
		p.down[b] = 0
		p.released[b] = 1
		if p.down[0] + p.down[1] + p.down[2] == 0 {
			C.ReleaseCapture()
		}
	}
}

// Win32 olaylarını C static'e yazar; wnd_proc her mesajda çağırır (DefWindowProc ayrıca çalışır).
fn record_input(hwnd voidptr, msg u32, wp usize, lp isize) {
	mut p := C.vcore_in_ptr()
	match msg {
		0x0200 { // WM_MOUSEMOVE: LOWORD/HIWORD işaretli; ekran dışı koordinat negatif olabilir
			p.mouse_x = int(i16(lp & 0xFFFF))
			p.mouse_y = int(i16((lp >> 16) & 0xFFFF))
		}
		0x0201 { set_button(hwnd, 0, true) }
		0x0202 { set_button(hwnd, 0, false) }
		0x0204 { set_button(hwnd, 1, true) }
		0x0205 { set_button(hwnd, 1, false) }
		0x0207 { set_button(hwnd, 2, true) }
		0x0208 { set_button(hwnd, 2, false) }
		0x020A { // WM_MOUSEWHEEL: delta wParam'ın işaretli üst kelimesinde, çentik 120
			p.wheel += f32(i16((wp >> 16) & 0xFFFF)) / 120.0
		}
		0x0100, 0x0104 { // WM_KEYDOWN, WM_SYSKEYDOWN; tekrarlar (bit 30) repeat bayrağıyla girer
			if p.vkey_count < 16 {
				p.vkeys[p.vkey_count] = u16(wp)
				p.vkey_repeat[p.vkey_count] = int((lp >> 30) & 1)
				p.vkey_count++
			}
		}
		0x0102 { // WM_CHAR: UTF-16 birimi; vekil çifti tek kod noktasına birleşir
			pend, cp := utf16_combine(C.vcore_pending_get(), u16(wp))
			C.vcore_pending_set(pend)
			if c := cp {
				if p.char_count < 32 {
					p.chars[p.char_count] = c
					p.char_count++
				}
			}
		}
		0x0007 { p.focused = 1 } // WM_SETFOCUS
		0x0008 { // WM_KILLFOCUS: bırakılmamış düğmeler kapanır
			for b in 0 .. 3 {
				if p.down[b] != 0 {
					p.down[b] = 0
					p.released[b] = 1
				}
			}
			C.ReleaseCapture()
			p.focused = 0
		}
		else {}
	}
	if msg == 0x0200 || msg == 0x0100 || msg == 0x0104 || (msg >= 0x0201 && msg <= 0x0208) {
		p.ctrl = key_down(0x11) // VK_CONTROL
		p.shift = key_down(0x10) // VK_SHIFT
		p.alt = key_down(0x12) // VK_MENU
		p.space = key_down(0x20) // VK_SPACE: tutulan durum (pan için)
	}
}

// Pencere, piksel formatı ve 3.3 core context. Hata durumunda kısmi kaynaklar serbest bırakılır.
pub fn Window.new(cfg WindowConfig) !Window {
	C.vcore_win_reset()
	if cfg.dpi_aware {
		C.vcore_set_dpi_aware()
	}
	inst := C.GetModuleHandleW(unsafe { nil })
	cls := class_name.to_wide()
	// Sınıf zaten kayıtlıysa RegisterClassExW 0 döner; CreateWindowExW başarısızlığı bunu yakalar.
	wc := C.WNDCLASSEXW{
		cbSize:        u32(sizeof(C.WNDCLASSEXW))
		style:         0x20 // CS_OWNDC
		lpfnWndProc:   voidptr(wnd_proc)
		hInstance:     inst
		hCursor:       C.vcore_cursor_load()
		lpszClassName: cls
	}
	C.RegisterClassExW(&wc)

	// dpi_aware false: boyut doğrudan fiziksel piksel, ölçek 1.0 (96).
	dpi := if cfg.dpi_aware { C.vcore_system_dpi() } else { 96 }
	mut rc := [0, 0, cfg.width * dpi / 96, cfg.height * dpi / 96]!
	C.vcore_adjust_rect(&rc[0], ws_overlappedwindow, dpi)
	ow := rc[2] - rc[0]
	oh := rc[3] - rc[1]
	title := cfg.title.to_wide()
	hwnd := C.CreateWindowExW(0, cls, title, ws_overlappedwindow, cw_usedefault,
		cw_usedefault, ow, oh, unsafe { nil }, unsafe { nil }, inst, unsafe { nil })
	unsafe {
		free(voidptr(title))
		free(voidptr(cls))
	}
	mut w := Window{
		hwnd: hwnd
	}
	if hwnd == unsafe { nil } {
		return error('CreateWindowExW basarisiz')
	}
	C.vcore_dpi_set(if cfg.dpi_aware { C.vcore_dpi_for_window(hwnd) } else { 96 })
	w.hdc = C.GetDC(hwnd)

	mut pfd := C.PIXELFORMATDESCRIPTOR{
		nSize:      u16(sizeof(C.PIXELFORMATDESCRIPTOR))
		nVersion:   1
		dwFlags:    0x4 | 0x20 | 0x1 // DRAW_TO_WINDOW | SUPPORT_OPENGL | DOUBLEBUFFER
		cColorBits: 32
		cDepthBits: 24
	}
	pf := C.ChoosePixelFormat(w.hdc, &pfd)
	if pf == 0 || C.SetPixelFormat(w.hdc, pf, &pfd) == 0 {
		w.close()
		return error('piksel formati ayarlanamadi')
	}

	// Core context için önce legacy context gerekir: wglCreateContextAttribsARB onun içinden yüklenir.
	legacy := C.wglCreateContext(w.hdc)
	if legacy == unsafe { nil } {
		w.close()
		return error('wglCreateContext basarisiz')
	}
	w.hglrc = legacy
	if C.wglMakeCurrent(w.hdc, legacy) == 0 {
		w.close()
		return error('wglMakeCurrent basarisiz')
	}
	p := gl_proc(c'wglCreateContextAttribsARB')
	if p == unsafe { nil } {
		w.close()
		return error('wglCreateContextAttribsARB yok')
	}
	create := unsafe { FnCreateCtx(p) }
	attrs := [0x2091, 3, 0x2092, 3, 0x9126, 0x1, 0]!
	core := create(w.hdc, unsafe { nil }, &attrs[0])
	if core == unsafe { nil } {
		w.close()
		return error('3.3 core context olusturulamadi')
	}
	if C.wglMakeCurrent(w.hdc, core) == 0 {
		C.wglDeleteContext(core)
		w.close()
		return error('core context current yapilamadi')
	}
	C.wglDeleteContext(legacy)
	w.hglrc = core

	if cfg.visible {
		C.ShowWindow(hwnd, 5) // SW_SHOW
	}
	return w
}

// Context, DC ve pencereyi serbest bırakır. Tekrar çağrılabilir.
pub fn (mut w Window) close() {
	if w.hglrc != unsafe { nil } {
		C.wglMakeCurrent(unsafe { nil }, unsafe { nil })
		C.wglDeleteContext(w.hglrc)
		w.hglrc = unsafe { nil }
	}
	if w.hdc != unsafe { nil } {
		C.ReleaseDC(w.hwnd, w.hdc)
		w.hdc = unsafe { nil }
	}
	if w.hwnd != unsafe { nil } {
		C.DestroyWindow(w.hwnd)
		w.hwnd = unsafe { nil }
	}
}

// Bekleyen mesajları boşaltır. Kapanış isteği (WM_CLOSE veya WM_QUIT) görülürse false döner.
pub fn (mut w Window) poll() bool {
	mut msg := C.MSG{}
	for C.PeekMessageW(&msg, unsafe { nil }, 0, 0, 0x0001) != 0 { // PM_REMOVE
		if msg.message == 0x0012 { // WM_QUIT
			C.vcore_win_mark_closed()
		}
		C.TranslateMessage(&msg)
		C.DispatchMessageW(&msg)
	}
	return C.vcore_win_closed() == 0
}

// Bu karenin girdisini döner ve kare başı alanları sıfırlar (pressed, released, wheel, vkeys, chars).
pub fn (mut w Window) input() InputFrame {
	mut p := C.vcore_in_ptr()
	mut f := InputFrame{
		mouse_x:    p.mouse_x
		mouse_y:    p.mouse_y
		wheel:      p.wheel
		vkey_count: p.vkey_count
		char_count: p.char_count
		ctrl:       p.ctrl != 0
		shift:      p.shift != 0
		alt:        p.alt != 0
		space:      p.space != 0
		focused:    p.focused != 0
	}
	for i in 0 .. 3 {
		f.down[i] = p.down[i] != 0
		f.pressed[i] = p.pressed[i] != 0
		f.released[i] = p.released[i] != 0
		p.pressed[i] = 0
		p.released[i] = 0
	}
	for i in 0 .. p.vkey_count {
		f.vkeys[i] = p.vkeys[i]
		f.vkey_repeat[i] = p.vkey_repeat[i] != 0
	}
	for i in 0 .. p.char_count {
		f.chars[i] = p.chars[i]
	}
	p.wheel = 0
	p.vkey_count = 0
	p.char_count = 0
	return f
}

// Ölçek = pencere DPI / 96; 1.0 DPI-farkında olmayan süreçte.
pub fn (w &Window) dpi_scale() f32 {
	return f32(C.vcore_dpi_get()) / 96.0
}

// İmleç, WM_SETCURSOR istemci alanında iken uygulanır.
pub fn (mut w Window) set_cursor(c Cursor) {
	C.vcore_cursor_set(cursor_idc(c))
}

pub fn (w &Window) swap() {
	C.SwapBuffers(w.hdc)
}

// İstemci alanı boyutu (piksel).
pub fn (w &Window) size() (int, int) {
	mut rc := [0, 0, 0, 0]!
	C.GetClientRect(w.hwnd, &rc[0])
	return rc[2] - rc[0], rc[3] - rc[1]
}

pub fn (w &Window) gl_version() string {
	p := C.glGetString(0x1F02) // GL_VERSION
	if p == unsafe { nil } {
		return ''
	}
	return unsafe { cstring_to_vstring(&char(p)) }
}

// wglGetProcAddress sarmalayıcısı. Windows'un döndürdüğü 0, 1, 2, 3 ve -1 hata değerleridir.
pub fn gl_proc(name &char) voidptr {
	p := C.wglGetProcAddress(name)
	v := u64(p)
	if v <= 3 || v == max_u64 {
		return unsafe { nil }
	}
	return p
}
