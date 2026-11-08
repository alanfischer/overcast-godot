extends "res://tests/suite.gd"

const RainFloor = preload("res://addons/overcast/overcast_rain_floor.gd")
const Field = preload("res://addons/overcast/overcast_snow_field.gd")

const LAYER := 0.3


## 10 m by 8 m of ground at 0, a cell a metre, with a roof 3 m up over x 0..1.
func _floor() -> RainFloor:
	var img := Image.create_empty(10, 8, false, Image.FORMAT_RF)
	img.fill_rect(Rect2i(0, 0, 2, 8), Color(3.0, 0, 0))
	return RainFloor.create(img, Vector3.ZERO, Vector2(10, 8), 10.0)


## Steps `seconds` of weather in frames of `dt`.
func _run_for(f: Field, seconds: float, settling: bool, rate: float, dt := 0.05) -> void:
	for i in roundi(seconds / dt):
		f.step(dt, settling, rate)


func test_snow_heaps_up_toward_its_target_and_comes_to_rest() -> void:
	var f := Field.new(_floor(), LAYER, true)
	assert_eq(f.depth_at(Vector3(5, 0, 4)), 0.0, "bare to start")
	_run_for(f, 5.0, true, 0.1)
	assert_almost_eq(f.depth_at(Vector3(5, 0, 4)), LAYER * 0.5, 0.02, "half the layer in half the time")
	assert_almost_eq(f.depth_at(Vector3(5, 0, 7)), LAYER * 0.5, 0.02, "on every row alike")
	_run_for(f, 6.0, true, 0.1)
	assert_almost_eq(f.depth_at(Vector3(5, 0, 4)), LAYER, 1e-6, "and no deeper than the layer")
	_run_for(f, 1.0, true, 0.1)
	assert_true(f.resting(), "all of it come to rest, a step does nothing")
	assert_almost_eq(f.image.get_pixel(5, 4).r, LAYER, 1e-6, "what the shaders read")


func test_snow_melts_away_when_it_stops() -> void:
	var f := Field.new(_floor(), LAYER, false)
	f.fill(1.0)
	_run_for(f, 5.0, false, 0.1)
	assert_almost_eq(f.depth_at(Vector3(5, 0, 4)), LAYER * 0.5, 0.02, "half gone in half the time")
	_run_for(f, 6.0, false, 0.1)
	assert_eq(f.depth_at(Vector3(5, 0, 4)), 0.0, "then all of it")


func test_a_drift_comes_round_to_a_new_wind() -> void:
	var f := Field.new(_floor(), LAYER, false)
	var drifted := f.target.duplicate()
	drifted[4 * 10 + 6] = 1.2
	f.set_target(drifted)
	f.fill(1.0)
	var turned := f.target.duplicate()
	turned[4 * 10 + 6] = LAYER
	turned[4 * 10 + 3] = 1.2
	f.set_target(turned)
	# A drift moves as fast as it would heap up from bare: its whole depth in 1 / rate.
	_run_for(f, 5.0, true, 0.1)
	assert_almost_eq(f.depth_at(Vector3(6.5, 0, 4.5)), 0.6, 0.02, "the old drift worn half its depth down")
	assert_almost_eq(f.depth_at(Vector3(3.5, 0, 4.5)), 0.9, 0.02, "as the new one heaps up as fast")
	_run_for(f, 6.0, true, 0.1)
	assert_almost_eq(f.depth_at(Vector3(6.5, 0, 4.5)), LAYER, 1e-6, "both come round to the new wind")
	assert_almost_eq(f.depth_at(Vector3(3.5, 0, 4.5)), 1.2, 1e-6, "in the time snow takes to settle")


func test_a_melt_digs_out_the_snow_and_it_fills_in_again() -> void:
	var f := Field.new(_floor(), LAYER, true)
	f.fill(1.0)
	_run_for(f, 1.0, true, 0.1)
	assert_true(f.resting(), "settled")
	f.melt(Vector3(5.5, 0.2, 4.5), 3.0)
	assert_eq(f.depth_at(Vector3(5.5, 0, 4.5)), 0.0, "bare where it struck")
	var edge := f.depth_at(Vector3(7.5, 0, 4.5))
	assert_true(edge > 0.0 and edge < LAYER, "thinner toward the edge (%s)" % edge)
	assert_almost_eq(f.depth_at(Vector3(9.5, 0, 4.5)), LAYER, 1e-6, "untouched past it")
	f.step(0.05, true, 0.1)
	assert_lt(f.image.get_pixel(5, 4).r, 0.01, "dug out for the shaders, without a jump from the rest")
	_run_for(f, 11.0, true, 0.1)
	assert_almost_eq(f.depth_at(Vector3(5.5, 0, 4.5)), LAYER, 1e-6, "filled in as the snow kept settling")


func test_a_melt_keeps_to_what_lies_near_its_height() -> void:
	var f := Field.new(_floor(), LAYER, false)
	f.fill(1.0)
	f.melt(Vector3(2.5, 0.2, 4.5), 2.0)
	assert_almost_eq(f.depth_at(Vector3(1.5, 3, 4.5)), LAYER, 1e-6, "the roof 3 m over a blast on the ground keeps its snow")
	assert_eq(f.depth_at(Vector3(2.5, 0, 4.5)), 0.0, "the ground beside it does not")


func test_snow_is_kept_off_what_lies_in_a_snowless_box() -> void:
	# A pool over x 5..7 whose bed, 1 m down, the rain floor takes for the ground.
	var img := Image.create_empty(10, 8, false, Image.FORMAT_RF)
	img.fill_rect(Rect2i(5, 0, 3, 8), Color(-1.0, 0, 0))
	var f := Field.new(RainFloor.create(img, Vector3.ZERO, Vector2(10, 8), 10.0), LAYER, false)
	f.fill(1.0)
	f.keep_off([AABB(Vector3(5, -1, 0), Vector3(3, 0.9, 8))])
	assert_eq(f.depth_at(Vector3(6.5, -1, 4.5)), 0.0, "none on the pool's bed")
	assert_almost_eq(f.depth_at(Vector3(3.5, 0, 4.5)), LAYER, 1e-6, "the bank keeps its snow")
	var drifted := f.target.duplicate()
	drifted.fill(1.0)
	f.set_target(drifted)
	_run_for(f, 11.0, true, 0.1)
	assert_eq(f.depth_at(Vector3(6.5, -1, 4.5)), 0.0, "nor does a wind drift any into it")
	assert_almost_eq(f.depth_at(Vector3(3.5, 0, 4.5)), 1.0, 1e-6, "while it drifts the bank")
	assert_eq(f.bare_cells().size(), 3 * 8, "the pool's cells, once each")
	f.keep_off([AABB(Vector3(5, -1, 0), Vector3(3, 0.9, 8))])
	assert_eq(f.bare_cells().size(), 3 * 8, "however often it is asked")
