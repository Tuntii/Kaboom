module render

// Yuva tablosu (gl_procs.h) ile ad listesi aynı boyda olmalı: fazla ad sessizce dizi dışına yazar.
fn test_gl_name_table_matches_slot_count() {
	assert gl_fn_names.len == C.VCORE_GL_SLOTS, 'gl_fn_names ${gl_fn_names.len} ad, VCORE_GL_SLOTS ${C.VCORE_GL_SLOTS}'
}
