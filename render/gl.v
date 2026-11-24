module render

import platform

#flag -lopengl32
#include <windows.h>
#include <GL/gl.h>
#include "@VMODROOT/render/gl_procs.h"

// GL 1.1 fonksiyonları opengl32'den doğrudan bağlanır.
fn C.glViewport(x int, y int, width int, height int)
fn C.glClear(mask u32)
fn C.glClearColor(r f32, g f32, b f32, a f32)
fn C.glReadPixels(x int, y int, width int, height int, format u32, typ u32, pixels voidptr)
fn C.glFinish()
fn C.glGetString(name u32) &u8
fn C.glGetError() u32
fn C.glGetIntegerv(pname u32, data voidptr)
fn C.glGenTextures(n int, textures voidptr)
fn C.glDeleteTextures(n int, textures voidptr)
fn C.glBindTexture(target u32, texture u32)
fn C.glTexImage2D(target u32, level int, internalformat int, width int, height int, border int, format u32, typ u32, pixels voidptr)
fn C.glTexParameteri(target u32, pname u32, param int)
fn C.glPixelStorei(pname u32, param int)
fn C.glEnable(cap u32)
fn C.glDisable(cap u32)
fn C.glBlendFunc(sfactor u32, dfactor u32)
fn C.glScissor(x int, y int, width int, height int)

fn C.vcore_gl_set(slot int, p voidptr)
fn C.vcore_gl_get(slot int) voidptr
fn C.vcore_gl_clear()
fn C.vcore_gl_ready() int
fn C.vcore_gl_set_ready(v int)

pub const gl_fragment_shader = u32(0x8B30)
pub const gl_vertex_shader = u32(0x8B31)
pub const gl_compile_status = u32(0x8B81)
pub const gl_link_status = u32(0x8B82)
pub const gl_info_log_length = u32(0x8B84)
pub const gl_array_buffer = u32(0x8892)
pub const gl_dynamic_draw = u32(0x88E8)
pub const gl_float = u32(0x1406)
pub const gl_unsigned_byte = u32(0x1401)
pub const gl_triangles = u32(0x0004)
pub const gl_color_buffer_bit = u32(0x4000)
pub const gl_rgba = u32(0x1908)
pub const gl_version = u32(0x1F02)
pub const gl_unsigned_int = u32(0x1405)
pub const gl_viewport = u32(0x0BA2)
pub const gl_texture_2d = u32(0x0DE1)
pub const gl_red = u32(0x1903)
pub const gl_r8 = u32(0x8229)
pub const gl_texture_min_filter = u32(0x2801)
pub const gl_texture_mag_filter = u32(0x2800)
pub const gl_linear = u32(0x2601)
pub const gl_nearest = u32(0x2600)
pub const gl_texture_wrap_s = u32(0x2802)
pub const gl_texture_wrap_t = u32(0x2803)
pub const gl_clamp_to_edge = u32(0x812F)
pub const gl_unpack_alignment = u32(0x0CF5)
pub const gl_texture0 = u32(0x84C0)
pub const gl_blend = u32(0x0BE2)
pub const gl_src_alpha = u32(0x0302)
pub const gl_one_minus_src_alpha = u32(0x0303)
pub const gl_one = u32(1)
pub const gl_scissor_test = u32(0x0C11)

// Yuva indeksleri; load_gl her birini kendi adıyla doldurur.
const slot_create_shader = 0
const slot_shader_source = 1
const slot_compile_shader = 2
const slot_get_shaderiv = 3
const slot_get_shader_info_log = 4
const slot_delete_shader = 5
const slot_create_program = 6
const slot_attach_shader = 7
const slot_link_program = 8
const slot_get_programiv = 9
const slot_get_program_info_log = 10
const slot_use_program = 11
const slot_delete_program = 12
const slot_get_uniform_location = 13
const slot_uniform4f = 14
const slot_gen_vertex_arrays = 15
const slot_bind_vertex_array = 16
const slot_delete_vertex_arrays = 17
const slot_gen_buffers = 18
const slot_bind_buffer = 19
const slot_buffer_data = 20
const slot_buffer_sub_data = 21
const slot_delete_buffers = 22
const slot_enable_vertex_attrib_array = 23
const slot_vertex_attrib_pointer = 24
const slot_vertex_attrib_divisor = 25
const slot_draw_arrays_instanced = 26
const slot_active_texture = 27
const slot_uniform1i = 28
const slot_uniform2f = 29
const slot_vertex_attrib_i_pointer = 30

