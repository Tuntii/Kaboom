module editor

import ecs
import math

// strtof: protocol/scene.v ile aynı C bağlaması (yuvarlama IEEE ile; metin → f32 bit-eşit kontrolü).
fn C.strtof(s &char, endp voidptr) f32

// İstek satırı kurucusu: sabit tampon, tahsis yok. Yanıt handle_from'un istek arenasında yaşar.
const req_cap = 1024

// f32 en büyük sonlu değeri: bunun ötesi (ve NaN, inf) JSON sayısı değildir, istek kurulmaz.
const editor_f32_max = f64(3.4028234663852886e+38)

pub struct ReqBuf {
mut:
	buf    [req_cap]u8
	n      int
	count  int
	failed bool
	depth  int
	saved  [8]int // iç nesnelerin dış düzey sayaçları (obj_begin/obj_end)
}

// Yeni istek: {"jsonrpc":"2.0","id":1,"method":"<m>","params":{...}}. Sayılar ve id protokolün kabul ettiği biçimdedir.
pub fn (mut r ReqBuf) begin(method string) {
	r.n = 0
	r.count = 0
	r.depth = 0
	r.failed = false
	r.put('{"jsonrpc":"2.0","id":1,"method":"')
	r.put(method)
	r.put('","params":{')
}

// İç nesne: "key":{ ... }; obj_end dış düzeye döner. En fazla 8 düzey (saved); daha derin çağrı yoktur.
pub fn (mut r ReqBuf) obj_begin(key string) {
	r.sep()
	r.put('"')
	r.put(key)
	r.put('":{')
	r.saved[r.depth] = r.count
	r.depth++
	r.count = 0
}

pub fn (mut r ReqBuf) obj_end() {
	r.put_byte(`}`)
	r.depth--
	r.count = r.saved[r.depth]
}

pub fn (mut r ReqBuf) param_int(key string, v int) {
	r.sep()
	r.put('"')
	r.put(key)
	r.put('":')
	if v < 0 {
		r.put_byte(`-`)
	}
	r.put_uint(if v < 0 { u64(-i64(v)) } else { u64(v) })
}

// Varlık kimliği: 48 bitlik işaretsiz tamsayı (indeks ve nesil), ondalık.
pub fn (mut r ReqBuf) param_entity(key string, e ecs.EntityID) {
	r.sep()
	r.put('"')
	r.put(key)
	r.put('":')
	r.put_uint(u64(e))
}

// f32 değeri, protocol.f32_text ile aynı metin: en kısa, bit-eşit geri okunan ondalık (1..9 basamak). Tahsissiz
// (yığın tamponu, strtof). Sonlu olmayan değer istek kurmaz.
pub fn (mut r ReqBuf) param_f32(key string, v f32) {
	x := f64(v)
	if x != x || x > editor_f32_max || x < -editor_f32_max {
		r.failed = true
		return
	}
	r.sep()
	r.put('"')
	r.put(key)
	r.put('":')
	// Tam sayılar sabit noktada (%g 100'ü 1e+02 yazar); -0 ayrı tutulur (protocol.f32_text ile aynı).
	if x == math.floor(x) && math.abs(x) < 1e7 {
		if math.f32_bits(v) == 0x80000000 {
			r.put('-0')
			return
		}
		if x < 0 {
			r.put_byte(`-`)
		}
		r.put_uint(u64(math.abs(x)))
		return
	}
	mut buf := [32]u8{}
	unsafe {
		mut n := 0
		for p in 1 .. 10 {
			n = C.snprintf(&char(&buf[0]), 32, &char('%.*g'.str), p, x)
			if C.strtof(&char(&buf[0]), nil) == v {
				break
			}
		}
		for i in 0 .. n {
			r.put_byte(buf[i])
		}
	}
}

pub fn (mut r ReqBuf) param_str(key string, val string) {
	r.sep()
	r.put('"')
	r.put(key)
	r.put('":"')
	// Yol gibi metinler: \ ve " kaçışlanır, denetim baytları \u00XX olur.
	for ch in val {
		match true {
			ch == 0x22 || ch == 0x5C {
				r.put_byte(0x5C)
				r.put_byte(ch)
			}
			ch < 0x20 {
				r.put('\\u00')
				r.put_byte(hex_digit(ch >> 4))
				r.put_byte(hex_digit(ch & 0x0F))
			}
			else {
				r.put_byte(ch)
			}
		}
	}
	r.put('"')
}

// Tamamlanmış satır: kapanış "}}" put_byte'ın ayırdığı iki baytta yazılır. Taşmışsa boş metin (handle_from yok sayar).
pub fn (mut r ReqBuf) end() string {
	if r.failed {
		return ''
	}
	r.buf[r.n] = `}`
	r.buf[r.n + 1] = `}`
	r.n += 2
	return unsafe { tos(&r.buf[0], r.n) }
}

fn (mut r ReqBuf) sep() {
	if r.count > 0 {
		r.put(',')
	}
	r.count++
}

fn (mut r ReqBuf) put(s string) {
	for i in 0 .. s.len {
		r.put_byte(s[i])
	}
}

fn (mut r ReqBuf) put_uint(v u64) {
	mut digits := [20]u8{}
	mut k := 0
	mut x := v
	for {
		digits[k] = u8(48 + x % 10)
		k++
		x /= 10
		if x == 0 {
			break
		}
	}
	for k > 0 {
		k--
		r.put_byte(digits[k])
	}
}

fn (mut r ReqBuf) put_byte(b u8) {
	if r.failed {
		return
	}
	// Son iki bayt kapanış ("}}") için ayrılır.
	if r.n + 2 >= req_cap {
		r.failed = true
		return
	}
	r.buf[r.n] = b
	r.n++
}

fn hex_digit(v u8) u8 {
	return if v < 10 { 48 + v } else { 87 + v }
}
