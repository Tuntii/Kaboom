module ecs

fn test_pack_roundtrip() {
	e := make_entity(0xFFFFFFFE, 0xFFFF)
	assert u64(e) == u64(0x0000FFFF_FFFFFFFE)
	assert e.index() == 0xFFFFFFFE && e.generation() == 0xFFFF
	assert u64(e) >> 48 == 0
}

fn test_null() {
	assert null_entity.is_null()
	assert !make_entity(0, 0).is_null()
}
