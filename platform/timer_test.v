module platform

fn test_qpc_to_ns_no_overflow() {
	assert qpc_to_ns(10_000_000, 10_000_000) == 1_000_000_000
	// 10 MHz sayaçta 30 gün: counter*1e9 u64'ü taşırırdı
	c := u64(10_000_000) * 86_400 * 30
	assert qpc_to_ns(c, 10_000_000) == u64(86_400) * 30 * 1_000_000_000
	assert qpc_to_ns(15, 10) == 1_500_000_000
}

fn test_now_ns_monotonic() {
	a := now_ns()
	b := now_ns()
	assert b >= a
}
