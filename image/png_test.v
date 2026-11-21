module image

import os
import memory

// Yalnızca bu dosyanın ürettiği stored deflate PNG'lerini çözer. Chunk CRC'lerini ve Adler-32'yi doğrular.
fn decode_stored_png(png []u8) !(int, int, []u8) {
	sig := [u8(0x89), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
	if png.len < 8 || png[..8] != sig {
		return error('imza yok')
	}
	mut pos := 8
	mut width := 0
	mut height := 0
	mut idat := []u8{}
	mut saw_iend := false
	for pos + 12 <= png.len {
		len := int(u32(png[pos]) << 24 | u32(png[pos + 1]) << 16 | u32(png[pos + 2]) << 8 | u32(png[pos + 3]))
		typ := png[pos + 4..pos + 8]
		data_start := pos + 8
		data_end := data_start + len
		if data_end + 4 > png.len {
			return error('chunk taşıyor')
		}
		data := png[data_start..data_end]
		stored_crc := u32(png[data_end]) << 24 | u32(png[data_end + 1]) << 16 | u32(png[data_end + 2]) << 8 | u32(png[data_end + 3])
		if stored_crc != crc32(png[pos + 4..data_end]) {
			return error('chunk CRC hatalı')
		}
		match typ.bytestr() {
			'IHDR' {
				width = int(u32(data[0]) << 24 | u32(data[1]) << 16 | u32(data[2]) << 8 | u32(data[3]))
				height = int(u32(data[4]) << 24 | u32(data[5]) << 16 | u32(data[6]) << 8 | u32(data[7]))
			}
			'IDAT' {
				idat << data
			}
			'IEND' {
				saw_iend = true
			}
			else {}
		}
		pos = data_end + 4
	}
	if !saw_iend {
		return error('IEND yok')
	}
	// zlib başlığı 2 bayt, sonda Adler-32 4 bayt.
	if idat.len < 6 || idat[0] != 0x78 || idat[1] != 0x01 {
		return error('zlib başlığı hatalı')
	}
	mut raw := []u8{}
	mut p := 2
	for {
		header := idat[p]
		len := int(u32(idat[p + 1]) | u32(idat[p + 2]) << 8)
		nlen := int(u32(idat[p + 3]) | u32(idat[p + 4]) << 8)
		if nlen != (len ^ 0xFFFF) {
			return error('NLEN ~LEN değil')
		}
		p += 5
		raw << idat[p..p + len]
		p += len
		if (header >> 1) & 0x3 != 0 {
			return error('stored olmayan blok')
		}
		if header & 1 == 1 {
			break
		}
	}
	adler := u32(idat[p]) << 24 | u32(idat[p + 1]) << 16 | u32(idat[p + 2]) << 8 | u32(idat[p + 3])
	if adler != adler32(raw) {
		return error('Adler-32 hatalı')
	}
	row := width * 4
	mut pixels := []u8{cap: row * height}
	for r in 0 .. height {
		base := r * (row + 1)
		if raw[base] != 0 {
			return error('filtre baytı 0 değil')
		}
		pixels << raw[base + 1..base + 1 + row]
	}
	return width, height, pixels
}

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
	w, h, pixels := decode_stored_png(png) or {
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
	_, _, pixels := decode_stored_png(png) or {
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
	dw, dh, pixels := decode_stored_png(png) or {
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
	_, _, pixels := decode_stored_png(bytes) or {
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
