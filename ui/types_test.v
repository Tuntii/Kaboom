module ui

fn test_rect_intersect_disjoint_is_empty() {
	a := Rect{
		x: 0
		y: 0
		w: 10
		h: 10
	}
	b := Rect{
		x: 20
		y: 20
		w: 5
		h: 5
	}
	r := a.intersect(b)
	assert r.w == 0
	assert r.h == 0
}

fn test_rect_intersect_overlap() {
	a := Rect{
		x: 0
		y: 0
		w: 10
		h: 10
	}
	b := Rect{
		x: 5
		y: 5
		w: 10
		h: 10
	}
	r := a.intersect(b)
	assert r.x == 5
	assert r.y == 5
	assert r.w == 5
	assert r.h == 5
}
