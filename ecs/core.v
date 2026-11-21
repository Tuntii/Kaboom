module ecs

// Kayıt sırası id'yi belirler; bu sabitler core_registry'deki sıraya bağlıdır.
pub const transform_id = u16(0)
pub const body_id = u16(1)
pub const sprite_id = u16(2)

// prev_* alanları interpolasyon için her tick başında sistem tarafından yazılır; kullanıcı düzenlemez.
pub struct Transform {
pub mut:
	x      f32 @[unit: 'm']
	y      f32 @[unit: 'm']
	prev_x f32 @[desc: 'Önceki tick konumu (interpolasyon)'; readonly; unit: 'm']
	prev_y f32 @[desc: 'Önceki tick konumu (interpolasyon)'; readonly; unit: 'm']
}

pub struct Body {
pub mut:
	vx f32 @[unit: 'm/s']
	vy f32 @[unit: 'm/s']
}

// Görünür varlık: Transform ile birlikte çizilir. size 0 iken görünmez.
pub struct Sprite {
pub mut:
	size f32 @[unit: 'm'; min: '0'; max: '1000']
	r    f32 @[min: '0'; max: '1']
	g    f32 @[min: '0'; max: '1']
	b    f32 @[min: '0'; max: '1']
}

pub fn core_registry() !Registry {
	mut r := Registry{}
	_ = r.register[Transform]()!
	_ = r.register[Body]()!
	_ = r.register[Sprite]()!
	return r
}
