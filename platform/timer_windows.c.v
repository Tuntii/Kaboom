module platform

#include "@VMODROOT/platform/win_state.h"

fn C.QueryPerformanceCounter(counter &u64) int
fn C.vcore_qpc_freq() u64

// Monoton duvar saati, ns cinsinden.
pub fn now_ns() u64 {
	mut c := u64(0)
	C.QueryPerformanceCounter(&c)
	return qpc_to_ns(c, C.vcore_qpc_freq())
}

#flag -lwinmm
#include <mmsystem.h>

fn C.timeBeginPeriod(period u32) u32
fn C.timeEndPeriod(period u32) u32

// Sistem zamanlayıcısını 1 ms'e çeker; yoksa time.sleep(1ms) ~15 ms'e yuvarlanır. Çağıran eşleşen end'i çağırmalı.
pub fn begin_timer_period() {
	C.timeBeginPeriod(1)
}

pub fn end_timer_period() {
	C.timeEndPeriod(1)
}
