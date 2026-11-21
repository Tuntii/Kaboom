module ecs

import memory

// Varlik slot tahsisatcisi. Nesil dizisi, bos liste (free_next uzerinden LIFO) ve canli bitmap
// parent arenadan 64 hizali alinir. Bos liste bossa free_head == null_index.
pub struct EntityAllocator {
mut:
	generations &u16
	free_next   &u32
	alive_bits  &u64
	free_head   u32
	capacity   u32
	// Hic verilmemis ilk indeks; high_water() ile okunur.
	fresh      u32
	alive      u32
	retired    u32
}

// Dizileri parent'tan alir ve ilk degerlerini kendisi yazar. Tasmada ya da capacity >= null_index ise none; parent geri sarilir.
pub fn EntityAllocator.new(mut parent memory.LinearArena, capacity u32) ?EntityAllocator {
	if capacity >= null_index {
		return none
	}
	// Boyutlar u64'te hesaplanir: V int 32 bit, capacity 2^31 ustu olabilir.
	words := (u64(capacity) + 63) / 64
	m := parent.mark()
	gens := parent.alloc_aligned(u64(capacity) * 2, 64) or {
		parent.rewind(m)
		return none
	}
	next := parent.alloc_aligned(u64(capacity) * 4, 64) or {
		parent.rewind(m)
		return none
	}
	bits := parent.alloc_aligned(words * 8, 64) or {
		parent.rewind(m)
		return none
	}
	generations := unsafe { &u16(gens) }
	free_next := unsafe { &u32(next) }
	alive_bits := unsafe { &u64(bits) }
	for i in u32(0) .. capacity {
		unsafe {
			generations[i] = 0
			free_next[i] = null_index
		}
	}
	for w in u32(0) .. u32(words) {
		unsafe {
			alive_bits[w] = 0
		}
	}
	return EntityAllocator{
		generations: generations
		free_next:   free_next
		alive_bits:  alive_bits
		free_head:   null_index
		capacity:    capacity
	}
}

// Once bos listeden verir, yoksa yeni slot acar. Ikisi de yoksa none.
pub fn (mut a EntityAllocator) create() ?EntityID {
	mut idx := null_index
	if a.free_head != null_index {
		idx = a.free_head
		a.free_head = unsafe { a.free_next[idx] }
	} else if a.fresh < a.capacity {
		idx = a.fresh
		a.fresh++
	} else {
		return none
	}
	w := int(idx / 64)
	unsafe {
		a.alive_bits[w] = a.alive_bits[w] | (u64(1) << u64(idx % 64))
	}
	a.alive++
	return make_entity(idx, unsafe { a.generations[idx] })
}

// Canli olmayan (sahte, eski ya da tekrar) handle icin false. Nesil max_generation ise slot emekli olur.
pub fn (mut a EntityAllocator) destroy(e EntityID) bool {
	if !a.is_alive(e) {
		return false
	}
	idx := e.index()
	w := int(idx / 64)
	unsafe {
		a.alive_bits[w] = a.alive_bits[w] & ~(u64(1) << u64(idx % 64))
	}
	a.alive--
	if unsafe { a.generations[idx] } == max_generation {
		a.retired++
		return true
	}
	unsafe {
		a.generations[idx] = a.generations[idx] + 1
		a.free_next[idx] = a.free_head
	}
	a.free_head = idx
	return true
}

pub fn (a &EntityAllocator) is_alive(e EntityID) bool {
	// Bit 48..63 her zaman 0 olmali; kanonik olmayan handle sahte sayilir.
	if u64(e) >> 48 != 0 {
		return false
	}
	idx := e.index()
	if idx >= a.fresh {
		return false
	}
	w := int(idx / 64)
	bit := u64(1) << u64(idx % 64)
	return (unsafe { a.alive_bits[w] } & bit) != 0 && unsafe { a.generations[idx] } == e.generation()
}

pub fn (a &EntityAllocator) alive_count() u32 {
	return a.alive
}

pub fn (a &EntityAllocator) retired_count() u32 {
	return a.retired
}

// Simdiye kadar verilmis indekslerin siniri (ilk hic verilmemis indeks).
pub fn (a &EntityAllocator) high_water() u32 {
	return a.fresh
}

// idx icin canli handle'i verir. idx high_water disinda ya da slot olu ise none.
pub fn (a &EntityAllocator) handle_at(idx u32) ?EntityID {
	if idx >= a.fresh {
		return none
	}
	w := int(idx / 64)
	bit := u64(1) << u64(idx % 64)
	if unsafe { a.alive_bits[w] } & bit == 0 {
		return none
	}
	return make_entity(idx, unsafe { a.generations[idx] })
}
