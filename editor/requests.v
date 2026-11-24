module editor

// İstek satırı kurucusu: sabit tampon, tahsis yok. Yanıt handle_from'un istek arenasında yaşar.
const req_cap = 1024

pub struct ReqBuf {
mut:
	buf    [req_cap]u8
	n      int
	count  int
	failed bool
}

// Yeni istek: {"jsonrpc":"2.0","id":1,"method":"<m>","params":{...}}. Sayılar ve id protokolün kabul ettiği biçimdedir.
pub fn (mut r ReqBuf) begin(method string) {
	r.n = 0
	r.count = 0
	r.failed = false
	r.put('{"jsonrpc":"2.0","id":1,"method":"')
	r.put(method)
	r.put('","params":{')
}

pub fn (mut r ReqBuf) param_int(key string, v int) {
	r.sep()
	r.put('"')
	r.put(key)
	r.put('":')
	if v < 0 {
		r.put_byte(`-`)
	}
	mut mag := if v < 0 { u64(-i64(v)) } else { u64(v) }
	mut digits := [20]u8{}
	mut k := 0
	for {
		digits[k] = u8(48 + mag % 10)
		k++
		mag /= 10
		if mag == 0 {
			break
		}
	}
	for k > 0 {
		k--
		r.put_byte(digits[k])
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
