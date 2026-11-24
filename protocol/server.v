module protocol

import sim
import ecs
import cmd
import memory

// İstek arenasının boyutu: her istek bu bölgede ayrıştırılır ve yanıtlanır. Taban 4 MiB; büyük kapasitede
// kapasite başına 256 bayt (100k varlıkta tüm varlıkları listeleyen sorgu yanıtı sığar, bkz. test).
const request_arena_floor = u64(4 << 20)
const request_arena_per_entity = u64(256)

fn request_arena_bytes(cfg sim.Config) u64 {
	scaled := u64(cfg.capacity) * request_arena_per_entity
	return if scaled > request_arena_floor { scaled } else { request_arena_floor }
}

// Yanıt kurulamadığında da hata yanıtında gerçek id yazılabilsin diye istek id'sinin arena dışı kopyası.
// Metin id'si 64 bayta kırpılır (yalnız arena dolduğunda kullanılan yolda); NUL sonlu tutulur.
struct SavedId {
mut:
	kind int // 0: null, 1: sayı, 2: metin
	num  f64
	text [65]u8
	tlen int
}

fn save_id(id Val) SavedId {
	mut s := SavedId{}
	if id.is_number() {
		s.kind = 1
		s.num = id.f64()
	} else if id.is_string() {
		t := id.str()
		s.kind = 2
		s.tlen = if t.len > 64 { 64 } else { t.len }
		for i in 0 .. s.tlen {
			s.text[i] = t[i]
		}
	}
	return s
}

fn (s SavedId) val() Val {
	return match s.kind {
		1 { num(s.num) }
		2 { str_val(unsafe { tos(&u8(&s.text[0]), s.tlen) }) }
		else { null_val() }
	}
}

// JSON-RPC sunucusu: bir sim.Sim, onun bellek bölgesini ve istek arenasını sahiplenir. İstekler tek tek
// işlenir; her istekten sonra kuyruk boşalmış olur. cJSON kancaları süreç geneldir: aynı anda yalnız bir
// Server canlı olmalıdır (yeni bir Server kancaları kendi arenasına yönlendirir).
pub struct Server {
mut:
	cfg        sim.Config
	reg        ecs.Registry
	region     &u8
	req_region &u8
	engine     sim.Sim
	is_paused  bool
	// İsteğin kaynağı (agent: stdin, editor: süreç içi); handle_from istek boyunca ayarlar.
	source cmd.Source
	// Açık editör grubu derinliği (history_begin_group ile); >0 iken geri al/yinele reddedilir.
	// Motor geçmişi yeniden kurulduğunda (sim.reset) sıfırlanır: iki kaynak tek sayaç olarak kalır.
	editor_depth u32
	// Ekran görüntüsü kancası: yalnız pencere varken (vcore run) kurulur.
	capture ?fn (path string) !(int, int)
	// Dünya değişiklik sayacı: başarıyla uygulanan her komutta, geri al/yinelede ve sim.reset'te artar.
	changes u64
}

// Bölgeyi cfg.bytes_needed kadar rezerve eder, istek arenasını ayırır ve Sim'i kurar.
pub fn Server.new(cfg sim.Config) !Server {
	reg := ecs.core_registry()!
	need := cfg.bytes_needed(&reg)
	region := memory.reserve(need) or { return error('protocol: bölge ayrilamadi (${need} bayt)') }
	req_region := memory.reserve(request_arena_bytes(cfg)) or {
		_ = memory.release(region)
		return error('protocol: istek arenasi ayrilamadi')
	}
	mut a := memory.LinearArena.new(region, need)
	engine := sim.Sim.new(mut a, &reg, cfg) or {
		_ = memory.release(region)
		_ = memory.release(req_region)
		return error('protocol: Sim kurulamadi')
	}
	arena_set(req_region, request_arena_bytes(cfg))
	return Server{
		cfg:        cfg
		reg:        reg
		region:     region
		req_region: req_region
		engine:     engine
		source:     .agent
	}
}

