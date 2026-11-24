module cmd

import ecs
import memory

// Geçmiş modu: normal işlem undo yığınını besler; undo/redo kendi ters işlemlerini karşı yığına yazar.
pub enum HistoryMode {
	normal
	undoing
	redoing
	off // yakalama kapalı: iptal edilen grubun ters blokları geçmişe girmez
}

// Bir komutun ters bloğu. Halkada start mutlak komut sırasıdır; hazırlama alanında göreli ofsettir.
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

// Tek yığın (undo ya da redo). Yalnızca tamamlanmış gruplar burada durur; açık grup History'nin hazırlama alanında.
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

// Sayaçları sıfırlar; düşürme sayısı (tanılama) korunur.
fn (mut s HistoryStack) reset() {
	s.cmd_first = 0
	s.cmd_next = 0
	s.blk_first = 0
	s.blk_next = 0
	s.grp_first = 0
	s.grp_next = 0
}

// En eski tamamlanmış grubu düşürür; kapasite baskısı ya da grup tablosu dolunca çağrılır.
fn (mut s HistoryStack) evict_oldest() {
	g := unsafe { s.groups[s.grp_first % s.gcap] }
	s.cmd_first = g.cend
	s.blk_first = g.bend
	s.grp_first++
	s.dropped++
}

// Tamamlanmış grubu yığına yerleştirir. Hazırlama alanındaki n komut ve nb blok tek bir bitişik
// parça olarak yazılır: sarma gerekiyorsa boşluk atlanır, böylece dilim doğrudan halkaya bakar.
// Sığmak için en eski gruplar düşer; grup tek başına kapasiteye sığar (çağıran garanti eder).
fn (mut s HistoryStack) push_group(src &Command, n u32, sblk &HistoryBlock, nb u32) {
	if s.grp_next - s.grp_first == s.gcap {
		s.evict_oldest()
	}
	mut gs := s.cmd_next
	if gs % s.cap + u64(n) > s.cap {
		gs += s.cap - gs % s.cap
	}
	for gs + u64(n) - s.cmd_first > s.cap || s.blk_next - s.blk_first + u64(nb) > s.cap {
		if s.grp_first == s.grp_next {
			// Tamamlanmış grup kalmadı: önceki boşluk veri değildir, yalnız bu grup sayılır.
			s.cmd_first = gs
			s.blk_first = s.blk_next
			break
		}
		s.evict_oldest()
	}
	for k in 0 .. nb {
		b := unsafe { sblk[k] }
		for i in 0 .. b.n {
			unsafe {
				s.cmds[(gs + b.start + u64(i)) % s.cap] = src[b.start + u64(i)]
			}
		}
		unsafe {
			s.blocks[(s.blk_next + u64(k)) % s.cap] = HistoryBlock{
				start: gs + b.start
				n:     b.n
			}
		}
	}
	unsafe {
		s.groups[s.grp_next % s.gcap] = HistoryGroup{
			cstart: gs
			cend:   gs + u64(n)
			bstart: s.blk_next
			bend:   s.blk_next + u64(nb)
		}
	}
	s.grp_next++
	s.blk_next += u64(nb)
	s.cmd_next = gs + u64(n)
}

