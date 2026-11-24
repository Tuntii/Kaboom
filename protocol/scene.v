module protocol

import math
import strings
import ecs

// Kısa f32 metni için C kütüphane fonksiyonları: snprintf ve strtof std sınıfıdır, V sarmalayıcısı yoktur.
fn C.strtof(s &char, endp voidptr) f32
fn C._wfopen(filename &u16, mode &u16) voidptr
fn C.MultiByteToWideChar(cp u32, flags u32, src &char, srclen int, dst &u16, dstlen int) int
fn C.fwrite(ptr voidptr, size usize, n usize, stream voidptr) usize
fn C.fclose(stream voidptr) int
fn C.MoveFileExW(existing &u16, new &u16, flags u32) bool
fn C.DeleteFileW(name &u16) bool

// En kısa geri-dönüşlü ondalık metni (p = 1..9 anlamlı basamak). Sonsuz ve NaN JSON'da olmadığı için metin olarak döner.
pub fn f32_text(v f32) string {
	x := f64(v)
	if v != v {
		return 'nan'
	}
	if x > max_f32 {
		return 'inf'
	}
	if x < -max_f32 {
		return '-inf'
	}
	if math.f32_bits(v) == 0x80000000 {
		return '-0'
	}
	// Küçük tamsayılar sabit noktada yazılır: %g 100'ü "1e+02" diye yazar, bu da bir tamsayı için okunaksızdır.
	if x == math.floor(x) && math.abs(x) < 1e7 {
		return '${i64(x)}'
	}
	mut buf := [32]u8{}
	for p in 1 .. 10 {
		unsafe {
			C.snprintf(&char(&buf[0]), 32, &char('%.*g'.str), p, x)
		}
		text := unsafe { tos(&u8(&buf[0]), int(C.strlen(&char(&buf[0])))) }
		// strtof yuvarlamayı IEEE ile yapar: bit-eşit geri okunan ilk p en kısa metindir.
		if math.f32_bits(C.strtof(&char(text.str), unsafe { nil })) == math.f32_bits(v) {
			return text.clone()
		}
	}
	// Dokuz basamak her f32'yi geri döndürür; buraya gelinmez.
	return '${x}'
}

// Bileşen ve alan adları tanımlayıcıdır: JSON'a kaçışsız yazılır.
fn scene_ident(name string) bool {
	if name.len == 0 {
		return false
	}
	for c in name {
		if !(c.is_letter() || c.is_digit() || c == `_`) {
			return false
		}
	}
	return true
}

// .vscene metni: canlı varlıklar index sırasıyla, bileşenler kayıt sırasıyla, alanlar şema sırasıyla.
// readonly alanlar (prev_*) yazılmaz: sistem her kare yeniden hesaplar. Yalnız f32 alanlar yazılır (entity.get ile aynı).
pub fn scene_text(w &ecs.World, reg &ecs.Registry) string {
	mut b := strings.new_builder(256)
	alloc := w.entities()
	b.write_string('{"format":"vscene","version":1,"capacity":${w.capacity()},"entities":[')
	b.write_u8(`\n`)
	mut first := true
	for i in 0 .. alloc.high_water() {
		e := alloc.handle_at(i) or { continue }
		if !first {
			b.write_string(',\n')
		}
		first = false
		b.write_string('{"components":{')
		mut first_comp := true
		for id in u16(0) .. reg.count() {
			if !w.has(e, id) {
				continue
			}
			schema := reg.component(id) or { continue }
			assert scene_ident(schema.name)
			if !first_comp {
				b.write_u8(`,`)
			}
			first_comp = false
			b.write_string('"${schema.name}":{')
			mut first_field := true
			for fi, f in schema.fields {
				if f.readonly || f.typ != .f32_ {
					continue
				}
				assert scene_ident(f.name)
				bits := w.get_field(e, id, u16(fi)) or { continue }
				if !first_field {
					b.write_u8(`,`)
				}
				first_field = false
				t := f32_text(math.f32_from_bits(u32(bits)))
				// Sonsuz ve NaN JSON sayısı değildir: tırnaklı metin olarak yazılır.
				if t == 'inf' || t == '-inf' || t == 'nan' {
					b.write_string('"${f.name}":"${t}"')
				} else {
					b.write_string('"${f.name}":${t}')
				}
			}
			b.write_u8(`}`)
		}
		b.write_string('}}')
	}
	if !first {
		b.write_u8(`\n`)
	}
	b.write_string(']}\n')
	return b.str()
}

// Dosyayı UTF-16 yolla açıp yazar (image/png.v'deki desen). Başarısızlıkta hata döner; çağıran tmp'yi siler.
fn write_wide_file(wpath &u16, data string) ! {
	mut wmode := [3]u16{}
	wmode[0] = u16(`w`)
	wmode[1] = u16(`b`)
	f := C._wfopen(wpath, &wmode[0])
	if f == unsafe { nil } {
		return error('dosya açılamadı')
	}
	written := C.fwrite(data.str, 1, usize(data.len), f)
	C.fclose(f)
	if written != usize(data.len) {
		return error('dosya yazılamadı')
	}
}

// Atomik yazım: önce <path>.tmp, sonra MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH ile yerine taşınır.
// Her başarısızlıkta tmp silinir; var olan path bu noktaya kadar dokunulmaz.
fn save_scene_atomic(path string, text string) ! {
	tmp := path + '.tmp'
	mut wtmp := [1024]u16{}
	mut wpath := [1024]u16{}
	n_tmp := C.MultiByteToWideChar(65001, 0, &char(tmp.str), tmp.len, &wtmp[0], 1023)
	n_path := C.MultiByteToWideChar(65001, 0, &char(path.str), path.len, &wpath[0], 1023)
	if n_tmp <= 0 || n_path <= 0 {
		return error('yol UTF-16e çevrilemedi')
	}
	write_wide_file(&wtmp[0], text) or {
		C.DeleteFileW(&wtmp[0])
		return error('geçici dosya yazılamadı')
	}
	// MOVEFILE_REPLACE_EXISTING 0x1, MOVEFILE_WRITE_THROUGH 0x8.
	if !C.MoveFileExW(&wtmp[0], &wpath[0], 0x9) {
		C.DeleteFileW(&wtmp[0])
		return error('dosya yerine taşınamadı')
	}
}
