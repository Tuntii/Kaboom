module editor

import ui

// Görünüm yüksekliği sınırları (metre) ve tekerlek çentiği başına yakınlaştırma çarpanı.
const cam_min_view_h = f32(1)
const cam_max_view_h = f32(10000)
const cam_zoom_notch = 1.15
// Kadraj kenar boşluğu: içerik her kenardan bu oranda boşlukla sığar (görünüm yüksekliğinin/genişliğinin payı).
const cam_frame_margin = f32(0.15)

// Editör kamerası. Ölçek render.Camera.scale ile aynıdır: sy = 2/view_h, sx = sy·h/w; dünya y yukarı, ekran y aşağı.
// Sahne dikdörtgeninin yüksekliği view_h metreye karşılık gelir, yani bir piksel = view_h/h metre.
pub struct EditorCamera {
pub mut:
	cx     f32
	cy     f32
	view_h f32
}

// Piksel başına dünya birimi tersi (metre → piksel).
fn (c EditorCamera) px_per_unit(r ui.Rect) f32 {
	return if c.view_h > 0 { r.h / c.view_h } else { f32(0) }
}

// Dünya noktasının ekran (mantıksal piksel) konumu.
pub fn (c EditorCamera) world_to_screen(r ui.Rect, x f32, y f32) (f32, f32) {
	k := c.px_per_unit(r)
	return r.x + r.w / 2 + (x - c.cx) * k, r.y + r.h / 2 - (y - c.cy) * k
}

// Ekran noktasının dünya konumu; ölçek yoksa kamera merkezi.
pub fn (c EditorCamera) screen_to_world(r ui.Rect, sx f32, sy f32) (f32, f32) {
	k := c.px_per_unit(r)
	if k <= 0 {
		return c.cx, c.cy
	}
	return c.cx + (sx - (r.x + r.w / 2)) / k, c.cy - (sy - (r.y + r.h / 2)) / k
}

// Dünya kutusunu (x0,y0)-(x1,y1) sahne dikdörtgenine %15 kenar boşluğuyla sığdırır: merkez kutunun merkezi, görünüm
// yüksekliği iki eksenden sınırlayanına göre. Görünüm yüksekliği [cam_min_view_h, cam_max_view_h] içine kıskaçlanır.
pub fn (mut c EditorCamera) frame_box(r ui.Rect, x0 f32, y0 f32, x1 f32, y1 f32) {
	fill := 1 - 2 * cam_frame_margin
	mut vh := (y1 - y0) / fill
	if r.w > 0 && r.h > 0 {
		vw := (x1 - x0) / fill * r.h / r.w
		if vw > vh {
			vh = vw
		}
	}
	if vh < cam_min_view_h {
		vh = cam_min_view_h
	}
	if vh > cam_max_view_h {
		vh = cam_max_view_h
	}
	c.view_h = vh
	c.cx = (x0 + x1) / 2
	c.cy = (y0 + y1) / 2
}

// Yakınlaştırma: factor > 1 yakınlaştırır (görünüm yüksekliği küçülür). İmleç altındaki dünya noktası yerinde kalır.
// view_h [cam_min_view_h, cam_max_view_h] aralığına kıskaçlanır. Geçersiz çarpan ya da boş sahne yok sayılır.
pub fn (mut c EditorCamera) zoom_at(r ui.Rect, sx f32, sy f32, factor f32) {
	if !(factor > 0) || r.h <= 0 || !(c.view_h > 0) {
		return
	}
	wx, wy := c.screen_to_world(r, sx, sy)
	mut vh := c.view_h / factor
	if vh < cam_min_view_h {
		vh = cam_min_view_h
	}
	if vh > cam_max_view_h {
		vh = cam_max_view_h
	}
	c.view_h = vh
	// Yeni ölçekte aynı ekran noktasının dünya konumu wx, wy olacak şekilde merkez.
	k := r.h / vh
	c.cx = wx - (sx - (r.x + r.w / 2)) / k
	c.cy = wy + (sy - (r.y + r.h / 2)) / k
}
