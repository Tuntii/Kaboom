module cmd

import os
import memory

// Dosya başlığı: magic "VCRC", 32 bayt. Sürüm 2 gövdesi: start_tick u64, snapshot_len u64, snapshot, girdiler.
// Sürüm 1 (yalnız girdiler, boş dünya, tick 0) okunmaya devam eder. Ham baytlar doğal sırada (x86'da küçük-uçlu) yazılır.
const record_magic = u32(0x43524356)
const record_version_1 = u32(1)
const record_version = u32(2)
const record_header_size = u64(32)
const record_prefix_v2 = u64(16)

// Tek kayıt: tick ve komut. 32 bayt sabit boyutlu ikili kayıt.
pub struct RecordEntry {
pub:
	tick u64
	cmd  Command
}

// Dosyadan yüklenmiş ve doğrulanmış kayıt. snapshot boşsa kayıt boş dünyayla başlar (sürüm 1).
pub struct Recording {
pub:
	capacity   u32
	start_tick u64
	end_tick   u64
	snapshot   []u8
	entries    []RecordEntry
}

// Kurulumda parent'tan bir kez ayrılan kayıt tamponu. append tick yolunda tahsis yapmaz.
pub struct Recorder {
mut:
	buf        &RecordEntry
	capacity   u32
	count      u32
	active     bool
	overflow   bool
	start_tick u64
	// Kayıt başladığında dünyanın görüntüsü; stop'ta serbest bırakılır.
	snap []u8
}

pub fn Recorder.new(mut parent memory.LinearArena, capacity u32) ?Recorder {
	p := parent.alloc_aligned(u64(capacity) * u64(sizeof(RecordEntry)), 8) or { return none }
	return Recorder{
		buf:      unsafe { &RecordEntry(p) }
		capacity: capacity
	}
}

// Yeni kayda başlar: önceki kayıt ve taşma durumu silinir. snapshot, start_tick anındaki dünyanın görüntüsüdür.
pub fn (mut r Recorder) start(snapshot []u8, start_tick u64) {
	r.drop_snapshot()
	r.snap = snapshot
	r.start_tick = start_tick
	r.count = 0
	r.overflow = false
	r.active = true
}

pub fn (mut r Recorder) stop() {
	r.active = false
	r.drop_snapshot()
}

fn (mut r Recorder) drop_snapshot() {
	if r.snap.len > 0 {
		unsafe { r.snap.free() }
	}
	r.snap = []u8{}
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
	snap_len := r.snap.len
	entries_off := int(record_header_size + record_prefix_v2) + snap_len
	mut buf := []u8{len: entries_off + n * int(sizeof(RecordEntry))}
	put_u32(mut buf, 0, record_magic)
	put_u32(mut buf, 4, record_version)
	put_u32(mut buf, 8, world_capacity)
	put_u32(mut buf, 12, 0)
	put_u64(mut buf, 16, end_tick)
	put_u64(mut buf, 24, u64(r.count))
	put_u64(mut buf, int(record_header_size), r.start_tick)
	put_u64(mut buf, int(record_header_size) + 8, u64(snap_len))
	if snap_len > 0 {
		unsafe { vmemcpy(&buf[record_header_size + record_prefix_v2], &r.snap[0], snap_len) }
	}
	if n > 0 {
		unsafe { vmemcpy(&buf[entries_off], r.buf, n * int(sizeof(RecordEntry))) }
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
	version := get_u32(hdr, 4)
	if version != record_version_1 && version != record_version {
		return error('kayit dosyasi: desteklenmeyen surum ${version}')
	}
	count := get_u64(hdr, 24)
	size := os.file_size(path)
	body := size - record_header_size
	// count <= body/32 önce kontrol edilir: count*32 bu noktada taşamaz.
	if count > body / 32 {
		return error('kayit dosyasi: ${size} bayt, sayac ${count} kayit icin uyusmuyor')
	}
	mut data := []u8{len: int(body)}
	if body > 0 {
		read := f.read_from(record_header_size, mut data) or { return error('kayit dosyasi govdesi okunamadi: ${err}') }
		if u64(read) != body {
			return error('kayit dosyasi govdesi eksik: ${read} / ${body} bayt')
		}
	}
	if record_checksum(data) != get_u32(hdr, 12) {
		return error('kayit dosyasi: checksum mismatch')
	}
	// Sürüm 1 gövdesi yalnız girdiler; sürüm 2'de önek ve dünya görüntüsü var.
	mut start_tick := u64(0)
	mut snapshot := []u8{}
	mut entries_off := u64(0)
	if version == record_version {
		if body < record_prefix_v2 {
			return error('kayit dosyasi: gövde ${body} bayt, önek için yetmiyor')
		}
		start_tick = get_u64(data, 0)
		snap_len := get_u64(data, 8)
		if snap_len > body - record_prefix_v2 {
			return error('kayit dosyasi: dünya görüntüsü uzunluğu ${snap_len} gövdeye sığmıyor')
		}
		snapshot = data[record_prefix_v2..record_prefix_v2 + snap_len].clone()
		entries_off = record_prefix_v2 + snap_len
	}
	if body - entries_off != count * 32 {
		return error('kayit dosyasi: ${size} bayt, sayac ${count} kayit icin uyusmuyor')
	}
	n := int(count)
	mut entries := []RecordEntry{len: n}
	if n > 0 {
		unsafe { vmemcpy(&entries[0], &data[int(entries_off)], n * int(sizeof(RecordEntry))) }
	}
	mut prev_tick := start_tick
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
		if e.tick < prev_tick {
			return error('kayit ${i}: tick geriye gidiyor (${e.tick} < ${prev_tick})')
		}
		prev_tick = e.tick
	}
	end_tick := get_u64(hdr, 16)
	if end_tick < prev_tick {
		return error('kayit dosyasi: end_tick ${end_tick} son kayit tick ${prev_tick} altinda')
	}
	return Recording{
		capacity:   get_u32(hdr, 8)
		start_tick: start_tick
		end_tick:   end_tick
		snapshot:   snapshot
		entries:    entries
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
