module render

import platform
import ui

// UI karesi 64x64; GL'de pencerenin alt-sol köşesini kullanır.
const ui_fb = 64

// Gizli pencere + GL. Pencere yoksa test atlanır (M3 testleriyle aynı desen).
fn open_gl_window() ?platform.Window {
	mut w := platform.Window.new(platform.WindowConfig{ visible: false, width: 200, height: 150 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return none
	}
	load_gl() or {
		w.close()
		assert false, 'load_gl: ${err}'
		return none
	}
	return w
}

// Tam ekran kırpmalı komut; alanlar testin gerektirdiği kadar doldurulur.
fn ui_cmd(x f32, y f32, w f32, h f32, color u32) ui.DrawCmd {
	return ui.DrawCmd{
		x:     x
		y:     y
		w:     w
		h:     h
		cx1:   f32(ui_fb)
		cy1:   f32(ui_fb)
		color: color
	}
}

// (x, y) sol üst köken; GL okuması alt-sol köken olduğundan y çevrilir.
fn ui_px(x int, y int) (int, int, int) {
	return gl_px(x, ui_fb - 1 - y)
}

fn gl_px(x int, gy int) (int, int, int) {
	mut px := []u8{len: 4}
	read_pixels(x, gy, 1, 1, gl_rgba, gl_unsigned_byte, px.data)
	return int(px[0]), int(px[1]), int(px[2])
}

fn near(v int, want int) bool {
	return v >= want - 1 && v <= want + 1
}

fn test_ui_cmd_is_72_bytes() {
	assert sizeof(ui.DrawCmd) == 72
}

fn test_rect_fill_and_rounded_corner() {
	mut w := open_gl_window() or { return }
	defer { w.close() }
	mut r := UiRenderer.new(4) or {
		assert false, 'UiRenderer.new: ${err}'
		return
	}
	defer { r.close() }
	mut list := ui.DrawList.new(4)
	list.push(ui.DrawCmd{ ...ui_cmd(8, 8, 48, 48, 0xFF0000FF), radius: 12 })
	clear_color(0, 0, 0, 1)
	clear(gl_color_buffer_bit)
	r.draw(&list, ui_fb, ui_fb)
	finish()
	cr, cg, cb := ui_px(32, 32)
	assert cr >= 254 && cg <= 1 && cb <= 1
	// Yuvarlak köşenin dışında kalan piksel siyah kalmalı.
	kr, kg, kb := ui_px(9, 9)
	assert kr <= 8 && kg <= 8 && kb <= 8
}

fn test_border_drawn_inside() {
	mut w := open_gl_window() or { return }
	defer { w.close() }
	mut r := UiRenderer.new(4) or {
		assert false, 'UiRenderer.new: ${err}'
		return
	}
	defer { r.close() }
	mut list := ui.DrawList.new(4)
	list.push(ui.DrawCmd{ ...ui_cmd(8, 8, 48, 48, 0x0000FFFF), radius: 12, border: 2, border_color: 0x00FF00FF })
	clear_color(0, 0, 0, 1)
	clear(gl_color_buffer_bit)
	r.draw(&list, ui_fb, ui_fb)
	finish()
	gr, gg, gb := ui_px(8, 32)
	assert gr <= 1 && gg >= 254 && gb <= 1
	cr, cg, cb := ui_px(32, 32)
	assert cr <= 1 && cg <= 1 && cb >= 254
}

fn test_clip_discards_outside() {
	mut w := open_gl_window() or { return }
	defer { w.close() }
	mut r := UiRenderer.new(4) or {
		assert false, 'UiRenderer.new: ${err}'
		return
	}
	defer { r.close() }
	mut list := ui.DrawList.new(4)
	mut c := ui_cmd(0, 0, ui_fb, ui_fb, 0xFFFFFFFF)
	c.cx1 = 32
	list.push(c)
	clear_color(0, 0, 0, 1)
	clear(gl_color_buffer_bit)
	r.draw(&list, ui_fb, ui_fb)
	finish()
	or_, og, ob := ui_px(48, 32)
	assert or_ <= 8 && og <= 8 && ob <= 8
	ir, ig, ib := ui_px(16, 32)
	assert ir >= 247 && ig >= 247 && ib >= 247
}

fn test_glyph_samples_atlas() {
	mut w := open_gl_window() or { return }
	defer { w.close() }
	mut r := UiRenderer.new(4) or {
		assert false, 'UiRenderer.new: ${err}'
		return
	}
	defer { r.close() }
	r.upload_atlas(2, 2, [u8(255), 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255])
	mut list := ui.DrawList.new(4)
	mut c := ui_cmd(8, 8, 48, 48, 0xFF0000FF)
	c.u1 = 1
	c.v1 = 1
	c.kind = u32(ui.DrawKind.glyph)
	list.push(c)
	clear_color(0, 0, 0, 1)
	clear(gl_color_buffer_bit)
	r.draw(&list, ui_fb, ui_fb)
	finish()
	gr, gg, gb := ui_px(32, 32)
	assert gr >= 254 && gg <= 1 && gb <= 1
}

fn test_color_byte_order() {
	mut w := open_gl_window() or { return }
	defer { w.close() }
	mut r := UiRenderer.new(4) or {
		assert false, 'UiRenderer.new: ${err}'
		return
	}
	defer { r.close() }
	mut list := ui.DrawList.new(4)
	list.push(ui_cmd(0, 0, ui_fb, ui_fb, 0x112233FF))
	clear_color(0, 0, 0, 1)
	clear(gl_color_buffer_bit)
	r.draw(&list, ui_fb, ui_fb)
	finish()
	pr, pg, pb := ui_px(32, 32)
	assert near(pr, 0x11) && near(pg, 0x22) && near(pb, 0x33)
}

fn test_one_draw_call_per_frame() {
	mut w := open_gl_window() or { return }
	defer { w.close() }
	mut r := UiRenderer.new(500) or {
		assert false, 'UiRenderer.new: ${err}'
		return
	}
	defer { r.close() }
	mut list := ui.DrawList.new(500)
	for i in 0 .. 500 {
		list.push(ui_cmd(f32(i % 60), 0, 4, 4, 0xFFFFFFFF))
	}
	before := r.draw_calls()
	r.draw(&list, ui_fb, ui_fb)
	assert r.draw_calls() == before + 1
}

// Bölge dışındaki piksel korunur; bölge içi surface_0 ile temizlenir.
fn test_draw_viewport_only_touches_region() {
	mut w := open_gl_window() or { return }
	defer { w.close() }
	cw, ch := w.size()
	mut r := Renderer.new(16) or {
		assert false, 'Renderer.new: ${err}'
		return
	}
	defer { r.close() }
	clear_color(0, 0, 1, 1)
	clear(gl_color_buffer_bit)
	viewport(0, 0, cw, ch)
	r.draw_viewport(Camera{ view_h: 100 }, 0, 0, 32, 64, 0)
	finish()
	or_, og, ob := gl_px(48, 32)
	assert or_ <= 1 && og <= 1 && ob >= 254
	// Sol üst köken (16, 32) → GL (16, ch-33); surface_0 = 0x111214.
	ir, ig, ib := gl_px(16, ch - 1 - 32)
	assert near(ir, 0x11) && near(ig, 0x12) && near(ib, 0x14)
}
