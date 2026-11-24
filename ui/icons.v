module ui

import math

pub enum Icon {
	play
	pause
	step
	undo
	redo
	plus
	trash
	save
	folder
	chevron_right
	chevron_down
	move
	eye
	warning
	close
	check
}

const icon_n = 16

// 24×24 ızgara; her yol açık çoklu çizgi.
struct IconPath {
mut:
	pts []f32
}

fn poly(pts ...f32) IconPath {
	return IconPath{
		pts: pts
	}
}

// Yayı yoldaki uç noktadan devam ettirir.
fn with_arc(p IconPath, cx f32, cy f32, r f32, a0 f32, a1 f32) IconPath {
	mut o := p
	o.pts << arc(cx, cy, r, a0, a1)
	return o
}

pub fn all_icons() []Icon {
	return [.play, .pause, .step, .undo, .redo, .plus, .trash, .save, .folder, .chevron_right,
		.chevron_down, .move, .eye, .warning, .close, .check]
}

// Yay: a0..a1 derece arası 12 parçalı çoklu çizgi.
fn arc(cx f32, cy f32, r f32, a0 f32, a1 f32) []f32 {
	mut pts := []f32{}
	for i in 0 .. 13 {
		a := f64(a0 + (a1 - a0) * f32(i) / 12.0) * math.pi / 180.0
		pts << cx + r * f32(math.cos(a))
		pts << cy + r * f32(math.sin(a))
	}
	return pts
}

fn icon_paths(ic Icon) []IconPath {
	return match ic {
		.play {
			[poly(7, 5, 19, 12, 7, 19, 7, 5)]
		}
		.pause {
			[poly(8, 5, 8, 19), poly(16, 5, 16, 19)]
		}
		.step {
			[poly(5, 5, 15, 12, 5, 19, 5, 5), poly(19, 5, 19, 19)]
		}
		.undo {
			[poly(9, 5, 4, 10, 9, 15), with_arc(poly(4, 10, 13, 10), 13, 15, 5, -90, 90)]
		}
		.redo {
			[poly(15, 5, 20, 10, 15, 15), with_arc(poly(20, 10, 11, 10), 11, 15, 5, -90, -270)]
		}
		.plus {
			[poly(12, 5, 12, 19), poly(5, 12, 19, 12)]
		}
		.trash {
			[poly(4, 7, 20, 7), poly(6, 7, 7, 20, 17, 20, 18, 7),
				poly(9, 7, 9, 4, 15, 4, 15, 7)]
		}
		.save {
			[poly(5, 4, 16, 4, 19, 7, 19, 20, 5, 20, 5, 4), poly(9, 20, 9, 14, 15, 14, 15, 20)]
		}
		.folder {
			[poly(3, 6, 10, 6, 12, 8, 21, 8, 21, 19, 3, 19, 3, 6)]
		}
		.chevron_right {
			[poly(9, 6, 15, 12, 9, 18)]
		}
		.chevron_down {
			[poly(6, 9, 12, 15, 18, 9)]
		}
		.move {
			[poly(12, 4, 12, 20), poly(4, 12, 20, 12), poly(10, 6, 12, 4, 14, 6),
				poly(10, 18, 12, 20, 14, 18), poly(6, 10, 4, 12, 6, 14),
				poly(18, 10, 20, 12, 18, 14)]
		}
		.eye {
			[poly(2, 12, 6, 7, 12, 6, 18, 7, 22, 12, 18, 17, 12, 18, 6, 17, 2, 12),
				IconPath{
					pts: arc(12, 12, 2, 0, 360)
				}]
		}
		.warning {
			[poly(12, 4, 21, 20, 3, 20, 12, 4), poly(12, 9.5, 12, 14.5),
				IconPath{
					pts: arc(12, 17.2, 1.4, 0, 360)
				}]
		}
		.close {
			[poly(6, 6, 18, 18), poly(18, 6, 6, 18)]
		}
		.check {
			[poly(4, 12, 9, 17, 20, 6)]
		}
	}
}

// Yuvarlak uçlu çizgi: piksel merkezinin en yakın segmente uzaklığından kapsama; yalnızca kutu içine yazar.
fn rasterize_icon(mut px []u8, side int, x0 int, y0 int, s int, sc f32, paths []IconPath) {
	k := f32(s) / 24.0
	half := 1.5 * sc / 2.0
	for py in 0 .. s {
		for qx in 0 .. s {
			gx := (f32(qx) + 0.5) / k
			gy := (f32(py) + 0.5) / k
			mut best := f32(1e9)
			for p in paths {
				for i := 0; i + 3 < p.pts.len; i += 2 {
					d := seg_dist(gx, gy, p.pts[i], p.pts[i + 1], p.pts[i + 2], p.pts[i + 3])
					if d < best {
						best = d
					}
				}
			}
			mut cov := half + 0.5 - best * k
			if cov <= 0 {
				continue
			}
			if cov > 1 {
				cov = 1
			}
			v := u8(cov * 255)
			idx := (y0 + py) * side + x0 + qx
			if v > px[idx] {
				px[idx] = v
			}
		}
	}
}

// Nokta-segment uzaklığı (ızgara birimi).
fn seg_dist(px f32, py f32, ax f32, ay f32, bx f32, by f32) f32 {
	dx := bx - ax
	dy := by - ay
	len2 := dx * dx + dy * dy
	mut t := f32(0)
	if len2 > 0 {
		t = ((px - ax) * dx + (py - ay) * dy) / len2
		if t < 0 {
			t = 0
		} else if t > 1 {
			t = 1
		}
	}
	ex := ax + t * dx - px
	ey := ay + t * dy - py
	return f32(math.sqrt(f64(ex * ex + ey * ey)))
}
