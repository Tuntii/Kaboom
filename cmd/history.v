module cmd

import ecs
import memory

// Geçmiş modu: normal işlem undo yığınını besler; undo/redo kendi ters işlemlerini karşı yığına yazar.
pub enum HistoryMode {
	normal
	undoing
	redoing
}

// Bir komutun ters işlemi: halkadaki mutlak komut sırası ve uzunluk. Blok halkada bitişik durur.
struct HistoryBlock {
	start u64
	n     u32
}

// Tamamlanmış bir kullanıcı adımı: komut ve blok aralıkları (mutlak sıra, yarı açık).
struct HistoryGroup {
	cstart u64
	cend   u64
	bstart u64
	bend   u64
}

// Tek yığın (undo ya da redo). Sıra numaraları u64 mutlak sayaçtır; halkaya mod ile yazılır.
struct HistoryStack {
mut:
	cmds      &Command
	blocks    &HistoryBlock
	groups    &HistoryGroup
	cap       u64
	gcap      u64
	cmd_first u64
	cmd_next  u64
	blk_first u64
	blk_next  u64
	grp_first u64
	grp_next  u64
	dropped   u64
	// Açık grup: ilk yazımda başlar, grup kapanınca yığına girer ya da taşarsa geri alınır.
	open_on   bool
	open_over bool
	open_c    u64
	open_b    u64
}

fn HistoryStack.new(mut parent memory.LinearArena, cap u32, gcap u32) ?HistoryStack {
	cmds := parent.alloc_aligned(u64(cap) * u64(sizeof(Command)), 8) or { return none }
	blocks := parent.alloc_aligned(u64(cap) * u64(sizeof(HistoryBlock)), 8) or { return none }
	groups := parent.alloc_aligned(u64(gcap) * u64(sizeof(HistoryGroup)), 8) or { return none }
	return HistoryStack{
		cmds:   unsafe { &Command(cmds) }
		blocks: unsafe { &HistoryBlock(blocks) }
		groups: unsafe { &HistoryGroup(groups) }
		cap:    u64(cap)
		gcap:   u64(gcap)
	}
}

fn (mut s HistoryStack) reset() {
	s.cmd_first = 0
	s.cmd_next = 0
	s.blk_first = 0
	s.blk_next = 0
	s.grp_first = 0
	s.grp_next = 0
	s.open_on = false
	s.open_over = false
}

// En eski tamamlanmış grubu düşürür; kapasite baskısı ya da grup tablosu dolunca çağrılır.
fn (mut s HistoryStack) evict_oldest() {
	g := unsafe { s.groups[s.grp_first % s.gcap] }
	s.cmd_first = g.cend
	s.blk_first = g.bend
	s.grp_first++
	s.dropped++
}

// Bloğu açık grubun sonuna yazar. Sığmıyorsa en eski gruplar düşer; düşecek grup yoksa açık grup taşar.
// Blok halkada sarmaz: sarma noktasında kalan boşluk atlanır, böylece dilim doğrudan halkaya bakabilir.
fn (mut s HistoryStack) write_block(src &Command, n u32) {
	if !s.open_on {
		s.open_on = true
		s.open_c = s.cmd_next
		s.open_b = s.blk_next
	}
	if s.open_over {
		return
	}
	mut start := s.cmd_next
	if start % s.cap + u64(n) > s.cap {
		start += s.cap - start % s.cap
	}
	for start + u64(n) - s.cmd_first > s.cap || s.blk_next - s.blk_first >= s.cap {
		if s.grp_first == s.grp_next {
			s.open_over = true
			return
		}
		s.evict_oldest()
	}
	for i in 0 .. n {
		unsafe {
			s.cmds[(start + u64(i)) % s.cap] = src[i]
		}
	}
	unsafe {
		s.blocks[s.blk_next % s.cap] = HistoryBlock{
			start: start
			n:     n
		}
	}
	s.blk_next++
	s.cmd_next = start + u64(n)
}

// Açık grubu kapatır: boşsa yığına girmez; taşmışsa tamamen geri alınır ve düşürülmüş sayılır.
fn (mut s HistoryStack) close_group() {
	if !s.open_on {
		return
	}
	s.open_on = false
	if s.open_over {
		s.open_over = false
		s.cmd_next = s.open_c
		s.blk_next = s.open_b
		s.dropped++
		return
	}
	if s.blk_next == s.open_b {
		return
	}
	if s.grp_next - s.grp_first == s.gcap {
		s.evict_oldest()
	}
	unsafe {
		s.groups[s.grp_next % s.gcap] = HistoryGroup{
			cstart: s.open_c
			cend:   s.cmd_next
			bstart: s.open_b
			bend:   s.blk_next
		}
	}
	s.grp_next++
}

