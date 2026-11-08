extends "res://tests/suite.gd"
## Showers of a few minutes with dry spells between, never a jump in the rain or the wind.

const Cycle = preload("res://addons/overcast/overcast_cycle.gd")


func test_showers_come_and_go() -> void:
	var cycle := Cycle.new(1234)
	var dt := 0.25
	var showers: Array[float] = []
	var dry_spells: Array[float] = []
	var run := 0.0
	var wet := false
	var last := 0.0
	var worst_step := 0.0
	var lo := INF
	var hi := -INF
	var t := 0.0
	while t < 3.0 * 3600.0:
		t += dt
		var r := cycle.rain_at(t)
		lo = minf(lo, r)
		hi = maxf(hi, r)
		if (r > 0.0) != wet:
			(showers if wet else dry_spells).append(run)
			wet = r > 0.0
			run = 0.0
		run += dt
		worst_step = maxf(worst_step, absf(r - last))
		last = r
	assert_true(lo == 0.0 and hi <= Cycle.PEAK.y and hi > 0.3, "rain spans dry to heavy (%.2f..%.2f)" % [lo, hi])
	assert_true(showers.size() >= 10, "it rains on and off (%d showers in 3 h)" % showers.size())
	for s in showers:
		assert_true(s >= Cycle.SHOWER.x - 1.0 and s <= Cycle.SHOWER.y + 1.0,
			"a shower lasts a few minutes (%.0f s)" % s)
	for d in dry_spells.slice(1):
		assert_true(d >= Cycle.DRY.x - 1.0, "dry for a while between showers (%.0f s)" % d)
	assert_true(worst_step < 0.02, "the rain never jumps (worst %.4f per %.2f s)" % [worst_step, dt])


func test_the_wind_rises_falls_and_turns() -> void:
	var cycle := Cycle.new(1234)
	var dt := 0.25
	var calm := INF
	var hardest := 0.0
	var worst_step := 0.0
	var widest_turn := 0.0
	var dry_mean := Vector2.ZERO  # sum, count
	var wet_mean := Vector2.ZERO
	var prevailing := cycle.wind_at(0.0)
	var last := prevailing
	var flat := true
	var t := 0.0
	while t < 3.0 * 3600.0:
		t += dt
		var r := cycle.rain_at(t)
		var w := cycle.wind_at(t)
		flat = flat and w.y == 0.0
		var speed := w.length()
		calm = minf(calm, speed)
		hardest = maxf(hardest, speed)
		worst_step = maxf(worst_step, w.distance_to(last))
		widest_turn = maxf(widest_turn, absf(Vector2(w.x, w.z).angle_to(Vector2(prevailing.x, prevailing.z))))
		if r > 0.0:
			wet_mean += Vector2(speed, 1.0)
		else:
			dry_mean += Vector2(speed, 1.0)
		last = w
	assert_true(flat, "the wind blows across the ground")
	assert_true(calm < 1.5 and hardest > 6.0, "the wind rises and falls (%.1f..%.1f m/s)" % [calm, hardest])
	assert_true(hardest <= Cycle.BREEZE.y + Cycle.SHOWER_WIND * Cycle.PEAK.y + 0.01, "and no harder than a gale")
	assert_true(widest_turn > 0.3 and widest_turn < 2.0 * Cycle.TURN,
		"it turns, and keeps roughly to where it prevails (%.2f rad)" % widest_turn)
	assert_gt(wet_mean.x / wet_mean.y, dry_mean.x / dry_mean.y + 1.0, "showers blow harder")
	assert_true(worst_step < dt, "the wind never jumps, at most 1 m/s a second (worst %.4f per %.2f s)" % [worst_step, dt])



func test_the_breeze_alone_leaves_the_showers_out() -> void:
	var cycle := Cycle.new(1234)
	var t := 0.0
	var gap := 0.0
	var hardest := 0.0
	var same_way := true
	while t < 3.0 * 3600.0:
		t += 1.0
		var calm := cycle.wind_at(t, false)
		var full := cycle.wind_at(t)
		hardest = maxf(hardest, calm.length())
		gap = maxf(gap, full.length() - calm.length())
		same_way = same_way and calm.normalized().is_equal_approx(full.normalized())
	assert_true(same_way, "it blows the way the full wind does")
	assert_lt(hardest, Cycle.BREEZE.y + 1e-4, "no harder than a breeze (%.1f m/s)" % hardest)
	assert_gt(gap, 1.0, "where the showers would have blown harder")

func test_one_seed_one_weather() -> void:
	var a := Cycle.new(77)
	var b := Cycle.new(77)
	for t in range(0, 7200, 5):
		if a.rain_at(t) != b.rain_at(t) or a.wind_at(t) != b.wind_at(t):
			assert_true(false, "two cycles on one seed part at %d s" % t)
			return
	assert_true(true, "two cycles on one seed agree for two hours")


func test_a_jump_ahead_lands_where_stepping_would() -> void:
	var stepped := Cycle.new(5)
	for t in range(0, 5000, 10):
		stepped.rain_at(t)
	var jumped := Cycle.new(5)
	assert_eq(jumped.rain_at(5000.0), stepped.rain_at(5000.0), "skipping showers keeps the plan")
