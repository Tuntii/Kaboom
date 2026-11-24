module main

import image
import math
import platform
import render
import time
import ui

// Vitrin penceresi: `vcore gallery`. Sahne görünümü quad Renderer ile, arayüz UiRenderer ile çizilir.
const gallery_nodes = u32(2048)
const gallery_cmds = u32(8192)
const gallery_quads = u32(12)
const gallery_view_h = f32(160)
// Senaryoda her karede sanal saat 600 ms ilerler: ipucu gecikmesi (500 ms) ve menü geçişi (100 ms) bir karede tamamlanır.
const gallery_tip_step_ms = f64(600)
const gallery_script_frames = 5

struct GalleryOpts {
mut:
	page          ui.ShowcasePage = .editor
	width         int             = 1280
	height        int             = 720
	scale         f32
	hidden        bool
	frames        int = 3
	screenshot    string
	open_menu     bool
	hover_tooltip bool
}

fn parse_gallery_opts(args []string) GalleryOpts {
	mut o := GalleryOpts{}
	mut i := 0
	for i < args.len {
		if args[i] == '--hidden' {
			o.hidden = true
			i++
			continue
		}
		if args[i] == '--open-menu' {
			o.open_menu = true
			i++
			continue
		}
		if args[i] == '--hover-tooltip' {
			o.hover_tooltip = true
			i++
			continue
		}
		if i + 1 >= args.len {
			usage()
		}
		v := args[i + 1]
		match args[i] {
			'--page' {
				o.page = match v {
					'editor' { ui.ShowcasePage.editor }
					'widgets' { ui.ShowcasePage.widgets }
					else { usage() }
				}
			}
			'--width' { o.width = parse_positive(v) }
			'--height' { o.height = parse_positive(v) }
			'--frames' { o.frames = parse_positive(v) }
			'--scale' {
				s := v.f32()
				if s <= 0 {
					usage()
				}
				o.scale = s
			}
			'--screenshot' { o.screenshot = v }
			else { usage() }
		}
		i += 2
	}
	return o
}

fn parse_positive(s string) int {
	n := s.parse_int(10, 32) or { usage() }
	if n <= 0 {
		usage()
	}
	return int(n)
}

// Sahne görünümü için sabit 12 quad (sahte veri). Renk R, G, B bayt sırasında rgba'ya yazılır.
fn fill_scene_quads(mut out []render.InstancePayload) {
	colors := [u32(0xE5484DFF), 0x3D6FD6FF, 0x30A46CFF, 0xF5A524FF]
	for k in 0 .. int(gallery_quads) {
		c := colors[k % colors.len]
		// R G B A bellekte; rgba sayısı little-endian: R düşük bayt.
		r := (c >> 24) & 0xFF
		g := (c >> 16) & 0xFF
		b := (c >> 8) & 0xFF
		out[k] = render.InstancePayload{
			x:    f32(k % 4) * 40 - 60
			y:    f32(k / 4) * 40 - 40
			size: f32(14 + (k % 3) * 4)
			rgba: r | (g << 8) | (b << 16) | u32(0xFF) << 24
		}
	}
}

fn cursor_for(h ui.CursorHint) platform.Cursor {
	return match h {
		.arrow { platform.Cursor.arrow }
		.text { platform.Cursor.text }
		.resize_h { platform.Cursor.resize_h }
		.hand { platform.Cursor.hand }
	}
}

// Mantıksal dikdörtgeni fiziksel piksel sınırlarına yuvarlar; kenarlar ayrı yuvarlanır.
fn to_physical(r ui.Rect, scale f32) (int, int, int, int) {
	x0 := int(math.round(r.x * scale))
	y0 := int(math.round(r.y * scale))
	x1 := int(math.round((r.x + r.w) * scale))
	y1 := int(math.round((r.y + r.h) * scale))
	return x0, y0, x1 - x0, y1 - y0
}

