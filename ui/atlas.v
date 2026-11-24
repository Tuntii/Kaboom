module ui

import math

// stbtt_fontinfo boyutu (64-bit MinGW'de 168); atlas_test.v sizeof ile doğrular.
const stbtt_info_size = 168
const roles_n = 7
const atlas_min_side = 512
const atlas_max_side = 4096

// Atlas dikdörtgenleri: u/v normalize, x/y fiziksel piksel (taban çizgisine göre).
pub struct Glyph {
pub mut:
	u0      f32
	v0      f32
	u1      f32
	v1      f32
	x0      f32
	y0      f32
	x1      f32
	y1      f32
	advance f32
}

struct RoleMetrics {
	fsc  f32 // fiziksel piksel / font birimi
	asc  f32 // mantıksal piksel
	line f32 // mantıksal piksel
}

// Tek kanallı (R8) atlas. Stb tutamaçları kerning için saklanır; bayt dizileri gömülü fontlara işaret eder.
pub struct Atlas {
pub:
	sc f32
mut:
	w       int
	h       int
	px      []u8
	cps     []u32
	glyphs  []Glyph
	icons   [icon_n]Glyph
	white_u f32
	white_v f32
	metrics [roles_n]RoleMetrics
	infos   [3][stbtt_info_size]u8
	kerns   [3][]KernPair // yüz başına sıralı çift tablosu (charset indeksleri)
}

pub fn Atlas.build(scale f32) !Atlas {
	if scale <= 0 {
		return error('atlas: ölçek pozitif olmalı')
	}
	cps := charset()
	n := cps.len
	roles := [TextRole.caption, .label, .body, .body_strong, .title, .heading, .mono]
	mut a := Atlas{
		sc:     scale
		cps:    cps
		glyphs: []Glyph{len: roles_n * n}
	}
	mut faces := [][]u8{}
	for face in [FontFace.sans, .sans_medium, .mono] {
		data := face_bytes(face)
		faces << data
		if C.stbtt_InitFont(info_of(&a.infos[int(face)]), unsafe { &u8(data.data) }, 0) == 0 {
			return error('atlas: font okunamadı')
		}
	}
	mut gid := []int{len: roles_n * n}
	// Eksik glifler '?' ile aynı atlas konumunu paylaşır; kendi yuvasını almaz.
	mut missing := []bool{len: roles_n * n}
	for r, role in roles {
		face, size := role.spec()
		info := info_of(&a.infos[int(face)])
		ph := int(math.round(f64(size * scale)))
		fsc := C.stbtt_ScaleForPixelHeight(info, f32(ph))
		mut asc := 0
		mut desc := 0
		mut gap := 0
		C.stbtt_GetFontVMetrics(info, &asc, &desc, &gap)
		a.metrics[r] = RoleMetrics{
			fsc:  fsc
			asc:  f32(asc) * fsc / scale
			line: f32(asc - desc + gap) * fsc / scale
		}
		for ci, cp in cps {
			mut g := C.stbtt_FindGlyphIndex(info, int(cp))
			if g == 0 {
				g = C.stbtt_FindGlyphIndex(info, 0x3F)
				missing[r * n + ci] = true
			}
			mut adv := 0
			mut lsb := 0
			C.stbtt_GetGlyphHMetrics(info, g, &adv, &lsb)
			mut x0 := 0
			mut y0 := 0
			mut x1 := 0
			mut y1 := 0
			C.stbtt_GetGlyphBitmapBox(info, g, fsc, fsc, &x0, &y0, &x1, &y1)
			a.glyphs[r * n + ci] = Glyph{
				x0:      f32(x0)
				y0:      f32(y0)
				x1:      f32(x1)
				y1:      f32(y1)
				advance: f32(adv) * fsc
			}
			gid[r * n + ci] = g
		}
	}
	// Kerning yalnızca gerçek glif kimlikleriyle; eksik glifler (0) atlanır.
	for face in [FontFace.sans, .sans_medium, .mono] {
		info := info_of(&a.infos[int(face)])
		mut gids := []int{len: n}
		for ci, cp in cps {
			gids[ci] = C.stbtt_FindGlyphIndex(info, int(cp))
		}
		a.kerns[int(face)] = gpos_kern_table(faces[int(face)], gids)
	}
	isz := int(math.round(f64(icon_size * scale)))
	mut dims := [][2]int{cap: 1 + roles_n * n + icon_n}
	dims << [1, 1]!
	for idx, g in a.glyphs {
		if missing[idx] {
			dims << [0, 0]!
		} else {
			dims << [int(g.x1 - g.x0), int(g.y1 - g.y0)]!
		}
	}
	for _ in 0 .. icon_n {
		dims << [isz, isz]!
	}
	side, pos := shelf_pack(dims)!
	a.w = side
	a.h = side
	a.px = []u8{len: side * side}
	for r in 0 .. roles_n {
		face, _ := roles[r].spec()
		info := info_of(&a.infos[int(face)])
		fsc := a.metrics[r].fsc
		for ci in 0 .. n {
			idx := r * n + ci
			g := a.glyphs[idx]
			w := int(g.x1 - g.x0)
			h := int(g.y1 - g.y0)
			if missing[idx] || w == 0 || h == 0 {
				continue
			}
			p := pos[idx + 1]
			C.stbtt_MakeGlyphBitmap(info, &a.px[p[1] * side + p[0]], w, h, side, fsc, fsc, gid[idx])
		}
	}
	for i, ic in all_icons() {
		p := pos[1 + roles_n * n + i]
		rasterize_icon(mut a.px, side, p[0], p[1], isz, scale, icon_paths(ic))
	}
	fs := f32(side)
	for idx in 0 .. roles_n * n {
		if !missing[idx] {
			a.glyphs[idx] = with_uv(a.glyphs[idx], pos[idx + 1], fs)
		}
	}
	// '?' charset'in ilk aralığında (U+0020 başlangıçlı): indeks 0x3F - 0x20.
	qi := 0x3F - 0x20
	for r in 0 .. roles_n {
		for ci in 0 .. n {
			if missing[r * n + ci] {
				a.glyphs[r * n + ci] = a.glyphs[r * n + qi]
			}
		}
	}
	for i in 0 .. icon_n {
		p := pos[1 + roles_n * n + i]
		a.icons[i] = with_uv(Glyph{ x1: f32(isz), y1: f32(isz), advance: f32(isz) }, p, fs)
	}
	wp := pos[0]
	a.px[wp[1] * side + wp[0]] = 255
	a.white_u = (f32(wp[0]) + 0.5) / fs
	a.white_v = (f32(wp[1]) + 0.5) / fs
	return a
}

