module render

// Vertex ve fragment shader'ı derler, programa bağlar ve linkler.
// Derleme veya link hatasında GL info log'u mesaja eklenir. Tick dışıdır; V string tahsisi yapabilir.
pub fn compile_program(vs string, fs string) !u32 {
	vsh := build_shader(gl_vertex_shader, vs)!
	fsh := build_shader(gl_fragment_shader, fs) or {
		delete_shader(vsh)
		return err
	}
	prog := create_program()
	attach_shader(prog, vsh)
	attach_shader(prog, fsh)
	link_program(prog)
	// Link sonrası shader nesneleri silinebilir; program kendi kopyasını tutar.
	delete_shader(vsh)
	delete_shader(fsh)
	mut ok := 0
	get_programiv(prog, gl_link_status, voidptr(&ok))
	if ok == 0 {
		msg := program_log(prog)
		delete_program(prog)
		return error('shader link hatasi: ${msg}')
	}
	return prog
}

fn build_shader(kind u32, src string) !u32 {
	id := create_shader(kind)
	if id == 0 {
		return error('glCreateShader basarisiz')
	}
	ptr := src.str
	src_len := src.len
	shader_source(id, 1, voidptr(&ptr), voidptr(&src_len))
	compile_shader(id)
	mut ok := 0
	get_shaderiv(id, gl_compile_status, voidptr(&ok))
	if ok == 0 {
		msg := shader_log(id)
		delete_shader(id)
		return error('shader derleme hatasi: ${msg}')
	}
	return id
}

fn shader_log(id u32) string {
	mut n := 0
	get_shaderiv(id, gl_info_log_length, voidptr(&n))
	if n <= 0 {
		return ''
	}
	// Sıfırlanmış tampon: GL yazmasa bile NUL ile biter.
	mut buf := []u8{len: n}
	get_shader_info_log(id, n, unsafe { nil }, buf.data)
	s := unsafe { cstring_to_vstring(&char(buf.data)) }
	return s.trim_right('\r\n')
}

fn program_log(id u32) string {
	mut n := 0
	get_programiv(id, gl_info_log_length, voidptr(&n))
	if n <= 0 {
		return ''
	}
	mut buf := []u8{len: n}
	get_program_info_log(id, n, unsafe { nil }, buf.data)
	s := unsafe { cstring_to_vstring(&char(buf.data)) }
	return s.trim_right('\r\n')
}
