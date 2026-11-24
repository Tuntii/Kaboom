module render

import ui

// Örnek verisi doğrudan ui.DrawCmd (72 bayt): öznitelik ofsetleri struct alanlarıyla birebir.
// Renk bellekte AA BB GG RR; .abgr ile RGBA'ya çevrilir.
const ui_vs = '#version 330 core
layout(location = 0) in vec4 a_rect;
layout(location = 1) in vec4 a_uv;
layout(location = 2) in vec4 a_clip;
layout(location = 3) in vec4 a_color;
layout(location = 4) in vec4 a_border_color;
layout(location = 5) in vec2 a_rb;
layout(location = 6) in uint a_kind;
uniform vec2 u_fb;
out vec2 v_uv;
flat out vec4 v_rect;
flat out vec4 v_clip;
flat out vec4 v_color;
flat out vec4 v_border_color;
flat out vec2 v_rb;
flat out uint v_kind;
const vec2 corners[6] = vec2[6](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0),
                                vec2(0.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));
void main() {
    vec2 c = corners[gl_VertexID];
    vec2 p = a_rect.xy + c * a_rect.zw;
    gl_Position = vec4(p.x / u_fb.x * 2.0 - 1.0, 1.0 - p.y / u_fb.y * 2.0, 0.0, 1.0);
    v_uv = mix(a_uv.xy, a_uv.zw, c);
    v_rect = a_rect;
    v_clip = a_clip;
    v_color = a_color.abgr;
    v_border_color = a_border_color.abgr;
    v_rb = a_rb;
    v_kind = a_kind;
}
'

const ui_fs = '#version 330 core
uniform sampler2D u_atlas;
uniform vec2 u_fb;
in vec2 v_uv;
flat in vec4 v_rect;
flat in vec4 v_clip;
flat in vec4 v_color;
flat in vec4 v_border_color;
flat in vec2 v_rb;
flat in uint v_kind;
out vec4 frag;
void main() {
    // gl_FragCoord alt-sol köken; kırpma ve SDF y-aşağı piksel uzayında.
    vec2 fp = vec2(gl_FragCoord.x, u_fb.y - gl_FragCoord.y);
    if (fp.x < v_clip.x || fp.y < v_clip.y || fp.x >= v_clip.z || fp.y >= v_clip.w) discard;
    if (v_kind == 1u) {
        frag = vec4(v_color.rgb, v_color.a * texture(u_atlas, v_uv).r);
        return;
    }
    vec2 half_size = v_rect.zw * 0.5;
    float r = min(v_rb.x, min(half_size.x, half_size.y));
    vec2 q = abs(fp - (v_rect.xy + half_size)) - (half_size - r);
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float outer = clamp(0.5 - d, 0.0, 1.0);
    // Kenarlık içte: iç şekil dış şeklin border kadar küçültülmüşü; border 0 ise dolgu.
    float inner = v_rb.y > 0.0 ? clamp(0.5 - (d + v_rb.y), 0.0, 1.0) : 1.0;
    vec4 col = mix(v_border_color, v_color, inner);
    frag = vec4(col.rgb, col.a * outer);
}
'

// Tüm UI komutları tek instanced çizimle; atlas tek kanallı (GL_R8).
pub struct UiRenderer {
mut:
	program u32
	vao     u32
	vbo     u32
	tex     u32
	fb_loc  int
	cap     u32
	draws   u64
}

