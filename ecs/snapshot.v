module ecs

// Dünyanın birebir ikili görüntüsü (D2): id'ler, nesiller, boş liste ve bileşen satırları.
// Düzen, hepsi küçük-uçlu: başlık 36 bayt [magic, sürüm, capacity, store sayısı, fresh, free_head, alive, retired, sağlama u32];
// her indeks < fresh için 7 bayt [nesil u16, free_next u32, canlı u8]; her store için
// [field_n u32, alan boyutları u32 × field_n, satır sayısı u32, dense u32 × satır, kolonlar alan alan, satır satır].
// Sağlama: başlıktan sonraki gövdenin FNV-1a 64 alt 32 biti. Sparse ve bit dizileri yazılmaz; dense ve canlılıktan türetilir.
const snapshot_magic = u32(0x53574356)
const snapshot_version = u32(1)
const snapshot_header_size = 36
const snapshot_slot_size = 7

// Tahsis yapar; tick yolunda çağrılmaz (kayıt başlangıcı).
pub fn (w &World) snapshot() []u8 {
	mut n := snapshot_header_size + int(w.alloc.fresh) * snapshot_slot_size
	for i in 0 .. w.stores.len {
		s := &w.stores[i]
		n += 8 + 4 * int(s.field_n) + 4 * int(s.count)
		for f in 0 .. s.field_n {
			n += int(s.count) * int(s.sizes[f])
		}
	}
	mut buf := []u8{len: n}
	put_le(mut buf, 0, u64(snapshot_magic), 4)
	put_le(mut buf, 4, u64(snapshot_version), 4)
	put_le(mut buf, 8, u64(w.alloc.capacity), 4)
	put_le(mut buf, 12, u64(w.stores.len), 4)
	put_le(mut buf, 16, u64(w.alloc.fresh), 4)
	put_le(mut buf, 20, u64(w.alloc.free_head), 4)
	put_le(mut buf, 24, u64(w.alloc.alive), 4)
	put_le(mut buf, 28, u64(w.alloc.retired), 4)
	mut off := snapshot_header_size
	for idx in 0 .. w.alloc.fresh {
		put_le(mut buf, off, u64(unsafe { w.alloc.generations[idx] }), 2)
		put_le(mut buf, off + 2, u64(unsafe { w.alloc.free_next[idx] }), 4)
		if slot_alive(&w.alloc, idx) {
			buf[off + 6] = 1
		}
		off += snapshot_slot_size
	}
	for i in 0 .. w.stores.len {
		s := &w.stores[i]
		put_le(mut buf, off, u64(s.field_n), 4)
		off += 4
		for f in 0 .. s.field_n {
			put_le(mut buf, off, u64(s.sizes[f]), 4)
			off += 4
		}
		put_le(mut buf, off, u64(s.count), 4)
		off += 4
		for row in 0 .. s.count {
			put_le(mut buf, off, u64(unsafe { s.dense[row] }), 4)
			off += 4
		}
		for f in 0 .. s.field_n {
			for row in 0 .. s.count {
				p := s.cell(f, row)
				for b in 0 .. int(s.sizes[f]) {
					buf[off] = unsafe { p[b] }
					off++
				}
			}
		}
	}
	put_le(mut buf, 32, u64(snapshot_checksum(buf[snapshot_header_size..])), 4)
	return buf
}

