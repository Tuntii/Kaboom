module platform

// Kare başına girdi anlık görüntüsü. Konum ve basılı tuşlar kalıcıdır; pressed, released,
// wheel, vkeys ve chars her input() çağrısında sıfırlanır. Konum fiziksel piksel, istemci alanına göre.
pub struct InputFrame {
pub mut:
	mouse_x    int
	mouse_y    int
	down       [3]bool
	pressed    [3]bool
	released   [3]bool
	wheel      f32
	vkeys      [16]u16
	vkey_count int
	vkey_repeat [16]bool // vkeys[i] otomatik tekrar mı (bit 30)
	chars      [32]u32
	char_count int
	ctrl       bool
	shift      bool
	alt        bool
	focused    bool
}

pub enum Cursor {
	arrow
	text
	resize_h
	hand
}

// Sistem imleç kimlikleri (IDC_*); Win32 LoadCursorW ile yüklenir.
fn cursor_idc(c Cursor) int {
	return match c {
		.arrow { 32512 }
		.text { 32513 }
		.resize_h { 32644 }
		.hand { 32649 }
	}
}

// UTF-16 biriminden kod noktası üretir. Dönen ilk değer yeni bekleyen yüksek vekildir (0 = yok);
// ikinci değer none ise henüz kod noktası yoktur. Eşleşmeyen yüksek vekil atılır, tek alçak vekil U+FFFD olur.
// V 0.5.2 skaler mut parametreye izin vermediği için bekleyen değer döndürülür.
pub fn utf16_combine(pending u16, unit u16) (u16, ?u32) {
	if pending != 0 && unit >= 0xDC00 && unit <= 0xDFFF {
		return u16(0), u32(0x10000) + ((u32(pending) - 0xD800) << 10) + (u32(unit) - 0xDC00)
	}
	if unit >= 0xD800 && unit <= 0xDBFF {
		return unit, none
	}
	if unit >= 0xDC00 && unit <= 0xDFFF {
		return u16(0), u32(0xFFFD)
	}
	return u16(0), u32(unit)
}
