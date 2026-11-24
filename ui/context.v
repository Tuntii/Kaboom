module ui

// Kimlik sözleşmesi: etiket = kimlik. Aynı ebeveyn altında aynı etiket aynı durumu (kaydırma, açık/kapalı,
// etkileşim) paylaşır. Tekrarlanan öğeler (liste satırı, inspector'da varlık başına) push_id(n) ile
// ayrılır, ör. inspector'da push_id(int(entity_index)); pop_id ile kapanır. Kimlik çakışması sessizdir.

import math

const fnv_offset = u32(2166136261)
const fnv_prime = u32(16777619)

// Kalıcı durum alanı (data) ofsetleri: hover geçişi (f32 değer, bayrak hedef, f64 başlangıç zamanı), bölüm açık/kapalı.
const off_base = 0
const off_target = 4
const off_collapsed = 5
const off_start = 8
const off_open = 5 // menü açık (menü kimliği bölümle çakışmaz)
// Sayı alanı (hover kullanmaz): sürükleme başlangıç değeri f32, sürükleniyor ve Esc ile iptal bayrakları.
const off_num_v0 = 0
const off_num_drag = 4
const off_num_cancel = 5
// Bölüm: varsayılan durumu uygulandı mı (ilk karede default_open'dan kurulur).
const off_sec_init = 6
// Menü tetikleyicisi: vurgulu öğe dizini (255 = yok) ve son karedeki öğe sayısı (klavye gezintisi).
const off_menu_hl = 6
const off_menu_n = 7
const menu_none = u8(255)

// Kalıcı durum: kimlikle anahtarlı; 2 kare görülmeyen girdi end()'de silinir.
struct StateSlot {
mut:
	id         u32
	seen       u32
	rect_frame u32
	rect       Rect
	scroll     f32
	tip_on     bool // ipucu: imleç bu kimlikteyken
	tip_since  f64  // ipucu: üzerinde durma başlangıcı
	data       [16]u8 // widget'a özel alan
}

// Hizalama yok: değer bayt kopyasıyla okunur/yazılır.
fn (s &StateSlot) f32_at(off int) f32 {
	mut v := f32(0)
	unsafe {
		vmemcpy(voidptr(&v), voidptr(&s.data[off]), 4)
	}
	return v
}

fn (mut s StateSlot) set_f32(off int, v f32) {
	unsafe {
		vmemcpy(voidptr(&s.data[off]), voidptr(&v), 4)
	}
}

fn (s &StateSlot) f64_at(off int) f64 {
	mut v := f64(0)
	unsafe {
		vmemcpy(voidptr(&v), voidptr(&s.data[off]), 8)
	}
	return v
}

fn (mut s StateSlot) set_f64(off int, v f64) {
	unsafe {
		vmemcpy(voidptr(&s.data[off]), voidptr(&v), 8)
	}
}

fn (s &StateSlot) flag(off int) bool {
	return s.data[off] != 0
}

fn (mut s StateSlot) set_flag(off int, v bool) {
	s.data[off] = if v { u8(1) } else { u8(0) }
}

pub enum CursorHint {
	arrow
	text
	resize_h
	hand
}

// Bir kimlikle etkileşim sonucu. Tıklama: basış ve bırakma aynı kimlik üzerinde.
pub struct Interaction {
pub:
	hovered  bool
	pressed  bool
	clicked  bool
	dragging bool
	drag_dx  f32
	drag_dy  f32
	focused  bool
}

