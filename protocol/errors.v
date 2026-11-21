module protocol

import x.json2
import ecs

// JSON-RPC 2.0 standart kodları.
pub const code_parse = -32700
pub const code_invalid_request = -32600
pub const code_method_not_found = -32601
pub const code_invalid_params = -32602
// Beklenmeyen sunucu içi hata; tasarım gereği normal akışta ulaşılmaz.
pub const code_internal = -32603

// Motor kodları. 1012 spec tablosunda yok; ecs.Status.invalid_command için eklendi.
pub const code_dead_entity = 1001
pub const code_unknown_component = 1002
pub const code_unknown_field = 1003
pub const code_already_has = 1004
pub const code_missing_component = 1005
pub const code_capacity_full = 1006
pub const code_queue_full = 1007
pub const code_record_state = 1008
pub const code_readonly_field = 1009
pub const code_io_error = 1010
pub const code_replay_diverged = 1011
pub const code_invalid_command = 1012

// Yapılandırılmış hata: ajan kendi hatasını düzeltebilsin diye kod, mesaj ve data taşır.
pub struct RpcError {
pub:
	err_code int
	message  string
	data     map[string]json2.Any
}

pub fn (e RpcError) msg() string {
	return e.message
}

pub fn (e RpcError) code() int {
	return e.err_code
}

// data her zaman bir hint içerir; ilgili entity, component ve field varsa onlar da eklenir.
pub fn rpc_error(code int, message string, data map[string]json2.Any) RpcError {
	return RpcError{
		err_code: code
		message:  message
		data:     data
	}
}

fn invalid_request(hint string) RpcError {
	return rpc_error(code_invalid_request, 'invalid request', {
		'hint': json2.Any(hint)
	})
}

fn internal_error(hint string) RpcError {
	return rpc_error(code_internal, 'internal error', {
		'hint': json2.Any(hint)
	})
}

pub fn invalid_params(hint string) RpcError {
	return rpc_error(code_invalid_params, 'invalid params', {
		'hint': json2.Any(hint)
	})
}

// ecs.Status -> JSON-RPC kodu. ok bu yola gelmez; gelirse sunucu içi hata.
fn status_code(st ecs.Status) int {
	return match st {
		.dead_entity { code_dead_entity }
		.unknown_component { code_unknown_component }
		.unknown_field { code_unknown_field }
		.already_has { code_already_has }
		.missing_component { code_missing_component }
		.capacity_full { code_capacity_full }
		.invalid_command { code_invalid_command }
		else { code_internal }
	}
}

fn status_hint(st ecs.Status) string {
	return match st {
		.dead_entity {
			'entity is not alive: it was despawned or the handle is stale; use query.entities for live ids'
		}
		.unknown_component {
			'no component with this name; see schema.components'
		}
		.unknown_field {
			'no field with this name on the component; see schema.components'
		}
		.already_has {
			'entity already has this component; use component.set to change its fields'
		}
		.missing_component {
			'entity does not have this component; add it with component.add first'
		}
		.capacity_full {
			'world capacity is full; despawn entities or start the server with a larger capacity'
		}
		.invalid_command {
			'command kind is not recognized by the engine'
		}
		else {
			'unexpected engine status'
		}
	}
}

// ecs.Status hatası; refs entity/component/field bağlamını taşır.
pub fn status_error(st ecs.Status, refs map[string]json2.Any) RpcError {
	mut data := refs.clone()
	data['hint'] = json2.Any(status_hint(st))
	return rpc_error(status_code(st), st.str(), data)
}
