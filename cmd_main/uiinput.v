module main

import platform
import ui

// Sanal tuş kodu → ui.Key. Eşlenmeyen tuşlar none döner ve atlanır.
fn vk_to_key(vk u16) ui.Key {
	return match vk {
		0x09 { .tab }
		0x0D { .enter }
		0x1B { .escape }
		0x08 { .backspace }
		0x2E { .delete }
		0x25 { .left }
		0x26 { .up }
		0x27 { .right }
		0x28 { .down }
		0x24 { .home }
		0x23 { .end }
		0x20 { .space }
		0x41 { .a }
		0x53 { .s }
		0x59 { .y }
		0x5A { .z }
		0x74 { .f5 }
		0x75 { .f6 }
		0x79 { .f10 }
		else { .none }
	}
}

// Pencere girdisini mantıksal (ölçekli) koordinatlı ui.Input'a çevirir. Kontrol karakterleri metne geçmez.
fn to_ui_input(f platform.InputFrame, scale f32, now_ms f64) ui.Input {
	mut inp := ui.Input{
		mouse_x:  f32(f.mouse_x) / scale
		mouse_y:  f32(f.mouse_y) / scale
		down:     f.down
		pressed:  f.pressed
		released: f.released
		wheel_y:  f.wheel
		ctrl:     f.ctrl
		shift:    f.shift
		alt:      f.alt
		time_ms:  now_ms
	}
	for i in 0 .. f.vkey_count {
		k := vk_to_key(f.vkeys[i])
		if k != .none && inp.key_count < inp.keys.len {
			inp.keys[inp.key_count] = k
			inp.key_repeat[inp.key_count] = f.vkey_repeat[i]
			inp.key_count++
		}
	}
	for i in 0 .. f.char_count {
		cp := f.chars[i]
		if (cp < 0x20 || cp == 0x7F) || inp.char_count >= inp.chars.len {
			continue
		}
		inp.chars[inp.char_count] = cp
		inp.char_count++
	}
	return inp
}
