module sim

fn test_steps_for_zero_accumulator() {
	n, rem := steps_for(0, step_ns, 8)
	assert n == 0
	assert rem == 0
}

fn test_steps_for_whole_steps_and_remainder() {
	n, rem := steps_for(step_ns * 3 + 5, step_ns, 8)
	assert n == 3
	assert rem == 5
}

fn test_steps_for_clamps_and_drops_backlog() {
	n, rem := steps_for(step_ns * 100, step_ns, 8)
	assert n == 8
	assert rem < step_ns
}
