module render

import ecs
import ui

// GPU'ya giden instance kaydı: 16 bayt. Konum metre, rgba bellekte R, G, B, A sırasında.
pub struct InstancePayload {
pub:
	x    f32
	y    f32
	size f32
	rgba u32
}

// Kayıttan çözülmüş alan indisleri. Çağıran ecs.core_registry üzerinden resolve_quad_fields ile bir kez alır.
pub struct QuadFields {
pub:
	x      u16
	y      u16
	prev_x u16
	prev_y u16
	size   u16
	r      u16
	g      u16
	b      u16
}

// Transform ve Sprite alan indislerini kayıttan çözer. Tick dışında, kurulumda çağrılır.
pub fn resolve_quad_fields(reg &ecs.Registry) !QuadFields {
	t := reg.component(ecs.transform_id) or { return error('Transform bileseni kayitli degil') }
	s := reg.component(ecs.sprite_id) or { return error('Sprite bileseni kayitli degil') }
	return QuadFields{
		x:      t.field_index('x') or { return error('Transform.x yok') }
		y:      t.field_index('y') or { return error('Transform.y yok') }
		prev_x: t.field_index('prev_x') or { return error('Transform.prev_x yok') }
		prev_y: t.field_index('prev_y') or { return error('Transform.prev_y yok') }
		size:   s.field_index('size') or { return error('Sprite.size yok') }
		r:      s.field_index('r') or { return error('Sprite.r yok') }
		g:      s.field_index('g') or { return error('Sprite.g yok') }
		b:      s.field_index('b') or { return error('Sprite.b yok') }
	}
}

// Renk bileşeni: [0, 1] dışı kırpılır, 0..255 bayta yuvarlanır.
fn channel_byte(c f32) u32 {
	v := if c < 0 { f32(0) } else if c > 1 { f32(1) } else { c }
	return u32(v * 255 + 0.5)
}

// Sprite satırlarını gezer; her biri için Transform satırını bulup konumu prev + (x - prev) * alpha ile interpolasyon.
// out sabit uzunluklu ve önceden ayrılmıştır; büyütülmez. Dönüş: (yazılan, kapasite yüzünden atlanan).
// Önkoşul: f, w'nin kayıtından çözülmüş olmalı (nil kolon denetlenmez).
pub fn prepare(w &ecs.World, f QuadFields, alpha f32, mut out []InstancePayload) (u32, u32) {
	tf := w.store(ecs.transform_id)
	sp := w.store(ecs.sprite_id)
	tx := tf.column_f32(f.x)
	ty := tf.column_f32(f.y)
	tpx := tf.column_f32(f.prev_x)
	tpy := tf.column_f32(f.prev_y)
	sz := sp.column_f32(f.size)
	sr := sp.column_f32(f.r)
	sg := sp.column_f32(f.g)
	sb := sp.column_f32(f.b)
	cap := u32(out.len)
	mut drawn := u32(0)
	mut skipped := u32(0)
	for row in 0 .. sp.len() {
		trow := tf.row_of(sp.index_at(row)) or { continue }
		if drawn >= cap {
			skipped++
			continue
		}
		px := unsafe { tpx[trow] }
		py := unsafe { tpy[trow] }
		out[drawn] = InstancePayload{
			x:    px + (unsafe { tx[trow] } - px) * alpha
			y:    py + (unsafe { ty[trow] } - py) * alpha
			size: unsafe { sz[row] }
			rgba: channel_byte(unsafe { sr[row] }) | channel_byte(unsafe { sg[row] }) << 8 | channel_byte(unsafe { sb[row] }) << 16 | u32(0xFF) << 24
		}
		drawn++
	}
	return drawn, skipped
}

// Birim quad köşeleri vertex ID'den üretilir; köşe tamponu yok. Instance: konum, boyut, renk.
const quad_vs = '#version 330 core
layout(location = 0) in vec2 pos;
layout(location = 1) in float size;
layout(location = 2) in vec4 color;
uniform vec4 u_view; // (cx, cy, sx, sy)
out vec4 v_color;
const vec2 corners[6] = vec2[6](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5),
                                vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
void main() {
    vec2 p = (pos + corners[gl_VertexID] * size - u_view.xy) * u_view.zw;
    gl_Position = vec4(p, 0.0, 1.0);
    v_color = color;
}
'

const quad_fs = '#version 330 core
in vec4 v_color;
out vec4 frag;
void main() { frag = v_color; }
'

// Instance tamponu ve VAO: tek çizim çağrısıyla tüm görünür varlıklar.
pub struct Renderer {
mut:
	program  u32
	vao      u32
	vbo      u32
	view_loc int
	capacity u32
	data     []InstancePayload
	draws    u64
}

// Ofset için voidptr; GL'nin pointer parametresi bayt ofsetidir.
fn offset_ptr(off int) voidptr {
	return unsafe { voidptr(usize(off)) }
}

