module memory

// Cift tamponlu kare arenasi. Her kare bir yarıya yazar, bir onceki kare
// yarisini yalnizca okur. advance() yeni yazma yarisini sifirlar.
pub struct EpochArena {
mut:
	arenas [2]LinearArena
	frame  u64
}

// Iki yariyi da parent'tan 64 hizali alir. Parent yetmezse none doner.
// shortcut: ikinci yari alinamazsa birinci yari parent'ta harcanmis kalir, geri alinmaz.
pub fn EpochArena.new(mut parent LinearArena, half_capacity u64) ?EpochArena {
	a := parent.alloc_aligned(half_capacity, 64) or { return none }
	b := parent.alloc_aligned(half_capacity, 64) or { return none }
	return EpochArena{
		arenas: [LinearArena.new(a, half_capacity), LinearArena.new(b, half_capacity)]!
	}
}

pub fn (mut e EpochArena) alloc(size u64, alignment u64) ?&u8 {
	return e.arenas[e.frame & 1].alloc_aligned(size, alignment)
}

// Okuma yarisi arenas[(frame - 1) & 1]. frame - 1 tasmasin diye (frame + 1) & 1 kullanilir.
pub fn (e &EpochArena) read_base() &u8 {
	return e.arenas[(e.frame + 1) & 1].base
}

pub fn (e &EpochArena) read_used() u64 {
	if e.frame == 0 {
		return 0
	}
	return e.arenas[(e.frame + 1) & 1].used()
}

pub fn (mut e EpochArena) advance() {
	e.frame++
	e.arenas[e.frame & 1].reset()
}
