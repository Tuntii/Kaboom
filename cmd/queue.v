module cmd

import ecs
import memory

// Sabit kapasiteli komut kuyruğu. Komutlar kurulumda ayrılan bellekte tutulur; push ve flush tahsis yapmaz.
// Flush her kaynak sınıfını script, editor, agent sırasıyla tarar; sınıf içinde push sırası geçerlidir.
pub struct CommandQueue {
mut:
	cmds     &Command
	results  &ApplyResult
	capacity u32
	count    u32
	applied  bool
}

pub fn CommandQueue.new(mut parent memory.LinearArena, capacity u32) ?CommandQueue {
	m := parent.mark()
	cmds := parent.alloc_aligned(u64(capacity) * u64(sizeof(Command)), 8) or {
		parent.rewind(m)
		return none
	}
	results := parent.alloc_aligned(u64(capacity) * u64(sizeof(ApplyResult)), 8) or {
		parent.rewind(m)
		return none
	}
	return CommandQueue{
		cmds:     unsafe { &Command(cmds) }
		results:  unsafe { &ApplyResult(results) }
		capacity: capacity
	}
}

// Flush'tan sonraki ilk push kuyruğu ve sonuçları temizler. Kapasite doluysa ya da kaynak geçersizse false.
pub fn (mut q CommandQueue) push(c Command) bool {
	if q.applied {
		q.count = 0
		q.applied = false
	}
	if q.count >= q.capacity || u8(c.source) > u8(Source.agent) {
		return false
	}
	unsafe {
		q.cmds[q.count] = c
	}
	q.count++
	return true
}

// Tüm kuyruğu kaynak sınıfı sırasıyla uygular; ok olanları kayda yazar. Bu kuyruk için ikinci çağrı 0 döner.
pub fn (mut q CommandQueue) flush(mut w ecs.World, tick u64, mut rec Recorder, mut hist History) u32 {
	if q.applied {
		return 0
	}
	mut ok := u32(0)
	for src in [Source.script, Source.editor, Source.agent]! {
		for i in 0 .. q.count {
			c := unsafe { q.cmds[i] }
			if c.source != src {
				continue
			}
			// Geçmiş ters bloğu uygulamadan önce hazırlar; script komutları geçmişe girmez.
			if c.source != .script {
				hist.capture_before(&w, c)
			}
			r := apply(mut w, c)
			hist.commit_capture(r)
			unsafe {
				q.results[i] = r
			}
			if r.status == .ok {
				ok++
				// Script komutları replay'de simülasyon tarafından yeniden üretilir; kaydedilirse iki kez uygulanır.
				if c.source != .script {
					mut rc := c
					if c.kind == .spawn {
						rc.entity = r.entity
					}
					rec.append(tick, rc)
				}
			}
		}
	}
	q.applied = true
	return ok
}

pub fn (q &CommandQueue) len() u32 {
	return q.count
}

// i'inci push edilen komutun sonucu; flush'tan önce ya da aralık dışında invalid_command döner.
pub fn (q &CommandQueue) result(i u32) ApplyResult {
	if !q.applied || i >= q.count {
		return ApplyResult{
			status: .invalid_command
			entity: ecs.null_entity
		}
	}
	return unsafe { q.results[i] }
}
