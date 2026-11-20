module memory

#include <windows.h>

fn C.VirtualAlloc(addr voidptr, size usize, typ u32, protect u32) voidptr
fn C.VirtualFree(addr voidptr, size usize, typ u32) int

// Sanal adres alanini rezerve edip taahhut eder. Basarisizlikta none doner.
pub fn reserve(size u64) ?&u8 {
	if size == 0 {
		return none
	}
	p := C.VirtualAlloc(unsafe { nil }, usize(size), u32(C.MEM_RESERVE | C.MEM_COMMIT), u32(C.PAGE_READWRITE))
	if p == unsafe { nil } {
		return none
	}
	return &u8(p)
}

// reserve ile alinmis bolgeyi serbest birakir. Basarili olursa true.
pub fn release(p &u8) bool {
	return C.VirtualFree(voidptr(p), 0, u32(C.MEM_RELEASE)) != 0
}
