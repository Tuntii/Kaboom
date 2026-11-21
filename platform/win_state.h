#ifndef VCORE_PLATFORM_WIN_STATE_H
#define VCORE_PLATFORM_WIN_STATE_H

// Pencere kapanış bayrağı ve QPC frekansı. V modül globalleri -enable-globals ister; bu yüzden
// durum C static'lerinde. Bayrak süreç başına tek pencere varsayar; Window.new sıfırlar.
#include <windows.h>

static int vcore_win_closed_flag = 0;

static void vcore_win_reset(void) { vcore_win_closed_flag = 0; }
static void vcore_win_mark_closed(void) { vcore_win_closed_flag = 1; }
static int vcore_win_closed(void) { return vcore_win_closed_flag; }

// Frekans değişmez; ilk çağrıda okunur, sonra önbellekten döner.
static unsigned long long vcore_qpc_freq(void) {
	static unsigned long long f = 0;
	if (f == 0) {
		QueryPerformanceFrequency((LARGE_INTEGER *)&f);
	}
	return f;
}

#endif