// Görüntüyü dünyaya yükler. Tüm doğrulama yazımdan önce biter: hata dönerse dünya değişmemiştir.
// Kapasite ve şema (store sayısı, alan sayısı ve boyutları) hedef dünyayla aynı olmalıdır.
pub fn (mut w World) restore(data []u8) ! {
	if data.len < snapshot_header_size {
		return error('world snapshot: ${data.len} bayt, başlık için yetmiyor')
	}
	if get_le(data, 0, 4) != u64(snapshot_magic) || get_le(data, 4, 4) != u64(snapshot_version) {
		return error('world snapshot: magic ya da sürüm tanınmıyor')
	}
	if get_le(data, 8, 4) != u64(w.alloc.capacity) {
		return error('world snapshot: kapasite ${get_le(data, 8, 4)} dünyanın ${w.alloc.capacity} değil')
	}
	if get_le(data, 12, 4) != u64(w.stores.len) {
		return error('world snapshot: bileşen sayısı ${get_le(data, 12, 4)} dünyada ${w.stores.len}')
	}
	fresh := u32(get_le(data, 16, 4))
	free_head := u32(get_le(data, 20, 4))
	alive := u32(get_le(data, 24, 4))
	retired := u32(get_le(data, 28, 4))
	if fresh > w.alloc.capacity || (free_head != null_index && free_head >= fresh) {
		return error('world snapshot: indeks sınırları geçersiz')
	}
	if !snapshot_fits(data, snapshot_header_size, u64(fresh) * snapshot_slot_size) {
		return error('world snapshot: kesik (varlık tablosu)')
	}
	if snapshot_checksum(data[snapshot_header_size..]) != u32(get_le(data, 32, 4)) {
		return error('world snapshot: sağlama uyuşmuyor')
	}
	// Varlık tablosu: canlılık bayrağı, serbest liste (bitküme) ve emekliler. Ölü slot ya listededir ya emekli;
	// emekli olan slotun nesli max'tır, ama listedeki slot da max nesile ulaşmış olabilir (0xFFFF'te yıkılıp listede kalır).
	mut on_list := []u64{len: int((fresh + 63) / 64)}
	defer {
		unsafe { on_list.free() }
	}
	mut live := u32(0)
	for idx in 0 .. fresh {
		flag := data[snapshot_header_size + int(idx) * snapshot_slot_size + 6]
		if flag > 1 {
			return error('world snapshot: indeks ${idx} canlılık bayrağı ${flag}')
		}
		if flag == 1 {
			live++
		}
	}
	if live != alive {
		return error('world snapshot: canlı sayısı tabloyla uyuşmuyor')
	}
	mut steps := u32(0)
	mut cur := free_head
	for cur != null_index {
		if cur >= fresh || steps >= fresh || snapshot_alive(data, cur) || bit_set(on_list, cur) {
			return error('world snapshot: serbest liste bozuk (indeks ${cur})')
		}
		bit_put(mut on_list, cur)
		steps++
		cur = u32(get_le(data, snapshot_header_size + int(cur) * snapshot_slot_size + 2, 4))
	}
	mut gone := u32(0)
	for idx in 0 .. fresh {
		if snapshot_alive(data, idx) || bit_set(on_list, idx) {
			continue
		}
		if snapshot_gen(data, idx) != u64(max_generation) {
			return error('world snapshot: ölü slot ${idx} ne listede ne emekli')
		}
		gone++
	}
	if gone != retired {
		return error('world snapshot: emekli sayısı tabloyla uyuşmuyor')
	}
	// Store bölümleri: şema, satır sınırları ve dense indeksleri (canlı olmalı) doğrulanır.
	// Dense tekrarları: store başına bitküme (kapasite genişliğinde, tek ayırma). Tekrarlı satır bozuk görüntüdür.
	mut dup := []u64{len: int((w.alloc.capacity + 63) / 64)}
	defer {
		unsafe { dup.free() }
	}
	mut off := snapshot_header_size + int(fresh) * snapshot_slot_size
	for i in 0 .. w.stores.len {
		s := &w.stores[i]
		for k in 0 .. dup.len {
			dup[k] = 0
		}
		if !snapshot_fits(data, off, 4) || get_le(data, off, 4) != u64(s.field_n) {
			return error('world snapshot: store ${i} alan sayısı uyuşmuyor')
		}
		off += 4
		for f in 0 .. s.field_n {
			if !snapshot_fits(data, off, 4) || get_le(data, off, 4) != u64(s.sizes[f]) {
				return error('world snapshot: store ${i} alan ${f} boyutu uyuşmuyor')
			}
			off += 4
		}
		if !snapshot_fits(data, off, 4) {
			return error('world snapshot: kesik (store ${i})')
		}
		count := u32(get_le(data, off, 4))
		off += 4
		if count > w.alloc.capacity || !snapshot_fits(data, off, u64(count) * 4) {
			return error('world snapshot: store ${i} satır sayısı ${count} geçersiz')
		}
		for row in 0 .. count {
			idx := u32(get_le(data, off + int(row) * 4, 4))
			if idx >= fresh || !snapshot_alive(data, idx) {
				return error('world snapshot: store ${i} satır ${row} canlı olmayan varlık ${idx}')
			}
			if bit_set(dup, idx) {
				return error('world snapshot: store ${i} satır ${row} tekrarlı varlık ${idx}')
			}
			bit_put(mut dup, idx)
		}
		off += int(count) * 4
		for f in 0 .. s.field_n {
			cols := u64(count) * u64(s.sizes[f])
			if !snapshot_fits(data, off, cols) {
				return error('world snapshot: kesik (store ${i} kolon ${f})')
			}
			off += int(cols)
		}
	}
	if off != data.len {
		return error('world snapshot: ${data.len - off} fazla bayt')
	}
	// Doğrulandı: yazım başlar. Varlık tablosunun geri kalanı sıfırlanır (yeni yaratmalar nesil 0 bekler).
	for idx in 0 .. w.alloc.capacity {
		unsafe {
			w.alloc.generations[idx] = 0
			w.alloc.free_next[idx] = null_index
		}
	}
	for wd in 0 .. (w.alloc.capacity + 63) / 64 {
		unsafe {
			w.alloc.alive_bits[wd] = 0
		}
	}
	for idx in 0 .. fresh {
		unsafe {
			w.alloc.generations[idx] = u16(snapshot_gen(data, idx))
			w.alloc.free_next[idx] = u32(get_le(data, snapshot_header_size + int(idx) * snapshot_slot_size + 2, 4))
		}
		if snapshot_alive(data, idx) {
			wd := idx / 64
			unsafe {
				w.alloc.alive_bits[wd] = w.alloc.alive_bits[wd] | (u64(1) << u64(idx % 64))
			}
		}
	}
	w.alloc.free_head = free_head
	w.alloc.fresh = fresh
	w.alloc.alive = alive
	w.alloc.retired = retired
	off = snapshot_header_size + int(fresh) * snapshot_slot_size
	for i in 0 .. w.stores.len {
		mut s := &w.stores[i]
		for row in 0 .. s.capacity {
			unsafe {
				s.sparse[row] = null_index
			}
		}
		off += 4 + 4 * int(s.field_n)
		count := u32(get_le(data, off, 4))
		off += 4
		s.count = count
		for row in 0 .. count {
			idx := u32(get_le(data, off + int(row) * 4, 4))
			unsafe {
				s.dense[row] = idx
				s.sparse[idx] = row
			}
		}
		off += int(count) * 4
		for f in 0 .. s.field_n {
			for row in 0 .. count {
				p := s.cell(f, row)
				for b in 0 .. int(s.sizes[f]) {
					unsafe {
						p[b] = data[off]
					}
					off++
				}
			}
		}
	}
}

