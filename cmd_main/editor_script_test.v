module main

import editor
import protocol
import sim
import ui

// Senaryo bitince run loop gerçek girdiye döner: running() yalnız bekleme ve adımlar sürerken doğrudur.
// dirty_strip: iki tıklama (6 kare) + 2 bekleme kare = 8 girdi çağrısı; sonra running() false.
fn test_editor_script_hands_back_input_after_steps() {
	mut s := editor_script_from(EditorOpts{ dirty_strip: true })
	assert s.running(), 'senaryo başta çalışıyor olmalı'
	assert s.frames_needed() == 10, 'kare sayısı: ${s.frames_needed()}'
	mut srv := protocol.Server.new(sim.Config{ capacity: 64, queue_capacity: 64, record_capacity: 1024 }) or {
		panic(err)
	}
	defer {
		srv.close()
	}
	mut atl := ui.Atlas.build(1.0) or { panic(err) }
	mut c := ui.Context.new(&atl, 4096, 8192) or { panic(err) }
	mut e := editor.Editor.new('')
	mut calls := 0
	for s.running() {
		_ = s.input(&c, &e, &srv, editor.EditorFrame{}, 0)
		calls++
		assert calls <= 20, 'senaryo sonsuz döngüde'
	}
	assert calls == 8, 'çağrı sayısı ${calls}'
	assert !s.running(), 'bitince running false'
	// Bittikten sonra senaryo girdi üretmez (çağıran gerçek pencere girdisini kullanır).
	inp := s.input(&c, &e, &srv, editor.EditorFrame{}, 0)
	assert inp.mouse_x == -1 && inp.mouse_y == -1 && inp.down[0] == false
}

// Bayrak yoksa senaryo hiç çalışmaz: gerçek girdi baştan kullanılır.
fn test_editor_script_inactive_without_flags() {
	s := editor_script_from(EditorOpts{})
	assert !s.active()
	assert !s.running()
}