// Kare başına tahsis yok: tüm tamponlar new'de ayrılır.
pub struct Context {
mut:
	atl          &Atlas
	inp          Input
	vw           f32
	vh           f32
	scale        f32
	nodes        []Node
	n            int
	stack        []int
	depth        int
	skip         int // kapasite aşımında düşen açık düğümlerin kapanış sayacı
	overflow     u32
	frame        u32
	id_stack     [32]u32
	id_top       int
	id_over      int
	states       []StateSlot
	scratch      []StateSlot
	list         DrawList
	hit_cur      u32 // bu karede imleç altındaki en üstteki kimlik (çizim sırası)
	hit_prev     u32 // bir önceki karenin sonucu
	active       u32 // sol tuşla basılmış kimlik
	focus        u32
	focus_cur    []u32 // bu karenin odaklanabilir kimlikleri, çizim sırasıyla (max_focus kapasiteli)
	focus_n      int
	focus_prev   []u32 // önceki kare; end() ikisini takas eder (kopya ve tahsis yok)
	focus_prev_n int
	max_focus    int
	state_ovf    u32 // durum tablosu ya da odak listesi dolu iken yapılan istek sayısı (sessiz düşme yok)
	visited      u32 // bu karede çizim geçişinin ziyaret ettiği (görünür) düğüm sayısı
	vl_bottom    f32 // sanal liste: alt boşluk yüksekliği (virtual_list_end kullanır)
	menu_idx     int  // açık menüde işlenen öğe sayısı (bu karede)
	kb_menu      bool // açık menü bu karede klavyeyi sahiplenir (önceki karenin durumu; menü tuşları diğer widget'lara gitmez)
	kb_menu_next bool // bu karede bir menü açıksa bir sonraki kare için kb_menu
	drag_dx      f32
	drag_dy      f32
	cursor       CursorHint
	last_id      u32 // en son açılan kutunun kimliği (ipucu hedefi)
	txt_id       u32 // odaktaki metin alanı (en fazla bir tane)
	txt_snap     TextBuf // metin alanı: odak anındaki metin (Esc geri alır)
	txt_cur      int
	num_id       u32 // düzenlenen sayı alanı; metin alanı odağı bunu silmez
	num_buf      TextBuf // sayı alanı düzenleme metni
	num_cur      int
	num_fresh    bool // sayı alanı: ilk yazım metni değiştirir (yazım gelene kadar kalır)
	num_moved    bool // bu basışta sürükleme oldu mu (tıklama düzenlemeye geçmez)
	focus_visible bool // odak klavyeyle (Tab) geldi: halka çizilir, Enter/Space etkinleştirir
	press_x      f32 // sol tuş basış konumu (sürükleme eşiği için)
	press_y      f32
	drag_on      bool // etkin basış eşiği aştı: sürükleme sürüyor
	num_bufs     [64][32]u8 // sayı alanı görüntü metinleri; kare başına döner
	num_n        int
	menu_cur     u32 // son menu_button kimliği (menu_item kapatır)
	menu_alpha   f32 // açık menünün opaklığı
	tip_shown    bool
	in_prop      bool // özellik satırı içinde: sayı alanı panelin kalanını doldurur
}

pub fn Context.new(atlas &Atlas, max_nodes u32, max_cmds u32) !Context {
	if max_nodes == 0 {
		return error('ui: max_nodes sıfır olamaz')
	}
	n := int(max_nodes)
	// Odak listesi düğüm sayısının dörtte biri kadar (en az 64); taşma state_overflow'a sayılır.
	max_focus := if n / 4 > 64 { n / 4 } else { 64 }
	return Context{
		// shortcut: atlas Context ömrü boyunca canlı kalmalı (çağıran sahibi), @[heap] yerine unsafe
		atl:        unsafe { atlas }
		nodes:      []Node{len: n}
		stack:      []int{len: n + 1}
		states:     []StateSlot{len: n * 2}
		scratch:    []StateSlot{len: n * 2}
		list:       DrawList.new(max_cmds)
		max_focus:  max_focus
		focus_cur:  []u32{len: max_focus}
		focus_prev: []u32{len: max_focus}
	}
}

// Durum tablosu ya da odak listesi dolu iken biriken istek sayısı (tablo büyüklüğü yetersizliğinin tanısı).
pub fn (c &Context) state_overflow() u32 {
	return c.state_ovf
}

// Son çizim geçişinde ziyaret edilen (görünür) düğüm sayısı; kırpma ayrıntısı için tanı.
pub fn (c &Context) paint_visits() u32 {
	return c.visited
}

// Mantıksal pencere boyutu; kök düğüm bu boyuttadır.
pub fn (mut c Context) begin(input Input, width f32, height f32, scale f32) {
	// Ölçek atlas ölçeğinden farklıysa glifler yanlış boyda çizilir; çağıran hatası, sessizce geçilmez.
	assert math.abs(scale - c.atl.scale()) <= 0.001, 'ui: begin ölçeği atlas ölçeğiyle eşleşmiyor'
	c.drag_dx = input.mouse_x - c.inp.mouse_x
	c.drag_dy = input.mouse_y - c.inp.mouse_y
	c.inp = input
	c.vw = width
	c.vh = height
	c.scale = scale
	c.frame++
	c.n = 0
	c.depth = 0
	c.skip = 0
	c.overflow = 0
	c.visited = 0
	c.menu_idx = 0
	c.kb_menu = c.kb_menu_next
	c.kb_menu_next = false
	c.id_top = 0
	c.id_over = 0
	c.hit_cur = 0
	c.focus_n = 0
	c.cursor = .arrow
	c.num_n = 0
	c.tip_shown = false
	c.list.clear()
	c.in_prop = false
	c.tab_focus()
	// Her basış odağı bırakır; metin ve sayı alanları kendi basışlarında yeniden alır.
	if input.pressed[0] {
		c.focus = 0
		c.focus_visible = false
	}
	root := c.alloc(0, Box{
		dir:    .column
		width:  fixed(width)
		height: fixed(height)
	}, -1)
	c.nodes[root].is_root = true
	c.push(root)
}

