module image

import os
import memory

// PNG yazımı tahsis sızıntısı yapmamalı: ısınma çağrısından sonra 10 yazım canlı tahsisi en çok 2 artırır.
fn test_write_png_does_not_leak() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap yok; PNG sızıntı testi koşmadı')
		return
	}
	tmp := os.join_path(os.temp_dir(), 'vcore_png_leak_${os.getpid()}.png')
	px := []u8{len: 64 * 64 * 4, init: u8(index % 251)}
	write_png(tmp, 64, 64, px, true) or { panic(err) }
	before := memory.heap_live_count()
	for _ in 0 .. 10 {
		write_png(tmp, 64, 64, px, true) or { panic(err) }
	}
	growth := memory.heap_live_count() - before
	os.rm(tmp) or {}
	assert growth <= 2, 'PNG canli tahsis artisi: ${growth}'
}
