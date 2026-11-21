module image

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
	write_bytes(path, png)!
}

fn C._wfopen(filename &u16, mode &u16) voidptr
fn C.MultiByteToWideChar(cp u32, flags u32, src &char, srclen int, dst &u16, dstlen int) int
fn C.fwrite(ptr voidptr, size usize, n usize, stream voidptr) usize
fn C.fclose(stream voidptr) int

// Dosyayı UTF-16 yolla açıp yazar. os.write_file_array her çağrıda iki geniş metni serbest bırakmadan
// ayırır (vfopen -> to_wide); bu yol yığın tamponu kullanır ve sızdırmaz.
fn write_bytes(path string, data []u8) ! {
	mut wpath := [1024]u16{}
	// CP_UTF8 = 65001; kapasite bir NUL için ayrılır, dizinin kalanı sıfırdır.
	n := C.MultiByteToWideChar(65001, 0, &char(path.str), path.len, &wpath[0], 1023)
	if n <= 0 {
		return error('yol UTF-16e çevrilemedi')
	}
	mut wmode := [3]u16{}
	wmode[0] = u16(`w`)
	wmode[1] = u16(`b`)
	f := C._wfopen(&wpath[0], &wmode[0])
	if f == unsafe { nil } {
		return error('dosya açılamadı')
	}
	written := C.fwrite(data.data, 1, usize(data.len), f)
	C.fclose(f)
	if written != usize(data.len) {
		return error('dosya yazılamadı')
	}
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