pub fn (mut c Context) end() &DrawList {
	c.drop_stale()
	c.layout()
	c.paint(0, Rect{
		w: c.vw
		h: c.vh
	})
	for i in 1 .. c.n {
		if c.nodes[i].is_root {
			c.paint(i, Rect{
				w: c.vw
				h: c.vh
			})
		}
	}
	c.hit_prev = c.hit_cur
	c.focus_prev, c.focus_cur = c.focus_cur, c.focus_prev
	c.focus_prev_n = c.focus_n
	if c.inp.released[0] {
		c.active = 0
	}
	c.persist()
	return &c.list
}

pub fn (mut c Context) open(label string, b Box) u32 {
	id := c.id(label)
	c.last_id = id
	if c.skip > 0 {
		c.skip++
		c.overflow++
		return id
	}
	i := c.alloc(id, b, c.top())
	if i < 0 {
		c.skip = 1
		c.overflow++
		return id
	}
	c.nodes[i].slot = c.touch(id)
	// Tekerlek: imleç kutunun son konumundaysa ofset değişir; kıskaç düzende (place) yapılır.
	if b.scroll_y && c.inp.wheel_y != 0 && c.nodes[i].slot >= 0 && c.hovered_prev(id) {
		c.states[c.nodes[i].slot].scroll -= c.inp.wheel_y * 3 * row_h
	}
	c.push(i)
	return id
}

pub fn (mut c Context) close() {
	if c.skip > 0 {
		c.skip--
		return
	}
	if c.depth > 1 {
		c.depth--
	}
}

pub fn (mut c Context) text(s string, role TextRole, color Color) {
	i := c.leaf(.text, Box{
		width:  fit()
		height: fit()
	})
	if i < 0 {
		return
	}
	c.nodes[i].text = s
	c.nodes[i].role = role
	c.nodes[i].color = color
	c.nodes[i].content[0] = c.atl.measure(s, role)
	c.nodes[i].content[1] = c.atl.line_height(role)
}

pub fn (mut c Context) icon(i Icon, color Color) {
	idx := c.leaf(.icon, Box{
		width:  fixed(icon_size)
		height: fixed(icon_size)
	})
	if idx < 0 {
		return
	}
	c.nodes[idx].icon = i
	c.nodes[idx].color = color
}

pub fn (mut c Context) spacer() {
	c.leaf(.plain, Box{
		width:  grow()
		height: fit()
	})
}

// Ağaçtan bağımsız kök; ağaç çizildikten sonra çizilir. close() ile kapanır.
pub fn (mut c Context) overlay(label string, x f32, y f32, b Box) u32 {
	id := c.id(label)
	if c.skip > 0 {
		c.skip++
		c.overflow++
		return id
	}
	i := c.alloc(id, b, -1)
	if i < 0 {
		c.skip = 1
		c.overflow++
		return id
	}
	c.nodes[i].is_root = true
	c.nodes[i].pos[0] = x
	c.nodes[i].pos[1] = y
	c.nodes[i].slot = c.touch(id)
	c.push(i)
	return id
}

pub fn (c &Context) id(label string) u32 {
	h := fnv_bytes(c.base_id(), label)
	return if h == 0 { u32(1) } else { h }
}

pub fn (mut c Context) push_id(n int) {
	mut h := c.base_id()
	for k in 0 .. 4 {
		h = (h ^ u32((n >> (k * 8)) & 0xFF)) * fnv_prime
	}
	if c.id_top < c.id_stack.len {
		c.id_stack[c.id_top] = h
		c.id_top++
	} else {
		c.id_over++
	}
}

pub fn (mut c Context) pop_id() {
	if c.id_over > 0 {
		c.id_over--
		return
	}
	if c.id_top > 0 {
		c.id_top--
	}
}

