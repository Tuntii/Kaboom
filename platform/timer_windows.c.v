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