// En yeni grubu yığından çıkarır; blokları ters sırada gezen görünüm döner.
fn (mut s HistoryStack) pop() ?GroupView {
	if s.grp_next == s.grp_first || s.open_on {
		return none
	}
	s.grp_next--
	g := unsafe { s.groups[s.grp_next % s.gcap] }
	s.cmd_next = g.cstart
	s.blk_next = g.bstart
	return GroupView{
		cmds:   s.cmds
		blocks: s.blocks
		cap:    s.cap
		bstart: g.bstart
		bend:   g.bend
	}
}

fn (mut s HistoryStack) remap(old ecs.EntityID, new ecs.EntityID) {
	for b in s.blk_first .. s.blk_next {
		blk := unsafe { s.blocks[b % s.cap] }
		for k in 0 .. blk.n {
			idx := (blk.start + u64(k)) % s.cap
			mut c := unsafe { s.cmds[idx] }
			if c.entity == old {
				c.entity = new
				unsafe {
					s.cmds[idx] = c
				}
			}
		}
	}
}

// Bir grubun blokları. block(0) en son bloktur; her blok uygulama sırasındaki komutlardır.
pub struct GroupView {
	cmds   &Command
	blocks &HistoryBlock
	cap    u64
	bstart u64
	bend   u64
}

pub fn (g &GroupView) block_count() int {
	return int(g.bend - g.bstart)
}

// Dilim halka belleğine bakar; çağıran değiştirmeden ya da yeni yazımdan önce kopyalar.
pub fn (g &GroupView) block(i int) []Command {
	blk := unsafe { g.blocks[(g.bend - 1 - u64(i)) % g.cap] }
	mut v := []Command{}
	unsafe {
		v = array{
			data:         voidptr(&g.cmds[blk.start % g.cap])
			len:          int(blk.n)
			cap:          int(blk.n)
			element_size: int(sizeof(Command))
		}
	}
	return v
}

// Geçmiş çekirdeği: yakalanan ters komutlar. Hepsi kurulumda ayrılan belleği kullanır; tick yolu tahsis yapmaz.
pub struct History {
mut:
	mode        HistoryMode
	depth       u32
	fresh       bool
	prepared    bool
	prep_kind   CommandKind
	scratch     &Command
	scratch_cap u32
	scratch_n   u32
	stacks      [2]HistoryStack // 0 undo, 1 redo
}

// Bir bloğun en büyük boyu: spawn/despawn ters bloğu, her bileşen için add ve her alan için set.
fn scratch_bound(reg &ecs.Registry) u32 {
	mut n := u32(1)
	for id in u16(0) .. reg.count() {
		schema := reg.component(id) or { break }
		n += 1 + u32(schema.fields.len)
	}
	return n
}

// Her iki yığın için halkalar ve kapsamı kadar hazırlık alanı. Hata olursa parent geri sarılır.
pub fn History.new(mut parent memory.LinearArena, reg &ecs.Registry, capacity u32, max_groups u32) ?History {
	if capacity == 0 || max_groups == 0 {
		return none
	}
	m := parent.mark()
	undo := HistoryStack.new(mut parent, capacity, max_groups) or {
		parent.rewind(m)
		return none
	}
	redo := HistoryStack.new(mut parent, capacity, max_groups) or {
		parent.rewind(m)
		return none
	}
	bound := scratch_bound(reg)
	scratch := parent.alloc_aligned(u64(bound) * u64(sizeof(Command)), 8) or {
		parent.rewind(m)
		return none
	}
	return History{
		scratch:     unsafe { &Command(scratch) }
		scratch_cap: bound
		stacks:      [undo, redo]!
	}
}

// Kurulumda ayrılacak toplam bayt; Config.bytes_needed bunu kullanır. Her tahsis için 64 bayt hizalama payı.
pub fn History.bytes_needed(reg &ecs.Registry, capacity u32, max_groups u32) u64 {
	per_stack := u64(capacity) * u64(sizeof(Command)) + u64(capacity) * u64(sizeof(HistoryBlock)) +
		u64(max_groups) * u64(sizeof(HistoryGroup))
	scratch := u64(scratch_bound(reg)) * u64(sizeof(Command))
	return 2 * per_stack + scratch + 7 * 64
}

// Kullanıcı adımı başlar. Derinlik sayacı: iç içe çağrılar dış grubu bekler.
pub fn (mut h History) begin_group() {
	if h.depth == 0 {
		h.fresh = true
	}
	h.depth++
}

// Dış grup kapanınca açık grup yığına girer (boşsa ya da taşmışsa girmez).
pub fn (mut h History) end_group() {
	if h.depth == 0 {
		return
	}
	h.depth--
	if h.depth == 0 {
		for i in 0 .. h.stacks.len {
			h.stacks[i].close_group()
		}
	}
}

pub fn (mut h History) set_mode(m HistoryMode) {
	h.mode = m
}

