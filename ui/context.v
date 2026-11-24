module ui

const fnv_offset = u32(2166136261)
const fnv_prime = u32(16777619)

// Kalıcı durum: kimlikle anahtarlı; 2 kare görülmeyen girdi end()'de silinir.
struct StateSlot {
mut:
	id         u32
	seen       u32
	rect_frame u32
	rect       Rect
	scroll     f32
	data       [16]u8 // widget'a özel alan
}

// Kare başına tahsis yok: tüm tamponlar new'de ayrılır.
pub struct Context {
mut:
	atl      &Atlas
	inp      Input
	vw       f32
	vh       f32
	scale    f32
	nodes    []Node
	n        int
	stack    []int
	depth    int
	skip     int // kapasite aşımında düşen açık düğümlerin kapanış sayacı
	overflow u32
	frame    u32
	id_stack [32]u32
	id_top   int
	id_over  int
	states   []StateSlot
	scratch  []StateSlot
	list     DrawList
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
	c.list.clear()
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
	c.persist()
	return &c.list
}

pub fn (mut c Context) open(label string, b Box) u32 {
	id := c.id(label)
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
