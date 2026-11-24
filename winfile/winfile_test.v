module winfile

import os

fn test_write_and_replace_unicode_path() {
	dir := os.join_path(os.temp_dir(), 'vcore_winfile_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	dst := os.join_path(dir, 'dosya_ğüş.bin')
	tmp := dst + '.tmp'
	write_file(dst, 'OLD'.bytes()) or { panic(err) }
	write_file(tmp, 'NEW'.bytes()) or { panic(err) }
	replace_file(tmp, dst) or { panic(err) }
	assert (os.read_file(dst) or { panic(err) }) == 'NEW'
	assert !os.exists(tmp)
}

fn test_write_file_missing_folder_fails() {
	dir := os.join_path(os.temp_dir(), 'vcore_winfile_missing_test')
	os.rmdir_all(dir) or {}
	path := os.join_path(dir, 'yok', 'a.bin')
	write_file(path, 'X'.bytes()) or {
		assert !os.exists(path)
		return
	}
	assert false, 'missing folder must fail'
}

fn test_replace_file_missing_tmp_keeps_dst() {
	dir := os.join_path(os.temp_dir(), 'vcore_winfile_replace_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	dst := os.join_path(dir, 'a.bin')
	os.write_file(dst, 'OLD') or { panic(err) }
	replace_file(os.join_path(dir, 'yok.tmp'), dst) or {
		assert (os.read_file(dst) or { panic(err) }) == 'OLD'
		return
	}
	assert false, 'missing tmp must fail'
}

fn test_read_file_unicode_path_roundtrip() {
	dir := os.join_path(os.temp_dir(), 'vcore_winfile_read_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'sahne_ğüş.vscene')
	write_file(path, [u8(0x00), 0x0a, 0xff, 0x0d]) or { panic(err) }
	got := read_file(path) or { panic(err) }
	assert got == [u8(0x00), 0x0a, 0xff, 0x0d]
}

fn test_read_file_missing_fails() {
	dir := os.join_path(os.temp_dir(), 'vcore_winfile_read_missing_test')
	os.rmdir_all(dir) or {}
	read_file(os.join_path(dir, 'yok.vscene')) or { return }
	assert false, 'missing file must fail'
}

// Sınır aşılınca dosya ayrılmadan reddedilir: 256 MiB'lik gerçek dosya yerine küçük bir sınır enjekte edilir.
fn test_read_file_refuses_over_cap_before_reading() {
	dir := os.join_path(os.temp_dir(), 'vcore_winfile_cap_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'sinir.bin')
	write_file(path, 'ABCDEFGHIJKLMNOP'.bytes()) or { panic(err) }
	mut refused := false
	read_file_capped(path, 8) or { refused = true }
	assert refused
	// Sınır tam dosya boyutuna eşitse okunur.
	got := read_file_capped(path, 16) or { panic(err) }
	assert got.len == 16
}
