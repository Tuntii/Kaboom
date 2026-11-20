module ecs

import memory
import math

fn new_store(cap u32) ComponentStore {
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	mut a := memory.LinearArena.new(region, 1 << 20)
	return ComponentStore.new(mut a, [FieldType.f32_, .f32_, .entity], cap) or { panic('new none') }
}

fn test_insert_set_get() {
	mut s := new_store(16)
	r := s.insert(5)?
	assert s.has(5) && s.row_of(5)? == r && s.len() == 1
	assert s.get_raw(r, 0) == 0
	s.set_raw(r, 1, u64(math.f32_bits(2.5)))
	s.set_raw(r, 2, u64(0x0000_0003_0000_0007))
	assert math.f32_from_bits(u32(s.get_raw(r, 1))) == 2.5
	assert s.get_raw(r, 2) == u64(0x0000_0003_0000_0007)
	assert s.insert(5) == none
	assert s.insert(16) == none
}

fn test_swap_and_pop_keeps_data() {
	mut s := new_store(16)
	for i in [u32(1), 2, 3] {
		r := s.insert(i)?
		s.set_raw(r, 0, u64(math.f32_bits(f32(i))))
	}
	assert s.remove(1)
	assert !s.has(1) && s.len() == 2
	r3 := s.row_of(3)?
	assert r3 == 0 && s.index_at(0) == 3
	assert math.f32_from_bits(u32(s.get_raw(r3, 0))) == 3.0
	assert !s.remove(1)
}

// Son satiri silmek swap gerektirmez; diger satirlar ve sparse kayitlari bozulmamali.
fn test_remove_last_row() {
	mut s := new_store(16)
	for i in [u32(1), 2, 3] {
		r := s.insert(i)?
		s.set_raw(r, 0, u64(math.f32_bits(f32(i))))
	}
	assert s.remove(3)
	assert s.len() == 2 && !s.has(3)
	assert s.row_of(1)? == 0 && s.row_of(2)? == 1
	assert math.f32_from_bits(u32(s.get_raw(1, 0))) == 2.0
	assert s.remove(1) && s.remove(2)
	assert s.len() == 0 && !s.has(2)
}

// Swap tum kolonlari tasimali: entity (8 B) kolonu da kopyalanmali.
fn test_swap_moves_all_columns() {
	mut s := new_store(16)
	r1 := s.insert(10)?
	r2 := s.insert(12)?
	s.set_raw(r1, 2, u64(0xAAAA))
	s.set_raw(r2, 2, u64(0xBBBB))
	assert s.remove(10)
	assert s.index_at(0) == 12
	assert s.get_raw(0, 2) == u64(0xBBBB)
}

// set_raw yalnizca alanin size baytini yazar; komsu satir ve alanlar etkilenmez.
fn test_set_raw_writes_only_field_size() {
	mut s := new_store(16)
	r0 := s.insert(0)?
	r1 := s.insert(1)?
	s.set_raw(r1, 0, u64(0x7777))
	s.set_raw(r0, 0, u64(0x1_0000_0002))
	assert s.get_raw(r0, 0) == 2
	assert s.get_raw(r1, 0) == 0x7777
	assert s.get_raw(r0, 1) == 0
}

fn test_queries() {
	mut s := new_store(16)
	assert s.field_count() == 3
	assert s.field_size(0) == 4 && s.field_size(2) == 8
	assert s.row_of(7) == none
	assert s.index_at(0) == null_index
	assert !s.remove(7)
}

fn test_columns_64_aligned() {
	s := new_store(16)
	assert u64(s.column_f32(0)) % 64 == 0
	assert u64(s.column_f32(1)) % 64 == 0
}

fn test_new_rejects_too_many_fields() {
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	defer { memory.release(region) }
	mut a := memory.LinearArena.new(region, 1 << 20)
	used := a.used()
	fields := []FieldType{len: max_fields + 1, init: .f32_}
	assert ComponentStore.new(mut a, fields, 16) == none
	assert a.used() == used
}

// Arena yetersizse none doner ve parent eski imlecine geri sarilir.
fn test_new_rolls_back_on_small_arena() {
	region := memory.reserve(1 << 20) or { panic('reserve basarisiz') }
	defer { memory.release(region) }
	mut a := memory.LinearArena.new(region, 256)
	used := a.used()
	assert ComponentStore.new(mut a, [FieldType.f32_, .entity], 64) == none
	assert a.used() == used
}

fn test_insert_out_of_capacity_after_churn() {
	mut s := new_store(2)
	s.insert(0)?
	s.insert(1)?
	assert s.insert(2) == none
	assert s.remove(0)
	assert s.insert(0)? == 1
}
