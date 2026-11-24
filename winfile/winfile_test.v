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
