module image

import os
import memory

fn test_crc32_known_vectors() {
	assert crc32('IEND'.bytes()) == 0xAE426082
	assert crc32('123456789'.bytes()) == 0xCBF43926
}

fn test_adler32_known_vector() {
	assert adler32('Wikipedia'.bytes()) == 0x11E60398
}

fn test_encode_header_and_iend() {
	png := encode_rgba(2, 1, [u8(255), 0, 0, 255, 0, 0, 255, 255], false) or {
		assert false, 'encode hata verdi: ${err}'
		return
	}
	assert png[..8] == [u8(0x89), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
	// IHDR: uzunluk 13, tür "IHDR", genişlik 2, yükseklik 1, bit derinliği 8, renk tipi 6.
	assert png[8..16] == [u8(0), 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
	assert png[16..24] == [u8(0), 0, 0, 2, 0, 0, 0, 1]
	assert png[24] == 8
	assert png[25] == 6
	assert png[png.len - 12..] == [u8(0), 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
}

fn test_round_trip_no_flip() {
	src := [u8(255), 0, 0, 255, 0, 0, 255, 255]
	png := encode_rgba(2, 1, src, false) or {
		assert false, 'encode hata verdi: ${err}'
		return
	}
	w, h, pixels := decode_png_stored(png) or {
		assert false, 'decode hata verdi: ${err}'
		return
	}
	assert w == 2
	assert h == 1
	assert pixels == src
}

fn test_flip_y_reverses_row_order() {
	// 2x2: üst satır kırmızı, alt satır mavi. flip_y ile çıktı satırları yer değiştirir.
	src := [u8(255), 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255]
	png := encode_rgba(2, 2, src, true) or {
		assert false, 'encode hata verdi: ${err}'
		return
	}
	_, _, pixels := decode_png_stored(png) or {
		assert false, 'decode hata verdi: ${err}'
		return
	}
	assert pixels == [u8(0), 0, 255, 255, 0, 0, 255, 255, 255, 0, 0, 255, 255, 0, 0, 255]
}

fn test_round_trip_multiple_stored_blocks() {
	// 200x100: ham veri 100 * 801 = 80100 bayt, yani iki stored blok (en çok 65535).
	w := 200
	h := 100
	mut src := []u8{len: w * h * 4}
	for i in 0 .. src.len {
		src[i] = u8((i * 31 + i / 7) & 0xFF)
	}
	png := encode_rgba(w, h, src, false) or {
		assert false, 'encode hata verdi: ${err}'
		return
	}
	dw, dh, pixels := decode_png_stored(png) or {
		assert false, 'decode hata verdi: ${err}'
		return
	}
	assert dw == w
	assert dh == h
	assert pixels == src
}

fn test_encode_rejects_bad_length() {
	mut failed := false
	encode_rgba(2, 1, [u8(1), 2, 3], false) or { failed = true }
	assert failed
}

fn test_encode_rejects_non_positive_size() {
	mut failed := false
	encode_rgba(0, 1, []u8{}, false) or { failed = true }
	assert failed
}

fn test_write_png_creates_file() {
	path := os.join_path(os.temp_dir(), 'vcore_image_png_test.png')
	write_png(path, 1, 1, [u8(1), 2, 3, 4], false) or {
		assert false, 'write_png hata verdi: ${err}'
		return
	}
	bytes := os.read_bytes(path) or {
		assert false, 'okunamadı: ${err}'
		return
	}
	os.rm(path) or {}
	assert bytes[..8] == [u8(0x89), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
	_, _, pixels := decode_png_stored(bytes) or {
		assert false, 'decode hata verdi: ${err}'
		return
	}
	assert pixels == [u8(1), 2, 3, 4]
}

fn test_encode_rejects_overflowing_width() {
	// 2^30 * 1 * 4 bayt 32-bit int'te taşar; boş tampon yine hata vermeli.
	mut failed := false
	encode_rgba(1073741824, 1, []u8{}, false) or { failed = true }
	assert failed
}

fn test_encode_rejects_width_over_limit() {
	mut failed := false
	encode_rgba(16385, 1, []u8{len: 16385 * 4}, false) or { failed = true }
	assert failed
}

fn test_encode_rejects_rgba_length_off_by_one() {
	mut short_failed := false
	encode_rgba(2, 2, []u8{len: 15}, false) or { short_failed = true }
	assert short_failed
	mut long_failed := false
	encode_rgba(2, 2, []u8{len: 17}, false) or { long_failed = true }
	assert long_failed
}

// Sızıntı ölçümünün (png_leak_test.v) dayandığı sayaç: tahsis yapılmadan canlı sayı değişmemeli.
// Bu test aynı zamanda memory modülünü bu derlemeye bağlar (-d track_heap kancaları için).
fn test_heap_live_count_is_stable_without_allocation() {
	before := memory.heap_live_count()
	after := memory.heap_live_count()
	assert before == after
}

fn decodes_ok(b []u8) bool {
	decode_png_stored(b) or { return false }
	return true
}

// Bozuk girdi hata döner ya da panik yapmaz: imza, kırpılmış dosya ve CRC bozulması.
fn test_decode_png_stored_rejects_bad_input() {
	png := encode_rgba(2, 2, []u8{len: 16, init: u8(index)}, false) or { panic(err) }
	assert decodes_ok(png)
	assert !decodes_ok([u8(1), 2, 3])
	assert !decodes_ok(png[..png.len - 10])
	mut bad := png.clone()
	bad[bad.len - 20] ^= 0xFF
	assert !decodes_ok(bad)
}
