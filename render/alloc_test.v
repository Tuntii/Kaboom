module render

import ecs
import math
import memory
import platform

// -d track_heap ile: 1000 varlıkta prepare + draw tick yolunda V heap tahsisi yapmaz.
// Test dosyaları ayrı derlenir; kurulum quads_test.v'deki yardımcıların kopyasıdır.
fn test_tick_path_has_zero_heap_allocs() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap ile calistir')
		return
	}
	mut w := platform.Window.new(platform.WindowConfig{ visible: false, width: 200, height: 150 }) or {
		eprintln('atlandi: GL yok: ${err}')
		return
	}
	defer { w.close() }
	load_gl() or {
		assert false, 'load_gl: ${err}'
		return
	}
	mut r := Renderer.new(1000) or {
		assert false, 'Renderer.new: ${err}'
		return
	}
	defer { r.close() }
	cw, ch := w.size()

	reg := ecs.core_registry() or { panic(err) }
	region := memory.reserve(1 << 22) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, 1 << 22)
	mut world := ecs.World.new(mut a, &reg, 1000) or { panic('World.new none') }
	f := resolve_quad_fields(&reg) or { panic(err) }
	for i in 0 .. 1000 {
		e := world.spawn() or { panic('spawn none') }
		world.add_component(e, ecs.transform_id)
		world.set_field(e, ecs.transform_id, f.x, u64(math.f32_bits(f32(i))))
		world.add_component(e, ecs.sprite_id)
		world.set_field(e, ecs.sprite_id, f.size, u64(math.f32_bits(1.0)))
	}
	mut buf := r.payload()
	before := memory.heap_alloc_count()
	for _ in 0 .. 10 {
		n, _ := prepare(&world, f, 0.5, mut buf)
		r.draw(Camera{ view_h: 220 }, cw, ch, n)
	}
	assert memory.heap_alloc_count() == before
}
