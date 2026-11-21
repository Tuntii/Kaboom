module memory

#include "@VMODROOT/memory/heapcount.h"

fn C.vcore_heap_count() u64
fn C.vcore_heap_free_count() u64

// Şu ana kadarki V heap tahsis sayısı; -d track_heap yoksa 0 kalır.
pub fn heap_alloc_count() u64 {
	return C.vcore_heap_count()
}

// Canlı tahsis sayısı: tahsisler eksi serbest bırakmalar. Sızıntı ölçümü için.
pub fn heap_live_count() i64 {
	return i64(C.vcore_heap_count()) - i64(C.vcore_heap_free_count())
}

pub fn heap_tracking_enabled() bool {
	$if track_heap ? {
		return true
	}
	return false
}
