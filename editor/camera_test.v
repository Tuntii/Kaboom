module editor

import ui

// Sahne dikdörtgeni kare değil: en-boy kuralının ayrı ayrı sınandığı ölçü.
fn cam_test_rect() ui.Rect {
	return ui.Rect{
		x: 10
		y: 20
		w: 800
		h: 600
	}
}

fn cam_close(a f32, b f32) bool {
	d := if a > b { a - b } else { b - a }
	return d < 1e-3
}

// Dünya → ekran → dünya gidiş-dönüşü ve render.Camera ile aynı NDC formülü (bağımsız hesap).
fn test_camera_roundtrip() {
	r := cam_test_rect()
	c := EditorCamera{
		cx:     3.5
		cy:     -2
		view_h: 40
	}
	for p in [[f32(0), 0], [f32(-7.25), 4.5], [f32(12), -9]] {
		sx, sy := c.world_to_screen(r, p[0], p[1])
		wx, wy := c.screen_to_world(r, sx, sy)
		assert cam_close(wx, p[0]) && cam_close(wy, p[1]), 'gidiş-dönüş: ${p} → ${wx},${wy}'
		// render.Camera.scale: sx = 2/(view_h·w/h), sy = 2/view_h; NDC = (dünya - cam)·ölçek; piksel = (NDC+1)/2·boyut.
		ndc_x := (p[0] - c.cx) * (2 / (c.view_h * r.w / r.h))
		ndc_y := (p[1] - c.cy) * (2 / c.view_h)
		assert cam_close(sx, r.x + (ndc_x + 1) / 2 * r.w), 'x ölçeği render ile uyuşmuyor'
		assert cam_close(sy, r.y + (1 - ndc_y) / 2 * r.h), 'y ölçeği render ile uyuşmuyor (y yukarı)'
	}
}

// İmleç altındaki dünya noktası zoom'dan sonra da aynı ekran noktasında kalır.
fn test_zoom_keeps_point_under_cursor() {
	r := cam_test_rect()
	mut c := EditorCamera{
		cx:     1
		cy:     2
		view_h: 40
	}
	sx := f32(300)
	sy := f32(200)
	wx0, wy0 := c.screen_to_world(r, sx, sy)
	c.zoom_at(r, sx, sy, cam_zoom_notch)
	assert cam_close(c.view_h, 40 / cam_zoom_notch), 'yakınlaştırma görünüm yüksekliğini küçültür: ${c.view_h}'
	wx1, wy1 := c.screen_to_world(r, sx, sy)
	assert cam_close(wx1, wx0) && cam_close(wy1, wy0), 'imleç noktası kaydı: ${wx0},${wy0} → ${wx1},${wy1}'
	c.zoom_at(r, sx, sy, 1 / cam_zoom_notch)
	wx2, wy2 := c.screen_to_world(r, sx, sy)
	assert cam_close(wx2, wx0) && cam_close(wy2, wy0), 'uzaklaştırmada da sabit'
}

// Görünüm yüksekliği [cam_min_view_h, cam_max_view_h] içinde kalır.
fn test_zoom_clamped() {
	r := cam_test_rect()
	mut c := EditorCamera{
		view_h: 40
	}
	for _ in 0 .. 200 {
		c.zoom_at(r, 400, 300, cam_zoom_notch)
	}
	assert c.view_h == cam_min_view_h, 'alt sınır: ${c.view_h}'
	for _ in 0 .. 400 {
		c.zoom_at(r, 400, 300, 1 / cam_zoom_notch)
	}
	assert c.view_h == cam_max_view_h, 'üst sınır: ${c.view_h}'
	// Geçersiz çarpan ve boş sahne alanı görünümü değiştirmez.
	zero := f32(0)
	c.zoom_at(r, 400, 300, zero)
	c.zoom_at(r, 400, 300, zero / zero)
	c.zoom_at(ui.Rect{}, 400, 300, 2)
	assert c.view_h == cam_max_view_h
}
