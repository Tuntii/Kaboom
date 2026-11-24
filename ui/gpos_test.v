module ui

// Referans (eski kaba kuvvet) PairPos okuyucusu: her sıralı çift için tüm alt tabloları tek tek tarar.
// Üretim yolu (gpos_kern_table) bununla bit-eşit olmalıdır; bu dosya dışında kullanılmaz.
struct RefPairSub {
	lk int
	st int
	ci int
}

fn ref_row_subtables(d []u8, ll int, lg int) []RefPairSub {
	mut out := []RefPairSub{}
	cnt := be_u16(d, ll)
	for li in 0 .. cnt {
		off := be_u16(d, ll + 2 + 2 * li)
		if off < 0 {
			continue
		}
		lk := ll + off
		typ := be_u16(d, lk)
		sub_cnt := be_u16(d, lk + 4)
		if typ < 0 || sub_cnt < 0 {
			continue
		}
		for i in 0 .. sub_cnt {
			st_off := be_u16(d, lk + 6 + 2 * i)
			if st_off < 0 {
				continue
			}
			mut st := lk + st_off
			mut t := typ
			if t == gpos_extension {
				t = be_u16(d, st + 2)
				ext := be_u32(d, st + 4)
				if ext < 0 {
					continue
				}
				st += ext
			}
			if t != gpos_pair_pos {
				continue
			}
			cov_off := be_u16(d, st + 2)
			if cov_off < 0 {
				continue
			}
			ci := coverage_index(d, st + cov_off, lg)
			if ci >= 0 {
				out << RefPairSub{
					lk: li
					st: st
					ci: ci
				}
			}
		}
	}
	return out
}

fn ref_pair_value(d []u8, s RefPairSub, lg int, rg int) (int, bool) {
	st := s.st
	fmt := be_u16(d, st)
	vf1 := be_u16(d, st + 4)
	vf2 := be_u16(d, st + 6)
	if vf1 < 0 || vf2 < 0 {
		return 0, false
	}
	has_xadv := vf1 & 0x0004 != 0
	xoff := value_size(vf1 & 0x0003)
	rec_vals := value_size(vf1) + value_size(vf2)
	if fmt == 1 {
		mut ps := be_u16(d, st + 10 + 2 * s.ci)
		if ps < 0 {
			return 0, false
		}
		ps += st
		mut lo := 0
		mut hi := be_u16(d, ps)
		for lo < hi {
			mid := (lo + hi) / 2
			r := ps + 2 + mid * (2 + rec_vals)
			sg := be_u16(d, r)
			if sg < 0 {
				return 0, false
			}
			if sg < rg {
				lo = mid + 1
			} else if sg > rg {
				hi = mid
			} else {
				if !has_xadv {
					return 0, true
				}
				return be_i16(d, r + 2 + xoff), true
			}
		}
		return 0, false
	}
	if fmt == 2 {
		cd1 := be_u16(d, st + 8)
		cd2 := be_u16(d, st + 10)
		c1cnt := be_u16(d, st + 12)
		c2cnt := be_u16(d, st + 14)
		if cd1 < 0 || cd2 < 0 || c1cnt < 0 || c2cnt < 0 {
			return 0, false
		}
		c1 := class_of(d, st + cd1, lg)
		c2 := class_of(d, st + cd2, rg)
		if c1 >= c1cnt || c2 >= c2cnt {
			return 0, false
		}
		if !has_xadv {
			return 0, true
		}
		r := st + 16 + (c1 * c2cnt + c2) * rec_vals
		return be_i16(d, r + xoff), true
	}
	return 0, false
}

// Sol glif satırı: her lookup'ta ilk eşleşen alt tablo; lookup'lar toplanır.
fn ref_row_pair(d []u8, subs []RefPairSub, lg int, rg int) int {
	mut sum := 0
	mut cur := -1
	mut found := false
	for s in subs {
		if s.lk != cur {
			cur = s.lk
			found = false
		}
		if found {
			continue
		}
		v, ok := ref_pair_value(d, s, lg, rg)
		if ok {
			sum += v
			found = true
		}
	}
	return sum
}

fn ref_gpos_pair_units(d []u8, ll int, lg int, rg int) int {
	return ref_row_pair(d, ref_row_subtables(d, ll, lg), lg, rg)
}

fn gpos_kern_table_ref(d []u8, gids []int) []KernPair {
	mut out := []KernPair{}
	ll := gpos_lookup_list(d)
	if ll < 0 {
		return out
	}
	for i, lg in gids {
		if lg == 0 {
			continue
		}
		subs := ref_row_subtables(d, ll, lg)
		if subs.len == 0 {
			continue
		}
		for j, rg in gids {
			if rg == 0 {
				continue
			}
			v := ref_row_pair(d, subs, lg, rg)
			if v != 0 {
				out << KernPair{
					key: u32(i) << 16 | u32(j)
					val: i16(v)
				}
			}
		}
	}
	return out
}

fn test_gpos_garbage_no_panic() {
	mut garbage := []u8{len: 512}
	for i in 0 .. garbage.len {
		garbage[i] = u8(0xFF - (i % 7))
	}
	assert gpos_lookup_list(garbage) < 0
	assert ref_gpos_pair_units(garbage, 0, 3, 7) == 0
	assert gpos_kern_table(garbage, [1, 2, 3]).len == 0
}

fn test_gpos_truncated_font_no_panic() {
	full := face_bytes(.sans)
	for cut in [12, 100, 1000, full.len / 2] {
		short := full[..cut].clone()
		// Kesik tabloda değerler geçerli olabilir; burada yalnızca panik olmadığı doğrulanır.
		ll := gpos_lookup_list(short)
		if ll >= 0 {
			_ = ref_gpos_pair_units(short, ll, 3, 7)
		}
		_ = gpos_kern_table(short, [1, 2, 3])
	}
}

// Numaralandırma tablosu, referans kaba kuvvet tablosuyla çift sayısı ve her değer bakımından eşit.
fn test_kern_table_matches_reference() {
	a := Atlas.build(1.0) or { panic(err) }
	for face in [FontFace.sans, .sans_medium, .mono] {
		d := face_bytes(face)
		gids := a.face_gids(face)
		want := gpos_kern_table_ref(d, gids)
		got := gpos_kern_table(d, gids)
		if face != .mono {
			assert want.len > 0
		}
		assert got.len == want.len, 'yuz ${int(face)}: ${got.len} != ${want.len}'
		for p in 0 .. want.len {
			assert got[p].key == want[p].key, "yuz ${int(face)} anahtar ${p}"
			assert got[p].val == want[p].val, "yuz ${int(face)} deger ${p}"
		}
	}
}