fn snapshot_gen(data []u8, idx u32) u64 {
	return get_le(data, snapshot_header_size + int(idx) * snapshot_slot_size, 2)
}

fn snapshot_alive(data []u8, idx u32) bool {
	return data[snapshot_header_size + int(idx) * snapshot_slot_size + 6] == 1
}

fn bit_set(bits []u64, idx u32) bool {
	return (bits[idx / 64] & (u64(1) << u64(idx % 64))) != 0
}

fn bit_put(mut bits []u64, idx u32) {
	bits[idx / 64] |= u64(1) << u64(idx % 64)
}

fn slot_alive(a &EntityAllocator, idx u32) bool {
	return (unsafe { a.alive_bits[idx / 64] } & (u64(1) << u64(idx % 64))) != 0
}

fn snapshot_fits(data []u8, off int, n u64) bool {
	return u64(off) + n <= u64(data.len)
}

fn put_le(mut buf []u8, off int, v u64, n int) {
	for b in 0 .. n {
		buf[off + b] = u8(v >> u64(8 * b))
	}
}

fn get_le(data []u8, off int, n int) u64 {
	mut v := u64(0)
	for b in 0 .. n {
		v |= u64(data[off + b]) << u64(8 * b)
	}
	return v
}

// Recording'in sağlamasıyla aynı FNV-1a; ecs, cmd'ye bağımlı olamaz.
fn snapshot_checksum(body []u8) u32 {
	mut h := u64(0xcbf29ce484222325)
	for b in body {
		h = (h ^ u64(b)) * u64(0x100000001b3)
	}
	return u32(h)
}
