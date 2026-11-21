module cmd

import ecs

// Dünyayı değiştiren tek birim. Sabit 24 bayt ikili kayıt; sıra ve boyut kayıt formatının parçasıdır.
pub enum CommandKind as u8 {
	spawn
	despawn
	add_component
	remove_component
	set_field
}

// Kaynak sınıfı; uygulama sırası budur (script < editor < agent).
pub enum Source as u8 {
	script
	editor
	agent
}

pub struct Command {
pub mut:
	kind   CommandKind
	source Source
	comp   u16
	field  u16
	pad    u16
	entity ecs.EntityID
	value  u64
}

pub struct ApplyResult {
pub:
	status ecs.Status
	entity ecs.EntityID
}

// Tick yolunda çağrılır, tahsis yapmaz. spawn'da entity yeni id'dir; diğer komutlarda c.entity.
pub fn apply(mut w ecs.World, c Command) ApplyResult {
	if c.kind == .spawn {
		e := w.spawn() or {
			return ApplyResult{
				status: .capacity_full
				entity: ecs.null_entity
			}
		}
		return ApplyResult{
			status: .ok
			entity: e
		}
	}
	st := match c.kind {
		.despawn {
			if w.despawn(c.entity) { ecs.Status.ok } else { ecs.Status.dead_entity }
		}
		.add_component {
			w.add_component(c.entity, c.comp)
		}
		.remove_component {
			w.remove_component(c.entity, c.comp)
		}
		.set_field {
			w.set_field(c.entity, c.comp, c.field, c.value)
		}
		// Diskten okunan kayıtta bilinmeyen tür: hiçbir şey değişmez.
		else {
			ecs.Status.invalid_command
		}
	}

	return ApplyResult{
		status: st
		entity: c.entity
	}
}