// Glifin atlas konumunu (sol üst köşe) ve boyutunu normalize UV'ye çevirir.
fn with_uv(g Glyph, p [2]int, fs f32) Glyph {
	mut o := g
	o.u0 = f32(p[0]) / fs
	o.v0 = f32(p[1]) / fs
	o.u1 = (f32(p[0]) + g.x1 - g.x0) / fs
	o.v1 = (f32(p[1]) + g.y1 - g.y0) / fs
	return o
}

// Sıralı raf yerleştirme, 1 px boşluk; sığmazsa kenar ikiye katlanır.
fn shelf_pack(dims [][2]int) !(int, [][2]int) {
	mut side := atlas_min_side
	for {
		if pos := shelf_place(dims, side) {
			return side, pos
		}
		side *= 2
		if side > atlas_max_side {
			return error('atlas: 4096 px sınırını aşıyor')
		}
	}
	return error('unreachable')
}

fn shelf_place(dims [][2]int, side int) ?[][2]int {
	mut pos := [][2]int{len: dims.len}
	mut x := 0
	mut y := 0
	mut shelf := 0
	for i, d in dims {
		if d[0] == 0 || d[1] == 0 {
			continue
		}
		if x + d[0] > side {
			x = 0
			y += shelf + 1
			shelf = 0
		}
		if x + d[0] > side || y + d[1] > side {
			return none
		}
		pos[i] = [x, y]!
		x += d[0] + 1
		if d[1] > shelf {
			shelf = d[1]
		}
	}
	return pos
}

fn info_of(buf &[stbtt_info_size]u8) &C.stbtt_fontinfo {
	return unsafe { &C.stbtt_fontinfo(buf) }
}

// Gömülü font baytları; ikiliden okunur (kopyasız), çalışma zamanında dosya yolu yoktur.
fn face_bytes(face FontFace) []u8 {
	if face == .sans {
		mut f := $embed_file('../assets/fonts/Inter-Regular.ttf')
		return unsafe { (&u8(f.data())).vbytes(f.len) }
	}
	if face == .sans_medium {
		mut f := $embed_file('../assets/fonts/Inter-Medium.ttf')
		return unsafe { (&u8(f.data())).vbytes(f.len) }
	}
	mut f := $embed_file('../assets/fonts/JetBrainsMono-Regular.ttf')
	return unsafe { (&u8(f.data())).vbytes(f.len) }
}

