module main

import editor
import math
import image
import platform
import protocol
import render
import sim
import time
import ui

// Editör penceresi: `vcore editor [scene] [--width W --height H --scale S --hidden --frames N --screenshot PATH]`.
// Mantık editor/ modülünde; burada yalnız pencere, GL çizimi ve stdin kanalı var.
const editor_nodes = u32(4096)
const editor_cmds = u32(16384)

struct EditorOpts {
mut:
	scene      string
	width      int = 1280
	height     int = 720
	scale      f32
	hidden     bool
	frames     int = 3
	screenshot string
}

fn parse_editor_opts(args []string) EditorOpts {
	mut o := EditorOpts{}
	mut i := 0
	for i < args.len {
		if args[i] == '--hidden' {
			o.hidden = true
			i++
			continue
		}
		if !args[i].starts_with('--') {
			if o.scene != '' {
				usage()
			}
			o.scene = args[i]
			i++
			continue
		}
		if i + 1 >= args.len {
			usage()
		}
		v := args[i + 1]
		match args[i] {
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

fn run_editor(args []string) {
	platform.begin_timer_period()
	defer {
		platform.end_timer_period()
	}
	o := parse_editor_opts(args)
	phys_w := if o.scale > 0 { int(math.round(f64(o.width) * f64(o.scale))) } else { o.width }
	phys_h := if o.scale > 0 { int(math.round(f64(o.height) * f64(o.scale))) } else { o.height }
	cfg := sim.Config{}
	mut srv := protocol.Server.new(cfg) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	defer {
		srv.close()
	}
	mut win := platform.Window.new(platform.WindowConfig{
		title:     'vcore editor'
		width:     phys_w
		height:    phys_h
		visible:   !o.hidden
		dpi_aware: o.scale == 0
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
	mut ctx := ui.Context.new(&atlas, editor_nodes, editor_cmds) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	mut ur := render.UiRenderer.new(editor_cmds) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	defer {
		ur.close()
	}
	ur.upload_atlas(atlas.width(), atlas.height(), atlas.pixels())
	qf := render.resolve_quad_fields(srv.registry()) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	mut rend := render.Renderer.new(cfg.capacity) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	defer {
		rend.close()
	}
	mut ed := editor.Editor.new(o.scene)
	mut fbo := render.Fbo{}
	defer {
		fbo.close()
	}

	ch := chan string{cap: 1024}
	spawn read_stdin(ch)

	mut last := platform.now_ns()
	mut acc := u64(0)
	mut eof := false
	mut frame := 0
	for {
		if drain_agent(ch, mut srv) {
			eof = true
		}
		if !win.poll() {
			break
		}
		fw, fh := win.size()
		if fw <= 0 || fh <= 0 {
			time.sleep(time.millisecond)
			continue
		}
		now := platform.now_ns()
		acc += now - last
		last = now
		steps, rem := sim.steps_for(acc, sim.step_ns, 8)
		srv.advance(steps)
		acc = rem
		alpha := if srv.paused() { f32(1.0) } else { f32(rem) / f32(sim.step_ns) }

		inp := to_ui_input(win.input(), scale, f64(now) / 1e6)
		ctx.begin(inp, f32(fw) / scale, f32(fh) / scale, scale)
		fr := ed.frame(mut ctx, mut srv)
		list := ctx.end()
		mut out := rend.payload()
		n, _ := render.prepare(srv.world(), qf, alpha, mut out)
		cam := render.Camera{
			cx:     fr.cam_cx
			cy:     fr.cam_cy
			view_h: fr.cam_view_h
		}

		if o.screenshot != '' && frame + 1 >= o.frames {
			// Ekran görüntüsü aynı kareyi FBO'ya çizer (gallery ile aynı yol); pencere hemen kapanır.
			fbo.resize(fw, fh) or {
				eprintln('vcore: ${err}')
				exit(1)
			}
			fbo.bind()
			draw_frame(mut rend, mut ur, fr.scene, cam, list, fw, fh, scale, n)
			render.finish()
			mut px := []u8{len: fw * fh * 4}
			defer {
				unsafe { px.free() }
			}
			render.read_pixels(0, 0, fw, fh, render.gl_rgba, render.gl_unsigned_byte, px.data)
			render.unbind_fbo()
			render.make_opaque(mut px)
			image.write_png(o.screenshot, fw, fh, px, true) or {
				eprintln('vcore: ${err}')
				exit(1)
			}
			return
		}
		draw_frame(mut rend, mut ur, fr.scene, cam, list, fw, fh, scale, n)
		win.set_cursor(cursor_for(fr.cursor))
		win.swap()
		frame++
		// Ekran görüntüsü bekliyorsa stdin EOF'u çıkış nedeni değildir: kare sayısı dolunca yakalanır.
		if o.hidden && eof && o.screenshot == '' {
			break
		}
		time.sleep(time.millisecond)
	}
}
