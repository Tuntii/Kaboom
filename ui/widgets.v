module ui

pub enum ButtonKind {
	primary
	secondary
	ghost
}

pub fn (mut c Context) button(label string, kind ButtonKind) bool {
	return c.button_ex(label, kind, true)
}

// Düğme renkleri, kenarlık rengi ve kalınlığı. Devre dışı öğe accent taşımaz (birincil: surface_2 + 1 px border).
fn button_style(kind ButtonKind, enabled bool, t f32) (Color, Color, Color, f32) {
	mut bg := mix(surface_2, surface_hover, t)
	mut fg := if enabled { text_primary } else { text_muted }
	mut edge := Color(0)
	mut edge_w := f32(0)
	match kind {
		.primary {
			if enabled {
				bg = mix(accent, accent_hover, t)
				fg = accent_text
			} else {
				bg = surface_2
				edge = border
				edge_w = 1
			}
		}
		.secondary {
			edge = border
			edge_w = 1
		}
		.ghost {
			bg = mix(surface_hover.with_alpha(0), surface_hover, t)
		}
	}
	return bg, fg, edge, edge_w
}

pub fn (mut c Context) button_ex(label string, kind ButtonKind, enabled bool) bool {
	id := c.id(label)
	it := c.interact(id, enabled)
	t := c.hover_t(id, enabled && it.hovered)
	bg, fg, edge, edge_w := button_style(kind, enabled, t)
	c.open(label, Box{
		width:       fit()
		height:      fixed(control_h)
		padding:     pad_xy(space_3, 0)
		align_main:  .center
		align_cross: .center
		bg:          bg
		border:      edge
		border_w:    edge_w
		radius:      radius_control
	})
	c.text(label, .body_strong, fg)
	c.close()
	return enabled && it.clicked
}

pub fn (mut c Context) icon_button(label string, i Icon, active bool) bool {
	id := c.id(label)
	it := c.interact(id, true)
	t := c.hover_t(id, it.hovered)
	bg := if active { surface_2 } else { mix(surface_hover.with_alpha(0), surface_hover, t) }
	c.open(label, Box{
		width:       fixed(control_h)
		height:      fixed(control_h)
		align_main:  .center
		align_cross: .center
		bg:          bg
		radius:      radius_control
	})
	c.icon(i, if active { text_primary } else { text_secondary })
	c.close()
	return it.clicked
}

// value bool parametresi V'de mut olamaz; çağıran &bool verir.
pub fn (mut c Context) checkbox(label string, mut value &bool) bool {
	it := c.interact(c.id(label), true)
	mut changed := false
	if it.clicked {
		unsafe {
			*value = !*value
		}
		changed = true
	}
	checked := unsafe { *value }
	c.open(label, Box{
		dir:         .row
		width:       fit()
		height:      fixed(control_h)
		gap:         space_2
		align_cross: .center
	})
	// İşaretli kutu: dolu vurgu ve check ikonu; işaretsiz kutu yalnızca çerçeve.
	mut idx := -1
	if checked {
		idx = c.leaf(.icon, Box{
			width:    fixed(icon_size)
			height:   fixed(icon_size)
			bg:       accent
			border:   accent
			border_w: 1
			radius:   radius_control
		})
		if idx >= 0 {
			c.nodes[idx].icon = .check
			c.nodes[idx].color = accent_text
		}
	} else {
		c.leaf(.plain, Box{
			width:    fixed(icon_size)
			height:   fixed(icon_size)
			bg:       surface_2
			border:   border_strong
			border_w: 1
			radius:   radius_control
		})
	}
	c.text(label, .body, text_primary)
	c.close()
	return changed
}

// Sağa ek içerik gerektiğinde list_row yerine bu çift kullanılır.
pub fn (mut c Context) list_row_begin(label string, selected bool) Interaction {
	id := c.id(label)
	it := c.interact(id, true)
	t := c.hover_t(id, it.hovered)
	bg := if selected { selection_bg } else { mix(surface_hover.with_alpha(0), surface_hover, t) }
	c.open(label, Box{
		dir:         .row
		width:       grow()
		height:      fixed(row_h)
		padding:     pad_xy(space_3, 0)
		gap:         space_2
		align_cross: .center
		bg:          bg
	})
	return it
}

pub fn (mut c Context) list_row_end() {
	c.close()
}

