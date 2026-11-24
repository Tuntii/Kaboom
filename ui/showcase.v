module ui

// Vitrin: tasarım sisteminin görsel kanıtı. Motor bağlantısı yok; veri sabit ve sahte.
// Kare başına tahsis yok: etiketler literal ya da const dizilerdir.

pub enum ShowcasePage {
	editor
	widgets
}

pub struct ShowcaseState {
pub mut:
	selected   int
	left_w     f32
	right_w    f32
	x          f32
	y          f32
	size       f32
	r          f32
	g          f32
	b          f32
	visible    bool
	name       TextBuf
	playing    bool
	check_a    bool
	check_b    bool
	text_empty TextBuf
	text_full  TextBuf
	text_focus TextBuf
	num_demo   f32
	sec_init   bool
}

pub fn ShowcaseState.new() ShowcaseState {
	mut st := ShowcaseState{
		selected: 3
		left_w:   240
		right_w:  300
		x:        12.5
		y:        -4
		size:     2.5
		r:        0.9
		g:        0.4
		b:        0.2
		visible:  true
		check_a:  true
		num_demo: 3.5
	}
	st.name.set('Işık')
	st.text_full.set('Kaydedilmemiş değişiklikler')
	st.text_focus.set('Odakta')
	return st
}

const hier_names = ['#0', '#1', '#2', '#3', '#4', '#5', '#6', '#7', '#8', '#9', '#10', '#11']
const hier_badges = ['T S', 'T B S', 'T S', 'T S', 'T B S', 'T S', 'T S', 'T B S', 'T S', 'T S', 'T B S', 'T S']
const showcase_icons = [Icon.play, .pause, .step, .undo, .redo, .plus, .trash, .save, .folder, .chevron_right,
	.chevron_down, .move, .eye, .warning, .close, .check]
const icon_labels = ['Oynat', 'Duraklat', 'Adım', 'Geri al', 'Yinele', 'Ekle', 'Sil', 'Kaydet', 'Klasör', 'Sağ ok',
	'Aşağı ok', 'Taşı', 'Göz', 'Uyarı', 'Kapat', 'Onay']
const role_names = ['caption', 'label', 'body', 'body_strong', 'title', 'heading', 'mono']
const showcase_roles = [TextRole.caption, .label, .body, .body_strong, .title, .heading, .mono]
const token_names = ['surface_0', 'surface_1', 'surface_2', 'surface_hover', 'border', 'border_strong', 'text_primary',
	'text_secondary', 'text_muted', 'accent', 'danger', 'warning']
const token_colors = [surface_0, surface_1, surface_2, surface_hover, border, border_strong, text_primary,
	text_secondary, text_muted, accent, danger, warning]

// Sahne görünümü için ayrılan orta alanın mantıksal dikdörtgeni; widgets sayfasında sıfır.
// Dikdörtgen bir önceki karenin düzeninden okunur (düzen end()'de hesaplanır).
pub fn showcase(mut c Context, mut st ShowcaseState, page ShowcasePage) Rect {
	if page == .editor {
		showcase_editor(mut c, mut st)
		return c.prev_rect(c.id('scene')) or { Rect{} }
	}
	showcase_widgets(mut c, mut st)
	return Rect{}
}

fn showcase_editor(mut c Context, mut st ShowcaseState) {
	c.toolbar_begin()
	if c.icon_button('Oynat', .play, st.playing) {
		st.playing = true
	}
	c.tooltip('Oynat')
	if c.icon_button('Duraklat', .pause, !st.playing) {
		st.playing = false
	}
	c.icon_button('Adım', .step, false)
	c.icon_button('Geri al', .undo, false)
	c.icon_button('Yinele', .redo, false)
	c.spacer()
	c.text('sahne.vscene •', .body_strong, text_primary)
	c.spacer()
	c.button('Aç', .secondary)
	c.button('Kaydet', .primary)
	c.toolbar_end()

	c.open('body', Box{
		dir:    .row
		width:  grow()
		height: grow()
	})
	c.open('hier', Box{
		dir:    .column
		width:  fixed(st.left_w)
		height: grow()
		bg:     surface_1
	})
	c.open('hier_head', Box{
		dir:         .row
		width:       grow()
		height:      fixed(toolbar_h)
		padding:     pad_xy(space_2, 0)
		gap:         space_1
		align_cross: .center
	})
	c.text('Hiyerarşi', .body_strong, text_primary)
	c.spacer()
	c.icon_button('Ekle', .plus, false)
	c.close()
	for k in 0 .. hier_names.len {
		it := c.list_row_begin(hier_names[k], st.selected == k)
		if it.clicked {
			st.selected = k
		}
		c.text(hier_names[k], .body, text_primary)
		c.spacer()
		c.text(hier_badges[k], .caption, text_muted)
		c.list_row_end()
	}
	c.close()
	c.splitter('split_l', mut &st.left_w, 160, 420, true)

	c.open('scene', Box{
		width:  grow()
		height: grow()
	})
	c.close()

	c.splitter('split_r', mut &st.right_w, 240, 420, false)
	c.open('inspector', Box{
		dir:     .column
		width:   fixed(st.right_w)
		height:  grow()
		padding: pad_all(space_3)
		gap:     space_2
		bg:      surface_1
	})
	c.text(hier_names[st.selected], .title, text_primary)
	if c.section('sec_transform', 'Transform') {
		c.number_field('x', mut &st.x, 'm', 0.1, -100, 100)
		c.number_field('y', mut &st.y, 'm', 0.1, -100, 100)
	}
	if c.section('sec_sprite', 'Sprite') {
		c.number_field('size', mut &st.size, 'm', 0.1, 0.1, 50)
		c.number_field('r', mut &st.r, '', 0.01, 0, 1)
		c.number_field('g', mut &st.g, '', 0.01, 0, 1)
		c.number_field('b', mut &st.b, '', 0.01, 0, 1)
		c.checkbox('visible', mut &st.visible)
	}
	if c.menu_button('add_component', 'Bileşen ekle') {
		c.menu_item('Collider')
		c.menu_item('Body')
		c.menu_item('Etiket')
		c.menu_end()
	}
	fill_v(mut c)
	c.close()
	c.close()

	c.statusbar_begin()
	c.statusbar_text('tick 1204 · 12 varlık · duraklatıldı · 120 fps')
	c.statusbar_end()
}

