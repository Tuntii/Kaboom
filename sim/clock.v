module sim

// Sabit adım: 1/120 sn, tam ns (f32 dt ile aynı oran).
pub const step_ns = u64(8_333_333)

// Birikmiş süreden koşulacak adım sayısını ve kalan süreyi (alfa payı) döner.
// max_steps'i aşan birikim atılır; böylece duraklama sonrası adımlar birikip döngü kilitlenmez.
pub fn steps_for(acc_ns u64, step_ns u64, max_steps u32) (u32, u64) {
	n := acc_ns / step_ns
	if n > u64(max_steps) {
		return max_steps, acc_ns % step_ns
	}
	return u32(n), acc_ns - n * step_ns
}
