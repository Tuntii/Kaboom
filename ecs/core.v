module ecs

// Kayıt sırası id'yi belirler; bu sabitler core_registry'deki sıraya bağlıdır.
pub const transform_id = u16(0)
pub const body_id = u16(1)

// prev_* alanları interpolasyon için her tick başında sistem tarafından yazılır; kullanıcı düzenlemez.
pub struct Transform {
pub mut:
	x      f32 @[unit: 'm']
	y      f32 @[unit: 'm']
	prev_x f32 @[unit: 'm'; readonly; desc: 'Önceki tick konumu (interpolasyon)']
	prev_y f32 @[unit: 'm'; readonly; desc: 'Önceki tick konumu (interpolasyon)']
}

pub struct Body {
pub mut:
	vx f32 @[unit: 'm/s']
	vy f32 @[unit: 'm/s']
}

pub fn core_registry() !Registry {
	mut r := Registry{}
	_ = r.register[Transform]()!
	_ = r.register[Body]()!
	return r
}
