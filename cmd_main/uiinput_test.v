module main

import platform
import ui

fn test_vk_mapping_and_scale() {
	mut f := platform.InputFrame{
		mouse_x: 300
		mouse_y: 150
	}
	f.vkeys[0] = u16(0x5A)
	f.vkey_count = 1
	f.ctrl = true
	f.chars[0] = u32(0x08)
	f.chars[1] = u32(0x61)
	f.char_count = 2
	in1 := to_ui_input(f, 1.5, 42.0)
	assert in1.mouse_x == 200
	assert in1.mouse_y == 100
	assert in1.time_ms == 42.0
	assert in1.key_count == 1
	assert in1.keys[0] == ui.Key.z
	assert in1.ctrl
	assert in1.char_count == 1
	assert in1.chars[0] == u32(0x61)
}

fn test_vk_f_maps_to_frame_key() {
	assert vk_to_key(u16(0x46)) == ui.Key.f
}
