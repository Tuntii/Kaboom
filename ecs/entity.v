module ecs

// EntityID bit düzeni: 0..31 index, 32..47 generation, 48..63 her zaman 0.
pub type EntityID = u64

pub const max_generation = u16(0xFFFF)
pub const null_index = u32(0xFFFFFFFF)

pub const null_entity = make_entity(null_index, 0)

@[inline]
pub fn make_entity(index u32, gen u16) EntityID {
	return EntityID(u64(index) | (u64(gen) << 32))
}

@[inline]
pub fn (e EntityID) index() u32 {
	return u32(u64(e) & 0xFFFFFFFF)
}

@[inline]
pub fn (e EntityID) generation() u16 {
	return u16((u64(e) >> 32) & 0xFFFF)
}

@[inline]
pub fn (e EntityID) is_null() bool {
	return e.index() == null_index
}
