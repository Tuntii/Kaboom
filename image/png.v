module image

import os

// Bağımlılıksız PNG yazıcı: RGBA8, stored (sıkıştırmasız) deflate blokları. Çıktı bayt düzeyinde deterministik.

// crc32 CRC-32 (IEEE 802.3, yansıtılmış polinom 0xEDB88320). Chunk ve IEND için kullanılır.
pub fn crc32(data []u8) u32 {
	mut table := []u32{len: 256}
	for i in 0 .. 256 {
		mut c := u32(i)
		for _ in 0 .. 8 {
			c = if c & 1 != 0 { 0xEDB88320 ^ (c >> 1) } else { c >> 1 }
		}
		table[i] = c
	}
	mut crc := u32(0xFFFFFFFF)
	for b in data {
		crc = table[(crc ^ u32(b)) & 0xFF] ^ (crc >> 8)
	}
	return crc ^ 0xFFFFFFFF
}

// adler32 Adler-32, zlib akışının sonunda yer alır.
pub fn adler32(data []u8) u32 {
	mut a := u32(1)
	mut b := u32(0)
	for x in data {
		a = (a + u32(x)) % 65521
		b = (b + a) % 65521
	}
	return (b << 16) | a
}

// Stored blok başına en çok bayt (deflate LEN alanı u16).
const max_stored_block = 65535

// encode_rgba bir RGBA8 tamponunu PNG baytlarına çevirir. flip_y, GL alt-sol orijinli okumalar içindir:
// satırlar alttan üste yazılır.
pub fn encode_rgba(width int, height int, rgba []u8, flip_y bool) ![]u8 {
	if width <= 0 || height <= 0 {
		return error('png: geçersiz boyut ${width}x${height}')
	}
	row := width * 4
	if rgba.len != row * height {
		return error('png: rgba uzunluğu ${rgba.len}, beklenen ${row * height}')
	}
	// Ham veri: her satır için 1 filtre baytı (0) ve satır pikselleri.
	mut raw := []u8{cap: (row + 1) * height}
	for r in 0 .. height {
		src := if flip_y { height - 1 - r } else { r }
		raw << u8(0)
		raw << rgba[src * row..src * row + row]
	}
	// zlib akışı: başlık, stored bloklar, Adler-32 (BE).
	mut z := []u8{cap: raw.len + raw.len / max_stored_block * 5 + 16}
	z << [u8(0x78), 0x01]
	mut pos := 0
	for {
		n := if raw.len - pos > max_stored_block { max_stored_block } else { raw.len - pos }
		last := pos + n == raw.len
		nlen := ~n & 0xFFFF
		z << [u8(if last { 1 } else { 0 }), u8(n), u8(n >> 8), u8(nlen), u8(nlen >> 8)]
		z << raw[pos..pos + n]
		pos += n
		if last {
			break
		}
	}
	put_u32_be(mut z, adler32(raw))

	mut out := []u8{cap: z.len + 64}
	out << [u8(0x89), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
	mut ihdr := []u8{cap: 13}
	put_u32_be(mut ihdr, u32(width))
	put_u32_be(mut ihdr, u32(height))
	// bit derinliği 8, renk tipi 6 (RGBA), sıkıştırma 0, filtre 0, interlace 0
	ihdr << [u8(8), 6, 0, 0, 0]
	write_chunk(mut out, 'IHDR', ihdr)
	write_chunk(mut out, 'IDAT', z)
	write_chunk(mut out, 'IEND', []u8{})
	return out
}

// write_png encode_rgba ile PNG üretip path'e yazar.
pub fn write_png(path string, width int, height int, rgba []u8, flip_y bool) ! {
	png := encode_rgba(width, height, rgba, flip_y)!
	os.write_file_array(path, png)!
}

fn put_u32_be(mut out []u8, v u32) {
	out << [u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)]
}

// Chunk: uzunluk (BE), tür, veri, CRC-32(tür + veri) (BE).
fn write_chunk(mut out []u8, typ string, data []u8) {
	put_u32_be(mut out, u32(data.len))
	start := out.len
	out << typ.bytes()
	out << data
	put_u32_be(mut out, crc32(out[start..]))
}
