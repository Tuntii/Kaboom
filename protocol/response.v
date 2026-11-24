module protocol

import ecs

// Editör için yanıt okuyucuları (protokol dışı kullanım). Yanıt istek arenasında ayrıştırılır:
// çağıran değeri bir sonraki handle çağrısından önce kopyalamalıdır.

// Yanıt başarılı mı (error üyesi yok).
pub fn response_ok(resp string) bool {
	v := parse(resp) or { return false }
	return v.get('error') == none
}

// Hata iletisi: ipucu (data.hint) varsa o, yoksa message. Başarılı yanıtta boş metin.
pub fn response_error_message(resp string) string {
	v := parse(resp) or { return '' }
	err := v.get('error') or { return '' }
	if data := err.get('data') {
		if hint := data.get('hint') {
			if hint.is_string() {
				return hint.str()
			}
		}
	}
	msg := err.get('message') or { return '' }
	return msg.str()
}

// Tek varlık yanıtındaki id (entity.spawn: {"result": {"entity": id}}).
pub fn response_entity(resp string) ?ecs.EntityID {
	v := parse(resp) or { return none }
	res := v.get('result') or { return none }
	ent := res.get('entity') or { return none }
	if !ent.is_number() {
		return none
	}
	return ecs.EntityID(u64(ent.f64()))
}
