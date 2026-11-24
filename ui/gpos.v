module ui

// GPOS PairPos (tip 2, tip 9 üzerinden) çifti kerning'i: saf bayt okuyucu.
// Her okuma sınır kontrollüdür; geçersiz ofset -1 ya da 0 döner, panik yoktur.

const gpos_pair_pos = 2
const gpos_extension = 9

// KernPair: sol<<16|sağ charset indeksleri ve font birimi XAdvance.
pub struct KernPair {
pub:
	key u32
	val i16
}

// Sol glifi kapsayan bir PairPos alt tablosu: lookup sırası, alt tablo ofseti, kapsama indeksi.
struct PairSub {
	lk int
	st int
	ci int
}

fn be_u16(d []u8, o int) int {
	if o < 0 || o + 2 > d.len {
		return -1
	}
	return int(u32(d[o]) << 8 | u32(d[o + 1]))
}

fn be_u32(d []u8, o int) int {
	if o < 0 || o + 4 > d.len {
		return -1
	}
	return int(u32(d[o]) << 24 | u32(d[o + 1]) << 16 | u32(d[o + 2]) << 8 | u32(d[o + 3]))
}

fn be_i16(d []u8, o int) int {
	v := be_u16(d, o)
	if v < 0 {
		return 0
	}
	if v >= 0x8000 {
		return v - 0x10000
	}
	return v
}

fn max_zero(v int) int {
	if v < 0 {
		return 0
	}
	return v
}

// Sfnt tablo dizininde etiketi arar; bulunamazsa -1.
fn sfnt_table(d []u8, tag string) int {
	n := be_u16(d, 4)
	for i in 0 .. n {
		r := 12 + i * 16
		if r + 16 > d.len {
			return -1
		}
		if d[r] == tag[0] && d[r + 1] == tag[1] && d[r + 2] == tag[2] && d[r + 3] == tag[3] {
			return be_u32(d, r + 8)
		}
	}
	return -1
}

// GPOS'taki LookupList'in mutlak ofseti; yoksa -1.
fn gpos_lookup_list(d []u8) int {
	gpos := sfnt_table(d, 'GPOS')
	if gpos < 0 {
		return -1
	}
	off := be_u16(d, gpos + 8)
	if off < 0 {
		return -1
	}
	return gpos + off
}

// Değer kaydındaki alanların toplam bayt boyu (bayrak başına 2 bayt).
fn value_size(vf int) int {
	mut n := 0
	mut v := vf
	for v != 0 {
		n += v & 1
		v >>= 1
	}
	return n * 2
}

// (başlangıç, bitiş, değer) kayıtlarında g'yi içeren kaydın mutlak ofseti; yoksa -1.
fn range_rec(d []u8, base int, cnt int, g int) int {
	mut lo := 0
	mut hi := cnt
	for lo < hi {
		mid := (lo + hi) / 2
		r := base + mid * 6
		s := be_u16(d, r)
		e := be_u16(d, r + 2)
		if s < 0 || e < 0 {
			return -1
		}
		if g < s {
			hi = mid
		} else if g > e {
			lo = mid + 1
		} else {
			return r
		}
	}
	return -1
}

// Kapsama tablosunda g'nin indeksi; kapsamda değilse -1. Format 1 ikili arama, format 2 aralık.
fn coverage_index(d []u8, cov int, g int) int {
	fmt := be_u16(d, cov)
	if fmt == 1 {
		mut lo := 0
		mut hi := be_u16(d, cov + 2)
		for lo < hi {
			mid := (lo + hi) / 2
			v := be_u16(d, cov + 4 + 2 * mid)
			if v < 0 {
				return -1
			}
			if v < g {
				lo = mid + 1
			} else if v > g {
				hi = mid
			} else {
				return mid
			}
		}
		return -1
	}
	if fmt == 2 {
		r := range_rec(d, cov + 4, be_u16(d, cov + 2), g)
		if r < 0 {
			return -1
		}
		return be_u16(d, r + 4) + g - be_u16(d, r)
	}
	return -1
}

// Sınıf tanımı; kapsam dışı glif sınıf 0.
fn class_of(d []u8, cd int, g int) int {
	fmt := be_u16(d, cd)
	if fmt == 1 {
		start := be_u16(d, cd + 2)
		cnt := be_u16(d, cd + 4)
		if start < 0 || cnt < 0 || g < start || g >= start + cnt {
			return 0
		}
		return max_zero(be_u16(d, cd + 6 + 2 * (g - start)))
	}
	if fmt == 2 {
		r := range_rec(d, cd + 4, be_u16(d, cd + 2), g)
		if r < 0 {
			return 0
		}
		return max_zero(be_u16(d, r + 4))
	}
	return 0
}

// Sol glifi kapsayan PairPos alt tablolarını (tip 9 çözülmüş) lookup sırasıyla toplar.
fn row_subtables(d []u8, ll int, lg int) []PairSub {
	mut out := []PairSub{}
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
				out << PairSub{
					lk: li
					st: st
					ci: ci
				}
			}
		}
	}
	return out
}

// Alt tablo için sağ glifin XAdvance değeri (font birimi) ve eşleşme.
fn pair_value(d []u8, s PairSub, lg int, rg int) (int, bool) {
	st := s.st
	fmt := be_u16(d, st)
	vf1 := be_u16(d, st + 4)
	vf2 := be_u16(d, st + 6)
	if vf1 < 0 || vf2 < 0 {
		return 0, false
	}
	// XAdvance yalnızca 0x0004 bayrağı varsa; value1'de ondan önceki bayraklı alanların boyu kadar ileride.
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

// Sol glifin satırı için sağ glif değeri: her lookup'ta ilk eşleşen alt tablo, lookup'lar toplanır.
fn row_pair(d []u8, subs []PairSub, lg int, rg int) int {
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
		v, ok := pair_value(d, s, lg, rg)
		if ok {
			sum += v
			found = true
		}
	}
	return sum
}

// Tek çift için toplam XAdvance (font birimi); testler ve kesik veri için.
fn gpos_pair_units(d []u8, ll int, lg int, rg int) int {
	return row_pair(d, row_subtables(d, ll, lg), lg, rg)
}

// Charset glif kimlikleri (gids) arasında sıfır olmayan tüm sıralı çiftler; sol<<16|sağ anahtarlı.
// gids indeksleri charset indeksleridir; 0 glif kimliği (eksik glif) atlanır.
fn gpos_kern_table(d []u8, gids []int) []KernPair {
	mut out := []KernPair{}
	ll := gpos_lookup_list(d)
	if ll < 0 {
		return out
	}
	for i, lg in gids {
		if lg == 0 {
			continue
		}
		subs := row_subtables(d, ll, lg)
		if subs.len == 0 {
			continue
		}
		for j, rg in gids {
			if rg == 0 {
				continue
			}
			v := row_pair(d, subs, lg, rg)
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
