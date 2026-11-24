#ifndef VCORE_PLATFORM_WIN_STATE_H
#define VCORE_PLATFORM_WIN_STATE_H

// Pencere kapanış bayrağı, girdi durumu, DPI ve QPC frekansı. V modül globalleri -enable-globals
// ister; bu yüzden durum C static'lerinde. Süreç başına tek pencere varsayar; Window.new sıfırlar.
#include <windows.h>

static int vcore_win_closed_flag = 0;

// Olay yazımı wnd_proc'ta (V), okuma input() ile; alanlar V tarafında int olarak erişilir.
typedef struct {
	int mouse_x;
	int mouse_y;
	int down[3];
	int pressed[3];
	int released[3];
	float wheel;
	unsigned short vkeys[16];
	int vkey_count;
	int vkey_repeat[16];
	unsigned int chars[32];
	int char_count;
	int ctrl;
	int shift;
	int alt;
	int space;
	int focused;
} VcoreInput;

static VcoreInput vcore_in;
static unsigned short vcore_pending_hi = 0;
static int vcore_dpi = 96;
static int vcore_cursor_id = 32512; // IDC_ARROW

static void vcore_input_reset(void) {
	vcore_in = (VcoreInput){0};
	vcore_pending_hi = 0;
	vcore_dpi = 96;
	vcore_cursor_id = 32512;
}

static VcoreInput *vcore_in_ptr(void) { return &vcore_in; }
static unsigned short vcore_pending_get(void) { return vcore_pending_hi; }
static void vcore_pending_set(unsigned short v) { vcore_pending_hi = v; }
static int vcore_dpi_get(void) { return vcore_dpi; }
static void vcore_dpi_set(int d) { vcore_dpi = d; }
static void vcore_cursor_set(int idc) { vcore_cursor_id = idc; }
static void *vcore_cursor_load(void) { return LoadCursorW(NULL, MAKEINTRESOURCEW(vcore_cursor_id)); }

static void vcore_win_reset(void) {
	vcore_win_closed_flag = 0;
	vcore_input_reset();
}
static void vcore_win_mark_closed(void) { vcore_win_closed_flag = 1; }
static int vcore_win_closed(void) { return vcore_win_closed_flag; }
static void vcore_win_clear_closed(void) { vcore_win_closed_flag = 0; }

// Frekans değişmez; ilk çağrıda okunur. 0 dönerse 1 kabul edilir ki now_ns sıfıra bölmesin.
static unsigned long long vcore_qpc_freq(void) {
	static unsigned long long f = 0;
	if (f == 0) {
		QueryPerformanceFrequency((LARGE_INTEGER *)&f);
		if (f == 0) {
			f = 1;
		}
	}
	return f;
}

// LOGPIXELSX; süreç DPI-farkında değilse 96 döner.
static int vcore_system_dpi(void) {
	HDC dc = GetDC(NULL);
	int d = GetDeviceCaps(dc, LOGPIXELSX);
	ReleaseDC(NULL, dc);
	return d > 0 ? d : 96;
}

// user32 dışa aktarımlarının bazıları eski Windows'ta yoktur; yoksa NULL döner.
static FARPROC vcore_user32(const char *name) {
	HMODULE u = GetModuleHandleW(L"user32.dll");
	return u ? GetProcAddress(u, name) : NULL;
}

typedef BOOL(WINAPI *vcore_set_dpi_ctx_fn)(void *);
typedef UINT(WINAPI *vcore_get_dpi_win_fn)(HWND);
typedef BOOL(WINAPI *vcore_adjust_dpi_fn)(LPRECT, DWORD, BOOL, DWORD, UINT);

// PER_MONITOR_AWARE_V2 (-4); başarısızlık yok sayılır.
static void vcore_set_dpi_aware(void) {
	FARPROC f = vcore_user32("SetProcessDpiAwarenessContext");
	if (f) {
		((vcore_set_dpi_ctx_fn)f)((void *)(LONG_PTR)-4);
	}
}

static int vcore_dpi_for_window(HWND h) {
	FARPROC f = vcore_user32("GetDpiForWindow");
	int d = f ? (int)((vcore_get_dpi_win_fn)f)(h) : 0;
	return d > 0 ? d : vcore_system_dpi();
}

// r: RECT ile aynı düzen (left, top, right, bottom).
static void vcore_adjust_rect(int *r, DWORD style, int dpi) {
	FARPROC f = vcore_user32("AdjustWindowRectExForDpi");
	if (f) {
		((vcore_adjust_dpi_fn)f)((LPRECT)r, style, FALSE, 0, (UINT)dpi);
	} else {
		AdjustWindowRect((LPRECT)r, style, FALSE);
	}
}

// Önerilen dikdörtgen SetWindowPos ile uygulanır; ölçek static'te güncellenir.
static void vcore_on_dpi_changed(HWND h, WPARAM wp, LPARAM lp) {
	RECT *r = (RECT *)lp;
	vcore_dpi = LOWORD(wp);
	SetWindowPos(h, NULL, r->left, r->top, r->right - r->left, r->bottom - r->top,
		SWP_NOZORDER | SWP_NOACTIVATE);
}

#endif
