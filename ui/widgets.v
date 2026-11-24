module ui

pub enum ButtonKind {
	primary
	secondary
	ghost
}

pub fn (mut c Context) button(label string, kind ButtonKind) bool {
	return c.button_ex(label, kind, true)
}

pub fn (mut c Context) button_ex(label string, kind ButtonKind, enabled bool) bool {
	id := c.id(label)
	it := c.interact(id, enabled)
	t := c.hover_t(id, enabled && it.hovered)
	mut bg := surface_2
	mut fg := text_primary
	match kind {
		.primary {
			bg = mix(accent, accent_hover, t)
			fg = accent_text
		}
		.secondary {
			bg = mix(surface_2, surface_hover, t)
		}
		.ghost {
			bg = mix(surface_hover.with_alpha(0), surface_hover, t)
		}
	}

	if !enabled {
		fg = text_muted
	}
	c.open(label, Box{
		width:       fit()
		height:      fixed(control_h)
		padding:     pad_xy(space_3, 0)
		align_main:  .center
		align_cross: .center
		bg:          bg
		border:      if kind == .secondary { border } else { Color(0) }
		border_w:    if kind == .secondary { f32(1) } else { f32(0) }
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
		padding:     pad_xy(space_2, 0)
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
	c.text(text, .body, text_primary)
	c.list_row_end()
	return it.clicked
}

// Katlanabilir başlık; açık durumu kalıcıdır, varsayılan açık. Açıksa true döner.
pub fn (mut c Context) section(label string, title string) bool {
	id := c.id(label)
	it := c.interact(id, true)
	open := c.section_open(id, it.clicked)
	t := c.hover_t(id, it.hovered)
	c.open(label, Box{
		dir:         .row
		width:       grow()
		height:      fixed(row_h)
		padding:     pad_xy(space_2, 0)
		gap:         space_1
		align_cross: .center
		bg:          mix(surface_hover.with_alpha(0), surface_hover, t)
	})
	c.icon(if open { Icon.chevron_down } else { Icon.chevron_right }, text_secondary)
	c.text(title, .body_strong, text_primary)
	c.close()
	return open
}

pub fn (mut c Context) separator() {
	c.leaf(.plain, Box{
		width:  grow()
		height: fixed(1)
		bg:     border
	})
}

// Dikey tutamak: sürükleme size'ı yatay delta kadar değiştirir, [min, max] içinde kalır.
// size &f32: V'de mut skaler parametre yok.
pub fn (mut c Context) splitter(label string, mut size &f32, min f32, max f32) {
	id := c.id(label)
	it := c.interact(id, false)
	active := it.hovered || it.dragging
	unsafe {
		mut v := *size
		if it.dragging {
			v += it.drag_dx
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
		width:  fixed(splitter_w)
		height: grow()
		bg:     mix(border, border_strong, t)
	})
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
pub fn (mut c Context) statusbar_begin() {
	c.open('statusbar', Box{
		dir:         .row
		width:       grow()
		height:      fixed(statusbar_h)
		padding:     pad_xy(space_2, 0)
		gap:         space_3
		align_cross: .center
		bg:          surface_1
	})
}

pub fn (mut c Context) statusbar_end() {
	c.close()
}

pub fn (mut c Context) statusbar_text(s string) {
	c.text(s, .caption, text_secondary)
}
