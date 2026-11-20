module ecs

import memory

// Dünya mutasyon ve sorgu sonucu. Protokol bu değerleri ajana olduğu gibi bildirir; sıra ve değerler sabittir.
pub enum Status as u8 {
	ok
	dead_entity
	unknown_component
	unknown_field
	already_has
	missing_component
	capacity_full
	invalid_command
}

// Varlık tahsisatçısı ve her bileşen için bir store. Store'lar kurulumda bir kez açılır, tick yolunda büyümez.
pub struct World {
mut:
	alloc  EntityAllocator
	stores []ComponentStore
}

// Kayıtlı her bileşen için bir store açar; store id'si bileşen id'sine eşittir. Hata olursa parent geri sarılır.
pub fn World.new(mut parent memory.LinearArena, reg &Registry, capacity u32) ?World {
	m := parent.mark()
	alloc := EntityAllocator.new(mut parent, capacity) or {
		parent.rewind(m)
		return none
	}
	mut stores := []ComponentStore{cap: int(reg.count())}
	for id in u16(0) .. reg.count() {
		schema := reg.component(id) or {
			parent.rewind(m)
			return none
		}
		mut types := []FieldType{cap: schema.fields.len}
		for f in schema.fields {
			types << f.typ
		}
		store := ComponentStore.new(mut parent, types, capacity) or {
			parent.rewind(m)
			return none
		}
		stores << store
	}
	return World{
		alloc:  alloc
		stores: stores
	}
}

pub fn (mut w World) spawn() ?EntityID {
	return w.alloc.create()
}

// Önce ayırıcıdan siler, sonra her store'dan çıkarır. Canlı değilse false.
pub fn (mut w World) despawn(e EntityID) bool {
	if !w.alloc.destroy(e) {
		return false
	}
	for i in 0 .. w.stores.len {
		w.stores[i].remove(e.index())
	}
	return true
}

pub fn (mut w World) add_component(e EntityID, comp u16) Status {
	if !w.is_alive(e) {
		return .dead_entity
	}
	if comp >= w.store_count() {
		return .unknown_component
	}
	if w.stores[comp].has(e.index()) {
		return .already_has
	}
	_ = w.stores[comp].insert(e.index()) or { return .capacity_full }
	return .ok
}

pub fn (mut w World) remove_component(e EntityID, comp u16) Status {
	if !w.is_alive(e) {
		return .dead_entity
	}
	if comp >= w.store_count() {
		return .unknown_component
	}
	if !w.stores[comp].remove(e.index()) {
		return .missing_component
	}
	return .ok
}

pub fn (mut w World) set_field(e EntityID, comp u16, field u16, bits u64) Status {
	if !w.is_alive(e) {
		return .dead_entity
	}
	if comp >= w.store_count() {
		return .unknown_component
	}
	row := w.stores[comp].row_of(e.index()) or { return .missing_component }
	// set_raw alan doğrulamaz; sınır burada kontrol edilir.
	if field >= w.stores[comp].field_count() {
		return .unknown_field
	}
	w.stores[comp].set_raw(row, field, bits)
	return .ok
}

pub fn (w &World) is_alive(e EntityID) bool {
	return w.alloc.is_alive(e)
}

// Bayat handle, aynı indeksi yeniden kullanan varlığın bileşenini gösteremez; is_alive bunu engeller.
pub fn (w &World) has(e EntityID, comp u16) bool {
	return w.is_alive(e) && comp < w.store_count() && w.stores[comp].has(e.index())
}

pub fn (w &World) get_field(e EntityID, comp u16, field u16) ?u64 {
	if !w.is_alive(e) || comp >= w.store_count() {
		return none
	}
	s := w.store(comp)
	if field >= s.field_count() {
		return none
	}
	row := s.row_of(e.index()) or { return none }
	return s.get_raw(row, field)
}

pub fn (w &World) store_count() u16 {
	return u16(w.stores.len)
}

// Çağıran comp < store_count() garantiler; bu sınır dışında dizi sınırı dışına okunur.
pub fn (w &World) store(comp u16) &ComponentStore {
	return &w.stores[comp]
}

pub fn (w &World) entities() &EntityAllocator {
	return &w.alloc
}

pub fn (w &World) alive_count() u32 {
	return w.alloc.alive_count()
}
