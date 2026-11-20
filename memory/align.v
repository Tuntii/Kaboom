module memory

// Hizalama matematigi, dallanmasiz. k bir 2'nin kuvveti olmali.
// (~p + 1) = -p (mod 2^64), dolayisiyla pad_for = (-p) mod k.
pub fn pad_for(p u64, k u64) u64 {
	return (~p + 1) & (k - 1)
}

pub fn align_forward(p u64, k u64) u64 {
	return p + pad_for(p, k)
}

pub fn is_pow2(k u64) bool {
	return k != 0 && (k & (k - 1)) == 0
}
