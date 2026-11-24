module render

import math

// Ortografik kamera, metre cinsinden. Protokolden yönetilmez; y yukarı.
pub struct Camera {
pub:
	cx     f32
	cy     f32
	view_h f32 = 220
}

// NDC ölçeği (sx, sy): görüntü yüksekliği view_h metreye karşılık gelir, genişlik en-boy oranına göre.
// Boyut ≤ 0 ise none; view_h sonlu ve pozitif değilse de none (NaN karşılaştırması false döner).
pub fn (c Camera) scale(width int, height int) ?(f32, f32) {
	if width <= 0 || height <= 0 || !(c.view_h > 0 && c.view_h < f32(math.inf(1))) {
		return none
	}
	sy := 2.0 / c.view_h
	sx := 2.0 / (c.view_h * f32(width) / f32(height))
	return sx, sy
}
