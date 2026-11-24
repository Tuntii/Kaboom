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

// Bir PairPos alt tablosu: lookup sırası ve (tip 9 çözülmüş) alt tablo ofseti.
struct PairSub {
	lk int
	st int
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

// Tüm PairPos alt tabloları (tip 9 çözülmüş), lookup sırasıyla; kapsama gliflere göre sonra bakılır.
fn pair_subtables(d []u8, ll int) []PairSub {
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
			if t == gpos_pair_pos {
				out << PairSub{
					lk: li
					st: st
				}
			}
		}
	}
	return out
}

// Charset glif kimlikleri (gids, indeks = charset indeksi; 0 eksik glif) arasında sıfır olmayan tüm sıralı
// çiftler; sol<<16|sağ anahtarlı. Her alt tablo için kapsama bir kez hesaplanır, çiftler numaralandırılır.
// Kural: lookup içinde ilk eşleşen alt tablo kazanır; lookup'ların değerleri toplanır.
// shortcut: PairSet'ler sıralı ve tekil varsayılır (OpenType zorunluluğu); bozuk veride doğrusal tarama ikili
// aramadan farklı kayıt seçebilir. Yükseltme: bozuk font verisi gerçekçi hale gelirse PairSet sıralılığı doğrulanmalı
// ya da ikili arama yolu geri getirilmeli; bit-eşitlik şimdilik yalnızca geçerli fontlarda garanti.
fn gpos_kern_table(d []u8, gids []int) []KernPair {
	mut out := []KernPair{}
	ll := gpos_lookup_list(d)
	if ll < 0 {
		return out
	}
	n := gids.len
	mut maxg := 0
	for g in gids {
		if g > maxg {
			maxg = g
		}
	}
	// Glif kimliğinden charset indekslerine bağlı liste: head[g] ilk indeks, nxt[i] aynı glifin sonrakisi.
	mut head := []int{len: maxg + 1, init: -1}
	mut nxt := []int{len: n, init: -1}
	for i := n - 1; i >= 0; i-- {
		g := gids[i]
		if g > 0 {
			nxt[i] = head[g]
			head[g] = i
		}
	}
	mut vals := []i32{len: n * n}
	mut done := []bool{len: n * n}
	mut cov := []int{len: n}
	mut cls := []int{len: n}
	mut cur := -1
	for s in pair_subtables(d, ll) {
		if s.lk != cur {
			cur = s.lk
			for k in 0 .. done.len {
				done[k] = false
			}
		}
		st := s.st
		fmt := be_u16(d, st)
		cov_off := be_u16(d, st + 2)
		vf1 := be_u16(d, st + 4)
		vf2 := be_u16(d, st + 6)
		if (fmt != 1 && fmt != 2) || cov_off < 0 || vf1 < 0 || vf2 < 0 {
			continue
		}
		for i in 0 .. n {
			cov[i] = if gids[i] > 0 { coverage_index(d, st + cov_off, gids[i]) } else { -1 }
		}
		// XAdvance yalnızca 0x0004 bayrağıyla; ondan önceki bayraklı alanların boyu kadar ileride.
		has_xadv := vf1 & 0x0004 != 0
		xoff := value_size(vf1 & 0x0003)
		rec_vals := value_size(vf1) + value_size(vf2)
		if fmt == 1 {
			for i in 0 .. n {
				ci := cov[i]
				if ci < 0 {
					continue
				}
				mut ps := be_u16(d, st + 10 + 2 * ci)
				if ps < 0 {
					continue
				}
				ps += st
				for k in 0 .. be_u16(d, ps) {
					r := ps + 2 + k * (2 + rec_vals)
					sg := be_u16(d, r)
					if sg < 0 {
						break
					}
					if sg > maxg {
						continue
					}
					mut j := head[sg]
					for j >= 0 {
						if !done[i * n + j] {
							done[i * n + j] = true
							if has_xadv {
								vals[i * n + j] += i32(be_i16(d, r + 2 + xoff))
							}
						}
						j = nxt[j]
					}
				}
			}
			continue
		}
		cd1 := be_u16(d, st + 8)
		cd2 := be_u16(d, st + 10)
		c1cnt := be_u16(d, st + 12)
		c2cnt := be_u16(d, st + 14)
		if cd1 < 0 || cd2 < 0 || c1cnt < 0 || c2cnt < 0 {
			continue
		}
		for j in 0 .. n {
			cls[j] = if gids[j] > 0 { class_of(d, st + cd2, gids[j]) } else { 0 }
		}
		for i in 0 .. n {
			if cov[i] < 0 {
				continue
			}
			c1 := class_of(d, st + cd1, gids[i])
			if c1 >= c1cnt {
				continue
			}
			for j in 0 .. n {
				c2 := cls[j]
				if gids[j] <= 0 || c2 >= c2cnt || done[i * n + j] {
					continue
				}
				done[i * n + j] = true
				if has_xadv {
					vals[i * n + j] += i32(be_i16(d, st + 16 + (c1 * c2cnt + c2) * rec_vals + xoff))
				}
			}
		}
	}
	for i in 0 .. n {
		for j in 0 .. n {
			v := int(vals[i * n + j])
			if v != 0 {
				out << KernPair{
					key: u32(i) << 16 | u32(j)
					val: i16(v)
				}
			}
		}
	}
	// Geçici tablolar -gc none altında toplanmaz; bu çağrı bitince elle serbest bırakılır.
	unsafe {
		vals.free()
		done.free()
	}
	return out
}