// Karakter kümesi, sıralı; U+0020–U+007E, U+00A0–U+017F ve ek noktalama/oklar.
fn charset() []u32 {
	pairs := [u32(0x20), 0x7E, 0xA0, 0xFF, 0x100, 0x17F, 0x2013, 0x2014, 0x2022, 0x2022, 0x2026, 0x2026, 0x2190,
		0x2193, 0x2212, 0x2212]
	mut out := []u32{}
	for i := 0; i < pairs.len; i += 2 {
		for cp := pairs[i]; cp <= pairs[i + 1]; cp++ {
			out << cp
		}
	}
	return out
}

pub fn (a &Atlas) width() int {
	return a.w
}

pub fn (a &Atlas) height() int {
	return a.h
}

pub fn (a &Atlas) pixels() []u8 {
	return a.px
}

pub fn (a &Atlas) scale() f32 {
	return a.sc
}

// Atlasta bulunan glif var mı (yüz başına; eksik glif '?' ile çizilir).
pub fn (a &Atlas) has_glyph(face FontFace, cp u32) bool {
	return C.stbtt_FindGlyphIndex(info_of(&a.infos[int(face)]), int(cp)) != 0
}

fn (a &Atlas) index_of(cp u32) int {
	mut lo := 0
	mut hi := a.cps.len
	for lo < hi {
		mid := (lo + hi) / 2
		if a.cps[mid] < cp {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < a.cps.len && a.cps[lo] == cp {
		return lo
	}
	return -1
}

// Atlasta olmayan kod noktası için '?' indeksi.
fn (a &Atlas) index_or_fallback(cp u32) int {
	i := a.index_of(cp)
	if i < 0 {
		return a.index_of(u32(0x3F))
	}
	return i
}

pub fn (a &Atlas) glyph(role TextRole, cp u32) Glyph {
	return a.glyphs[int(role) * a.cps.len + a.index_or_fallback(cp)]
}

pub fn (a &Atlas) icon(i Icon) Glyph {
	return a.icons[int(i)]
}

pub fn (a &Atlas) white_uv() (f32, f32) {
	return a.white_u, a.white_v
}

// Mantıksal piksel genişlik; kerning dahil, tahsis yok.
pub fn (a &Atlas) measure(text string, role TextRole) f32 {
	mut total := f32(0)
	mut prev := u32(0)
	mut i := 0
	for i < text.len {
		cp, next := utf8_next(text, i)
		if i > 0 {
			total += a.kern(role, prev, cp)
		}
		total += a.glyph(role, cp).advance
		prev = cp
		i = next
	}
	return total / a.sc
}

pub fn (a &Atlas) line_height(role TextRole) f32 {
	return a.metrics[int(role)].line
}

pub fn (a &Atlas) ascent(role TextRole) f32 {
	return a.metrics[int(role)].asc
}

// Fiziksel piksel; GPOS çifti tablosunda ikili arama, tahsis yok.
pub fn (a &Atlas) kern(role TextRole, prev u32, cp u32) f32 {
	face, _ := role.spec()
	tab := a.kerns[int(face)]
	key := u32(a.index_or_fallback(prev)) << 16 | u32(a.index_or_fallback(cp))
	mut lo := 0
	mut hi := tab.len
	for lo < hi {
		mid := (lo + hi) / 2
		if tab[mid].key < key {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < tab.len && tab[lo].key == key {
		return f32(tab[lo].val) * a.metrics[int(role)].fsc
	}
	return 0
}

// Kod noktası ve sonraki bayt indeksi; geçersiz dizi U+FFFD, 1 bayt ilerler.
pub fn utf8_next(s string, i int) (u32, int) {
	b0 := s[i]
	if b0 < 0x80 {
		return u32(b0), i + 1
	}
	mut n := 0
	mut cp := u32(0)
	mut lo := u8(0x80)
	mut hi := u8(0xBF)
	if b0 >= 0xC2 && b0 <= 0xDF {
		n = 2
		cp = u32(b0 & 0x1F)
	} else if b0 >= 0xE0 && b0 <= 0xEF {
		n = 3
		cp = u32(b0 & 0x0F)
		if b0 == 0xE0 {
			lo = 0xA0
		} else if b0 == 0xED {
			hi = 0x9F
		}
	} else if b0 >= 0xF0 && b0 <= 0xF4 {
		n = 4
		cp = u32(b0 & 0x07)
		if b0 == 0xF0 {
			lo = 0x90
		} else if b0 == 0xF4 {
			hi = 0x8F
		}
	} else {
		return 0xFFFD, i + 1
	}
	if i + n > s.len {
		return 0xFFFD, i + 1
	}
	for k in 1 .. n {
		b := s[i + k]
		l := if k == 1 { lo } else { u8(0x80) }
		h := if k == 1 { hi } else { u8(0xBF) }
		if b < l || b > h {
			return 0xFFFD, i + 1
		}
		cp = (cp << 6) | u32(b & 0x3F)
	}
	return cp, i + n
}