// Bölgeleri serbest birakir. Sonrasindaki istekler yapilandirilmis hata döner.
pub fn (mut s Server) close() {
	if s.region != unsafe { nil } {
		s.engine.free()
		_ = memory.release(s.region)
		s.region = unsafe { nil }
	}
	if s.req_region != unsafe { nil } {
		_ = memory.release(s.req_region)
		s.req_region = unsafe { nil }
		arena_set(unsafe { nil }, 0)
	}
}

// Simülasyonu steps adım ilerletir; duraklatılmışken no-op. sim.step bu yoldan geçmez, duraklatılmışken de çalışır.
pub fn (mut s Server) advance(steps u32) {
	if s.is_paused {
		return
	}
	for _ in 0 .. steps {
		s.engine.step()
	}
	// R6: her ilerleyen adım dünya değişikliğidir (duraklatılmışken artmaz).
	s.changes += u64(steps)
}

pub fn (s &Server) world() &ecs.World {
	return &s.engine.world
}

pub fn (s &Server) registry() &ecs.Registry {
	return &s.reg
}

pub fn (s &Server) paused() bool {
	return s.is_paused
}

// Simülasyon tick'i (sim.step ve akış ilerlemesiyle artar).
pub fn (s &Server) tick() u64 {
	return s.engine.tick()
}

// Kaydedilmemiş değişiklik tespiti için: değişmediyse dünya aynıdır.
pub fn (s &Server) change_count() u64 {
	return s.changes
}

// Geri al ve yineleme yığınlarının grup sayıları (buton etkinliği için).
pub fn (s &Server) history_lens() (int, int) {
	return s.engine.history.undo_len(), s.engine.history.redo_len()
}

// Ekran görüntüsü kancasını kurar; run komutu pencere kurulduktan sonra çağırır.
pub fn (mut s Server) set_capture(f fn (path string) !(int, int)) {
	s.capture = f
}

// Tek satır istek alir; yanıt satırını ya da none döner (bildirim ve bos satır).
// Hiçbir girdi panik yaratmaz: ayrıştırma ve yürütme hatalari yapilandirilmis yanıta dönüşür.
// Sözleşme: döndürülen yanıt istek arenasında yaşar. Her çağrı arenayı baştan sıfırlar, yani
// yanıt bir sonraki handle çağrısına kadar geçerlidir; kalıcı tutulacaksa çağıran kopyalamalıdır.
// Arena dolarsa yanıt, arenaya ihtiyaç duymayan sabit bir -32600 satırıdır.
pub fn (mut s Server) handle(line string) ?string {
	return s.handle_from(line, .agent)
}

