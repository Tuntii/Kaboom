module protocol

import cmd
import ecs

// Geri alma / yineleme yürütmesi ve editör grup API'si. Bir yığın grubu ters bloklarıyla kopyalanır,
// komutlar kuyrukta tek tek (her biri kendi flush'ıyla) uygulanır.

// Spawn ile yeniden doğan varlığın eski ve yeni id'si.
struct IdPair {
	old ecs.EntityID
	new ecs.EntityID
}

pub fn (mut s Server) history_undo() !Val {
	return s.history_run(true)
}

pub fn (mut s Server) history_redo() !Val {
	return s.history_run(false)
}

fn (mut s Server) history_run(undo bool) !Val {
	// Açık editör grubunun içinde geri alma tanımsızdır: yığınlara dokunmadan reddedilir.
	if s.editor_depth > 0 {
		return history_refused('editor_group_open')
	}
	popped := if undo { s.engine.history.pop_undo() } else { s.engine.history.pop_redo() }
	// Yığın boşsa hata değil: applied false.
	view := popped or { return history_refused('empty') }
	// Kopya önce alınır: ters işlemin yakalaması halkanın üzerine yazar. Komutlar isteği yapanın kaynağını taşır.
	mut blocks := copy_blocks(view, s.source)
	defer {
		free_blocks(mut blocks)
	}
	mode := if undo { cmd.HistoryMode.undoing } else { cmd.HistoryMode.redoing }
	// Tüm yürütme tek grup: karşı yığına (yineleme ya da geri alma) tek bir adım olarak girer.
	s.engine.history.begin_group()
	s.engine.history.set_mode(mode)
	ok, failed, pairs := s.apply_blocks(mut blocks)
	s.engine.history.set_mode(.normal)
	s.engine.history.end_group()
	res := history_result(true, ok, failed, pairs)
	unsafe { pairs.free() }
	return res
}

// Editör API'si (protokol komutu değil): açık grup, süreç içi istekleri tek geri alma adımında toplar.
pub fn (mut s Server) history_begin_group() {
	s.editor_depth++
	s.engine.history.begin_group()
}

// Açık editör grubu yoksa hiçbir şey yapma: dengesiz end, bir isteğin grubunu erken kapatmasın.
pub fn (mut s Server) history_end_group() {
	if s.editor_depth == 0 {
		return
	}
	s.editor_depth--
	s.engine.history.end_group()
}

// Açık grubun ters bloklarını hemen ters sırada uygular (yakalama kapalı) ve grubu hiçbir yığına koymaz.
// Hazırlama alanı kapasiteyi aştıysa hiçbir şey uygulanmaz, grup açık kalır ve hata döner: çağıran
// history_end_group ile normal kapatabilir (taşan grup düşürülür).
pub fn (mut s Server) history_cancel_group() ! {
	// Editör grubu açık değilse iptal bir şey yapmaz: istek düzeyindeki hazırlama alanına dokunulmaz.
	if s.editor_depth == 0 {
		return error('no editor group open')
	}
	if s.engine.history.stage_overflowed() {
		return error('history: open group overflowed the staging area; nothing was undone, end the group normally')
	}
	view := s.engine.history.staged()
	// Editör API'leri yalnız editörden çağrılır (R4): iptal, handle_from dışında çağrıldığı için s.source (varsayılan agent) değil .editor etiketler.
	mut blocks := copy_blocks(view, .editor)
	defer {
		free_blocks(mut blocks)
	}
	s.engine.history.abandon_group()
	s.editor_depth = 0
	s.engine.history.set_mode(.off)
	_, _, pairs := s.apply_blocks(mut blocks)
	unsafe { pairs.free() }
	s.engine.history.set_mode(.normal)
}

// Blokları sırayla uygular. Başarısız komut sayılır ve yürütme sürer. Spawn'ın eski id'si yeni id ile
// değişir: geçmiş yığınları ve bu blokların kalan komutları yeniden eşlenir.
fn (mut s Server) apply_blocks(mut blocks [][]cmd.Command) (u32, u32, []IdPair) {
	mut ok := u32(0)
	mut failed := u32(0)
	mut pairs := []IdPair{}
	for bi in 0 .. blocks.len {
		for ci in 0 .. blocks[bi].len {
			c := blocks[bi][ci]
			if !s.engine.push(c) {
				failed++
				continue
			}
			_ = s.engine.flush()
			r := s.engine.queue.result(0)
			if r.status != .ok {
				failed++
				continue
			}
			ok++
			if c.kind == .spawn && r.entity != c.entity {
				pairs << IdPair{
					old: c.entity
					new: r.entity
				}
				s.engine.history.remap(c.entity, r.entity)
				rewrite_after(mut blocks, bi, ci, c.entity, r.entity)
			}
		}
	}
	return ok, failed, pairs
}

// Yeni id'yi (bi, ci) komutundan sonraki komutlarda uygular: kopyalar halkadan okunmaz.
fn rewrite_after(mut blocks [][]cmd.Command, bi int, ci int, old ecs.EntityID, new ecs.EntityID) {
	for bj in bi .. blocks.len {
		for cj in 0 .. blocks[bj].len {
			if bj == bi && cj <= ci {
				continue
			}
			if blocks[bj][cj].entity == old {
				mut c := blocks[bj][cj]
				c.entity = new
				blocks[bj][cj] = c
			}
		}
	}
}

// copy_blocks'un ayırdığı dış ve iç dizileri serbest bırakır.
fn free_blocks(mut blocks [][]cmd.Command) {
	for mut b in blocks {
		unsafe { b.free() }
	}
	unsafe { blocks.free() }
}

// Blokları ring belleğinden ayrı dizilere kopyalar; block(0) en son blok, yani uygulama sırası.
// Her komut, bu işlemi tetikleyen isteğin kaynağını taşır (kayıtta kimin yaptığı görünsün).
fn copy_blocks(view cmd.GroupView, src cmd.Source) [][]cmd.Command {
	mut out := [][]cmd.Command{}
	for i in 0 .. view.block_count() {
		mut dst := []cmd.Command{}
		for c in view.block(i) {
			mut sc := c
			sc.source = src
			dst << sc
		}
		out << dst
	}
	return out
}

// Reddedilen geri alma/yineleme: uygulanmadı, neden alanı çağırana ne olduğunu söyler ("empty" ya da "editor_group_open").
fn history_refused(reason string) Val {
	out := history_result(false, 0, 0, []IdPair{})
	out.set('reason', str_val(reason))
	return out
}

fn history_result(applied bool, ok u32, failed u32, pairs []IdPair) Val {
	out := obj()
	out.set('applied', bool_val(applied))
	out.set('commands', num(f64(ok)))
	out.set('failed', num(f64(failed)))
	list := arr()
	for p in pairs {
		e := obj()
		e.set('old', num(f64(u64(p.old))))
		e.set('new', num(f64(u64(p.new))))
		list.push(e)
	}
	out.set('remap', list)
	return out
}
