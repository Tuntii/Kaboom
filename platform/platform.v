module platform

// Pencere yapılandırması. width/height istemci alanıdır: dpi_aware true ise mantıksal piksel
// (sistem DPI'ı ile fiziksel piksele ölçeklenir), false ise doğrudan fiziksel (framebuffer) piksel.
pub struct WindowConfig {
pub:
	title     string = 'V-Core'
	width     int    = 1280
	height    int    = 720
	visible   bool   = true
	dpi_aware bool   = true
}

// Saf fonksiyon: sayaç tiklerini ns'ye çevirir. Tam ve kesir kısımlar ayrı hesaplanır.
// shortcut: (kalan)*1e9 çarpımı freq <= 1.8e10 için taşmaz; QPC tipik 10 MHz, üst sınır gerekirse düzeltilir.
pub fn qpc_to_ns(counter u64, freq u64) u64 {
	return (counter / freq) * 1_000_000_000 + (counter % freq) * 1_000_000_000 / freq
}