// Bir önceki karenin mantıksal dikdörtgeni; yalnızca hemen önceki kare için geçerli.
pub fn (c &Context) prev_rect(id u32) ?Rect {
	h := c.probe(id)
	if h < 0 || c.states[h].id != id {
		return none
	}
	s := c.states[h]
	if s.rect_frame == 0 || s.rect_frame + 1 != c.frame {
		return none
	}
	return s.rect
}

pub fn (c &Context) input() &Input {
	return &c.inp
}

pub fn (c &Context) atlas() &Atlas {
	return c.atl
}

pub fn (c &Context) node_overflow() u32 {
	return c.overflow
}

// Son tamamlanan düzendeki dikdörtgen; kare denetimi yok (vitrin betiği kareler arası konum bulur).
pub fn (c &Context) last_rect(label string) ?Rect {
	return c.last_rect_id(c.id(label))
}

// Kimlikle son karenin dikdörtgeni (kimlik push_id yığınına bağlıysa etikete bakılamaz); tahsissiz.
pub fn (c &Context) last_rect_id(id u32) ?Rect {
	h := c.probe(id)
	if h < 0 || c.states[h].id != id || c.states[h].rect_frame == 0 {
		return none
	}
	return c.states[h].rect
}

// Bu karenin düğüm sayısı (ölçüm ve tanı için).
pub fn (c &Context) node_count() u32 {
	return u32(c.n)
}

// Etkileşim: hover, basış, tıklama (basış ve bırakma aynı kimlikte), sürükleme.
// Kimlik odaklanabilirse çizim sırasına eklenir (Tab için). Fare basışı yalnızca metin ve sayı alanlarına odak verir.
pub fn (mut c Context) interact(id u32, focusable bool) Interaction {
	return c.interact_kb(id, focusable, true, false)
}

// key_click false: odaktaki Enter/Space tıklama üretmez (metin ve sayı alanları kendi tuşlarını işler).
// mouse_focus: basış bu kimliğe odak verir (metin ve sayı alanları).
fn (mut c Context) interact_kb(id u32, focusable bool, key_click bool, mouse_focus bool) Interaction {
	c.touch(id)
	if focusable {
		if c.focus_n < c.focus_cur.len {
			c.focus_cur[c.focus_n] = id
			c.focus_n++
		} else {
			c.state_ovf++
		}
	}
	hovered := c.hit_prev == id && c.hovered_prev(id)
	if c.inp.pressed[0] && hovered {
		c.active = id
		c.press_x = c.inp.mouse_x
		c.press_y = c.inp.mouse_y
		c.drag_on = false
		if mouse_focus {
			c.focus = id
		}
	}
	mut clicked := false
	mut dragging := false
	mut dx := c.drag_dx
	mut dy := c.drag_dy
	if c.active == id {
		if c.inp.released[0] {
			clicked = hovered
			c.active = 0
			c.drag_on = false
		} else if c.inp.down[0] && !c.inp.pressed[0] {
			// Eşik: basıştan kümülatif hareket; eşiği geçen karede tam ofset, sonra kare farkı.
			if !c.drag_on {
				ox := c.inp.mouse_x - c.press_x
				oy := c.inp.mouse_y - c.press_y
				if math.abs(ox) >= drag_threshold || math.abs(oy) >= drag_threshold {
					c.drag_on = true
					dx = ox
					dy = oy
				}
			}
			dragging = c.drag_on
		}
	}
	// Odaktayken (yalnızca klavyeyle gelmişse) Enter/Space etkinleştirir (klavye erişilebilirliği).
	if key_click && focusable && c.focus == id && c.focus_visible && (c.key_pressed(.enter) || c.key_pressed(.space)) {
		clicked = true
	}
	return Interaction{
		hovered:  hovered
		pressed:  c.active == id && c.inp.down[0]
		clicked:  clicked
		dragging: dragging
		drag_dx:  if dragging { dx } else { f32(0) }
		drag_dy:  if dragging { dy } else { f32(0) }
		focused:  c.focus == id
	}
}

pub fn (c &Context) focused_id() u32 {
	return c.focus
}

pub fn (mut c Context) set_cursor_hint(h CursorHint) {
	c.cursor = h
}

pub fn (c &Context) cursor_hint() CursorHint {
	return c.cursor
}

