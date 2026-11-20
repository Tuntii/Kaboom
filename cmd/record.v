module cmd

import os
import memory

// Dosya başlığı: magic "VCRC", sürüm 1, 32 bayt. Ham baytlar doğal sırada (x86'da küçük-uçlu) yazılır.
const record_magic = u32(0x43524356)
const record_version = u32(1)
const record_header_size = u64(32)

// Tek kayıt: tick ve komut. 32 bayt sabit boyutlu ikili kayıt.
pub struct RecordEntry {
pub:
	tick u64
	cmd  Command
}

// Dosyadan yüklenmiş ve doğrulanmış kayıt.
pub struct Recording {
pub:
	capacity u32
	end_tick u64
	entries  []RecordEntry
}

// Kurulumda parent'tan bir kez ayrılan kayıt tamponu. append tick yolunda tahsis yapmaz.
pub struct Recorder {
mut:
	buf      &RecordEntry
	capacity u32
	count    u32
	active   bool
	overflow bool
}

pub fn Recorder.new(mut parent memory.LinearArena, capacity u32) ?Recorder {
	p := parent.alloc_aligned(u64(capacity) * u64(sizeof(RecordEntry)), 8) or { return none }
	return Recorder{
		buf:      unsafe { &RecordEntry(p) }
		capacity: capacity
	}
}

// Yeni kayda başlar: önceki kayıt ve taşma durumu silinir.
pub fn (mut r Recorder) start() {
	r.count = 0
	r.overflow = false
	r.active = true
}

pub fn (mut r Recorder) stop() {
	r.active = false
}

// Tick yolu: aktif değilse no-op; tampon doluysa kayıt atılır ve overflow işaretlenir.
pub fn (mut r Recorder) append(tick u64, c Command) {
	if !r.active {
		return
	}
	if r.count >= r.capacity {
		r.overflow = true
		return
	}
	unsafe {
		r.buf[r.count] = RecordEntry{
			tick: tick
			cmd:  c
		}
	}
	r.count++
}

pub fn (r &Recorder) is_active() bool {
	return r.active
}

pub fn (r &Recorder) len() u32 {
	return r.count
}

pub fn (r &Recorder) overflowed() bool {
	return r.overflow
}

// Dosya I/O; tick dışındadır. Taşmış kaydı yazmaz: eksik kayıt sessizce kaydedilmez.
pub fn (r &Recorder) save(path string, world_capacity u32, end_tick u64) ! {
	if r.overflow {
		return error('kayit tampon tasti, dosya yazilmadi')
	}
	n := int(r.count)
	mut buf := []u8{len: int(record_header_size) + n * int(sizeof(RecordEntry))}
	put_u32(mut buf, 0, record_magic)
	put_u32(mut buf, 4, record_version)
	put_u32(mut buf, 8, world_capacity)
	put_u32(mut buf, 12, 0)
	put_u64(mut buf, 16, end_tick)
	put_u64(mut buf, 24, u64(r.count))
	if n > 0 {
		unsafe { vmemcpy(&buf[record_header_size], r.buf, n * int(sizeof(RecordEntry))) }
	}
	os.write_file_array(path, buf)!
}

// Dosyayı okur ve kopyalamadan önce başlık ve uzunluğu, kopyaladıktan sonra her girdiyi doğrular.
pub fn load_recording(path string) !Recording {
	data := os.read_bytes(path)!
	if u64(data.len) < record_header_size {
		return error('kayit dosyasi cok kisa: ${data.len} bayt')
	}
	if get_u32(data, 0) != record_magic {
		return error('kayit dosyasi: magic yanlis')
	}
	if get_u32(data, 4) != record_version {
		return error('kayit dosyasi: desteklenmeyen surum ${get_u32(data, 4)}')
	}
	count := get_u64(data, 24)
	body := u64(data.len) - record_header_size
	// count <= body/32 önce kontrol edilir: count*32 bu noktada taşamaz.
	if count > body / 32 || body != count * 32 {
		return error('kayit dosyasi: ${data.len} bayt, sayac ${count} kayit icin uyusmuyor')
	}
	n := int(count)
	mut entries := []RecordEntry{len: n}
	if n > 0 {
		unsafe { vmemcpy(&entries[0], &data[int(record_header_size)], int(body)) }
	}
	for i, e in entries {
		kind := u8(e.cmd.kind)
		if kind >= 5 {
			return error('kayit ${i}: gecersiz komut turu ${kind}')
		}
		source := u8(e.cmd.source)
		if source >= 3 {
			return error('kayit ${i}: gecersiz kaynak ${source}')
		}
		if e.cmd.pad != 0 {
			return error('kayit ${i}: pad sifir degil')
		}
	}
	return Recording{
		capacity: get_u32(data, 8)
		end_tick: get_u64(data, 16)
		entries:  entries
	}
}

fn put_u32(mut buf []u8, off int, v u32) {
	unsafe { vmemcpy(&buf[off], &v, 4) }
}

fn put_u64(mut buf []u8, off int, v u64) {
	unsafe { vmemcpy(&buf[off], &v, 8) }
}

fn get_u32(data []u8, off int) u32 {
	mut v := u32(0)
	unsafe { vmemcpy(&v, &data[off], 4) }
	return v
}

fn get_u64(data []u8, off int) u64 {
	mut v := u64(0)
	unsafe { vmemcpy(&v, &data[off], 8) }
	return v
}