// handle ile aynı, ama istek ürettiği komutları verilen kaynakla etiketler (editör süreç içinden .editor gönderir).
pub fn (mut s Server) handle_from(line string, source cmd.Source) ?string {
	prev := s.source
	s.source = source
	defer {
		s.source = prev
	}
	text := trim_view(line)
	if text == '' {
		return none
	}
	// Kapalı sunucunun arenası yok (kancalar boş bölgeye bağlı): ayrıştırılamaz, sabit hata döner.
	// Bildirimler de bu satırı alır; kapalı sunucuda id okunamadığı için bilinçli bir sapmadır.
	if s.region == unsafe { nil } {
		return closed_line
	}
	// Her istek bir geçmiş grubudur. Açık editör grubu varken ajan isteği (editör dışı kaynak) kendi grubunu
	// kurar (D1): editör grubunun geri alınmasına girmez; editör istekleri editör grubunun içinde kalır.
	s.engine.history.begin_request(source != .editor && s.editor_depth > 0)
	defer {
		s.engine.history.end_request()
	}
	arena_reset()
	// Ayrıştırıcı özyinelemelidir ve NUL ile kesilen metinleri (strlen görünümü) kabul etmez:
	// derinlik ve NUL denetimi decode'a girmeden yapılır.
	too_deep, has_nul := scan_json(text)
	if too_deep {
		return error_line(null_val(), SavedId{}, rpc_error(code_parse, 'parse error', hint_data('JSON nesting deeper than 64')))
	}
	if has_nul {
		return error_line(null_val(), SavedId{}, rpc_error(code_parse, 'parse error', hint_data('NUL characters are not allowed')))
	}
	req := parse(text) or {
		if exhausted() {
			return too_large_line
		}
		return error_line(null_val(), SavedId{}, rpc_error(code_parse, 'parse error', hint_data('request line is not valid JSON')))
	}
	if !req.is_object() {
		return error_line(null_val(), SavedId{},
			invalid_request('request must be a single JSON object; batches are not supported'))
	}
	// id alani yoksa istek bildirimdir: yürütülür ama yanıt yazilmaz.
	id_v := req.get('id')
	has_id := id_v != none
	id := id_v or { null_val() }
	if has_id && !is_valid_id(id) {
		return error_line(null_val(), SavedId{}, invalid_request('id must be a number, a string or null'))
	}
	// Kimlik arena dolmadan önce kopyalanır: yanıt kurulamazsa gerçek id hata yanıtında kullanılır.
	saved := save_id(id)
	// Surum uyesi yoksa ya da "2.0" degilse istek yurutulmez; bildirimse yanit da yazilmaz.
	if !is_jsonrpc_20(req) {
		if !has_id {
			return none
		}
		return error_line(id, saved, invalid_request('jsonrpc member must be "2.0"'))
	}
	result := s.invoke(req) or {
		if !has_id {
			return none
		}
		return error_line(id, saved, err)
	}
	if !has_id {
		return none
	}
	return success_line(id, saved, result)
}

// Yöntemi ve parametreleri doğrular, ilgili işleyiciye yönlendirir.
fn (mut s Server) invoke(m Val) !Val {
	if s.region == unsafe { nil } {
		return internal_error('server is closed; create a new server')
	}
	method_v := m.get('method') or { null_val() }
	if !method_v.is_string() {
		return invalid_request('method must be a string')
	}
	// Params yoksa p nil'dir: işleyiciler nil'i boş nesne gibi okur.
	mut p := Val{}
	if pv := m.get('params') {
		if !pv.is_object() {
			return invalid_params('params must be an object')
		}
		p = pv
	}
	return s.dispatch(method_v.str(), p)
}

fn (mut s Server) dispatch(method string, p Val) !Val {
	match method {
		'entity.spawn' { return s.entity_spawn(p) }
		'entity.despawn' { return s.entity_despawn(p) }
		'component.add' { return s.component_add(p) }
		'component.remove' { return s.component_remove(p) }
		'component.set' { return s.component_set(p) }
		'entity.get' { return s.entity_get(p) }
		'query.entities' { return s.query_entities(p) }
		'schema.components' { return s.schema_components() }
		'schema.commands' { return schema_commands() }
		'sim.step' { return s.sim_step(p) }
		'sim.reset' { return s.sim_reset() }
		'sim.state_hash' { return s.sim_state_hash() }
		'sim.pause' { return s.sim_pause() }
		'sim.resume' { return s.sim_resume() }
		'capture.screenshot' { return s.capture_screenshot(p) }
		'history.undo' { return s.history_undo() }
		'history.redo' { return s.history_redo() }
		'record.start' { return s.record_start() }
		'record.stop' { return s.record_stop(p) }
		'replay.run' { return s.replay_run(p) }
		'scene.save' { return s.scene_save(p) }
		'scene.load' { return s.scene_load(p) }
		else {}
	}

	return rpc_error(code_method_not_found, 'method not found', hint_data('unknown method "${method}"; see schema.commands'))
}

// string.trim_space ile aynı küme (boşluk, \t, \n, \v, \f, \r), ama kopyasız: görünüm girdinin kendisidir.
fn trim_view(s string) string {
	mut a := 0
	mut b := s.len
	for a < b && is_trim_space(s[a]) {
		a++
	}
	for b > a && is_trim_space(s[b - 1]) {
		b--
	}
	return unsafe { tos(&u8(u64(s.str) + u64(a)), b - a) }
}

