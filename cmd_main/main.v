module main

import os
import protocol
import sim

const usage_text = 'kullanim: vcore headless [--capacity N]
       vcore run [--capacity N] [--width W] [--height H] [--hidden] [--paused]'

// Girdi: vcore headless | vcore run. headless stdin'den satır okur, her yanıtı tek satır yazar.
@[console]
fn main() {
	args := os.args[1..]
	if args.len == 0 {
		usage()
	}
	match args[0] {
		'headless' { run_headless(args[1..]) }
		'run' { run_window(args[1..]) }
		else { usage() }
	}
}

fn run_headless(args []string) {
	mut capacity := u32(100_000)
	mut i := 0
	for i < args.len {
		if args[i] == '--capacity' && i + 1 < args.len {
			n := args[i + 1].parse_uint(10, 32) or { usage() }
			if n == 0 {
				usage()
			}
			capacity = u32(n)
			i += 2
			continue
		}
		usage()
	}

	mut srv := protocol.Server.new(sim.Config{ capacity: capacity }) or {
		eprintln('vcore: ${err}')
		exit(1)
	}
	defer {
		srv.close()
	}
	for {
		// get_raw_line satırı '\n' ile döner; boş satır ('\n') EOF değildir.
		line := os.get_raw_line()
		if line.len == 0 {
			break
		}
		if resp := srv.handle(line) {
			println(resp)
			flush_stdout()
		}
	}
}

@[noreturn]
fn usage() {
	eprintln(usage_text)
	exit(2)
}
