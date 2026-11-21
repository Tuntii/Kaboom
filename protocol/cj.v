module protocol

// cJSON 1.7.17 (MIT) üzerinde ince bir değer katmanı. Düğüm ve tamponlar istek arenasından gelir;
// arena her istekte sıfırlanır, yani döndürülen string'ler bir sonraki istek çağrısına kadar geçerlidir.
#flag -I @VMODROOT/third_party/cJSON
#include "@VMODROOT/third_party/cJSON/cJSON.c"
#include "@VMODROOT/protocol/cj_arena.h"

@[typedef]
pub struct C.cJSON {}

fn C.cJSON_ParseWithLengthOpts(value &char, buffer_length u64, return_parse_end voidptr, require_null_terminated int) &C.cJSON
fn C.cJSON_PrintUnformatted(item &C.cJSON) &char
fn C.cJSON_CreateObject() &C.cJSON
fn C.cJSON_CreateArray() &C.cJSON
fn C.cJSON_CreateNull() &C.cJSON
fn C.cJSON_CreateBool(b int) &C.cJSON
fn C.cJSON_CreateNumber(num f64) &C.cJSON
fn C.cJSON_CreateString(s &char) &C.cJSON
fn C.cJSON_Duplicate(item &C.cJSON, recurse int) &C.cJSON
fn C.cJSON_AddItemToObject(object &C.cJSON, name &char, item &C.cJSON) int
fn C.cJSON_AddItemToArray(array &C.cJSON, item &C.cJSON) int
fn C.cJSON_GetArraySize(array &C.cJSON) int
fn C.cJSON_GetArrayItem(array &C.cJSON, index int) &C.cJSON
fn C.cJSON_IsObject(item &C.cJSON) int
fn C.cJSON_IsArray(item &C.cJSON) int
fn C.cJSON_IsString(item &C.cJSON) int
fn C.cJSON_IsNumber(item &C.cJSON) int
fn C.cJSON_IsBool(item &C.cJSON) int
fn C.cJSON_IsNull(item &C.cJSON) int
fn C.cJSON_IsTrue(item &C.cJSON) int
fn C.cJSON_GetNumberValue(item &C.cJSON) f64
fn C.cJSON_GetStringValue(item &C.cJSON) &char
fn C.vcore_cj_set(base &u8, cap u64)
fn C.vcore_cj_reset()
fn C.vcore_cj_exhausted() int
fn C.vcore_cj_install()
fn C.vcore_cj_child(item &C.cJSON) &C.cJSON
fn C.vcore_cj_next(item &C.cJSON) &C.cJSON
fn C.vcore_cj_key(item &C.cJSON) &char
fn C.strlen(s &char) u64

// Arena'da yaşayan C metninin görünümü. cstring_to_vstring kopyalar (her anahtar ve değerde tahsis);
// burada kopya yok, metin istek arenasının ömründe geçerlidir.
fn view(p &char) string {
	if p == unsafe { nil } {
		return ''
	}
	return unsafe { tos(&u8(p), int(C.strlen(p))) }
}

// Düğüm sarmalayıcısı. n nil ise "yok"; okuyucular nil'de güvenle döner.
pub struct Val {
pub:
	n &C.cJSON = unsafe { nil }
}

pub fn (v Val) is_nil() bool {
	return v.n == unsafe { nil }
}

pub fn (v Val) is_object() bool {
	return !v.is_nil() && C.cJSON_IsObject(v.n) != 0
}

pub fn (v Val) is_array() bool {
	return !v.is_nil() && C.cJSON_IsArray(v.n) != 0
}

pub fn (v Val) is_string() bool {
	return !v.is_nil() && C.cJSON_IsString(v.n) != 0
}

pub fn (v Val) is_number() bool {
	return !v.is_nil() && C.cJSON_IsNumber(v.n) != 0
}

pub fn (v Val) is_bool() bool {
	return !v.is_nil() && C.cJSON_IsBool(v.n) != 0
}

pub fn (v Val) is_null() bool {
	return !v.is_nil() && C.cJSON_IsNull(v.n) != 0
}

// Sayı değilse 0 döner; çağıran önce is_number ile denetler.
pub fn (v Val) f64() f64 {
	if !v.is_number() {
		return 0
	}
	return C.cJSON_GetNumberValue(v.n)
}

// Metin değilse boş string döner.
pub fn (v Val) str() string {
	if !v.is_string() {
		return ''
	}
	return view(C.cJSON_GetStringValue(v.n))
}

pub fn (v Val) as_bool() bool {
	return v.is_bool() && C.cJSON_IsTrue(v.n) != 0
}