pub fn (mut c Context) list_row(label string, text string, selected bool) bool {
	it := c.list_row_begin(label, selected)
	c.text_trunc(text, .body, text_primary, c.prev_inner_w(c.id(label), space_3))
	c.list_row_end()
	return it.clicked
}

// Bölüm seçenekleri. trailing_icon doluysa başlığın sağ ucunda ghost ikon düğmesi çıkar (ör. bileşen çıkar).
pub struct SectionOpts {
pub:
	default_open  bool = true
	trailing_icon ?Icon
	trailing_tip  string
}

pub struct SectionResult {
pub:
	open             bool
	trailing_clicked bool
}

// Katlanabilir başlık; açık durumu kalıcıdır, varsayılan açık. Açıksa true döner.
pub fn (mut c Context) section(label string, title string) bool {
	return c.section_ex(label, title, SectionOpts{}).open
}

// section'ın seçenekli biçimi. Sağ ikon başlığı katlamaz; yalnızca trailing_clicked olur.
pub fn (mut c Context) section_ex(label string, title string, o SectionOpts) SectionResult {
	id := c.id(label)
	it := c.interact(id, true)
	open := c.section_open(id, it.clicked, o.default_open)
	t := c.hover_t(id, it.hovered)
	c.open(label, Box{
		dir:         .row
		width:       grow()
		height:      fixed(row_h)
		gap:         space_1
		align_cross: .center
		bg:          mix(surface_hover.with_alpha(0), surface_hover, t)
	})
	c.icon(if open { Icon.chevron_down } else { Icon.chevron_right }, text_secondary)
	c.text(title, .body_strong, text_primary)
	mut trailing := false
	if icon := o.trailing_icon {
		c.spacer()
		// Kimlik: bölüm kimliğinin altında (push_id) ayrı; düğüm kimliği open ile aynı taban üzerinden.
		c.push_id(1)
		trailing = c.section_trailing(icon)
		c.pop_id()
		if o.trailing_tip.len > 0 {
			c.tooltip(o.trailing_tip)
		}
	}
	c.close()
	return SectionResult{
		open:             open
		trailing_clicked: trailing
	}
}

// Bölüm başlığının sağ ghost düğmesi: row_h kare, tıklanınca true.
fn (mut c Context) section_trailing(i Icon) bool {
	it := c.interact(c.id('trail'), true)
	t := c.hover_t(c.id('trail'), it.hovered)
	c.open('trail', Box{
		width:       fixed(row_h)
		height:      fixed(row_h)
		align_main:  .center
		align_cross: .center
		bg:          mix(surface_hover.with_alpha(0), surface_hover, t)
		radius:      radius_control
	})
	c.icon(i, text_secondary)
	c.close()
	return it.clicked
}

const ellipsis_cp = u32(0x2026)

// Sığmayan metin sonunda … ile, kod noktası sınırında kesilir. Yeni string kurulmaz: glifler yerleşim
// sırasında doğrudan çizilir. max_w mantıksal piksel; metnin kendisi çizilmiş genişliği ≤ max_w (…dahil).
pub fn (mut c Context) text_trunc(s string, role TextRole, color Color, max_w f32) {
	i := c.leaf(.text, Box{
		width:  fit()
		height: fit()
	})
	if i < 0 {
		return
	}
	c.nodes[i].text = s
	c.nodes[i].role = role
	c.nodes[i].color = color
	c.nodes[i].content[1] = c.atl.line_height(role)
	full := c.atl.measure(s, role)
	if full <= max_w {
		c.nodes[i].content[0] = full
		return
	}
	at, w := trunc_prefix(c.atl, s, role, max_w * c.atl.scale())
	c.nodes[i].ell = true
	c.nodes[i].ell_at = at
	c.nodes[i].content[0] = w / c.atl.scale()
}

// En uzun kod noktası sınırı (bayt indeksi) ki prefix + … fiziksel max_px içine sığsın; genişlik … dahil (fiziksel).
// Hiçbiri sığmazsa 0 ve yalnız … (taşar; sığmayan dar kutu en kötü durumdur).
fn trunc_prefix(a &Atlas, s string, role TextRole, max_px f32) (int, f32) {
	ell_adv := a.glyph(role, ellipsis_cp).advance
	mut pen := f32(0)
	mut prev := u32(0)
	mut k := 0
	mut best := 0
	mut best_w := ell_adv
	for {
		wk := if k > 0 { pen + a.kern(role, prev, ellipsis_cp) + ell_adv } else { ell_adv }
		if wk > max_px {
			break
		}
		best = k
		best_w = wk
		if k >= s.len {
			break
		}
		cp, next := utf8_next(s, k)
		if k > 0 {
			pen += a.kern(role, prev, cp)
		}
		pen += a.glyph(role, cp).advance
		prev = cp
		k = next
	}
	return best, best_w
}