// Kalan dikey alanı doldurur: sonraki öğeleri alt kenara iter.
fn fill_v(mut c Context) {
	c.open('fill_v', Box{
		width:  grow()
		height: grow()
	})
	c.close()
}

fn showcase_widgets(mut c Context, mut st ShowcaseState) {
	if !st.sec_init {
		st.sec_init = true
		h := c.touch(c.id('w_sec_b'))
		if h >= 0 {
			c.states[h].set_flag(off_collapsed, true)
		}
	}
	// Odak yoksa odaklı örnek alana verilir; böylece odak durumu sayfada görünür.
	if c.focused_id() == 0 {
		c.focus = c.id('w_tf_odak')
	}
	c.open('wpage', Box{
		dir:     .row
		width:   grow()
		height:  grow()
		padding: pad_all(space_4)
		gap:     space_6
	})
	showcase_col1(mut c, mut st)
	showcase_col2(mut c, mut st)
	showcase_col3(mut c)
	c.close()
}

fn showcase_col1(mut c Context, mut st ShowcaseState) {
	c.open('wc1', Box{
		dir:    .column
		width:  grow()
		height: fit()
		gap:    space_3
	})
	c.text('Buton', .title, text_primary)
	c.open('w_btn_row', Box{
		dir:    .row
		width:  fit()
		height: fit()
		gap:    space_2
	})
	c.button('Birincil', .primary)
	c.button('İkincil', .secondary)
	c.button('Hayalet', .ghost)
	c.close()
	c.open('w_btn_dis', Box{
		dir:    .row
		width:  fit()
		height: fit()
		gap:    space_2
	})
	c.push_id(1)
	c.button_ex('Birincil', .primary, false)
	c.button_ex('İkincil', .secondary, false)
	c.button_ex('Hayalet', .ghost, false)
	c.pop_id()
	c.close()
	c.text('İkon düğmesi', .title, text_primary)
	for half in 0 .. 2 {
		c.push_id(half)
		c.open('w_icon_row', Box{
			dir:    .row
			width:  fit()
			height: fit()
			gap:    space_1
		})
		for k in 0 .. 8 {
			i := half * 8 + k
			c.icon_button(icon_labels[i], showcase_icons[i], i == 0)
		}
		c.close()
		c.pop_id()
	}
	c.text('Onay kutusu', .title, text_primary)
	c.checkbox('Açık', mut &st.check_a)
	c.checkbox('Kapalı', mut &st.check_b)
	c.text('Metin alanı', .title, text_primary)
	c.text('Boş', .caption, text_muted)
	c.text_field('w_tf_bos', mut st.text_empty, 220)
	c.text('Dolu', .caption, text_muted)
	c.text_field('w_tf_dolu', mut st.text_full, 220)
	c.text('Odaklı', .caption, text_muted)
	c.text_field('w_tf_odak', mut st.text_focus, 220)
	c.close()
}

fn showcase_col2(mut c Context, mut st ShowcaseState) {
	c.open('wc2', Box{
		dir:    .column
		width:  grow()
		height: fit()
		gap:    space_3
	})
	c.text('Bölüm', .title, text_primary)
	if c.section('w_sec_a', 'Açık bölüm') {
		c.text('Bölüm içeriği görünür.', .body, text_secondary)
	}
	if c.section('w_sec_b', 'Kapalı bölüm') {
		c.text('Bu içerik kapalı başlar.', .body, text_secondary)
	}
	c.text('Liste satırı', .title, text_primary)
	c.list_row('w_row_n', 'Normal satır', false)
	c.list_row('w_row_s', 'Seçili satır', true)
	c.separator()
	c.text('Sayı alanı', .title, text_primary)
	c.number_field('Değer', mut &st.num_demo, '', 0.1, 0, 10)
	c.text('Açılır menü', .title, text_primary)
	if c.menu_button('w_menu', 'Menü') {
		c.menu_item('Birinci')
		c.menu_item('İkinci')
		c.menu_end()
	}
	c.close()
}

fn showcase_col3(mut c Context) {
	c.open('wc3', Box{
		dir:    .column
		width:  grow()
		height: fit()
		gap:    space_3
	})
	c.text('Tipografi', .title, text_primary)
	for i, role in showcase_roles {
		c.text(role_names[i], .caption, text_muted)
		c.text('Kaydedilmemiş değişiklikler — Işık, Ğ, Ş, İ', role, text_primary)
	}
	c.text("Renk token'ları", .title, text_primary)
	for r in 0 .. 3 {
		c.push_id(r)
		c.open('sw_row', Box{
			dir:    .row
			width:  fit()
			height: fit()
			gap:    space_3
		})
		for k in 0 .. 4 {
			i := r * 4 + k
			c.open(token_names[i], Box{
				dir:    .column
				width:  fixed(96)
				height: fit()
				gap:    space_1
			})
			c.leaf(.plain, Box{
				width:    fixed(96)
				height:   fixed(28)
				bg:       token_colors[i]
				border:   border_strong
				border_w: 1
				radius:   radius_control
			})
			c.text(token_names[i], .caption, text_secondary)
			c.close()
		}
		c.close()
		c.pop_id()
	}
	c.close()
}