// Kimlik başına 0..1 hover değeri; hedef değişince motion_ms içinde ease-out ile yürür.
pub fn (mut c Context) hover_t(id u32, hovered bool) f32 {
	h := c.touch(id)
	if h < 0 {
		return if hovered { f32(1) } else { f32(0) }
	}
	now := c.inp.time_ms
	mut s := &c.states[h]
	cur := motion_value(s.f32_at(off_base), s.flag(off_target), s.f64_at(off_start), now)
	if hovered != s.flag(off_target) {
		s.set_f32(off_base, cur)
		s.set_flag(off_target, hovered)
		s.set_f64(off_start, now)
	}
	return cur
}

fn motion_value(base f32, target bool, start f64, now f64) f32 {
	mut p := (now - start) / f64(motion_ms)
	if p < 0 {
		p = 0
	}
	if p > 1 {
		p = 1
	}
	e := f32(1 - (1 - p) * (1 - p))
	return if target { base + (1 - base) * e } else { base * (1 - e) }
}

// Bölüm açık/kapalı durumu; açıksa true. Tıklama durumu çevirir. İlk karede default_open'dan kurulur.
fn (mut c Context) section_open(id u32, clicked bool, default_open bool) bool {
	h := c.touch(id)
	if h < 0 {
		return true
	}
	if !c.states[h].flag(off_sec_init) {
		c.states[h].set_flag(off_sec_init, true)
		c.states[h].set_flag(off_collapsed, !default_open)
	}
	if clicked {
		c.states[h].set_flag(off_collapsed, !c.states[h].flag(off_collapsed))
	}
	return !c.states[h].flag(off_collapsed)
}

fn fnv_bytes(seed u32, s string) u32 {
	mut h := seed
	for i in 0 .. s.len {
		h = (h ^ u32(s[i])) * fnv_prime
	}
	return h
}

fn (c &Context) base_id() u32 {
	return if c.id_top > 0 { c.id_stack[c.id_top - 1] } else { fnv_offset }
}

fn (c &Context) top() int {
	return if c.depth > 0 { c.stack[c.depth - 1] } else { -1 }
}

fn (mut c Context) push(i int) {
	c.stack[c.depth] = i
	c.depth++
}

fn (mut c Context) alloc(id u32, b Box, parent int) int {
	if c.n >= c.nodes.len {
		return -1
	}
	i := c.n
	c.n++
	c.nodes[i] = Node{
		id:     id
		box:    b
		parent: parent
		first:  -1
		last:   -1
		next:   -1
		slot:   -1
	}
	if parent >= 0 {
		last := c.nodes[parent].last
		if last >= 0 {
			c.nodes[last].next = i
		} else {
			c.nodes[parent].first = i
		}
		c.nodes[parent].last = i
	}
	return i
}

fn (mut c Context) leaf(kind NodeKind, b Box) int {
	if c.skip > 0 {
		c.overflow++
		return -1
	}
	i := c.alloc(0, b, c.top())
	if i < 0 {
		c.overflow++
		return -1
	}
	c.nodes[i].kind = kind
	return i
}

// Açık adresleme: id'nin yuvası ya da ilk boş yuva; tablo doluysa -1.
fn (c &Context) probe(id u32) int {
	cap := c.states.len
	mut h := int(id % u32(cap))
	for _ in 0 .. cap {
		if c.states[h].id == id || c.states[h].id == 0 {
			return h
		}
		h = (h + 1) % cap
	}
	return -1
}

fn (mut c Context) touch(id u32) int {
	h := c.probe(id)
	if h < 0 {
		// Dolu tablo: çağıran durumsuz davranır (sürükleme olayları atlanır); sayaç bunu görünür kılar.
		c.state_ovf++
		return -1
	}
	if c.states[h].id == 0 {
		c.states[h].id = id
	}
	c.states[h].seen = c.frame
	return h
}

// Bu karede k tuşu basıldı mı. Açık menü (kb_menu) Tab/Enter/Space/Esc/Ok tuşlarını sahiplenir: diğer widget'lar bunları görmez.
fn (c &Context) key_pressed(k Key) bool {
	if c.kb_menu && (k == .enter || k == .space || k == .escape || k == .up || k == .down || k == .tab) {
		return false
	}
	return c.raw_key(k)
}

// Menünün kendi tuşları ve sahiplik dışı sorgular: Input.keys kenar olayları (otomatik tekrar sayılmaz).
fn (c &Context) raw_key(k Key) bool {
	for i in 0 .. c.inp.key_count {
		if c.inp.keys[i] == k && !c.inp.key_repeat[i] {
			return true
		}
	}
	return false
}