fn (mut h History) put(c Command) {
	// Sınır scratch_bound ile kurulumda hesaplanır; aşım bir kurulum hatasıdır.
	assert h.scratch_n < h.scratch_cap
	unsafe {
		h.scratch[h.scratch_n] = c
	}
	h.scratch_n++
}

// Uygulamadan önce çağrılır: komutun ters bloğunu scratch alanına yazar. Script komutları ve
// uygulanamayacak komutlar (yok varlık/bileşen) hazırlanmaz.
pub fn (mut h History) capture_before(w &ecs.World, c Command) {
	h.prepared = false
	if c.source == .script {
		return
	}
	h.scratch_n = 0
	h.prep_kind = c.kind
	match c.kind {
		.spawn {
			// Yeni id commit_capture'da yazılır.
			h.put(Command{
				kind:   .despawn
				source: c.source
				entity: ecs.null_entity
			})
		}
		.despawn {
			if !w.is_alive(c.entity) {
				return
			}
			h.put(Command{
				kind:   .spawn
				source: c.source
				entity: c.entity
			})
			for comp in 0 .. w.store_count() {
				if !w.has(c.entity, comp) {
					continue
				}
				h.put(Command{
					kind:   .add_component
					source: c.source
					comp:   comp
					entity: c.entity
				})
				for f in 0 .. w.store(comp).field_count() {
					v := w.get_field(c.entity, comp, f) or { u64(0) }
					h.put(Command{
						kind:   .set_field
						source: c.source
						comp:   comp
						field:  f
						entity: c.entity
						value:  v
					})
				}
			}
		}
		.add_component {
			h.put(Command{
				kind:   .remove_component
				source: c.source
				comp:   c.comp
				entity: c.entity
			})
		}
		.remove_component {
			if !w.has(c.entity, c.comp) {
				return
			}
			h.put(Command{
				kind:   .add_component
				source: c.source
				comp:   c.comp
				entity: c.entity
			})
			for f in 0 .. w.store(c.comp).field_count() {
				v := w.get_field(c.entity, c.comp, f) or { u64(0) }
				h.put(Command{
					kind:   .set_field
					source: c.source
					comp:   c.comp
					field:  f
					entity: c.entity
					value:  v
				})
			}
		}
		.set_field {
			old := w.get_field(c.entity, c.comp, c.field) or { return }
			h.put(Command{
				kind:   .set_field
				source: c.source
				comp:   c.comp
				field:  c.field
				entity: c.entity
				value:  old
			})
		}
	}
	h.prepared = true
}

// Uygulamadan sonra çağrılır: başarılıysa hazırlanan bloğu aktif yığına ekler. Grup dışında her blok kendi grubudur.
pub fn (mut h History) commit_capture(r ApplyResult) {
	if !h.prepared {
		return
	}
	h.prepared = false
	if r.status != .ok {
		return
	}
	auto := h.depth == 0
	if auto {
		h.begin_group()
	}
	// Spawn'ın ters bloğu yeni id'yi siler; id ancak uygulamadan sonra bilinir.
	if h.prep_kind == .spawn {
		mut c := unsafe { h.scratch[0] }
		c.entity = r.entity
		unsafe {
			h.scratch[0] = c
		}
	}
	// Normal modda yeni grubun ilk bloğu ileri alma yığınını geçersiz kılar.
	if h.mode == .normal && h.fresh {
		h.stacks[1].reset()
		h.fresh = false
	}
	t := if h.mode == .undoing { 1 } else { 0 }
	h.stacks[t].write_block(h.scratch, h.scratch_n)
	if auto {
		h.end_group()
	}
}

// En yeni undo grubunu çıkarır. Dönen görünüm halka belleğine bakar; değiştirmeden önce kopyalanmalıdır.
pub fn (mut h History) pop_undo() ?GroupView {
	return h.stacks[0].pop()
}

pub fn (mut h History) pop_redo() ?GroupView {
	return h.stacks[1].pop()
}

// Her iki yığındaki tüm komutlarda entity alanını old'dan new'e çevirir (spawn ile yeniden doğan varlık).
pub fn (mut h History) remap(old ecs.EntityID, new ecs.EntityID) {
	for i in 0 .. h.stacks.len {
		h.stacks[i].remap(old, new)
	}
}

pub fn (mut h History) clear() {
	h.stacks[0].reset()
	h.stacks[1].reset()
	h.prepared = false
}

pub fn (h &History) undo_len() int {
	return int(h.stacks[0].grp_next - h.stacks[0].grp_first)
}

pub fn (h &History) redo_len() int {
	return int(h.stacks[1].grp_next - h.stacks[1].grp_first)
}

// Kapasite ya da grup tablosu baskısıyla kaybolan ve tek başına sığmayan grupların toplamı.
pub fn (h &History) dropped_groups() u64 {
	return h.stacks[0].dropped + h.stacks[1].dropped
}
