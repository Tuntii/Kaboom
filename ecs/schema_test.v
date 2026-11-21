module ecs

fn test_core_registry_layout() {
	r := core_registry()!
	assert r.count() == 2
	t := r.component(transform_id)?
	assert t.name == 'Transform'
	assert t.fields.map(it.name) == ['x', 'y', 'prev_x', 'prev_y']
	assert t.fields[0].typ == .f32_ && t.fields[0].unit == 'm'
	assert t.fields[2].readonly && !t.fields[0].readonly
	b := r.component(body_id)?
	assert b.fields.map(it.name) == ['vx', 'vy']
	assert b.fields[0].unit == 'm/s'
	assert r.find('Body')? == body_id
	assert r.find('Nope') == none
	assert t.field_index('prev_y')? == 3
}

struct Ranged {
pub mut:
	v f32 @[desc: 'aralik'; max: '5'; min: '-5']
}

fn test_attr_parsing() {
	mut r := Registry{}
	id := r.register[Ranged]()!
	f := r.component(id)?.fields[0]
	assert f.min == -5.0 && f.max == 5.0 && f.desc == 'aralik'
}

fn test_attr_defaults_are_f32_range() {
	mut r := Registry{}
	id := r.register[Transform]()!
	f := r.component(id)?.fields[0]
	assert f.min == -3.4028234663852886e38 && f.max == 3.4028234663852886e38
}

struct BadType {
pub mut:
	s string
}

fn test_register_rejects() {
	mut r := core_registry()!
	if _ := r.register[Transform]() {
		assert false
	}
	if _ := r.register[BadType]() {
		assert false
	}
}

struct WithEntity {
pub mut:
	target EntityID
}

fn test_entity_alias_maps_to_entity() {
	mut r := Registry{}
	id := r.register[WithEntity]()!
	f := r.component(id)?.fields[0]
	assert f.typ == .entity && f.typ.size() == 8
}

fn test_field_type_sizes() {
	assert FieldType.f32_.size() == 4
	assert FieldType.i32_.size() == 4
	assert FieldType.bool_.size() == 4
	assert FieldType.entity.size() == 8
	assert FieldType.symbol.size() == 4
	assert FieldType.entity.name() == 'entity'
}

struct BadAttrKey {
pub mut:
	speed f32 @[unt: 'm']
}

// Bilinmeyen öznitelik anahtarı sessizce atılmaz: hata anahtarı ve alanı adlandırmalı.
fn test_unknown_attr_key_fails_fast() {
	mut r := Registry{}
	r.register[BadAttrKey]() or {
		assert err.msg().contains('unt')
		assert err.msg().contains('speed')
		return
	}
	assert false
}
