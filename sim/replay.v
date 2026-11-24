module sim

import cmd
import ecs
import memory

// Tekrar oynatma sonucu: bitiş tick'i ve o tick'teki durum hash'i.
pub struct ReplayResult {
pub:
	end_tick u64
	hash     u64
}

// Kaydı taze bir Sim'de yeniden oynatır: önce dünya görüntüsü (sürüm 1'de boş dünya), sonra tick ve girdiler doğrudan uygulanır.
pub fn replay(rec cmd.Recording, reg &ecs.Registry) !ReplayResult {
	// Doğrulama tahsis gerektirmez; bozuk kayıt bölge ayrılmadan reddedilir.
	mut prev := rec.start_tick
	for e in rec.entries {
		if e.tick < prev {
			return error('replay ayrıştı: tick ${e.tick}: kayıt sırası monoton değil (önceki tick ${prev})')
		}
		prev = e.tick
	}
	if rec.end_tick < prev {
		return error('replay ayrıştı: tick ${rec.end_tick}: bitiş son girdiden (tick ${prev}) önce')
	}

	// Replay kuyruk ve flush kullanmaz; geçmiş yalnızca Sim kurulumu için küçük ayrılır.
	cfg := Config{
		capacity:         rec.capacity
		record_capacity:  1
		history_capacity: 1
		history_groups:   1
	}
	need := cfg.bytes_needed(reg)
	region := memory.reserve(need) or { return error('replay setup failed: region reservation failed (${need} bytes)') }
	defer { memory.release(region) }
	mut a := memory.LinearArena.new(region, need)
	mut s := Sim.new(mut a, reg, cfg) or { return error('replay setup failed: Sim could not be created') }
	if rec.snapshot.len > 0 {
		s.world.restore(rec.snapshot) or { return error('replay snapshot rejected: ${err.msg()}') }
	}
	s.set_tick(rec.start_tick)

	// Ayrışma "replay diverged: " önekiyle döner; protokol bu öneki 1011 olarak eşler.
	for i, e in rec.entries {
		for s.tick() < e.tick {
			s.step()
		}
		r := cmd.apply(mut s.world, e.cmd)
		if r.status != .ok {
			return error('replay diverged: tick ${e.tick} entry ${i} status ${r.status} entity ${e.cmd.entity}')
		}
		// Spawn'ın ürettiği id kayıtla aynı olmalı; değilse dünya ayrışmıştır.
		if e.cmd.kind == .spawn && r.entity != e.cmd.entity {
			return error('replay diverged: tick ${e.tick} entry ${i} status ok expected_entity ${e.cmd.entity} got ${r.entity}')
		}
	}
	for s.tick() < rec.end_tick {
		s.step()
	}
	return ReplayResult{
		end_tick: s.tick()
		hash:     s.state_hash()
	}
}
