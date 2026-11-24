module ui

import math

// Renk: 0xRRGGBBAA.
pub type Color = u32

pub fn rgba(r u8, g u8, b u8, a u8) Color {
	return Color((u32(r) << 24) | (u32(g) << 16) | (u32(b) << 8) | u32(a))
}

pub fn (c Color) with_alpha(a u8) Color {
	return Color((u32(c) & 0xFFFFFF00) | u32(a))
}

// Dört kanal doğrusal karışım; t 0..1 aralığına kıskaçlı.
pub fn mix(a Color, b Color, t f32) Color {
	k := if t < 0 {
		f32(0)
	} else if t > 1 {
		f32(1)
	} else {
		t
	}
	r := mix_channel((u32(a) >> 24) & 0xFF, (u32(b) >> 24) & 0xFF, k)
	g := mix_channel((u32(a) >> 16) & 0xFF, (u32(b) >> 16) & 0xFF, k)
	bl := mix_channel((u32(a) >> 8) & 0xFF, (u32(b) >> 8) & 0xFF, k)
	al := mix_channel(u32(a) & 0xFF, u32(b) & 0xFF, k)
	return Color((r << 24) | (g << 16) | (bl << 8) | al)
}

fn mix_channel(a u32, b u32, k f32) u32 {
	return u32(math.round(f64(f32(a) + (f32(b) - f32(a)) * k)))
}

// WCAG 2.x göreli parlaklık; alfa yok sayılır.
fn luminance(c Color) f64 {
	lin := fn (v f64) f64 {
		x := v / 255.0
		return if x <= 0.03928 { x / 12.92 } else { math.pow((x + 0.055) / 1.055, 2.4) }
	}
	r := lin(f64((u32(c) >> 24) & 0xFF))
	g := lin(f64((u32(c) >> 16) & 0xFF))
	b := lin(f64((u32(c) >> 8) & 0xFF))
	return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

pub fn contrast_ratio(a Color, b Color) f32 {
	la := luminance(a)
	lb := luminance(b)
	hi := if la > lb { la } else { lb }
	lo := if la > lb { lb } else { la }
	return f32((hi + 0.05) / (lo + 0.05))
}

// Yüzeyler.
pub const surface_0 = Color(0x111214FF) // pencere/sahne zemini
pub const surface_1 = Color(0x17181BFF) // panel
pub const surface_2 = Color(0x1F2024FF) // yükseltilmiş: menü, girdi
pub const surface_hover = Color(0x26272CFF)
pub const border = Color(0x2A2B30FF)
pub const border_strong = Color(0x34363CFF)

// Metin.
pub const text_primary = Color(0xE6E7EAFF)
pub const text_secondary = Color(0xA1A3AAFF)
pub const text_muted = Color(0x6E7079FF)

// Vurgu ve durum.
pub const accent = Color(0x3D6FD6FF)
pub const accent_hover = Color(0x4A7BE0FF)
pub const accent_text = Color(0xFFFFFFFF)
pub const selection_bg = Color(0x3D6FD62E)
pub const danger = Color(0xE5484DFF)
pub const warning = Color(0xF5A524FF)

// Aralık.
pub const space_1 = f32(4)
pub const space_2 = f32(8)
pub const space_3 = f32(12)
pub const space_4 = f32(16)
pub const space_6 = f32(24)
pub const space_8 = f32(32)

// Köşe yarıçapları.
pub const radius_control = f32(4)
pub const radius_panel = f32(6)
pub const radius_menu = f32(8)

// Ölçüler.
pub const control_h = f32(28)
pub const row_h = f32(26)
pub const toolbar_h = f32(40)
pub const statusbar_h = f32(24)
pub const icon_size = f32(16)
pub const splitter_w = f32(4)
pub const num_field_w = f32(96)
pub const label_col_w = f32(56) // özellik satırı etiket sütunu
pub const menu_min_w = f32(160) // açılır menünün asgari genişliği

pub enum FontFace {
	sans
	sans_medium
	mono
}

pub enum TextRole {
	caption
	label
	body
	body_strong
	title
	heading
	mono
}

pub fn (r TextRole) spec() (FontFace, f32) {
	return match r {
		.caption { FontFace.sans, f32(11) }
		.label { FontFace.sans, f32(12) }
		.body { FontFace.sans, f32(13) }
		.body_strong { FontFace.sans_medium, f32(13) }
		.title { FontFace.sans_medium, f32(15) }
		.heading { FontFace.sans_medium, f32(18) }
		.mono { FontFace.mono, f32(12) }
	}
}

// Hareket: yalnızca hover/basılı geçişi ve menü açılışı.
pub const motion_ms = f32(100)
pub const tooltip_delay_ms = f64(500)