// Kurulum: program, VAO (72 baytlık örnek kaydı), atlas dokusu. Tick dışıdır.
pub fn UiRenderer.new(max_cmds u32) !UiRenderer {
	if !gl_ready() {
		return error('GL hazir degil: load_gl basarisiz ya da cagrilmadi')
	}
	if max_cmds == 0 {
		return error('kapasite 0 olamaz')
	}
	program := compile_program(ui_vs, ui_fs)!
	use_program(program)
	uniform1i(get_uniform_location(program, c'u_atlas'), 0)
	fb_loc := get_uniform_location(program, c'u_fb')
	vao := gen_vertex_array()
	bind_vertex_array(vao)
	vbo := gen_buffer()
	bind_buffer(gl_array_buffer, vbo)
	stride := int(sizeof(ui.DrawCmd))
	buffer_data(gl_array_buffer, isize(max_cmds) * isize(stride), unsafe { nil }, gl_dynamic_draw)
	ui_attrib(0, 4, gl_float, 0, stride, 0)
	ui_attrib(1, 4, gl_float, 0, stride, 16)
	ui_attrib(2, 4, gl_float, 0, stride, 32)
	ui_attrib(3, 4, gl_unsigned_byte, 1, stride, 48)
	ui_attrib(4, 4, gl_unsigned_byte, 1, stride, 52)
	ui_attrib(5, 2, gl_float, 0, stride, 56)
	enable_vertex_attrib_array(6)
	vertex_attrib_i_pointer(6, 1, gl_unsigned_int, stride, offset_ptr(64))
	vertex_attrib_divisor(6, 1)
	bind_vertex_array(0)
	bind_buffer(gl_array_buffer, 0)
	return UiRenderer{
		program: program
		vao:     vao
		vbo:     vbo
		tex:     gen_texture()
		fb_loc:  fb_loc
		cap:     max_cmds
	}
}

fn ui_attrib(index u32, size int, typ u32, normalized u8, stride int, off int) {
	enable_vertex_attrib_array(index)
	vertex_attrib_pointer(index, size, typ, normalized, stride, offset_ptr(off))
	vertex_attrib_divisor(index, 1)
}

// Atlas pikselleri (tek kanal, satır sırası üstten alta). Piksel tamponu w*h'den kısa olamaz.
pub fn (mut r UiRenderer) upload_atlas(w int, h int, pixels []u8) {
	assert pixels.len >= w * h
	bind_texture(gl_texture_2d, r.tex)
	pixel_storei(gl_unpack_alignment, 1)
	tex_image_2d(gl_texture_2d, 0, int(gl_r8), w, h, 0, gl_red, gl_unsigned_byte, pixels.data)
	// Glifler tam piksele oturur; doğrusal örnekleme merkezlerde birebir değerdir.
	tex_parameteri(gl_texture_2d, gl_texture_min_filter, int(gl_linear))
	tex_parameteri(gl_texture_2d, gl_texture_mag_filter, int(gl_linear))
	tex_parameteri(gl_texture_2d, gl_texture_wrap_s, int(gl_clamp_to_edge))
	tex_parameteri(gl_texture_2d, gl_texture_wrap_t, int(gl_clamp_to_edge))
}

// Tek glBufferSubData ve tek glDrawArraysInstanced. Temizlemez; boş listede çizim yapılmaz.
pub fn (mut r UiRenderer) draw(list &ui.DrawList, fb_w int, fb_h int) {
	n := if list.len() > r.cap { r.cap } else { list.len() }
	if n == 0 {
		return
	}
	viewport(0, 0, fb_w, fb_h)
	use_program(r.program)
	uniform2f(r.fb_loc, f32(fb_w), f32(fb_h))
	active_texture(gl_texture0)
	bind_texture(gl_texture_2d, r.tex)
	bind_buffer(gl_array_buffer, r.vbo)
	buffer_sub_data(gl_array_buffer, 0, isize(n) * isize(sizeof(ui.DrawCmd)), list.data())
	bind_vertex_array(r.vao)
	enable(gl_blend)
	blend_func(gl_src_alpha, gl_one_minus_src_alpha)
	draw_arrays_instanced(gl_triangles, 0, 6, int(n))
	disable(gl_blend)
	r.draws++
}

// Kümülatif instanced çizim çağrısı sayısı.
pub fn (r &UiRenderer) draw_calls() u64 {
	return r.draws
}

// Kaynakları serbest bırakır; tekrar çağrılabilir. Context canlıyken çağrılmalı.
pub fn (mut r UiRenderer) close() {
	if r.tex != 0 {
		delete_texture(r.tex)
		r.tex = 0
	}
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
