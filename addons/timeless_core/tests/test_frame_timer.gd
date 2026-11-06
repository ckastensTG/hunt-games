extends TestCase
## FrameTimer: averages and percentiles, hitches kept apart.


func test_mean_percentile_and_fps() -> void:
	var t := FrameTimer.new()
	for i in 9:
		t.add(1.0 / 60.0)
	t.add(1.0 / 30.0)
	check_eq(t.count(), 10, "ten frames")
	check(absf(t.mean_ms() - (9 * 16.667 + 33.333) / 10.0) < 0.05, "mean %.2f ms" % t.mean_ms())
	check(absf(t.percentile_ms(0.5) - 16.667) < 0.05, "median is a 60 fps frame")
	check(absf(t.percentile_ms(1.0) - 33.333) < 0.05, "slowest is the 30 fps frame")
	check(absf(t.fps() - 10.0 / (9.0 / 60.0 + 1.0 / 30.0)) < 0.01, "frames per second")


func test_hitches_are_kept_apart() -> void:
	var t := FrameTimer.new()
	t.add(0.016)
	t.add(0.9)  # a stall while something loads
	t.add(0.016)
	check_eq(t.hitches, 1, "one hitch")
	check_eq(t.count(), 2, "not in the frames")
	check(absf(t.mean_ms() - 16.0) < 0.01, "the mean ignores it")
	t.clear()
	check_eq(t.count(), 0, "cleared")
	check_eq(t.hitches, 0, "hitches cleared")
	check_eq(t.mean_ms(), 0.0, "empty mean")
