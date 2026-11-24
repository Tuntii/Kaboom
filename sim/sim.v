module sim

import ecs
import cmd
import memory

#flag -ffp-contract=off

// Sabit adım: 120 Hz. f32 sabiti; FMA ve f64 kullanılmaz.
pub const dt = f32(1.0) / f32(120.0)

pub struct Config {
pub:
	capacity        u32 = 100_000
	queue_capacity  u32 = 65_536
	record_capacity u32 = 1_048_576
	history_capacity u32 = 65_536
	history_groups   u32 = 4_096
}

// Üst sınır: her tahsis en fazla 63 bayt hizalama boşluğu yer; tahsis başına 64 bayt bunu karşılar.
pub fn (c Config) bytes_needed(reg &ecs.Registry) u64 {
	mut total := u64(0)
	mut allocs := u64(0)
	// EntityAllocator: nesil u16, boş liste u32, canlı bit dizisi u64 kelimeleri.
	words := (u64(c.capacity) + 63) / 64
	total += u64(c.capacity) * 6 + words * 8
	allocs += 3
	for id in u16(0) .. reg.count() {
		schema := reg.component(id) or { break }
		// Sparse ve dense dizileri u32.
		total += u64(c.capacity) * 8
		allocs += 2
		for f in schema.fields {
			total += u64(c.capacity) * u64(f.typ.size())
			allocs++
		}
	}
	total += u64(c.queue_capacity) * (u64(sizeof(cmd.Command)) + u64(sizeof(cmd.ApplyResult)))
	allocs += 2
	total += u64(c.record_capacity) * u64(sizeof(cmd.RecordEntry))
	allocs++
	// Geçmiş kendi ayırma payını (7 tahsis) içinde hesaplar.
	total += cmd.History.bytes_needed(reg, c.history_capacity, c.history_groups)
	return total + allocs * 64
}

// Sim tüm belleğini parent arenadan alır; tick yolu tahsis yapmaz.
pub struct Sim {
pub mut:
	world    ecs.World
	queue    cmd.CommandQueue
	recorder cmd.Recorder
	history  cmd.History
mut:
	// Alan adı tick() metoduyla çakışmasın diye current_tick.
	current_tick u64
	// Alan indeksleri Sim.new'de registry'den çözülür; sabit koda gömülmez.
	tr_x      u16
	tr_y      u16
	tr_prev_x u16
	tr_prev_y u16
	body_vx   u16
	body_vy   u16
}

// Hata olursa parent başladığı konuma geri sarılır. Transform ya da Body alanı registry'de yoksa none.
pub fn Sim.new(mut parent memory.LinearArena, reg &ecs.Registry, cfg Config) ?Sim {
	tr := reg.component(ecs.transform_id) or { return none }
	body := reg.component(ecs.body_id) or { return none }
	tr_x := tr.field_index('x') or { return none }
	tr_y := tr.field_index('y') or { return none }
	tr_prev_x := tr.field_index('prev_x') or { return none }
	tr_prev_y := tr.field_index('prev_y') or { return none }
	body_vx := body.field_index('vx') or { return none }
	body_vy := body.field_index('vy') or { return none }
	m := parent.mark()
	world := ecs.World.new(mut parent, reg, cfg.capacity) or {
		parent.rewind(m)
		return none
	}
	queue := cmd.CommandQueue.new(mut parent, cfg.queue_capacity) or {
		parent.rewind(m)
		return none
	}
	recorder := cmd.Recorder.new(mut parent, cfg.record_capacity) or {
		parent.rewind(m)
		return none
	}
	history := cmd.History.new(mut parent, reg, cfg.history_capacity, cfg.history_groups) or {
		parent.rewind(m)
		return none
	}
	return Sim{
		world:     world
		queue:     queue
		recorder:  recorder
		history:   history
		tr_x:      tr_x
		tr_y:      tr_y
		tr_prev_x: tr_prev_x
		tr_prev_y: tr_prev_y
		body_vx:   body_vx
		body_vy:   body_vy
	}
}

// Motorun V heap'teki ayırmalarını (dünya bileşen dizisi) serbest bırakır; geri kalan bellek parent arenadadır.
pub fn (mut s Sim) free() {
	s.world.free()
}

pub fn (mut s Sim) push(c cmd.Command) bool {
	return s.queue.push(c)
}

// Kuyruğu o anki tick numarasıyla uygular.
pub fn (mut s Sim) flush() u32 {
	return s.queue.flush(mut s.world, s.current_tick, mut s.recorder, mut s.history)
}

// Sıra: komutlar, prev_* yazımı, hareket, tick++.
pub fn (mut s Sim) step() {
	s.flush()
	tr := s.world.store(ecs.transform_id)
	x := tr.column_f32(s.tr_x)
	y := tr.column_f32(s.tr_y)
	px := tr.column_f32(s.tr_prev_x)
	py := tr.column_f32(s.tr_prev_y)
	for row in 0 .. tr.len() {
		unsafe {
			px[row] = x[row]
			py[row] = y[row]
		}
	}
	// Body satırlarından Transform satırına: sparse-set üzerinden varlık eşlemesi.
	body := s.world.store(ecs.body_id)
	vx := body.column_f32(s.body_vx)
	vy := body.column_f32(s.body_vy)
	for row in 0 .. body.len() {
		tr_row := tr.row_of(body.index_at(row)) or { continue }
		unsafe {
			x[tr_row] = x[tr_row] + vx[row] * dt
			y[tr_row] = y[tr_row] + vy[row] * dt
		}
	}
	s.current_tick++
}

pub fn (s &Sim) tick() u64 {
	return s.current_tick
}

// Tekrar oynatma: kayıt başlangıç tick'ine çekilir. Tick yolunda kullanılmaz.
pub fn (mut s Sim) set_tick(t u64) {
	s.current_tick = t
}

// Kaydı o anki dünyanın görüntüsü ve tick'iyle başlatır (D2: her dünyada çalışır). Tahsis yapar; tick yolunda değildir.
pub fn (mut s Sim) start_recording() {
	s.recorder.start(s.world.snapshot(), s.current_tick)
}

pub fn (s &Sim) state_hash() u64 {
	return state_hash(&s.world, s.current_tick)
}