// Fonksiyon işaretçi tipleri. Parametreler GL'nin C imzasıyla birebir: GLsizei ve GLint = int, GLuint ve GLenum = u32.
type FnCreateShader = fn (u32) u32
type FnShaderSource = fn (u32, int, voidptr, voidptr)
type FnCompileShader = fn (u32)
type FnGetShaderiv = fn (u32, u32, voidptr)
type FnGetShaderInfoLog = fn (u32, int, voidptr, voidptr)
type FnDeleteShader = fn (u32)
type FnCreateProgram = fn () u32
type FnAttachShader = fn (u32, u32)
type FnLinkProgram = fn (u32)
type FnGetProgramiv = fn (u32, u32, voidptr)
type FnGetProgramInfoLog = fn (u32, int, voidptr, voidptr)
type FnUseProgram = fn (u32)
type FnDeleteProgram = fn (u32)
type FnGetUniformLocation = fn (u32, &char) int
type FnUniform4f = fn (int, f32, f32, f32, f32)
type FnGenVertexArrays = fn (int, voidptr)
type FnBindVertexArray = fn (u32)
type FnDeleteVertexArrays = fn (int, voidptr)
type FnGenBuffers = fn (int, voidptr)
type FnBindBuffer = fn (u32, u32)
type FnBufferData = fn (u32, isize, voidptr, u32)
type FnBufferSubData = fn (u32, isize, isize, voidptr)
type FnDeleteBuffers = fn (int, voidptr)
type FnEnableVertexAttribArray = fn (u32)
type FnVertexAttribPointer = fn (u32, int, u32, u8, int, voidptr)
type FnVertexAttribDivisor = fn (u32, u32)
type FnDrawArraysInstanced = fn (u32, int, int, int)
type FnActiveTexture = fn (u32)
type FnUniform1i = fn (int, int)
type FnUniform2f = fn (int, f32, f32)
type FnVertexAttribIPointer = fn (u32, int, u32, int, voidptr)

// Yuva sırası slot_* sabitleriyle aynıdır: gl_fn_names[slot_x] == 'glX'.
const gl_fn_names = ['glCreateShader', 'glShaderSource', 'glCompileShader', 'glGetShaderiv',
	'glGetShaderInfoLog', 'glDeleteShader', 'glCreateProgram', 'glAttachShader', 'glLinkProgram',
	'glGetProgramiv', 'glGetProgramInfoLog', 'glUseProgram', 'glDeleteProgram',
	'glGetUniformLocation', 'glUniform4f', 'glGenVertexArrays', 'glBindVertexArray',
	'glDeleteVertexArrays', 'glGenBuffers', 'glBindBuffer', 'glBufferData', 'glBufferSubData',
	'glDeleteBuffers', 'glEnableVertexAttribArray', 'glVertexAttribPointer',
	'glVertexAttribDivisor', 'glDrawArraysInstanced', 'glActiveTexture', 'glUniform1i', 'glUniform2f',
	'glVertexAttribIPointer']

// names[i] işaretçisini yuva i'ye yükler. Eksik olanların TAMAMINI tek hatada virgüllü listeler;
// hata durumunda tüm yuvalar ve hazır bayrağı sıfırlanır (kısmi durum kalmaz).
fn load_names(names []string) ! {
	C.vcore_gl_clear()
	mut missing := []string{}
	for i, name in names {
		p := platform.gl_proc(&char(name.str))
		if p == unsafe { nil } {
			missing << name
			continue
		}
		C.vcore_gl_set(i, p)
	}
	if missing.len > 0 {
		C.vcore_gl_clear()
		return error('GL fonksiyonu yok: ${missing.join(', ')}')
	}
}

// Tüm GL 2.0+ fonksiyonlarını yükler. Bir context current iken çağrılmalı.
// Başarıda gl_ready() true olur; hatada false kalır.
pub fn load_gl() ! {
	load_names(gl_fn_names)!
	C.vcore_gl_set_ready(1)
}

// Her fonksiyon yüklendiyse true. Çağıran kurulumda bir kez denetler.
pub fn gl_ready() bool {
	return C.vcore_gl_ready() == 1
}

// GL 2.0+ sarmalayıcıları: ince, imzaları C ile aynı.
// Önkoşul: gl_ready() true olmalı. Çağıran bunu kurulumda bir kez denetler; sarmalayıcılarda denetim yok (tick yolu).

pub fn create_shader(kind u32) u32 {
	f := unsafe { FnCreateShader(C.vcore_gl_get(slot_create_shader)) }
	return f(kind)
}

