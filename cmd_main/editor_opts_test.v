module main

// --screenshot-after-eof yalnız --screenshot ile anlamlıdır: tek başına kullanım hatası (sessiz no-op olmaz).
fn test_screenshot_after_eof_requires_screenshot() {
	assert editor_opts_invalid(EditorOpts{ screenshot_after_eof: true }), 'ekran görüntüsü yolu olmadan kullanım hatası'
	assert !editor_opts_invalid(EditorOpts{ screenshot_after_eof: true, screenshot: 'a.png' }), 'yol varsa geçerli'
	assert !editor_opts_invalid(EditorOpts{ screenshot: 'a.png' }), 'yalnız --screenshot geçerli'
}