// Vitrin senaryosu: --open-menu ve --hover-tooltip, önceki karenin düzeninden hedef konumu bulur.
// Kare 0 yalnızca düzen kurar; imleç hedefe 1. karede gelir, böylece 2. karede basış/ipucu hazırdır.
fn script_mouse(ctx &ui.Context, mut inp ui.Input, o GalleryOpts, frame int) {
	target := if o.open_menu { 'add_component' } else { 'Oynat' }
	if frame == 0 {
		inp.mouse_x = -1
		inp.mouse_y = -1
		return
	}
	if r := ctx.last_rect(target) {
		inp.mouse_x = r.x + r.w / 2
		inp.mouse_y = r.y + r.h / 2
	}
	if o.open_menu && frame == 2 {
		inp.pressed[0] = true
		inp.down[0] = true
	}
	if o.open_menu && frame == 3 {
		inp.released[0] = true
	}
}

fn run_gallery(args []string) {
	o := parse_gallery_opts(args)
	mut win := platform.Window.new(platform.WindowConfig{
		title:     'vcore gallery'
		width:     o.width
		height:    o.height
		visible:   !o.hidden
		dpi_aware: true
	}) or { gl_fail(err) }
	defer {
		win.close()
	}
	render.load_gl() or { gl_fail(err) }
	scale := if o.scale > 0 { o.scale } else { win.dpi_scale() }
	atlas := ui.Atlas.build(scale) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	mut ctx := ui.Context.new(&atlas, gallery_nodes, gallery_cmds) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	mut ur := render.UiRenderer.new(gallery_cmds) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	defer {
		ur.close()
	}
	ur.upload_atlas(atlas.width(), atlas.height(), atlas.pixels())
	mut rend := render.Renderer.new(gallery_quads) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	defer {
		rend.close()
	}
	mut quads := rend.payload()
	fill_scene_quads(mut quads)
	mut st := ui.ShowcaseState.new()
	scripted := o.open_menu || o.hover_tooltip
	frames := if scripted && o.frames < gallery_script_frames { gallery_script_frames } else { o.frames }
	n := if o.page == .editor { gallery_quads } else { u32(0) }

	mut frame := 0
	mut tip_ms := f64(0)
	for {
		if !win.poll() {
			break
		}
		fw, fh := win.size()
		if fw <= 0 || fh <= 0 {
			time.sleep(time.millisecond)
			continue
		}
		if scripted && frame >= 1 {
			tip_ms += gallery_tip_step_ms
		}
		now := f64(platform.now_ns()) / 1e6 + tip_ms
		mut inp := to_ui_input(win.input(), scale, now)
		// Senaryo ve gizli pencere gerçek imlece bağlı kalmaz.
		if scripted {
			script_mouse(&ctx, mut inp, o, frame)
		} else if o.hidden {
			inp.mouse_x = -1
			inp.mouse_y = -1
		}
		ctx.begin(inp, f32(fw) / scale, f32(fh) / scale, scale)
		scene := ui.showcase(mut ctx, mut st, o.page)
		list := ctx.end()

		render.viewport(0, 0, fw, fh)
		c := u32(ui.surface_0)
		render.clear_color(f32((c >> 24) & 0xFF) / 255, f32((c >> 16) & 0xFF) / 255, f32((c >> 8) & 0xFF) / 255, 1.0)
		render.clear(render.gl_color_buffer_bit)
		if scene.w > 0 && scene.h > 0 {
			x, y, w, h := to_physical(scene, scale)
			rend.draw_viewport(render.Camera{ view_h: gallery_view_h }, x, y, w, h, fh, n)
		}
		ur.draw(list, fw, fh)
		win.set_cursor(cursor_for(ctx.cursor_hint()))

		if o.screenshot != '' && frame + 1 >= frames {
			render.finish()
			mut px := []u8{len: fw * fh * 4}
			defer {
				unsafe { px.free() }
			}
			render.read_pixels(0, 0, fw, fh, render.gl_rgba, render.gl_unsigned_byte, px.data)
			image.write_png(o.screenshot, fw, fh, px, true) or {
				eprintln('vcore: ${err}')
				exit(1)
			}
			return
		}
		win.swap()
		frame++
		time.sleep(time.millisecond)
	}
}
