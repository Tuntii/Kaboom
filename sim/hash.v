module sim

import ecs

const fnv_offset = u64(0xcbf29ce484222325)
const fnv_prime = u64(0x100000001b3)

// Durum özeti: canlı varlıklar index sırasıyla (id, sonra id sırasıyla bileşenler), en sonda tick. FNV-1a 64, küçük-uçlu baytlar.
pub fn state_hash(w &ecs.World, tick u64) u64 {
	mut h := fnv_offset
	for idx in 0 .. w.entities().high_water() {
		e := w.entities().handle_at(idx) or { continue }
		h = fnv_fold(h, u64(e), 8)
		for comp in 0 .. w.store_count() {
			s := w.store(comp)
			row := s.row_of(idx) or { continue }
			h = fnv_fold(h, u64(comp), 2)
			for f in 0 .. s.field_count() {
				h = fnv_fold(h, s.get_raw(row, f), s.field_size(f))
			}
		}
	}
	return fnv_fold(h, tick, 8)
}

// v'nin alttaki size baytını küçük-uçlu olarak ekler.
fn fnv_fold(h u64, v u64, size u32) u64 {
	mut r := h
	for b in 0 .. size {
		r = (r ^ u64(u8(v >> u64(8 * b)))) * fnv_prime
	}
	return r
}