fn is_trim_space(c u8) bool {
	return c == ` ` || c == `\n` || c == `\t` || c == `\v` || c == `\f` || c == `\r`
}

// Tek kaçışlı tarama: [ ve { derinliği (tırnak içi hariç) 64'ü aşarsa too_deep; ham NUL baytı ya da
// tırnak içinde \u0000 kaçışı varsa has_nul. "\\u0000" (kaçışlı ters eğik çizgi) NUL değildir.
fn scan_json(text string) (bool, bool) {
	mut depth := 0
	mut in_str := false
	mut has_nul := false
	mut i := 0
	for i < text.len {
		c := text[i]
		if c == 0 {
			has_nul = true
		}
		if in_str {
			if c == `\\` {
				if i + 5 < text.len && text[i + 1] == `u` && text[i + 2] == `0` && text[i + 3] == `0`
					&& text[i + 4] == `0` && text[i + 5] == `0` {
					has_nul = true
				}
				i += 2
				continue
			}
			if c == `"` {
				in_str = false
			}
		} else if c == `"` {
			in_str = true
		} else if c == `[` || c == `{` {
			depth++
			if depth > 64 {
				return true, has_nul
			}
		} else if c == `]` || c == `}` {
			depth--
		}
		i++
	}
	return false, has_nul
}

fn is_jsonrpc_20(m Val) bool {
	v := m.get('jsonrpc') or { return false }
	return v.is_string() && v.str() == '2.0'
}

fn is_valid_id(id Val) bool {
	return id.is_number() || id.is_string() || id.is_null()
}

// Arena dolmuşken kurulamayan yanıt için sabit satır (arenaya dokunmaz).
// Kapalı sunucu yanıtı (id null): arenaya dokunmaz.
const closed_line = '{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"internal error","data":{"hint":"server is closed; create a new server"}}}'

const too_large_line ='{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"invalid request","data":{"hint":"request or response too large"}}}'

// Yanıt kodlanır; arena dolduysa yanıt yeniden kurulur: arena sıfırlanır, gerçek id ile -32600 hatası yazılır.
fn finish_line(m Val, saved SavedId) string {
	line := print(m)
	if !exhausted() {
		return line
	}
	return too_large_response(saved)
}

// Yalnız kısa bir hata nesnesi kurar; yeni arenada sığar. Bu da sığmazsa id'siz sabit satır döner.
fn too_large_response(saved SavedId) string {
	arena_reset()
	e := obj()
	e.set('code', num(f64(code_invalid_request)))
	e.set('message', str_val('invalid request'))
	e.set('data', hint_data('response too large; use the limit parameter'))
	m := obj()
	m.set('jsonrpc', str_val('2.0'))
	m.set('id', saved.val())
	m.set('error', e)
	line := print(m)
	if exhausted() {
		return too_large_line
	}
	return line
}

fn success_line(id Val, saved SavedId, result Val) string {
	mut m := obj()
	m.set('jsonrpc', str_val('2.0'))
	// id istek ağacına aittir; yanıta kopyası konur ki kardeş bağlantıları bozulmasın.
	m.set('id', dup(id))
	m.set('result', result)
	return finish_line(m, saved)
}

// Hata yanıtı; IError RpcError degilse sunucu içi hata olarak raporlanır.
// Alanlar smartcast ile okunur.
fn error_line(id Val, saved SavedId, err IError) string {
	mut code := code_internal
	mut message := 'internal error'
	mut data := hint_data('unexpected error')
	if err is RpcError {
		code = err.err_code
		message = err.message
		data = err.data
	}
	mut e := obj()
	e.set('code', num(f64(code)))
	e.set('message', str_val(message))
	e.set('data', data)
	mut m := obj()
	m.set('jsonrpc', str_val('2.0'))
	m.set('id', dup(id))
	m.set('error', e)
	return finish_line(m, saved)
}
