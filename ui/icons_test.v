module ui

fn test_every_icon_has_ink() {
	a := Atlas.build(1.0) or { panic(err) }
	w := a.width()
	h := a.height()
	pix := a.pixels()
	icons := [Icon.play, .pause, .step, .undo, .redo, .plus, .trash, .save, .folder, .chevron_right,
		.chevron_down, .move, .eye, .warning, .close]
	for ic in icons {
		g := a.icon(ic)
		sz := int(g.x1)
		x0 := int(g.u0 * f32(w) + 0.5)
		y0 := int(g.v0 * f32(h) + 0.5)
		mut peak := u8(0)
		for yy in y0 .. y0 + sz {
			for xx in x0 .. x0 + sz {
				if pix[yy * w + xx] > peak {
					peak = pix[yy * w + xx]
				}
			}
		}
		assert peak >= 128
		for yy in y0 - 1 .. y0 + sz + 1 {
			for xx in x0 - 1 .. x0 + sz + 1 {
				if xx >= x0 && xx < x0 + sz && yy >= y0 && yy < y0 + sz {
					continue
				}
				if xx < 0 || yy < 0 || xx >= w || yy >= h {
					continue
				}
				assert pix[yy * w + xx] == 0
			}
		}
	}
}
