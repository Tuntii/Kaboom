module platform

fn test_utf16_combine_pairs() {
	p1, r1 := utf16_combine(u16(0), 0xD83D)
	assert p1 == 0xD83D && r1 == none
	p2, r2 := utf16_combine(p1, 0xDE00)
	assert p2 == 0 && (r2 or { u32(0) }) == 0x1F600
	_, r3 := utf16_combine(u16(0), 0xDE00)
	assert (r3 or { u32(0) }) == 0xFFFD
	_, r4 := utf16_combine(u16(0), 0x011F)
	assert (r4 or { u32(0) }) == 0x011F
}
