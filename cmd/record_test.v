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
	rec.start([]u8{}, 0)
	rec.append(1, Command{ kind: .spawn, source: .agent })
	rec.append(2, Command{ kind: .set_field, source: .editor, entity: 5, comp: 1, field: 2, value: 99 })
	rec.save(path, 100, 42) or { panic(err) }
}

fn patch_byte(path string, off int, v u8) {
	mut data := os.read_bytes(path) or { panic(err) }
	data[off] = v
	os.write_file_array(path, data) or { panic(err) }
}

// Gövde baytını değiştirip checksum'u yeniden mühürler: girdi doğrulamasının ulaşılmasını sağlar.
fn patch_entry_byte(path string, off int, v u8) {
	mut data := os.read_bytes(path) or { panic(err) }
	data[off] = v
	put_u32(mut data, 12, record_checksum(data[int(record_header_size)..]))
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
	rec.start([]u8{}, 0)
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
	rec.start([]u8{}, 0)
	rec.append(1, Command{ kind: .set_field, source: .agent, entity: 5, comp: 0, field: 1, value: 77 })
	rec.append(2, Command{ kind: .spawn, source: .agent, entity: 6 })
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
	assert got.entries[1] == RecordEntry{ tick: 2, cmd: Command{ kind: .spawn, source: .agent, entity: 6 } }
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
	patch_byte(path, 4, 3) // yanlış sürüm
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
	patch_entry_byte(path, 48 + 32 + 8, 5) // entry 1, cmd.kind = 5 (geçersiz)
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
	patch_entry_byte(path, 48 + 0 + 9, 3) // entry 0, cmd.source = 3 (geçersiz)
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
	patch_entry_byte(path, 48 + 32 + 14, 1) // entry 1, cmd.pad != 0
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
	rec.start([]u8{}, 0)
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

fn test_load_rejects_checksum_mismatch() {
	path := temp_record_path('bad_checksum')
	defer {
		os.rm(path) or {}
	}
	write_valid_recording(path)
	patch_byte(path, 48 + 5, 0x7F) // gövde baytı değişti, checksum yeniden mühürlenmedi
	load_recording(path) or {
		assert err.msg().contains('checksum mismatch')
		return
	}
	assert false
}

fn test_load_rejects_script_source_with_index() {
	region, mut rec := recorder_env(4)
	defer {
		memory.release(region)
	}
	rec.start([]u8{}, 0)
	rec.append(1, Command{ kind: .spawn, source: .agent })
	rec.append(2, Command{ kind: .spawn, source: .script })
	path := temp_record_path('script_source')
	defer {
		os.rm(path) or {}
	}
	rec.save(path, 100, 2) or { panic(err) }
	load_recording(path) or {
		assert err.msg().contains('kayit 1')
		assert err.msg().contains('script')
		return
	}
	assert false
}

fn test_load_rejects_non_monotonic_ticks_with_index() {
	region, mut rec := recorder_env(4)
	defer {
		memory.release(region)
	}
	rec.start([]u8{}, 0)
	rec.append(5, Command{ kind: .spawn, source: .agent })
	rec.append(3, Command{ kind: .spawn, source: .agent })
	path := temp_record_path('non_monotonic')
	defer {
		os.rm(path) or {}
	}
	rec.save(path, 100, 5) or { panic(err) }
	load_recording(path) or {
		assert err.msg().contains('kayit 1')
		return
	}
	assert false
}

fn test_load_rejects_end_tick_before_last_entry() {
	region, mut rec := recorder_env(4)
	defer {
		memory.release(region)
	}
	rec.start([]u8{}, 0)
	rec.append(5, Command{ kind: .spawn, source: .agent })
	path := temp_record_path('end_tick')
	defer {
		os.rm(path) or {}
	}
	rec.save(path, 100, 4) or { panic(err) }
	assert load_fails(path)
}

// Sürüm 2: dünya görüntüsü ve başlangıç tick'i dosyadan aynen geri okunur.
fn test_save_load_v2_keeps_snapshot_and_start_tick() {
	region, mut rec := recorder_env(4)
	defer {
		memory.release(region)
	}
	snap := [u8(1), 2, 3, 4, 5]
	rec.start(snap, 7)
	rec.append(8, Command{ kind: .spawn, source: .agent })
	path := temp_record_path('v2_roundtrip')
	defer {
		os.rm(path) or {}
	}
	rec.save(path, 100, 9) or { panic(err) }
	got := load_recording(path) or { panic(err) }
	assert got.start_tick == 7
	assert got.end_tick == 9
	assert got.snapshot == snap
	assert got.entries.len == 1 && got.entries[0].tick == 8
}

// Sürüm 1 dosyası (başlıkta 1, gövde yalnız girdiler) hâlâ okunur: boş dünya, tick 0.
fn test_load_version1_file_has_empty_start() {
	path := temp_record_path('v1_file')
	defer {
		os.rm(path) or {}
	}
	mut buf := []u8{len: 64}
	put_u32(mut buf, 0, record_magic)
	put_u32(mut buf, 4, record_version_1)
	put_u32(mut buf, 8, 100)
	put_u64(mut buf, 16, 42)
	put_u64(mut buf, 24, 1)
	e := RecordEntry{
		tick: 3
		cmd:  Command{ kind: .spawn, source: .agent }
	}
	unsafe { vmemcpy(&buf[32], &e, 32) }
	put_u32(mut buf, 12, record_checksum(buf[32..]))
	os.write_file_array(path, buf) or { panic(err) }
	got := load_recording(path) or { panic(err) }
	assert got.start_tick == 0
	assert got.snapshot.len == 0
	assert got.end_tick == 42
	assert got.entries.len == 1 && got.entries[0].tick == 3
}

// Sürüm 2'de girdi, başlangıç tick'inden önce olamaz.
fn test_load_rejects_entry_before_start_tick() {
	region, mut rec := recorder_env(4)
	defer {
		memory.release(region)
	}
	rec.start([u8(1), 2, 3, 4], 10)
	rec.append(5, Command{ kind: .spawn, source: .agent })
	path := temp_record_path('before_start')
	defer {
		os.rm(path) or {}
	}
	rec.save(path, 100, 20) or { panic(err) }
	load_recording(path) or {
		assert err.msg().contains('kayit 0')
		return
	}
	assert false
}