pub fn shader_source(shader u32, count int, src voidptr, length voidptr) {
	f := unsafe { FnShaderSource(C.vcore_gl_get(slot_shader_source)) }
	f(shader, count, src, length)
}

pub fn compile_shader(shader u32) {
	f := unsafe { FnCompileShader(C.vcore_gl_get(slot_compile_shader)) }
	f(shader)
}

pub fn get_shaderiv(shader u32, pname u32, params voidptr) {
	f := unsafe { FnGetShaderiv(C.vcore_gl_get(slot_get_shaderiv)) }
	f(shader, pname, params)
}

pub fn get_shader_info_log(shader u32, buf_size int, length voidptr, info_log voidptr) {
	f := unsafe { FnGetShaderInfoLog(C.vcore_gl_get(slot_get_shader_info_log)) }
	f(shader, buf_size, length, info_log)
}

pub fn delete_shader(shader u32) {
	f := unsafe { FnDeleteShader(C.vcore_gl_get(slot_delete_shader)) }
	f(shader)
}

pub fn create_program() u32 {
	f := unsafe { FnCreateProgram(C.vcore_gl_get(slot_create_program)) }
	return f()
}

pub fn attach_shader(program u32, shader u32) {
	f := unsafe { FnAttachShader(C.vcore_gl_get(slot_attach_shader)) }
	f(program, shader)
}

pub fn link_program(program u32) {
	f := unsafe { FnLinkProgram(C.vcore_gl_get(slot_link_program)) }
	f(program)
}

pub fn get_programiv(program u32, pname u32, params voidptr) {
	f := unsafe { FnGetProgramiv(C.vcore_gl_get(slot_get_programiv)) }
	f(program, pname, params)
}

pub fn get_program_info_log(program u32, buf_size int, length voidptr, info_log voidptr) {
	f := unsafe { FnGetProgramInfoLog(C.vcore_gl_get(slot_get_program_info_log)) }
	f(program, buf_size, length, info_log)
}

pub fn use_program(program u32) {
	f := unsafe { FnUseProgram(C.vcore_gl_get(slot_use_program)) }
	f(program)
}

pub fn delete_program(program u32) {
	f := unsafe { FnDeleteProgram(C.vcore_gl_get(slot_delete_program)) }
	f(program)
}

pub fn get_uniform_location(program u32, name &char) int {
	f := unsafe { FnGetUniformLocation(C.vcore_gl_get(slot_get_uniform_location)) }
	return f(program, name)
}

pub fn uniform4f(location int, x f32, y f32, z f32, w f32) {
	f := unsafe { FnUniform4f(C.vcore_gl_get(slot_uniform4f)) }
	f(location, x, y, z, w)
}

// Tek kimlik üreten sarmalayıcı: glGenVertexArrays(1, ...).
pub fn gen_vertex_array() u32 {
	mut id := u32(0)
	f := unsafe { FnGenVertexArrays(C.vcore_gl_get(slot_gen_vertex_arrays)) }
	f(1, voidptr(&id))
	return id
}

pub fn bind_vertex_array(array u32) {
	f := unsafe { FnBindVertexArray(C.vcore_gl_get(slot_bind_vertex_array)) }
	f(array)
}

// Tek kimlik silen sarmalayıcı: glDeleteVertexArrays(1, ...).
pub fn delete_vertex_array(array u32) {
	mut id := array
	f := unsafe { FnDeleteVertexArrays(C.vcore_gl_get(slot_delete_vertex_arrays)) }
	f(1, voidptr(&id))
}

// Tek kimlik üreten sarmalayıcı: glGenBuffers(1, ...).
pub fn gen_buffer() u32 {
	mut id := u32(0)
	f := unsafe { FnGenBuffers(C.vcore_gl_get(slot_gen_buffers)) }
	f(1, voidptr(&id))
	return id
}

pub fn bind_buffer(target u32, buffer u32) {
	f := unsafe { FnBindBuffer(C.vcore_gl_get(slot_bind_buffer)) }
	f(target, buffer)
}

pub fn buffer_data(target u32, size isize, data voidptr, usage u32) {
	f := unsafe { FnBufferData(C.vcore_gl_get(slot_buffer_data)) }
	f(target, size, data, usage)
}

pub fn buffer_sub_data(target u32, offset isize, size isize, data voidptr) {
	f := unsafe { FnBufferSubData(C.vcore_gl_get(slot_buffer_sub_data)) }
	f(target, offset, size, data)
}