// En yeni grubu yığından çıkarır; blokları ters sırada gezen görünüm döner.
fn (mut s HistoryStack) pop() ?GroupView {
	if s.grp_next == s.grp_first {
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

// Açık bir grubun yakalanmış blokları: komutlar ve blok aralıkları, grup 0'dan başlar.
struct Stage {
mut:
	cmds &Command
	blks &HistoryBlock
	cap  u32
	n    u32
	b    u32
	over bool
	t    int // hedef yığın (0 undo, 1 redo); -1 açık grup yok
}

fn Stage.new(mut parent memory.LinearArena, cap u32) ?Stage {
	cmds := parent.alloc_aligned(u64(cap) * u64(sizeof(Command)), 8) or { return none }
	blks := parent.alloc_aligned(u64(cap) * u64(sizeof(HistoryBlock)), 8) or { return none }
	return Stage{
		cmds: unsafe { &Command(cmds) }
		blks: unsafe { &HistoryBlock(blks) }
		cap:  cap
		t:    -1
	}
}

fn (mut s Stage) reset() {
	s.n = 0
	s.b = 0
	s.over = false
	s.t = -1
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
	// Açık grup yığınlara girmeden hazırlama alanlarında birikir: sığmayan grup hiçbir eski grubu düşürmez.
	// stg[0] editör grubu ve düz (istek ya da otomatik) gruplar; stg[1] editör grubu açıkken gelen ajan isteği.
	stg         [2]Stage
	cur         int  // yakalamanın yazıldığı hazırlama alanı (0 ya da 1)
	iso         bool // ajan isteği kendi grubunda (stg[1]) açık
	// Yürütücünün ters bloğu: blok spawn ile başlıyorsa yalnız bu spawn'ın ters işlemi (despawn) yakalanır.
	in_block    bool
	block_head  bool
	block_skip  bool // blok başı yakalandıktan sonra geri kalan komutlar (kısmen) yakalanmaz
	block_add   bool // blok başı add_component ise yalnız aynı (varlık, bileşen) set'leri atlanır
	block_ent   ecs.EntityID
	block_comp  u16
	head_pending bool // son yakalanan komut bloğun ilk komutu; başarılıysa atlama kurulur
	head_kind    CommandKind
	head_ent     ecs.EntityID
	head_comp    u16
	stage_base  u32 // açık bloğun ters komutlarının etkin hazırlama alanındaki başlangıcı
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

// Her iki yığın, hazırlama alanı ve scratch için bellek. Hata olursa parent geri sarılır.
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
	stage0 := Stage.new(mut parent, capacity) or {
		parent.rewind(m)
		return none
	}
	stage1 := Stage.new(mut parent, capacity) or {
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
		stg:         [stage0, stage1]!
	}
}

// Kurulumda ayrılacak toplam bayt; Config.bytes_needed bunu kullanır. Her tahsis için 64 bayt hizalama payı.
pub fn History.bytes_needed(reg &ecs.Registry, capacity u32, max_groups u32) u64 {
	per_stack := u64(capacity) * u64(sizeof(Command)) + u64(capacity) * u64(sizeof(HistoryBlock)) +
		u64(max_groups) * u64(sizeof(HistoryGroup))
	stage := u64(capacity) * u64(sizeof(Command)) + u64(capacity) * u64(sizeof(HistoryBlock))
	scratch := u64(scratch_bound(reg)) * u64(sizeof(Command))
	return 2 * per_stack + 2 * stage + scratch + 11 * 64
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
		h.close_stage(0)
	}
}

// İstek grubu. Editör grubu açıkken (depth > 0) ajan isteği (isolate) kendi hazırlama alanında kurulur:
// editör grubuna karışmaz, bitince yığına kendi grubu olarak girer. Diğer durumlarda begin_group ile aynıdır.
pub fn (mut h History) begin_request(isolate bool) {
	if !isolate || h.depth == 0 {
		h.begin_group()
		return
	}
	h.iso = true
	h.cur = 1
	h.fresh = true
}

// begin_request ile açılanı kapatır: izole istek kendi grubunu yığına iter, diğeri end_group'tur.
pub fn (mut h History) end_request() {
	if h.iso {
		h.iso = false
		h.close_stage(1)
		h.cur = 0
		return
	}
	h.end_group()
}

// Hazırlama alanının grubunu hedef yığına yerleştirir. Taşmışsa hiçbir yığına dokunmadan düşürülmüş sayılır.
fn (mut h History) close_stage(i int) {
	t := h.stg[i].t
	if t == -1 {
		return
	}
	if h.stg[i].over {
		h.stacks[t].dropped++
	} else if h.stg[i].b > 0 {
		h.stacks[t].push_group(h.stg[i].cmds, h.stg[i].n, h.stg[i].blks, h.stg[i].b)
	}
	h.stg[i].reset()
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

// Bileşenin her alanı için eski değerli set yazar. Bir okuma başarısızsa false döner: sıfır değerli
// (yanlış) ters işlem yazılmaz, çağıran yakalamayı iptal eder.
fn (mut h History) put_fields(w &ecs.World, e ecs.EntityID, comp u16, source Source) bool {
	for f in 0 .. w.store(comp).field_count() {
		v := w.get_field(e, comp, f) or { return false }
		h.put(Command{
			kind:   .set_field
			source: source
			comp:   comp
			field:  f
			entity: e
			value:  v
		})
	}
	return true
}

// Uygulamadan önce çağrılır: komutun ters bloğunu scratch alanına yazar. Script komutları ve
// uygulanamayacak komutlar (yok varlık/bileşen, okunamayan alan) hazırlanmaz.
pub fn (mut h History) capture_before(w &ecs.World, c Command) {
	h.prepared = false
	// Blok spawn ile başlıyorsa yalnız o spawn yakalanır (ters: despawn); bloğun geri kalanı onun içindedir.
	first := h.in_block && h.block_head
	h.block_head = false
	h.head_pending = first
	if first {
		h.head_kind = c.kind
		h.head_ent = c.entity
		h.head_comp = c.comp
	}
	// Tek varlık kuralı: bir blok en fazla bir varlığın spawn/add'iyle başlar; atlama ona göre yapılır.
	if h.block_skip && (!h.block_add || (c.kind == .set_field && c.entity == h.block_ent && c.comp == h.block_comp)) {
		return
	}
	if h.mode == .off || c.source == .script {
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
				if !h.put_fields(w, c.entity, comp, c.source) {
					return
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
			if !h.put_fields(w, c.entity, c.comp, c.source) {
				return
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

// Yürütücü bir ters bloğu uygulamadan önce çağırır: blok komutları tek parça geçmişe girsin diye.
// Blok bir grup içinde çağrılmalı (yoksa yakalanan ters sessizce düşer); iç içe blok dış bloğu bozar.
pub fn (mut h History) begin_block() {
	// Yakalama kapalıyken (iptal) grup gerekmez: hiçbir şey yazılmaz.
	assert h.depth > 0 || h.mode == .off, 'begin_block grup dışında'
	assert !h.in_block, 'begin_block iç içe'
	h.in_block = true
	h.block_head = true
	h.block_skip = false
	h.stage_base = h.stg[h.cur].n
}

// Bloğun tüm ters komutları tek bir staged blok olur: geri alma/yineleme adımı blok sayısından bağımsız kalır.
pub fn (mut h History) end_block() {
	if h.in_block && h.stg[h.cur].t != -1 && !h.stg[h.cur].over && h.stg[h.cur].n > h.stage_base {
		if h.stg[h.cur].b >= h.stg[h.cur].cap {
			h.stg[h.cur].over = true
		} else {
			unsafe {
				h.stg[h.cur].blks[h.stg[h.cur].b] = HistoryBlock{
					start: u64(h.stage_base)
					n:     h.stg[h.cur].n - h.stage_base
				}
			}
			h.stg[h.cur].b++
		}
	}
	h.in_block = false
	h.block_head = false
	h.block_skip = false
}

// Blok içinde ters komutu mevcut blokların önüne ekler: sonradan yakalananlar önce uygulanır (ters sıra).
fn (mut h History) prepend_inverse(t int, src &Command, n u32) {
	if h.stg[h.cur].t == -1 {
		h.stg[h.cur].t = t
	}
	if h.stg[h.cur].over {
		return
	}
	if h.stg[h.cur].n + n > h.stg[h.cur].cap {
		h.stg[h.cur].over = true
		return
	}
	mut i := h.stg[h.cur].n
	for i > h.stage_base {
		i--
		unsafe {
			h.stg[h.cur].cmds[i + n] = h.stg[h.cur].cmds[i]
		}
	}
	for k in 0 .. n {
		unsafe {
			h.stg[h.cur].cmds[h.stage_base + k] = src[k]
		}
	}
	h.stg[h.cur].n += n
}

// Hazırlama alanına blok ekler. Hedef yığın grubun ilk bloğunda sabitlenir; sonraki bloklar aynı yığına gider.
fn (mut h History) stage_block(t int, src &Command, n u32) {
	if h.stg[h.cur].t == -1 {
		h.stg[h.cur].t = t
	}
	if h.stg[h.cur].over {
		return
	}
	if h.stg[h.cur].n + n > h.stg[h.cur].cap || h.stg[h.cur].b >= h.stg[h.cur].cap {
		h.stg[h.cur].over = true
		return
	}
	for i in 0 .. n {
		unsafe {
			h.stg[h.cur].cmds[h.stg[h.cur].n + i] = src[i]
		}
	}
	unsafe {
		h.stg[h.cur].blks[h.stg[h.cur].b] = HistoryBlock{
			start: u64(h.stg[h.cur].n)
			n:     n
		}
	}
	h.stg[h.cur].b++
	h.stg[h.cur].n += n
}

// Uygulamadan sonra çağrılır: başarılıysa hazırlanan bloğu açık gruba ekler. Grup dışında her blok kendi grubudur.
pub fn (mut h History) commit_capture(r ApplyResult) {
	head := h.head_pending
	h.head_pending = false
	if !h.prepared {
		return
	}
	h.prepared = false
	if r.status != .ok {
		return
	}
	// Atlama yalnız blok başı başarıyla uygulandıysa kurulur: başarısız başın tersi yoktur, set'ler yakalanmalı.
	if head {
		h.block_skip = h.head_kind == .spawn || h.head_kind == .add_component
		h.block_add = h.head_kind == .add_component
		h.block_ent = h.head_ent
		h.block_comp = h.head_comp
	}
	auto := h.depth == 0 && !h.iso
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
	if h.in_block {
		h.prepend_inverse(t, h.scratch, h.scratch_n)
	} else {
		h.stage_block(t, h.scratch, h.scratch_n)
	}
	if auto {
		h.end_group()
	}
}

// En yeni undo grubunu çıkarır. Dönen görünüm halka belleğine bakar; değiştirmeden önce kopyalanmalıdır.
pub fn (mut h History) pop_undo() ?GroupView {
	if h.stg[0].t != -1 {
		return none
	}
	return h.stacks[0].pop()
}

pub fn (mut h History) pop_redo() ?GroupView {
	if h.stg[0].t != -1 {
		return none
	}
	return h.stacks[1].pop()
}

// Her iki yığındaki tüm komutlarda entity alanını old'dan new'e çevirir (spawn ile yeniden doğan varlık).
pub fn (mut h History) remap(old ecs.EntityID, new ecs.EntityID) {
	for i in 0 .. h.stacks.len {
		h.stacks[i].remap(old, new)
	}
}

// Açık grubun yakalanmış blokları (ters sırada: block(0) en son blok). Yığın okunmaz, hazırlama alanı okunur.
// Editör grubunun (stg[0]) blokları; ajan isteği grubu (stg[1]) burada görünmez.
pub fn (h &History) staged() GroupView {
	return GroupView{
		cmds:   h.stg[0].cmds
		blocks: h.stg[0].blks
		cap:    u64(h.stg[0].cap)
		bstart: 0
		bend:   u64(h.stg[0].b)
	}
}

// Açık grup kapasiteyi aştıysa blokların bir kısmı yakalanmamıştır; staged eksik kalır.
pub fn (h &History) stage_overflowed() bool {
	return h.stg[0].over
}

// Açık grubu hiçbir yığına koymadan atar ve derinliği sıfırlar. Çağıran önce staged ile blokları okumalıdır.
pub fn (mut h History) abandon_group() {
	h.depth = 0
	h.stg[0].reset()
}

// Her iki hazırlama alanı ve yığınlar temizlenir; izole istek durumuna dokunulmaz (açıksa kendi end'i kapatır).
pub fn (mut h History) clear() {
	h.stacks[0].reset()
	h.stacks[1].reset()
	h.prepared = false
	h.stg[0].reset()
	h.stg[1].reset()
}

pub fn (h &History) undo_len() int {
	return int(h.stacks[0].grp_next - h.stacks[0].grp_first)
}

pub fn (h &History) redo_len() int {
	return int(h.stacks[1].grp_next - h.stacks[1].grp_first)
}

// Halka baskısı ya da tek başına sığmayan grup yüzünden kaybolan grupların toplamı.
pub fn (h &History) dropped_groups() u64 {
	return h.stacks[0].dropped + h.stacks[1].dropped
}