// Önceki karenin kutusunun yatay iç genişliği (kenar boşlukları düşülür); ilk karede sınır yok.
fn (c &Context) prev_inner_w(id u32, pad f32) f32 {
	r := c.prev_rect(id) or { return f32(1e9) }
	return r.w - 2 * pad
}

pub fn (mut c Context) separator() {
	c.leaf(.plain, Box{
		width:  grow()
		height: fixed(1)
		bg:     border
	})
}

// Dikey tutamak: sürükleme size'ı yatay delta kadar değiştirir, [min, max] içinde kalır.
// grows_right: sağa sürükleme size'ı artırır (sol panel); false ise sağ panel için ters yönlüdür.
// size &f32: V'de mut skaler parametre yok. Tıklama alanı splitter_w; görünen çizgi 1 px.
pub fn (mut c Context) splitter(label string, mut size &f32, min f32, max f32, grows_right bool) {
	id := c.id(label)
	it := c.interact(id, false)
	active := it.hovered || it.dragging
	unsafe {
		mut v := *size
		if it.dragging {
			v += if grows_right { it.drag_dx } else { -it.drag_dx }
		}
		if v < min {
			v = min
		}
		if v > max {
			v = max
		}
		*size = v
	}
	if active {
		c.set_cursor_hint(.resize_h)
	}
	t := c.hover_t(id, active)
	c.open(label, Box{
		width:      fixed(splitter_w)
		height:     grow()
		align_main: .center
	})
	c.leaf(.plain, Box{
		width:  fixed(1)
		height: grow()
		bg:     mix(border, accent, t)
	})
	c.close()
}

// Özellik satırı: sabit genişlikte etiket sütunu, kalan genişliği dolduran alan (number_field).
// Bir bölümdeki satırlar aynı etiket sütununu paylaşır; etiket dikeyde ortalı.
pub fn (mut c Context) property_row_begin(label string) {
	c.open('prop_row', Box{
		dir:         .row
		width:       grow()
		height:      fit()
		gap:         space_2
		align_cross: .center
	})
	c.open('prop_label', Box{
		width:  fixed(label_col_w)
		height: fit()
	})
	c.text(label, .label, text_secondary)
	c.close()
	c.open('prop_field', Box{
		dir:         .row
		width:       grow()
		height:      fit()
		align_cross: .center
	})
	c.in_prop = true
}

pub fn (mut c Context) property_row_end() {
	c.in_prop = false
	c.close()
	c.close()
}

// Araç çubuğu: sütunun en altında 1 px kenarlık; satır toolbar_h yüksekliğinde.
pub fn (mut c Context) toolbar_begin() {
	c.open('toolbar', Box{
		dir:    .column
		width:  grow()
		height: fixed(toolbar_h + 1)
		bg:     surface_1
	})
	c.open('toolbar_row', Box{
		dir:         .row
		width:       grow()
		height:      grow()
		padding:     pad_xy(space_2, 0)
		gap:         space_1
		align_cross: .center
	})
}

pub fn (mut c Context) toolbar_end() {
	c.close()
	c.separator()
	c.close()
}

// Durum çubuğu kapsayıcısı; içerik statusbar_text ile yazılır.
// Üstte 1 px kenarlık; metin dikeyde ortalı, sol kenar space_3.
pub fn (mut c Context) statusbar_begin() {
	c.open('statusbar', Box{
		dir:    .column
		width:  grow()
		height: fixed(statusbar_h)
		bg:     surface_1
	})
	c.separator()
	c.open('statusbar_row', Box{
		dir:         .row
		width:       grow()
		height:      grow()
		padding:     pad_xy(space_3, 0)
		gap:         space_3
		align_cross: .center
	})
}

pub fn (mut c Context) statusbar_end() {
	c.close()
	c.close()
}

pub fn (mut c Context) statusbar_text(s string) {
	c.text(s, .caption, text_secondary)
}