// Nesne ya da dizinin ilk alt düğümü; yoksa nil.
pub fn (v Val) first() Val {
	return Val{
		n: C.vcore_cj_child(v.n)
	}
}

// Kardeş düğüm; yoksa nil.
pub fn (v Val) next() Val {
	return Val{
		n: C.vcore_cj_next(v.n)
	}
}

// Nesne alt düğümünün anahtarı; dizi öğesinde boş string.
pub fn (v Val) key() string {
	p := C.vcore_cj_key(v.n)
	if p == unsafe { nil } {
		return ''
	}
	return view(p)
}

// Anahtarın değeri. Yinelenen anahtarda son değer geçerlidir (eski ayrıştırıcı davranışı).
pub fn (v Val) get(key string) ?Val {
	if !v.is_object() {
		return none
	}
	mut found := Val{}
	mut c := v.first()
	for !c.is_nil() {
		if c.key() == key {
			found = c
		}
		c = c.next()
	}
	if found.is_nil() {
		return none
	}
	return found
}

// c, bu nesnede kendi anahtarının geçerli (son) düğümü mü? Yinelenenleri bir kez işlemek için.
pub fn (v Val) is_last(c Val) bool {
	last := v.get(c.key()) or { return false }
	return last.n == c.n
}

// Dizi öğesi; sınır dışı ya da dizi değilse none.
pub fn (v Val) at(i int) ?Val {
	if !v.is_array() || i < 0 || i >= v.len() {
		return none
	}
	return Val{
		n: C.cJSON_GetArrayItem(v.n, i)
	}
}

pub fn (v Val) len() int {
	if !v.is_array() {
		return 0
	}
	return C.cJSON_GetArraySize(v.n)
}

pub fn obj() Val {
	return Val{
		n: C.cJSON_CreateObject()
	}
}

pub fn arr() Val {
	return Val{
		n: C.cJSON_CreateArray()
	}
}

pub fn num(x f64) Val {
	return Val{
		n: C.cJSON_CreateNumber(x)
	}
}

// Metin arenaya kopyalanır; kaynak istek ağacından bağımsız kalır.
pub fn str_val(s string) Val {
	return Val{
		n: C.cJSON_CreateString(&char(s.str))
	}
}

pub fn bool_val(b bool) Val {
	return Val{
		n: C.cJSON_CreateBool(int(b))
	}
}

pub fn null_val() Val {
	return Val{
		n: C.cJSON_CreateNull()
	}
}

// Derin kopya: istek ağacındaki bir düğümü yanıta taşırken kardeş bağlantılarını koparır.
pub fn dup(v Val) Val {
	return Val{
		n: C.cJSON_Duplicate(v.n, 1)
	}
}

// Nesneye anahtar ekler; anahtar cJSON tarafından kopyalanır. Arena dolduysa sessizce düşer;
// çağıran exhausted() ile denetler.
pub fn (v Val) set(key string, x Val) {
	if v.is_nil() || x.is_nil() {
		return
	}
	C.cJSON_AddItemToObject(v.n, &char(key.str), x.n)
}

pub fn (v Val) push(x Val) {
	if v.is_nil() || x.is_nil() {
		return
	}
	C.cJSON_AddItemToArray(v.n, x.n)
}

// JSON metnini çözer. Uzunluk açıkça verilir (NUL gerekmez); sonda yalnız boşluk olabilir.
pub fn parse(text string) ?Val {
	mut end := &char(unsafe { nil })
	root := C.cJSON_ParseWithLengthOpts(&char(text.str), u64(text.len), voidptr(&end), 0)
	if root == unsafe { nil } {
		return none
	}
	off := u64(voidptr(end)) - u64(voidptr(text.str))
	for i in off .. u64(text.len) {
		c := text[i]
		if c != ` ` && c != `\t` && c != `\n` && c != `\r` {
			return none
		}
	}
	return Val{
		n: root
	}
}

// Kompakt JSON metni. Arena dolduysa boş string döner; çağıran exhausted() ile denetler.
pub fn print(v Val) string {
	if v.is_nil() {
		return ''
	}
	p := C.cJSON_PrintUnformatted(v.n)
	if p == unsafe { nil } {
		return ''
	}
	return view(p)
}

// İstek arenası bu istekte yetmediyse true.
pub fn exhausted() bool {
	return C.vcore_cj_exhausted() != 0
}

// Kancaları verilen bölgeye bağlar. Bölge nil geçilirse her tahsis başarısız olur.
pub fn arena_set(base &u8, cap u64) {
	C.vcore_cj_set(base, cap)
	C.vcore_cj_install()
}

// Her handle çağrısının başında: önceki yanıt ve düğümler geri alınır.
pub fn arena_reset() {
	C.vcore_cj_reset()
}
