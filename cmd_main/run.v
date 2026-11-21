module main

import os
import time
import image
import platform
import protocol
import render
import sim

#include "@VMODROOT/cmd_main/run_ctx.h"

fn C.vcore_run_set(p voidptr)
fn C.vcore_run_get() voidptr

// Girdi: vcore run [--capacity N] [--width W] [--height H] [--hidden] [--paused].
struct RunOpts {
mut:
	capacity u32 = 100_000
	width    int = 1280
	height   int = 720
	hidden   bool
	paused   bool
}

// Pencere ve çizim durumu. Ekran görüntüsü kancası bu yapıya C static işaretçisi üzerinden erişir.
struct RunCtx {
mut:
	win   &platform.Window
	rend  &render.Renderer
	srv   &protocol.Server
	qf    render.QuadFields
	alpha f32
}

fn parse_run_opts(args []string) RunOpts {
	mut o := RunOpts{}
	mut i := 0
	for i < args.len {
		if args[i] == '--hidden' {
			o.hidden = true
			i++
			continue
		}
		if args[i] == '--paused' {
			o.paused = true
			i++
			continue
		}
		if i + 1 >= args.len {
			usage()
		}
		n := args[i + 1].parse_int(10, 32) or { usage() }
		if n <= 0 {
			usage()
		}
		match args[i] {
			'--capacity' { o.capacity = u32(n) }
			'--width' { o.width = int(n) }
			'--height' { o.height = int(n) }
			else { usage() }
		}
		i += 2
	}
	return o
}

// Pencere veya GL kurulamadıysa tek satırlık hata ve çıkış kodu 3.
@[noreturn]
fn gl_fail(err IError) {
	eprintln('GL yok: ${err}')
	exit(3)
}

// stdin'i okuyan thread: satırları kanala yazar, EOF'ta kanalı kapatır. GL'ye dokunmaz.
fn read_stdin(ch chan string) {
	for {
		line := os.get_raw_line()
		if line.len == 0 {
			break
		}
		ch <- line
	}
	ch.close()
}

// Ekran görüntüsü: mevcut kareyi yeniden çizer, okur ve PNG olarak yazar. Tick dışında çalışır.
fn capture_frame(path string) !(int, int) {
	mut c := unsafe { &RunCtx(C.vcore_run_get()) }
	w, h := c.win.size()
	if w <= 0 || h <= 0 {
		return error('pencere boyutu sifir')
	}
	mut out := c.rend.payload()
	// Ekran görüntüsü mevcut tick'i gösterir: alfa 1.0 (entity.get ile aynı konum).
	n, _ := render.prepare(c.srv.world(), c.qf, 1.0, mut out)
	c.rend.draw(render.Camera{}, w, h, n)
	render.finish()
	mut px := []u8{len: w * h * 4}
	defer {
		unsafe { px.free() }
	}
	render.read_pixels(0, 0, w, h, render.gl_rgba, render.gl_unsigned_byte, px.data)
	image.write_png(path, w, h, px, true)!
	return w, h
}

// Pencereli döngü: stdin ayrı thread'de okunur, GL ana thread'de çalışır.
fn run_window(args []string) {
	o := parse_run_opts(args)
	mut srv := protocol.Server.new(sim.Config{ capacity: o.capacity }) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	defer {
		srv.close()
	}
	mut win := platform.Window.new(platform.WindowConfig{
		width:   o.width
		height:  o.height
		visible: !o.hidden
	}) or { gl_fail(err) }
	defer {
		win.close()
	}
	render.load_gl() or { gl_fail(err) }
	qf := render.resolve_quad_fields(srv.registry()) or { gl_fail(err) }
	mut rend := render.Renderer.new(o.capacity) or { gl_fail(err) }
	defer {
		rend.close()
	}
	mut ctx := RunCtx{
		win:   &win
		rend:  &rend
		srv:   &srv
		qf:    qf
		alpha: 1.0
	}
	C.vcore_run_set(voidptr(&ctx))
	srv.set_capture(capture_frame)
	if o.paused {
		// Bildirim (id yok) yanıt üretmez; duraklatma protokolün kendi yolundan geçer.
		_ = srv.handle('{"jsonrpc":"2.0","method":"sim.pause"}')
	}

	ch := chan string{cap: 1024}
	spawn read_stdin(ch)

	mut last := platform.now_ns()
	mut acc := u64(0)
	mut eof := false
	for {
		// Kanalı bekletmeden boşalt; her yanıt hemen yazılır.
		for {
			mut line := ''
			st := ch.try_pop(mut line)
			if st == .closed {
				eof = true
				break
			}
			if st != .success {
				break
			}
			if resp := srv.handle(line) {
				println(resp)
				flush_stdout()
			}
		}
		if !win.poll() {
			break
		}
		now := platform.now_ns()
		acc += now - last
		last = now
		steps, rem := sim.steps_for(acc, sim.step_ns, 8)
		srv.advance(steps)
		acc = rem
		// Duraklatılmış kare mevcut tick'i gösterir.
		ctx.alpha = if srv.paused() { f32(1.0) } else { f32(rem) / f32(sim.step_ns) }
		mut out := rend.payload()
		n, _ := render.prepare(srv.world(), qf, ctx.alpha, mut out)
		ww, wh := win.size()
		rend.draw(render.Camera{}, ww, wh, n)
		win.swap()
		if o.hidden && eof {
			break
		}
		// Takas (swap) sürücü senkronu olmadan bloklamaz; kısa uyku olmazsa döngü tek çekirdeği yakar.
		time.sleep(time.millisecond)
	}
}
