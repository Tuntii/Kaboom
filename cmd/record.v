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
	put_u32(mut buf, 12, record_checksum(buf[int(record_header_size)..]))
	os.write_file_array(path, buf)!
}

// Dosyayı okur. Önce yalnızca 32 baytlık başlık okunur ve uzunluk doğrulanır; gövde ondan sonra okunur.
// Sonra checksum ve her girdi doğrulanır: dosya güvenilmez girdi sayılır.
pub fn load_recording(path string) !Recording {
	mut f := os.open(path)!
	defer {
		f.close()
	}
	mut hdr := []u8{len: int(record_header_size)}
	got := f.read_from(0, mut hdr) or { return error('kayit dosyasi okunamadi: ${err}') }
	if u64(got) < record_header_size {
		return error('kayit dosyasi cok kisa: ${got} bayt')
	}
	if get_u32(hdr, 0) != record_magic {
		return error('kayit dosyasi: magic yanlis')
	}
	if get_u32(hdr, 4) != record_version {
		return error('kayit dosyasi: desteklenmeyen surum ${get_u32(hdr, 4)}')
	}
	count := get_u64(hdr, 24)
	size := os.file_size(path)
	body := size - record_header_size
	// count <= body/32 önce kontrol edilir: count*32 bu noktada taşamaz.
	if count > body / 32 || body != count * 32 {
		return error('kayit dosyasi: ${size} bayt, sayac ${count} kayit icin uyusmuyor')
	}
	n := int(count)
	mut data := []u8{len: int(body)}
	if n > 0 {
		read := f.read_from(record_header_size, mut data) or { return error('kayit dosyasi govdesi okunamadi: ${err}') }
		if u64(read) != body {
			return error('kayit dosyasi govdesi eksik: ${read} / ${body} bayt')
		}
	}
	if record_checksum(data) != get_u32(hdr, 12) {
		return error('kayit dosyasi: checksum mismatch')
	}
	mut entries := []RecordEntry{len: n}
	if n > 0 {
		unsafe { vmemcpy(&entries[0], &data[0], int(body)) }
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
		if e.cmd.source == .script {
			return error('kayit ${i}: script kaynakli komut kayda girmez')
		}
		if i > 0 && e.tick < entries[i - 1].tick {
			return error('kayit ${i}: tick geriye gidiyor (${e.tick} < ${entries[i - 1].tick})')
		}
	}
	end_tick := get_u64(hdr, 16)
	if n > 0 && end_tick < entries[n - 1].tick {
		return error('kayit dosyasi: end_tick ${end_tick} son kayit tick ${entries[n - 1].tick} altinda')
	}
	return Recording{
		capacity: get_u32(hdr, 8)
		end_tick: end_tick
		entries:  entries
	}
}

// Gövde bütünlük sağlaması: FNV-1a 64'ün alt 32 biti (bayt bayt). Başlığın reserved alanına yazılır.
fn record_checksum(body []u8) u32 {
	mut h := u64(0xcbf29ce484222325)
	for b in body {
		h = (h ^ u64(b)) * u64(0x100000001b3)
	}
	return u32(h)
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
