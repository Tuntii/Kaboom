module memory

import math.bits

// Sabit boyutlu slot havuzu. Bitmap'te 1 = bos. Son kelimede slot_count'u asan bitler 0.
pub struct PoolAllocator {
mut:
	slots      &u8
	stride     u64
	slot_count u32
	free_bits  &u64
	word_count u32
	live       u32
	// Bundan dusuk kelimeler tamamen dolu; acquire oradan baslar.
	first_free u32
}

// Slot blogu ve bitmap parent'tan 64 hizali alinir. Tasmada ya da gecersiz boyutta none; parent geri sarilir.
pub fn PoolAllocator.new(mut parent LinearArena, slot_size u64, slot_count u32) ?PoolAllocator {
	max := u64(-1)
	// align_forward(slot_size, 16) sarmasin diye ust sinir; slot_size 0 ise gecersiz.
	if slot_count == 0 || slot_size == 0 || slot_size > max - 15 {
		return none
	}
	stride := align_forward(slot_size, 16)
	if stride > max / u64(slot_count) {
		return none
	}
	// u64'te hesaplanir: u32 toplami slot_count > 0xFFFFFFC0 icin sarardi.
	word_count := u32((u64(slot_count) + 63) / 64)
	m := parent.mark()
	slots := parent.alloc_aligned(stride * u64(slot_count), 64) or {
		parent.rewind(m)
		return none
	}
	bitmap := parent.alloc_aligned(u64(word_count) * 8, 64) or {
		parent.rewind(m)
		return none
	}
	free_bits := unsafe { &u64(bitmap) }
	for w in 0 .. int(word_count) {
		unsafe {
			free_bits[w] = max
		}
	}
	// Son kelimede slot_count'u asan bitler hic verilmesin diye 0'la.
	rem := slot_count % 64
	if rem != 0 {
		unsafe {
			free_bits[int(word_count) - 1] = (u64(1) << rem) - 1
		}
	}
	return PoolAllocator{
		slots:      unsafe { slots }
		stride:     stride
		slot_count: slot_count
		free_bits:  free_bits
		word_count: word_count
	}
}

// En dusuk bos slotu verir. Dolu ise none.
pub fn (mut p PoolAllocator) acquire() ?u32 {
	for w in int(p.first_free) .. int(p.word_count) {
		word := unsafe { p.free_bits[w] }
		if word == 0 {
			continue
		}
		bit := u32(bits.trailing_zeros_64(word))
		unsafe {
			p.free_bits[w] = word & ~(u64(1) << bit)
		}
		p.first_free = u32(w)
		p.live++
		return u32(w) * 64 + bit
	}
	p.first_free = p.word_count
	return none
}

// Slotu geri verir. Aralik disi ya da zaten bos ise false.
pub fn (mut p PoolAllocator) release(idx u32) bool {
	if idx >= p.slot_count {
		return false
	}
	w := int(idx / 64)
	bit := u64(1) << u64(idx % 64)
	word := unsafe { p.free_bits[w] }
	if word & bit != 0 {
		return false
	}
	unsafe {
		p.free_bits[w] = word | bit
	}
	if u32(w) < p.first_free {
		p.first_free = u32(w)
	}
	p.live--
	return true
}

pub fn (p &PoolAllocator) slot_ptr(idx u32) &u8 {
	assert idx < p.slot_count
	return unsafe { &u8(u64(p.slots) + u64(idx) * p.stride) }
}

pub fn (p &PoolAllocator) live_count() u32 {
	return p.live
}
