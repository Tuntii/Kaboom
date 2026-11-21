module memory

// Bump allocator. Tum tahsisatcilar bunun uzerine kurulur.
@[aligned: 64]
pub struct LinearArena {
mut:
	base     &u8
	capacity u64
	offset   u64
	failed   u64
}

pub fn LinearArena.new(base &u8, cap u64) LinearArena {
	return LinearArena{
		base:     unsafe { base }
		capacity: cap
	}
}

// Hizalanmis tahsis. Tasmada ya da gecersiz hizalamada none doner ve offset degismez.
// Toplama yapmadan once kontrol edilir: offset <= capacity invariantı altinda
// capacity - offset asla negatif olmaz, align_forward'in u64 sarmasina guvenilmez.
pub fn (mut a LinearArena) alloc_aligned(size u64, alignment u64) ?&u8 {
	// assert -prod'da silinir; hizalama kontrolu her derlemede calismali.
	if !is_pow2(alignment) {
		a.failed++
		return none
	}
	curr := u64(a.base) + a.offset
	padding := pad_for(curr, alignment)
	if padding > a.capacity - a.offset || size > a.capacity - a.offset - padding {
		a.failed++
		return none
	}
	a.offset += padding + size
	return unsafe { &u8(curr + padding) }
}

pub fn (mut a LinearArena) reset() {
	a.offset = 0
}

pub fn (a &LinearArena) used() u64 {
	return a.offset
}

// Geri sarma noktasi: su anki imlec.
pub fn (a &LinearArena) mark() u64 {
	return a.offset
}

// Imleci m'e geri alir. m mevcut imlecten ilerideyse yok sayilir (ileri sarma yok).
pub fn (mut a LinearArena) rewind(m u64) {
	if m <= a.offset {
		a.offset = m
	}
}

// Reddedilen (tasmali ya da gecersiz hizalamali) tahsis sayisi.
pub fn (a &LinearArena) failed_allocs() u64 {
	return a.failed
}
