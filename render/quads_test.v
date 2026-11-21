module render

import ecs
import math
import memory
import platform

// Test dünyası: core kayıt, alan indisleri kayıttan çözülür (sabit kodlama yok).
fn open_test_world(cap u32) (ecs.World, QuadFields) {
	reg := ecs.core_registry() or { panic(err) }
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, 1 << 20)
	w := ecs.World.new(mut a, &reg, cap) or { panic('World.new none') }
	f := resolve_quad_fields(&reg) or { panic(err) }
	return w, f
}

// Transform (ve isteğe bağlı Sprite) olan bir varlık oluşturur.
fn spawn_quad(mut w ecs.World, f QuadFields, x f32, prev_x f32, size f32, r f32, g f32, b f32) {
	e := w.spawn() or { panic('spawn none') }
	w.add_component(e, ecs.transform_id)
	w.set_field(e, ecs.transform_id, f.x, u64(math.f32_bits(x)))
	w.set_field(e, ecs.transform_id, f.prev_x, u64(math.f32_bits(prev_x)))
	w.add_component(e, ecs.sprite_id)
	w.set_field(e, ecs.sprite_id, f.size, u64(math.f32_bits(size)))
	w.set_field(e, ecs.sprite_id, f.r, u64(math.f32_bits(r)))
	w.set_field(e, ecs.sprite_id, f.g, u64(math.f32_bits(g)))
	w.set_field(e, ecs.sprite_id, f.b, u64(math.f32_bits(b)))
}

fn test_payload_is_16_bytes() {
	assert sizeof(InstancePayload) == 16
}

fn test_prepare_interpolates_position() {
	mut w, f := open_test_world(4)
	spawn_quad(mut w, f, 10, 0, 1, 1, 1, 1)
	mut out := []InstancePayload{len: 4}
	n, skipped := prepare(&w, f, 0.25, mut out)
	assert n == 1 && skipped == 0
	assert out[0].x == 2.5
}

fn test_prepare_packs_color_rgba_bytes() {
	mut w, f := open_test_world(4)
	spawn_quad(mut w, f, 0, 0, 1, 1, 0.5, 0)
	mut out := []InstancePayload{len: 4}
	prepare(&w, f, 1.0, mut out)
	// Bellekte R, G, B, A sırası; küçük-uçlu u32 = A<<24 | B<<16 | G<<8 | R.
	assert out[0].rgba == 0xFF0080FF
}

fn test_prepare_skips_entity_without_sprite() {
	mut w, f := open_test_world(4)
	e := w.spawn() or { panic('spawn none') }
	w.add_component(e, ecs.transform_id)
	mut out := []InstancePayload{len: 4}
	n, skipped := prepare(&w, f, 1.0, mut out)
	assert n == 0 && skipped == 0
}

fn test_prepare_counts_capacity_overflow() {
	mut w, f := open_test_world(4)
	for _ in 0 .. 3 {
		spawn_quad(mut w, f, 0, 0, 1, 1, 1, 1)
	}
	mut out := []InstancePayload{len: 2}
	n, skipped := prepare(&w, f, 1.0, mut out)
	assert n == 2 && skipped == 1
}

// GL yoksa atlanır: pencere ve context olmadan load_gl başarısız olur.
fn test_renderer_new_requires_gl() {
	if gl_ready() {
		eprintln('atlandi: GL zaten yuklu')
		return
	}
	Renderer.new(4) or {
		assert err.msg().len > 0
		return
	}
	assert false, 'GL yokken Renderer.new basarili dondu'
}

// Gizli 200x150 pencere (sistem minimumu nedeniyle 64x64 yerine). Merkez piksel, boyutlardan hesaplanır.
fn test_draw_center_pixel_is_red() {
	mut w := platform.Window.new(platform.WindowConfig{ visible: false, width: 200, height: 150 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	load_gl() or {
		assert false, 'load_gl: ${err}'
		return
	}
	mut r := Renderer.new(16) or {
		assert false, 'Renderer.new: ${err}'
		return
	}
	defer { r.close() }
	cw, ch := w.size()

	mut world, f := open_test_world(4)
	spawn_quad(mut world, f, 0, 0, 50, 1, 0, 0)
	mut buf := r.payload()
	n, _ := prepare(&world, f, 1.0, mut buf)

	clear_color(0, 0, 1, 1)
	assert r.draw_calls() == 0
	r.draw(Camera{ view_h: 100 }, cw, ch, n)
	assert r.draw_calls() == 1
	finish()

	mut px := []u8{len: 4}
	read_pixels(cw / 2, ch / 2, 1, 1, gl_rgba, gl_unsigned_byte, px.data)
	assert px[0] >= 254 && px[1] <= 1 && px[2] <= 1
	// Köşe: temizleme rengi (mavi).
	read_pixels(0, 0, 1, 1, gl_rgba, gl_unsigned_byte, px.data)
	assert px[0] <= 1 && px[1] <= 1 && px[2] >= 254
}
