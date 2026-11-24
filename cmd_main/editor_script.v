module main

import ecs
import editor
import protocol
import ui

// Editör senaryosu (--select N, --open-menu, --dirty-strip, --bad-value): UI'ye sentetik fare ve klavye girdisi
// (gallery'deki script_mouse deseni). Her tıklama üç kare sürer (üzerine gel, bas, bırak); hedefin konumu önceki
// karenin düzeninden bulunur. Editörün iç durumuna dokunulmaz: seçim sahne tıklamasıyla olur.

// Bir tıklama üç karedir: üzerine gel, bas, bırak (sceneview ve inspektör testleriyle aynı).
const script_click_frames = 3
// Senaryo ilk karelerde bekler: ilk kare sahneyi yükler, ikinci kare düzeni verir.
const script_warm_frames = 2
// Son adımdan sonra bir kare: son değişikliğin çizimi.
const script_settle_frames = 2

enum EditorStepKind {
	select_row // N. satırdaki varlığın (Transform sırası) sahnedeki noktası
	click      // etiketli düğme (last_rect)
	field      // Sprite.r sayı kutusu
	add_menu   // Bileşen ekle düğmesi (inspektör kapsamında)
	type_text  // metin girdisi (bir kare)
	enter      // Enter tuşu (bir kare)
}

struct EditorStep {
	kind  EditorStepKind
	n     int
	label string
	text  string
}

struct EditorScript {
mut:
	steps []EditorStep
	cur   int
	sub   int // tıklamanın kaçıncı karesi: 0 üzerine gel, 1 bas, 2 bırak
	warm  int
	mx    f32 = -1 // son hedef (metin ve Enter bu noktada yazılır)
	my    f32 = -1
}

// Senaryo kurulur: seçim (--select, ya da --open-menu/--bad-value için 0), sonra istenen eylemler.
fn editor_script_from(o EditorOpts) EditorScript {
	mut steps := []EditorStep{}
	sel := if o.select >= 0 {
		o.select
	} else if o.open_menu || o.bad_value {
		0
	} else {
		-1
	}
	if sel >= 0 {
		steps << EditorStep{
			kind: .select_row
			n:    sel
		}
	}
	if o.dirty_strip {
		// Yeni varlık kirletir; Aç kaydedilmemiş değişiklik şeridini çıkarır.
		steps << EditorStep{
			kind:  .click
			label: 'Ekle'
		}
		steps << EditorStep{
			kind:  .click
			label: 'Aç'
		}
	}
	if o.open_menu {
		steps << EditorStep{
			kind: .add_menu
		}
	}
	if o.bad_value {
		steps << EditorStep{
			kind: .field
		}
		steps << EditorStep{
			kind: .type_text
			text: '2'
		}
		steps << EditorStep{
			kind: .enter
		}
	}
	return EditorScript{
		steps: steps
	}
}

// Senaryonun gerektirdiği toplam kare sayısı (bekleme, adımlar, yerleşim payı).
fn (s &EditorScript) frames_needed() int {
	mut n := script_warm_frames + script_settle_frames
	for st in s.steps {
		n += if st.kind == .type_text || st.kind == .enter { 1 } else { script_click_frames }
	}
	return n
}

fn (s &EditorScript) active() bool {
	return s.steps.len > 0
}

// Senaryo hâlâ girdi üretiyor mu (bekleme ya da adım kaldı). Bittikten sonra çağıran gerçek pencere girdisine döner.
fn (s &EditorScript) running() bool {
	return s.active() && (s.warm < script_warm_frames || s.cur < s.steps.len)
}

// Bu karenin girdisi. Adımlar bitince ya da bekleme sürerken fare dışarıdadır.
fn (mut s EditorScript) input(c &ui.Context, ed &editor.Editor, srv &protocol.Server, fr editor.EditorFrame, now f64) ui.Input {
	mut inp := ui.Input{
		mouse_x: -1
		mouse_y: -1
		time_ms: now
	}
	if s.warm < script_warm_frames {
		s.warm++
		return inp
	}
	if s.cur >= s.steps.len {
		return inp
	}
	st := s.steps[s.cur]
	match st.kind {
		.type_text {
			for i, ch in st.text {
				inp.chars[i] = u32(ch)
			}
			inp.char_count = st.text.len
			s.advance_step()
		}
		.enter {
			inp.keys[0] = .enter
			inp.key_count = 1
			s.advance_step()
		}
		else {
			if s.sub == 0 {
				// Hedef yalnız ilk karede çözülür: sonraki kareler aynı noktaya basar.
				ok, mx, my := s.target(c, ed, srv, fr, st)
				if !ok && st.kind == .select_row {
					// Sessiz seçimsiz ekran görüntüsü yanlış kanıt olur: hata ver ve çık.
					eprintln('vcore: --select ${st.n}: satır yok (sahnede ${srv.world().store(ecs.transform_id).len()} varlık)')
					exit(1)
				}
				s.mx = mx
				s.my = my
			}
			inp.mouse_x = s.mx
			inp.mouse_y = s.my
			if s.sub == 1 {
				inp.down[0] = true
				inp.pressed[0] = true
			} else if s.sub == 2 {
				inp.released[0] = true
			}
			s.sub++
			if s.sub == script_click_frames {
				s.advance_step()
			}
		}
	}
	return inp
}

fn (mut s EditorScript) advance_step() {
	s.cur++
	s.sub = 0
}

// Hedef noktası; bulunamazsa ok false ve (-1, -1): fare dışarıda kalır (--select dışında adım boşa gider).
fn (s &EditorScript) target(c &ui.Context, ed &editor.Editor, srv &protocol.Server, fr editor.EditorFrame, st EditorStep) (bool, f32, f32) {
	match st.kind {
		.select_row {
			ok, x, y := row_world(srv, st.n)
			if !ok {
				return false, f32(-1), f32(-1)
			}
			cam := editor.EditorCamera{
				cx:     fr.cam_cx
				cy:     fr.cam_cy
				view_h: fr.cam_view_h
			}
			sx, sy := cam.world_to_screen(fr.scene, x, y)
			return true, sx, sy
		}
		.field {
			comp := ecs.sprite_id
			cs := srv.registry().component(comp) or { return false, f32(-1), f32(-1) }
			fi := cs.field_index('r') or { return false, f32(-1), f32(-1) }
			r := ed.field_rect(c, comp, fi) or { return false, f32(-1), f32(-1) }
			return true, r.x + r.w / 2, r.y + r.h / 2
		}
		.add_menu {
			r := ed.add_component_rect(c) or { return false, f32(-1), f32(-1) }
			return true, r.x + r.w / 2, r.y + r.h / 2
		}
		else {
			r := c.last_rect(st.label) or { return false, f32(-1), f32(-1) }
			return true, r.x + r.w / 2, r.y + r.h / 2
		}
	}
}

// Transform satırının dünya konumu (x, y); satır yoksa ok false. Yalnız okuma.
fn row_world(srv &protocol.Server, n int) (bool, f32, f32) {
	tf := srv.world().store(ecs.transform_id)
	if n < 0 || u32(n) >= tf.len() {
		return false, 0, 0
	}
	cs := srv.registry().component(ecs.transform_id) or { return false, 0, 0 }
	fx := cs.field_index('x') or { return false, 0, 0 }
	fy := cs.field_index('y') or { return false, 0, 0 }
	xs := tf.column_f32(fx)
	ys := tf.column_f32(fy)
	return true, unsafe { xs[n] }, unsafe { ys[n] }
}
