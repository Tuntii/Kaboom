module image

import winfile

// Bağımlılıksız PNG yazıcı: RGBA8, stored (sıkıştırmasız) deflate blokları. Çıktı bayt düzeyinde deterministik.

// crc32 CRC-32 (IEEE 802.3, yansıtılmış polinom 0xEDB88320). Chunk ve IEND için kullanılır.
pub fn crc32(data []u8) u32 {
	mut table := []u32{len: 256}
	defer {
		unsafe { table.free() }
	}
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

// En büyük kenar; GL maksimum doku boyutu sınıfı.
const max_side = 16384

// encode_rgba bir RGBA8 tamponunu PNG baytlarına çevirir. flip_y, GL alt-sol orijinli okumalar içindir:
// satırlar alttan üste yazılır.
pub fn encode_rgba(width int, height int, rgba []u8, flip_y bool) ![]u8 {
	// Boyut sınırı: GL üst sınırı; i64 çarpımı 32-bit int taşmasını önler.
	if width <= 0 || height <= 0 || width > max_side || height > max_side {
		return error('png: geçersiz boyut ${width}x${height}')
	}
	if i64(rgba.len) != i64(width) * i64(height) * 4 {
		return error('png: rgba uzunluğu ${rgba.len}, beklenen ${i64(width) * i64(height) * 4}')
	}
	row := width * 4
	// Ham veri: her satır için 1 filtre baytı (0) ve satır pikselleri. Geçici tamponlar çıkışta serbest bırakılır.
	mut raw := []u8{cap: (row + 1) * height}
	defer {
		unsafe { raw.free() }
	}
	for r in 0 .. height {
		src := if flip_y { height - 1 - r } else { r }
		raw << u8(0)
		raw << rgba[src * row..src * row + row]
	}
	// zlib akışı: başlık, stored bloklar, Adler-32 (BE).
	mut z := []u8{cap: raw.len + raw.len / max_stored_block * 5 + 16}
	defer {
		unsafe { z.free() }
	}
	z << u8(0x78)
	z << u8(0x01)
	mut pos := 0
	for {
		n := if raw.len - pos > max_stored_block { max_stored_block } else { raw.len - pos }
		last := pos + n == raw.len
		nlen := ~n & 0xFFFF
		z << u8(if last { 1 } else { 0 })
		z << u8(n)
		z << u8(n >> 8)
		z << u8(nlen)
		z << u8(nlen >> 8)
		z << raw[pos..pos + n]
		pos += n
		if last {
			break
		}
	}
	put_u32_be(mut z, adler32(raw))

	mut out := []u8{cap: z.len + 64}
	out << u8(0x89)
	out << u8(0x50)
	out << u8(0x4E)
	out << u8(0x47)
	out << u8(0x0D)
	out << u8(0x0A)
	out << u8(0x1A)
	out << u8(0x0A)
	mut ihdr := []u8{cap: 13}
	defer {
		unsafe { ihdr.free() }
	}
	put_u32_be(mut ihdr, u32(width))
	put_u32_be(mut ihdr, u32(height))
	// bit derinliği 8, renk tipi 6 (RGBA), sıkıştırma 0, filtre 0, interlace 0
	ihdr << u8(8)
	ihdr << u8(6)
	ihdr << u8(0)
	ihdr << u8(0)
	ihdr << u8(0)
	write_chunk(mut out, 'IHDR', ihdr)
	write_chunk(mut out, 'IDAT', z)
	write_chunk(mut out, 'IEND', []u8{})
	return out
}

// write_png encode_rgba ile PNG üretip path'e yazar. Kodlanmış tampon yazımdan sonra serbest bırakılır.
pub fn write_png(path string, width int, height int, rgba []u8, flip_y bool) ! {
	mut png := encode_rgba(width, height, rgba, flip_y)!
	defer {
		unsafe { png.free() }
	}
	winfile.write_file(path, png)!
}

fn put_u32_be(mut out []u8, v u32) {
	out << u8(v >> 24)
	out << u8(v >> 16)
	out << u8(v >> 8)
	out << u8(v)
}

// Chunk: uzunluk (BE), tür, veri, CRC-32(tür + veri) (BE). Tür dört ASCII baytı olarak doğrudan eklenir.
fn write_chunk(mut out []u8, typ string, data []u8) {
	put_u32_be(mut out, u32(data.len))
	start := out.len
	for i in 0 .. 4 {
		out << typ[i]
	}
	out << data
	put_u32_be(mut out, crc32(out[start..]))
}

// Bu modülün ürettiği stored deflate RGBA8 PNG'lerini çözer (test ve gallery ekran görüntüsü doğrulaması).
// Chunk CRC'leri ve Adler-32 doğrulanır; sınır dışı okuma hata döner.
pub fn decode_png_stored(png []u8) !(int, int, []u8) {
	sig := [u8(0x89), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
	if png.len < 8 || png[..8] != sig {
		return error('imza yok')
	}
	mut pos := 8
	mut width := i64(0)
	mut height := i64(0)
	mut idat := []u8{}
	mut saw_iend := false
	for pos + 12 <= png.len {
		// Uzunluk işaretsiz okunur: 0x80000000 üstü int'te negatife döner.
		clen := u64(u32(png[pos]) << 24 | u32(png[pos + 1]) << 16 | u32(png[pos + 2]) << 8 | u32(png[pos + 3]))
		typ := png[pos + 4..pos + 8]
		data_start := u64(pos + 8)
		if data_start + clen + 4 > u64(png.len) {
			return error('chunk taşıyor')
		}
		data_end := int(data_start + clen)
		data := png[int(data_start)..data_end]
		stored_crc := u32(png[data_end]) << 24 | u32(png[data_end + 1]) << 16 | u32(png[data_end + 2]) << 8 | u32(png[data_end + 3])
		if stored_crc != crc32(png[pos + 4..data_end]) {
			return error('chunk CRC hatalı')
		}
		match typ.bytestr() {
			'IHDR' {
				if data.len < 13 {
					return error('IHDR kısa')
				}
				width = i64(u32(data[0]) << 24 | u32(data[1]) << 16 | u32(data[2]) << 8 | u32(data[3]))
				height = i64(u32(data[4]) << 24 | u32(data[5]) << 16 | u32(data[6]) << 8 | u32(data[7]))
				// Yalnız RGBA8, sıkıştırmasız satır, filtre 0, etkileşimsiz (interlace 0) desteklenir.
				if data[8] != 8 || data[9] != 6 || data[12] != 0 {
					return error('yalnız RGBA8 ve interlace 0 desteklenir')
				}
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
	if width <= 0 || height <= 0 || width > max_side || height > max_side {
		return error('boyut geçersiz')
	}
	// zlib başlığı 2 bayt, sonda Adler-32 4 bayt.
	if idat.len < 6 || idat[0] != 0x78 || idat[1] != 0x01 {
		return error('zlib başlığı hatalı')
	}
	mut raw := []u8{}
	mut p := 2
	for {
		if p + 5 > idat.len {
			return error('zlib blok başlığı kısa')
		}
		header := idat[p]
		len := int(u32(idat[p + 1]) | u32(idat[p + 2]) << 8)
		nlen := int(u32(idat[p + 3]) | u32(idat[p + 4]) << 8)
		if nlen != (len ^ 0xFFFF) {
			return error('NLEN ~LEN değil')
		}
		p += 5
		if p + len > idat.len {
			return error('stored blok taşıyor')
		}
		raw << idat[p..p + len]
		p += len
		if (header >> 1) & 0x3 != 0 {
			return error('stored olmayan blok')
		}
		if header & 1 == 1 {
			break
		}
	}
	if p + 4 > idat.len {
		return error('Adler-32 eksik')
	}
	adler := u32(idat[p]) << 24 | u32(idat[p + 1]) << 16 | u32(idat[p + 2]) << 8 | u32(idat[p + 3])
	if adler != adler32(raw) {
		return error('Adler-32 hatalı')
	}
	// Boyutlar üst sınırla bağlı; çarpım i64'te hesaplanır ve indekslemeden önce ham veriyle karşılaştırılır.
	row := width * 4
	if i64(raw.len) < height * (row + 1) {
		return error('ham veri kısa')
	}
	w := int(width)
	h := int(height)
	row_b := w * 4
	mut pixels := []u8{cap: row_b * h}
	for r in 0 .. h {
		base := r * (row_b + 1)
		if raw[base] != 0 {
			return error('filtre baytı 0 değil')
		}
		pixels << raw[base + 1..base + 1 + row_b]
	}
	return w, h, pixels
}
