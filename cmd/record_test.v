module cmd

import os
import memory

fn temp_record_path(name string) string {
	return os.join_path(os.temp_dir(), 'vcore_cmd_${name}.vcrc')
}

// Test ortamı: yalnızca kayıt tamponu; çağıran bölgeyi serbest bırakır.
fn recorder_env(capacity u32) (&u8, Recorder) {
	region := memory.reserve(1 << 16) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, 1 << 16)
	rec := Recorder.new(mut a, capacity) or { panic('Recorder.new none') }
	return region, rec
}

// Üç geçerli girdili kaydı dosyaya yazar (iki girdi için bayt ofsetleri testlerde kullanılır).
fn write_valid_recording(path string) {
	region, mut rec := recorder_env(4)
	defer {
		memory.release(region)
	}
	rec.start()
	rec.append(1, Command{ kind: .spawn, source: .agent })
	rec.append(2, Command{ kind: .set_field, source: .editor, entity: 5, comp: 1, field: 2, value: 99 })
	rec.save(path, 100, 42) or { panic(err) }
}

fn patch_byte(path string, off int, v u8) {
	mut data := os.read_bytes(path) or { panic(err) }
	data[off] = v
	os.write_file_array(path, data) or { panic(err) }
}

fn load_fails(path string) bool {
	load_recording(path) or { return true }
	return false
}

fn test_entry_is_32_bytes() {
	assert sizeof(RecordEntry) == 32
}

fn test_append_inactive_is_noop() {
	region, mut rec := recorder_env(4)
	defer {
		memory.release(region)
	}
	rec.append(1, Command{ kind: .spawn, source: .agent })
	assert rec.len() == 0
	assert !rec.is_active()
	rec.start()
	rec.append(1, Command{ kind: .spawn, source: .agent })
	rec.stop()
	rec.append(2, Command{ kind: .spawn, source: .agent })
	assert rec.len() == 1
}

fn test_save_load_roundtrip() {
	region, mut rec := recorder_env(4)
	defer {
		memory.release(region)
	}
	rec.start()
	rec.append(1, Command{ kind: .set_field, source: .agent, entity: 5, comp: 0, field: 1, value: 77 })
	rec.append(2, Command{ kind: .spawn, source: .script, entity: 6 })
	rec.append(2, Command{ kind: .despawn, source: .editor, entity: 6 })
	path := temp_record_path('roundtrip')
	defer {
		os.rm(path) or {}
	}
	rec.save(path, 100, 42) or { panic(err) }
	got := load_recording(path) or { panic(err) }
	assert got.capacity == 100
	assert got.end_tick == 42
	assert got.entries.len == 3
	assert got.entries[0] == RecordEntry{ tick: 1, cmd: Command{ kind: .set_field, source: .agent, entity: 5, comp: 0, field: 1, value: 77 } }
	assert got.entries[1] == RecordEntry{ tick: 2, cmd: Command{ kind: .spawn, source: .script, entity: 6 } }
	assert got.entries[2] == RecordEntry{ tick: 2, cmd: Command{ kind: .despawn, source: .editor, entity: 6 } }
}

fn test_load_rejects_bad_files() {
	path := temp_record_path('bad')
	defer {
		os.rm(path) or {}
	}
	assert load_fails(temp_record_path('missing_file_does_not_exist'))

	os.write_file(path, '0123456789') or { panic(err) }
	assert load_fails(path) // 10 bayt: başlık bile sığmıyor

	write_valid_recording(path)
	patch_byte(path, 0, 0) // yanlış magic
	assert load_fails(path)

	write_valid_recording(path)
	patch_byte(path, 4, 2) // yanlış sürüm
	assert load_fails(path)

	write_valid_recording(path)
	patch_byte(path, 31, 0xFF) // count'un en yüksek baytı: sınır kontrolü taşmadan yakalamalı
	assert load_fails(path)

	write_valid_recording(path)
	data := os.read_bytes(path) or { panic(err) }
	os.write_file_array(path, data[..data.len - 1]) or { panic(err) } // kesik dosya
	assert load_fails(path)
}

// Entry geçerlilik kontrolleri: hata, bozuk girdinin indeksini adlandırmalı.
fn test_load_rejects_bad_kind_with_index() {
	path := temp_record_path('bad_kind')
	defer {
		os.rm(path) or {}
	}
	write_valid_recording(path)
	patch_byte(path, 32 + 32 + 8, 5) // entry 1, cmd.kind = 5 (geçersiz)
	load_recording(path) or {
		assert err.msg().contains('kayit 1')
		return
	}
	assert false
}

fn test_load_rejects_bad_source_with_index() {
	path := temp_record_path('bad_source')
	defer {
		os.rm(path) or {}
	}
	write_valid_recording(path)
	patch_byte(path, 32 + 0 + 9, 3) // entry 0, cmd.source = 3 (geçersiz)
	load_recording(path) or {
		assert err.msg().contains('kayit 0')
		return
	}
	assert false
}

fn test_load_rejects_nonzero_pad_with_index() {
	path := temp_record_path('bad_pad')
	defer {
		os.rm(path) or {}
	}
	write_valid_recording(path)
	patch_byte(path, 32 + 32 + 14, 1) // entry 1, cmd.pad != 0
	load_recording(path) or {
		assert err.msg().contains('kayit 1')
		return
	}
	assert false
}

fn test_overflow_blocks_save() {
	region, mut rec := recorder_env(1)
	defer {
		memory.release(region)
	}
	rec.start()
	rec.append(1, Command{ kind: .spawn, source: .agent })
	rec.append(2, Command{ kind: .spawn, source: .agent })
	assert rec.overflowed()
	assert rec.len() == 1
	path := temp_record_path('overflow')
	defer {
		os.rm(path) or {}
	}
	rec.save(path, 100, 2) or {
		assert !os.exists(path)
		return
	}
	assert false
}