// GL kurulumu. Tick dışıdır: program derler, tamponu ayırır ve payload dizisini bir kez oluşturur.
// load_gl başarılı olmadan (gl_ready false) hata döner.
pub fn Renderer.new(capacity u32) !Renderer {
	if !gl_ready() {
		return error('GL hazir degil: load_gl basarisiz ya da cagrilmadi')
	}
	if capacity == 0 {
		return error('kapasite 0 olamaz')
	}
	program := compile_program(quad_vs, quad_fs)!
	vao := gen_vertex_array()
	bind_vertex_array(vao)
	vbo := gen_buffer()
	bind_buffer(gl_array_buffer, vbo)
	buffer_data(gl_array_buffer, isize(capacity) * isize(sizeof(InstancePayload)), unsafe { nil }, gl_dynamic_draw)
	stride := int(sizeof(InstancePayload))
	enable_vertex_attrib_array(0)
	vertex_attrib_pointer(0, 2, gl_float, 0, stride, offset_ptr(0))
	vertex_attrib_divisor(0, 1)
	enable_vertex_attrib_array(1)
	vertex_attrib_pointer(1, 1, gl_float, 0, stride, offset_ptr(8))
	vertex_attrib_divisor(1, 1)
	enable_vertex_attrib_array(2)
	vertex_attrib_pointer(2, 4, gl_unsigned_byte, 1, stride, offset_ptr(12))
	vertex_attrib_divisor(2, 1)
	bind_vertex_array(0)
	bind_buffer(gl_array_buffer, 0)
	view_loc := get_uniform_location(program, c'u_view')
	set_default_clear()
	return Renderer{
		program:  program
		vao:      vao
		vbo:      vbo
		view_loc: view_loc
		capacity: capacity
		data:     []InstancePayload{len: int(capacity)}
	}
}

// Renderer'ın sahip olduğu sabit dizi; prepare buraya yazar.
pub fn (mut r Renderer) payload() []InstancePayload {
	return r.data
}

// Tek glBufferSubData ve tek glDrawArraysInstanced. Ölçek üretilemezse yalnız temizleme yapılır.
pub fn (mut r Renderer) draw(cam Camera, width int, height int, n u32) {
	viewport(0, 0, width, height)
	clear(gl_color_buffer_bit)
	sx, sy := cam.scale(width, height) or { return }
	r.draw_instances(cam, sx, sy, n)
}

// Koyu gri zemin: her karede temizleme bu rengi kullanır; GL varsayılanı siyahtır.
fn set_default_clear() {
	clear_color(0.08, 0.08, 0.10, 1.0)
}

// Yalnız (x, y, w, h) bölgesini surface_0 ile temizleyip çizer; bölge dışına dokunmaz.
// x, y sol üst köken; fb_h framebuffer yüksekliği (y aşağı → GL'de fb_h - y - h). Viewport bölgede
// kalır: sonraki çizim kendi viewport'unu ayarlamalı (Renderer.draw ve UiRenderer.draw ayarlar).
pub fn (mut r Renderer) draw_viewport(cam Camera, x int, y int, w int, h int, fb_h int, n u32) {
	sx, sy := cam.scale(w, h) or { return }
	gl_y := fb_h - y - h
	viewport(x, gl_y, w, h)
	scissor(x, gl_y, w, h)
	enable(gl_scissor_test)
	c := u32(ui.surface_0)
	clear_color(f32((c >> 24) & 0xFF) / 255, f32((c >> 16) & 0xFF) / 255, f32((c >> 8) & 0xFF) / 255, 1.0)
	clear(gl_color_buffer_bit)
	disable(gl_scissor_test)
	set_default_clear()
	r.draw_instances(cam, sx, sy, n)
}

// Instance tamponunu yükler ve tek instanced çizim yapar. Viewport ve temizleme çağırana aittir.
fn (mut r Renderer) draw_instances(cam Camera, sx f32, sy f32, n u32) {
	count := if n > r.capacity { r.capacity } else { n }
	use_program(r.program)
	uniform4f(r.view_loc, cam.cx, cam.cy, sx, sy)
	bind_buffer(gl_array_buffer, r.vbo)
	buffer_sub_data(gl_array_buffer, 0, isize(count) * isize(sizeof(InstancePayload)), r.data.data)
	bind_vertex_array(r.vao)
	draw_arrays_instanced(gl_triangles, 0, 6, int(count))
	r.draws++
}

// Kümülatif instanced çizim çağrısı sayısı.
pub fn (r &Renderer) draw_calls() u64 {
	return r.draws
}

// Kaynakları serbest bırakır; tekrar çağrılabilir. Context canlıyken çağrılmalı.
pub fn (mut r Renderer) close() {
	if r.vbo != 0 {
		delete_buffer(r.vbo)
		r.vbo = 0
	}
	if r.vao != 0 {
		delete_vertex_array(r.vao)
		r.vao = 0
	}
	if r.program != 0 {
		delete_program(r.program)
		r.program = 0
	}
}
