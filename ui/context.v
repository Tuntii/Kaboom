module ui

const fnv_offset = u32(2166136261)
const fnv_prime = u32(16777619)

// Kalıcı durum alanı (data) ofsetleri: hover geçişi (f32 değer, bayrak hedef, f64 başlangıç zamanı), bölüm açık/kapalı.
const off_base = 0
const off_target = 4
const off_collapsed = 5
const off_start = 8
const off_open = 5 // menü açık (menü kimliği bölümle çakışmaz)

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
	focus_cur    [64]u32 // bu karenin odaklanabilir kimlikleri, çizim sırasıyla
	focus_n      int
	focus_prev   [64]u32
	focus_prev_n int
	drag_dx      f32
	drag_dy      f32
	cursor       CursorHint
	last_id      u32 // en son açılan kutunun kimliği (ipucu hedefi)
	edit_id      u32 // düzenlenen metin/sayı alanı; odakla birlikte değişir
	edit_buf     TextBuf // sayı alanı düzenleme metni
	edit_snap    TextBuf // metin alanı: odak anındaki metin (Esc geri alır)
	edit_cur     int
	edit_fresh   bool // sayı alanı: ilk yazım metni değiştirir
	num_moved    bool // bu basışta sürükleme oldu mu (tıklama düzenlemeye geçmez)
	num_bufs     [64][32]u8 // sayı alanı görüntü metinleri; kare başına döner
	num_n        int
	menu_cur     u32 // son menu_button kimliği (menu_item kapatır)
	menu_alpha   f32 // açık menünün opaklığı
	tip_shown    bool
}

pub fn Context.new(atlas &Atlas, max_nodes u32, max_cmds u32) !Context {
	if max_nodes == 0 {
		return error('ui: max_nodes sıfır olamaz')
	}
	n := int(max_nodes)
	return Context{
		// shortcut: atlas Context ömrü boyunca canlı kalmalı (çağıran sahibi), @[heap] yerine unsafe
		atl:     unsafe { atlas }
		nodes:   []Node{len: n}
		stack:   []int{len: n + 1}
		states:  []StateSlot{len: n * 2}
		scratch: []StateSlot{len: n * 2}
		list:    DrawList.new(max_cmds)
	}
}

// Mantıksal pencere boyutu; kök düğüm bu boyuttadır.
pub fn (mut c Context) begin(input Input, width f32, height f32, scale f32) {
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
	c.id_top = 0
	c.id_over = 0
	c.hit_cur = 0
	c.focus_n = 0
	c.cursor = .arrow
	c.num_n = 0
	c.tip_shown = false
	c.list.clear()
	c.tab_focus()
	if input.pressed[0] && c.hit_prev == 0 {
		c.focus = 0
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
	c.focus_prev = c.focus_cur
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

// Etkileşim: hover, basış, tıklama (basış ve bırakma aynı kimlikte), sürükleme.
// Kimlik odaklanabilirse çizim sırasına eklenir (Tab için).
pub fn (mut c Context) interact(id u32, focusable bool) Interaction {
	return c.interact_kb(id, focusable, true)
}

// key_click false: odaktaki Enter/Space tıklama üretmez (metin ve sayı alanları kendi tuşlarını işler).
fn (mut c Context) interact_kb(id u32, focusable bool, key_click bool) Interaction {
	c.touch(id)
	if focusable && c.focus_n < c.focus_cur.len {
		c.focus_cur[c.focus_n] = id
		c.focus_n++
	}
	hovered := c.hit_prev == id && c.hovered_prev(id)
	if c.inp.pressed[0] && hovered {
		c.active = id
		if focusable {
			c.focus = id
		}
	}
	mut clicked := false
	mut dragging := false
	if c.active == id {
		if c.inp.released[0] {
			clicked = hovered
			c.active = 0
		} else if c.inp.down[0] && !c.inp.pressed[0] && (c.drag_dx != 0 || c.drag_dy != 0) {
			dragging = true
		}
	}
	// Odaktayken Enter/Space etkinleştirir (klavye erişilebilirliği).
	if key_click && focusable && c.focus == id && (c.key_pressed(.enter) || c.key_pressed(.space)) {
		clicked = true
	}
	return Interaction{
		hovered:  hovered
		pressed:  c.active == id && c.inp.down[0]
		clicked:  clicked
		dragging: dragging
		drag_dx:  if dragging { c.drag_dx } else { f32(0) }
		drag_dy:  if dragging { c.drag_dy } else { f32(0) }
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

// Bölüm açık/kapalı durumu; açıksa true. Tıklama durumu çevirir.
fn (mut c Context) section_open(id u32, clicked bool) bool {
	h := c.touch(id)
	if h < 0 {
		return true
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
		return -1
	}
	if c.states[h].id == 0 {
		c.states[h].id = id
	}
	c.states[h].seen = c.frame
	return h
}

// Bu karede k tuşu basıldı mı (Input.keys kenar olayları).
fn (c &Context) key_pressed(k Key) bool {
	for i in 0 .. c.inp.key_count {
		if c.inp.keys[i] == k {
			return true
		}
	}
	return false
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
