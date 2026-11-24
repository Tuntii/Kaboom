module render

import math

// Yükseklik 220 m; genişlik en-boy oranıyla gelir. Ölçek NDC'ye dönüşüm katsayısıdır.
fn scale_is_none(width int, height int) bool {
	Camera{}.scale(width, height) or { return true }
	return false
}

fn test_camera_scale_rejects_zero_size() {
	assert scale_is_none(0, 720)
	assert scale_is_none(1280, 0)
}

fn test_camera_scale_matches_aspect() {
	sx, sy := Camera{}.scale(1280, 720) or {
		assert false, 'gecerli boyutta none dondu'
		return
	}
	assert math.abs(sy - f32(2.0 / 220.0)) < 1e-6
	assert math.abs(sx - f32(2.0 / (220.0 * 1280.0 / 720.0))) < 1e-6
}

fn scale_none_for_view_h(view_h f32) bool {
	Camera{ view_h: view_h }.scale(1280, 720) or { return true }
	return false
}

// Yükseklik sıfır, negatif ya da sonlu değilse ölçek üretilmez (NDC bölmesi bozulmasın).
fn test_scale_rejects_nonpositive_view_h() {
	assert scale_none_for_view_h(0)
	assert scale_none_for_view_h(-1)
	assert scale_none_for_view_h(f32(math.nan()))
}
