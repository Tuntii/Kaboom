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

// Editör penceresi: `vcore editor [scene] [--width W --height H --scale S --hidden --frames N --screenshot PATH [--screenshot-after-eof]]`.
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
	// Ekran görüntüsünü stdin EOF'u ve boşalmış ajan kanalını bekleyerek al (istekli ajan testleri için).
	screenshot_after_eof bool
	// Senaryo bayrakları (editor_script.v): UI'ye sentetik girdi; editörün iç durumuna dokunmaz.
	select      int = -1 // N. satırdaki varlığı seç (sahnede tıklanır)
	open_menu   bool     // Bileşen ekle menüsünü aç
	dirty_strip bool     // kirlet ve Aç: kaydedilmemiş değişiklik şeridi
	bad_value   bool     // Sprite.r alanına aralık dışı değer yaz (hata satırı)
}

// Senaryo bayrakları için: negatif olmayan tamsayı; yoksa kullanım hatası.
fn parse_nonneg(s string) int {
	n := s.parse_int(10, 32) or { usage() }
	if n < 0 {
		usage()
	}
	return int(n)
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
		if args[i] == '--screenshot-after-eof' {
			o.screenshot_after_eof = true
			i++
			continue
		}
		if args[i] == '--open-menu' || args[i] == '--dirty-strip' || args[i] == '--bad-value' {
			match args[i] {
				'--open-menu' { o.open_menu = true }
				'--dirty-strip' { o.dirty_strip = true }
				else { o.bad_value = true }
			}
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
			'--select' { o.select = parse_nonneg(v) }
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
	if editor_opts_invalid(o) {
		usage()
	}
	return o
}

// Bayrak birleşimi geçersiz mi: --screenshot-after-eof, ekran görüntüsü yolu olmadan sessiz no-op olurdu.
fn editor_opts_invalid(o EditorOpts) bool {
	return o.screenshot_after_eof && o.screenshot == ''
}

fn run_editor(args []string) {
	platform.begin_timer_period()
	defer {
		platform.end_timer_period()
	}
	mut o := parse_editor_opts(args)
	mut script := editor_script_from(o)
	if script.active() && script.frames_needed() > o.frames {
		o.frames = script.frames_needed()
	}
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
	mut restored := false // küçültülmüş pencere: her kapatma isteğinde en fazla bir geri yükleme
	mut prev := editor.EditorFrame{} // önceki karenin düzeni (senaryo hedefleri için)
	for {
		if drain_agent(ch, mut srv) {
			eof = true
		}
		if !win.poll() {
			// WM_QUIT her zaman çıkar; WM_CLOSE pencereyi kapatmaz: istek editöre gider (kirliyse şerit).
			if win.quit_requested() {
				break
			}
			win.clear_close()
			ed.request_close()
			restored = false
		}
		fw, fh := win.size()
		if fw <= 0 || fh <= 0 {
			// Küçültülmüşken kare çizilmez: kapanış burada işlenir; şerit gerekiyorsa pencere geri yüklenir.
			ed.poll_close(mut srv)
			if ed.should_close() {
				break
			}
			if !restored && ed.confirm_pending() && win.minimized() {
				win.restore()
				restored = true
			}
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

		// Senaryo bitince (ya da hiç yoksa) gerçek pencere girdisi geri gelir.
		inp := if script.running() {
			script.input(&ctx, &ed, &srv, prev, f64(now) / 1e6)
		} else {
			to_ui_input(win.input(), scale, f64(now) / 1e6)
		}
		ctx.begin(inp, f32(fw) / scale, f32(fh) / scale, scale)
		fr := ed.frame(mut ctx, mut srv)
		prev = fr
		list := ctx.end()
		mut out := rend.payload()
		n, _ := render.prepare(srv.world(), qf, alpha, mut out)
		cam := render.Camera{
			cx:     fr.cam_cx
			cy:     fr.cam_cy
			view_h: fr.cam_view_h
		}

		// Ekran görüntüsü kare sayısında alınır (stdin'den bağımsız). --screenshot-after-eof ile önce stdin EOF'u
		// ve boşalmış kanal beklenir: o noktada tüm istekler işlenmiş ve yanıtları yazılmıştır.
		if o.screenshot != '' && frame + 1 >= o.frames && !script.running() && (eof || !o.screenshot_after_eof) {
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
		if ed.should_close() {
			break
		}
		// Ekran görüntüsü bekliyorsa stdin EOF'u çıkış nedeni değildir: kare sayısı dolunca yakalanır.
		if o.hidden && eof && o.screenshot == '' {
			break
		}
		time.sleep(time.millisecond)
	}
}