// Tek kimlik silen sarmalayıcı: glDeleteBuffers(1, ...).
pub fn delete_buffer(buffer u32) {
	mut id := buffer
	f := unsafe { FnDeleteBuffers(C.vcore_gl_get(slot_delete_buffers)) }
	f(1, voidptr(&id))
}

pub fn enable_vertex_attrib_array(index u32) {
	f := unsafe { FnEnableVertexAttribArray(C.vcore_gl_get(slot_enable_vertex_attrib_array)) }
	f(index)
}

pub fn vertex_attrib_pointer(index u32, size int, typ u32, normalized u8, stride int, pointer voidptr) {
	f := unsafe { FnVertexAttribPointer(C.vcore_gl_get(slot_vertex_attrib_pointer)) }
	f(index, size, typ, normalized, stride, pointer)
}

pub fn vertex_attrib_divisor(index u32, divisor u32) {
	f := unsafe { FnVertexAttribDivisor(C.vcore_gl_get(slot_vertex_attrib_divisor)) }
	f(index, divisor)
}

pub fn draw_arrays_instanced(mode u32, first int, count int, instance_count int) {
	f := unsafe { FnDrawArraysInstanced(C.vcore_gl_get(slot_draw_arrays_instanced)) }
	f(mode, first, count, instance_count)
}

pub fn active_texture(unit u32) {
	f := unsafe { FnActiveTexture(C.vcore_gl_get(slot_active_texture)) }
	f(unit)
}

pub fn uniform1i(location int, v int) {
	f := unsafe { FnUniform1i(C.vcore_gl_get(slot_uniform1i)) }
	f(location, v)
}

pub fn uniform2f(location int, x f32, y f32) {
	f := unsafe { FnUniform2f(C.vcore_gl_get(slot_uniform2f)) }
	f(location, x, y)
}

// Tamsayı girdi (GLSL uint/int): float'a dönüşmeden bellek bitleri olduğu gibi okunur.
pub fn vertex_attrib_i_pointer(index u32, size int, typ u32, stride int, pointer voidptr) {
	f := unsafe { FnVertexAttribIPointer(C.vcore_gl_get(slot_vertex_attrib_i_pointer)) }
	f(index, size, typ, stride, pointer)
}

// GL 1.1 sarmalayıcıları: doğrudan opengl32 çağrıları.

pub fn viewport(x int, y int, width int, height int) {
	C.glViewport(x, y, width, height)
}

pub fn clear(mask u32) {
	C.glClear(mask)
}

pub fn clear_color(r f32, g f32, b f32, a f32) {
	C.glClearColor(r, g, b, a)
}

pub fn read_pixels(x int, y int, width int, height int, format u32, typ u32, pixels voidptr) {
	C.glReadPixels(x, y, width, height, format, typ, pixels)
}

pub fn finish() {
	C.glFinish()
}

pub fn get_string(name u32) &u8 {
	return C.glGetString(name)
}

pub fn get_error() u32 {
	return C.glGetError()
}

pub fn get_integerv(pname u32, data voidptr) {
	C.glGetIntegerv(pname, data)
}

// Tek doku kimliği üreten sarmalayıcı: glGenTextures(1, ...).
pub fn gen_texture() u32 {
	mut id := u32(0)
	C.glGenTextures(1, voidptr(&id))
	return id
}

pub fn bind_texture(target u32, texture u32) {
	C.glBindTexture(target, texture)
}

// Tek doku kimlik silen sarmalayıcı: glDeleteTextures(1, ...).
pub fn delete_texture(texture u32) {
	mut id := texture
	C.glDeleteTextures(1, voidptr(&id))
}

pub fn tex_image_2d(target u32, level int, internal_format int, width int, height int, border int, format u32, typ u32, pixels voidptr) {
	C.glTexImage2D(target, level, internal_format, width, height, border, format, typ, pixels)
}

pub fn tex_parameteri(target u32, pname u32, param int) {
	C.glTexParameteri(target, pname, param)
}

pub fn pixel_storei(pname u32, param int) {
	C.glPixelStorei(pname, param)
}

pub fn enable(cap u32) {
	C.glEnable(cap)
}

pub fn disable(cap u32) {
	C.glDisable(cap)
}

pub fn blend_func(sfactor u32, dfactor u32) {
	C.glBlendFunc(sfactor, dfactor)
}

pub fn scissor(x int, y int, width int, height int) {
	C.glScissor(x, y, width, height)
}
