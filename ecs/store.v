module ecs

import memory

// Tek bir bileşen tipinin deposu: sparse-set + alan başına bir SoA kolonu.
// Anahtar entity index'idir; canlılık kontrolü World'de yapılır.
// Tüm diziler parent arenadan 64 hizalı alınır.
pub struct ComponentStore {
mut:
	// shortcut: düz sparse dizi (kapasite × 4 B); M6'da betik bileşenleri çoğalınca sayfalı yapıya geç
	sparse   &u32
	dense    &u32
	columns  [max_fields]&u8
	sizes    [max_fields]u8
	field_n  u16
	capacity u32
	count    u32
}

// Alanlar tek tek sıfırdan yüklenir; tasmada ya da max_fields / null_index sınırında none ve parent geri sarılır.
pub fn ComponentStore.new(mut parent memory.LinearArena, fields []FieldType, capacity u32) ?ComponentStore {
	if fields.len > max_fields || capacity >= null_index {
		return none
	}
	m := parent.mark()
	// Boyutlar u64'te hesaplanir: V int 32 bit, capacity * size tasabilir.
	sparse_mem := parent.alloc_aligned(u64(capacity) * 4, 64) or {
		parent.rewind(m)
		return none
	}
	dense_mem := parent.alloc_aligned(u64(capacity) * 4, 64) or {
		parent.rewind(m)
		return none
	}
	mut s := ComponentStore{
		sparse:   unsafe { &u32(sparse_mem) }
		dense:    unsafe { &u32(dense_mem) }
		field_n:  u16(fields.len)
		capacity: capacity
	}
	for i, f in fields {
		col := parent.alloc_aligned(u64(capacity) * u64(f.size()), 64) or {
			parent.rewind(m)
			return none
		}
		s.columns[i] = unsafe { col }
		s.sizes[i] = u8(f.size())
	}
	for i in u32(0) .. capacity {
		unsafe {
			s.sparse[i] = null_index
		}
	}
	return s
}

// Yeni satır açar, tüm alanlarını 0'lar ve satır no döner. Zaten varsa ya da index >= capacity ise none.
pub fn (mut s ComponentStore) insert(index u32) ?u32 {
	if index >= s.capacity || s.has(index) {
		return none
	}
	row := s.count
	unsafe {
		s.sparse[index] = row
		s.dense[row] = index
	}
	for f in 0 .. s.field_n {
		p := s.cell(f, row)
		for b in 0 .. int(s.sizes[f]) {
			unsafe {
				p[b] = 0
			}
		}
	}
	s.count++
	return row
}

// Swap-and-pop: son satırın tüm kolonları silinen satıra taşınır, taşınan entity'nin sparse kaydı güncellenir.
pub fn (mut s ComponentStore) remove(index u32) bool {
	if !s.has(index) {
		return false
	}
	row := unsafe { s.sparse[index] }
	last := s.count - 1
	if row != last {
		moved := unsafe { s.dense[last] }
		for f in 0 .. s.field_n {
			src := s.cell(f, last)
			dst := s.cell(f, row)
			for b in 0 .. int(s.sizes[f]) {
				unsafe {
					dst[b] = src[b]
				}
			}
		}
		unsafe {
			s.dense[row] = moved
			s.sparse[moved] = row
		}
	}
	unsafe {
		s.sparse[index] = null_index
	}
	s.count--
	return true
}

pub fn (s &ComponentStore) has(index u32) bool {
	if index >= s.capacity {
		return false
	}
	row := unsafe { s.sparse[index] }
	return row < s.count && unsafe { s.dense[row] } == index
}

pub fn (s &ComponentStore) row_of(index u32) ?u32 {
	if !s.has(index) {
		return none
	}
	return unsafe { s.sparse[index] }
}

pub fn (s &ComponentStore) len() u32 {
	return s.count
}

// row >= len ise null_index döner.
pub fn (s &ComponentStore) index_at(row u32) u32 {
	if row >= s.count {
		return null_index
	}
	return unsafe { s.dense[row] }
}

pub fn (s &ComponentStore) field_count() u16 {
	return s.field_n
}

// field aralık dışıysa 0 döner.
pub fn (s &ComponentStore) field_size(field u16) u32 {
	if field >= s.field_n {
		return 0
	}
	return u32(s.sizes[field])
}

// Ham bitler, küçük-uçlu okunur ve u64'e sıfır genişletilir. Geçersiz alan ya da satırda 0.
pub fn (s &ComponentStore) get_raw(row u32, field u16) u64 {
	if field >= s.field_n || row >= s.count {
		return 0
	}
	p := s.cell(field, row)
	mut v := u64(0)
	for b in 0 .. int(s.sizes[field]) {
		v |= u64(unsafe { p[b] }) << u64(8 * b)
	}
	return v
}

// Yalnızca alanın size baytını yazar (küçük-uçlu). Geçersiz alan ya da satırda hiçbir şey yapmaz.
pub fn (mut s ComponentStore) set_raw(row u32, field u16, bits u64) {
	if field >= s.field_n || row >= s.count {
		return
	}
	p := s.cell(field, row)
	for b in 0 .. int(s.sizes[field]) {
		unsafe {
			p[b] = u8(bits >> u64(8 * b))
		}
	}
}

// f32 kolonun başlangıç adresi; 64 hizalıdır. field >= field_count() ise nil döner; çağıran bunu denetlemelidir.
pub fn (s &ComponentStore) column_f32(field u16) &f32 {
	if field >= s.field_n {
		return unsafe { nil }
	}
	return unsafe { &f32(s.columns[field]) }
}

// Satırdaki alanın bayt adresi. Çağıran row < capacity ve field < field_n garantisini verir.
fn (s &ComponentStore) cell(field u16, row u32) &u8 {
	return unsafe { &u8(u64(s.columns[field]) + u64(row) * u64(s.sizes[field])) }
}