// Bu karede kimlik çizildi mi (touch ile işaretlenir). Çizilmeyen kimliğin odağı ve düzenlemesi atılır.
fn (c &Context) seen_now(id u32) bool {
	h := c.probe(id)
	return h >= 0 && c.states[h].id == id && c.states[h].seen == c.frame
}

// Çizilmeyen alanın bekleyen düzenlemesi atılır (değer uygulanmaz); eski kimlik sonraki alana karışmaz.
fn (mut c Context) drop_stale() {
	if c.focus != 0 && !c.seen_now(c.focus) {
		c.focus = 0
		c.focus_visible = false
	}
	if c.num_id != 0 && !c.seen_now(c.num_id) {
		c.num_id = 0
	}
	if c.txt_id != 0 && !c.seen_now(c.txt_id) {
		c.txt_id = 0
	}
}

// Metin ya da sayı alanı düzenleniyorken true: editör kısayolları bu karede atlanmalı.
// Alanlar kendi karesinde çizilirken güncellenir; çağıran kareyi alan çizimlerinden sonra sorgulamalı.
pub fn (c &Context) keyboard_captured() bool {
	return c.txt_id != 0 || c.num_id != 0
}

// Odağı etikete verir (kare içinde, alan çizilmeden önce): editör yol alanı açılınca yazı hemen girilir.
pub fn (mut c Context) focus_label(label string) {
	c.focus = c.id(label)
}

// Açık menü (önceki karenin durumu) klavyeyi sahiplenir: menü açıkken kısayollar çalışmaz.
pub fn (c &Context) menu_open() bool {
	return c.kb_menu
}

// Düzenleme ve sürükleme durumunu bırakır; değer yazılmaz. Çağıran, widget'ların eski kimliklerini yeni dünyaya
// taşımamak için dünya değiştiğinde çağırır (sayı alanı sürüklemesi ve düzenlemesi, metin alanı, odak).
pub fn (mut c Context) abandon_edit() {
	c.active = 0
	c.drag_on = false
	c.num_id = 0
	c.txt_id = 0
	c.focus = 0
	c.focus_visible = false
}

// Kısayol: k bu karede basıldı, klavye bir alanda değil ve açık menü klavyeyi sahiplenmiyor.
// Çağıran kısayolu alanları çizdikten sonra sorgulamalı.
pub fn (c &Context) shortcut(k Key) bool {
	return !c.keyboard_captured() && !c.kb_menu && c.key_pressed(k)
}

// Önceki karenin dikdörtgeni imleci içeriyor mu.
fn (c &Context) hovered_prev(id u32) bool {
	r := c.prev_rect(id) or { return false }
	return r.contains(c.inp.mouse_x, c.inp.mouse_y)
}

// Tab: odaklanabilir kimlikler arasında ileri, Shift+Tab geri (önceki karenin listesi).
fn (mut c Context) tab_focus() {
	n := c.focus_prev_n
	if !c.key_pressed(.tab) || n == 0 {
		return
	}
	mut cur := -1
	for i in 0 .. n {
		if c.focus_prev[i] == c.focus {
			cur = i
		}
	}
	next := if c.inp.shift {
		if cur <= 0 { n - 1 } else { cur - 1 }
	} else {
		(cur + 1) % n
	}
	c.focus = c.focus_prev[next]
	c.focus_visible = true
}

// Görülen düğümlerin dikdörtgenleri yazılır; sonra iki kare görülmeyenler atılır.
fn (mut c Context) persist() {
	for i in 0 .. c.n {
		nd := c.nodes[i]
		if nd.id == 0 || nd.slot < 0 {
			continue
		}
		c.states[nd.slot].rect = Rect{
			x: nd.pos[0]
			y: nd.pos[1]
			w: nd.sz[0]
			h: nd.sz[1]
		}
		c.states[nd.slot].rect_frame = c.frame
	}
	c.compact()
}

fn (mut c Context) compact() {
	mut k := 0
	for j in 0 .. c.states.len {
		if c.states[j].id != 0 && c.frame - c.states[j].seen < 2 {
			c.scratch[k] = c.states[j]
			k++
		}
	}
	for j in 0 .. c.states.len {
		c.states[j] = StateSlot{}
	}
	for j in 0 .. k {
		h := c.probe(c.scratch[j].id)
		c.states[h] = c.scratch[j]
	}
}
