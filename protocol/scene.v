module protocol

import math
import strings
import ecs
import winfile

// strtof std sınıfıdır, V sarmalayıcısı yoktur.
fn C.strtof(s &char, endp voidptr) f32

// En kısa geri-dönüşlü f32 metni. Kural: |v| < 1e7 ve tamsayı ise tam sayı olarak (100, 9999999);
// aksi halde p = 1..9 için %.*g denenir ve strtof ile bit-eşit geri okunan ilk p kullanılır
// (1/3 → 0.33333334, 1e7 → 1e+07). Sonsuz ve NaN JSON'da olmadığı için metin olarak döner (inf, -inf, nan).
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
	// Tamsayılar sabit noktada yazılır: %g 100'ü "1e+02" diye yazar, bu da bir tamsayı için okunaksızdır.
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
			// Kayıt id'leri 0..count arasındadır: eksik bileşen ya da değer bir iç hatadır, sessizce atlanmaz.
			schema := reg.component(id) or {
				assert false, 'registry has no component ${id} (entity ${u64(e)})'
				return ''
			}
			assert scene_ident(schema.name)
			if !first_comp {
				b.write_u8(`,`)
			}
			first_comp = false
			b.write_string('"${schema.name}":{')
			mut first_field := true
			for fi, f in schema.fields {
				if f.readonly {
					continue
				}
				assert f.typ == .f32_, 'non-f32 field ${schema.name}.${f.name} not supported by .vscene v1'
				assert scene_ident(f.name)
				bits := w.get_field(e, id, u16(fi)) or {
					assert false, 'entity ${u64(e)} has no value for ${schema.name}.${f.name}'
					return ''
				}
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

// Atomik yazım: önce <path>.tmp (yazılamazsa winfile tmp'yi siler), sonra yerine taşınır.
// Taşıma başarısızsa tmp silinir; var olan path bu noktaya kadar dokunulmaz.
fn save_scene_atomic(path string, text string) ! {
	tmp := path + '.tmp'
	winfile.write_file(tmp, text.bytes())!
	winfile.replace_file(tmp, path)!
}
