module ecs

import strconv

pub const max_components = 64
pub const max_fields = 16

// Min/max verilmeyen alanlar için f32 aralığı; f32 alanın hiçbir değeri dışarıda kalmaz.
const default_range = 3.4028234663852886e38

pub enum FieldType as u8 {
	f32_
	i32_
	bool_
	entity
	symbol
}

pub fn (t FieldType) name() string {
	return match t {
		.f32_ { 'f32' }
		.i32_ { 'i32' }
		.bool_ { 'bool' }
		.entity { 'entity' }
		.symbol { 'symbol' }
	}
}

// Depolamadaki bayt boyu; entity 8 bayt (EntityID u64).
pub fn (t FieldType) size() u32 {
	return match t {
		.f32_, .i32_, .bool_, .symbol { u32(4) }
		.entity { u32(8) }
	}
}

pub struct FieldSchema {
pub mut:
	name     string
	typ      FieldType
	unit     string
	min      f64
	max      f64
	desc     string
	readonly bool
}

pub struct ComponentSchema {
pub:
	id     u16
	name   string
	fields []FieldSchema
}

pub fn (s &ComponentSchema) field_index(name string) ?u16 {
	for i, f in s.fields {
		if f.name == name {
			return u16(i)
		}
	}
	return none
}

// Setup zamanı kullanılır; bileşenler kayıt sırasıyla id alır.
pub struct Registry {
mut:
	comps []ComponentSchema
}

pub fn (mut r Registry) register[T]() !u16 {
	if r.comps.len >= max_components {
		return error('bileşen üst sınırı aşıldı: ${max_components}')
	}
	// T.name modül önekiyle gelir (ecs.Transform); önek atılır.
	name := T.name.all_after_last('.')
	if r.find(name) != none {
		return error('bileşen zaten kayıtlı: ${name}')
	}
	mut fields := []FieldSchema{}
	$for f in T.fields {
		mut fs := FieldSchema{
			name: f.name
			min:  -default_range
			max:  default_range
		}
		// EntityID u64 takma adıdır; ayrı bir dal olarak entity tipine eşlenir.
		$if f.typ is f32 {
			fs.typ = .f32_
		} $else $if f.typ is i32 {
			fs.typ = .i32_
		} $else $if f.typ is bool {
			fs.typ = .bool_
		} $else $if f.typ is EntityID {
			fs.typ = .entity
		} $else {
			return error('desteklenmeyen alan tipi: ${name}.${f.name}')
		}
		// Öznitelik biçimi: `unit: 'm'`; tek kelimelik olan `readonly` gibi bayraktır.
		// Bilinmeyen anahtar hata verir: yazım hatası (ör. `unt`) sessizce yutulmaz.
		for attr in f.attrs {
			parts := attr.split_nth(': ', 2)
			if parts.len == 1 {
				if parts[0] == 'readonly' {
					fs.readonly = true
					continue
				}
				return error('bilinmeyen öznitelik: ${name}.${f.name} (${parts[0]})')
			}
			value := parts[1].trim("'")
			match parts[0] {
				'unit' {
					fs.unit = value
				}
				'desc' {
					fs.desc = value
				}
				'min' {
					fs.min = strconv.atof64(value) or {
						return error('min sayıya çevrilemedi: ${name}.${f.name}')
					}
				}
				'max' {
					fs.max = strconv.atof64(value) or {
						return error('max sayıya çevrilemedi: ${name}.${f.name}')
					}
				}
				else {
					return error('bilinmeyen öznitelik: ${name}.${f.name} (${parts[0]})')
				}
			}
		}
		fields << fs
	}
	if fields.len > max_fields {
		return error('alan üst sınırı aşıldı: ${name} (${max_fields})')
	}
	id := u16(r.comps.len)
	r.comps << ComponentSchema{
		id:     id
		name:   name
		fields: fields
	}
	return id
}

pub fn (r &Registry) count() u16 {
	return u16(r.comps.len)
}

pub fn (r &Registry) component(id u16) ?ComponentSchema {
	if int(id) >= r.comps.len {
		return none
	}
	return r.comps[id]
}

pub fn (r &Registry) find(name string) ?u16 {
	for c in r.comps {
		if c.name == name {
			return c.id
		}
	}
	return none
}
