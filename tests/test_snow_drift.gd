extends "res://tests/suite.gd"

const RainFloor = preload("res://addons/overcast/overcast_rain_floor.gd")
const Drift = preload("res://addons/overcast/overcast_snow_drift.gd")
const NO_GAP := -1e6

const W := 60
const H := 30


## Flat ground at 0, a cell a metre, with `walls` (Rect2i of cells -> height) standing solid on it
## and `roofs` (Rect2i -> height) over open air.
func _floor(walls := {}, roofs := {}) -> RainFloor:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RF)
	var air := Image.create_empty(W, H, false, Image.FORMAT_RGF)
	air.fill(Color(NO_GAP, NO_GAP, 0))
	for rect: Rect2i in walls:
		img.fill_rect(rect, Color(walls[rect], 0, 0))
	for rect: Rect2i in roofs:
		img.fill_rect(rect, Color(roofs[rect], 0, 0))
		air.fill_rect(rect, Color(roofs[rect] - 0.2, 0.0, 0))
	return RainFloor.create(img, Vector3.ZERO, Vector2(W, H), 10.0, air)


func _at(img: Image, i: int, j: int) -> float:
	return img.get_pixel(i, j).r


func test_a_calm_leaves_an_even_layer() -> void:
	var f := _floor({Rect2i(20, 10, 1, 10): 2.0})
	var d := Drift.bake(f, Vector3(1, 0, 0), 0.3)
	assert_eq(d.get_size(), Vector2i(W, H))
	assert_eq(d.get_format(), Image.FORMAT_RF)
	for p in [Vector2i(5, 5), Vector2i(21, 15), Vector2i(20, 15), Vector2i(50, 25)]:
		assert_almost_eq(_at(d, p.x, p.y), 0.3, 1e-5, "even at %s" % p)


func test_a_wall_drifts_deep_in_its_lee_and_runs_out_downwind() -> void:
	# A wall 2 m high across the wind, at x 20, z 10..19; the wind blows +x.
	var f := _floor({Rect2i(20, 10, 1, 10): 2.0})
	var d := Drift.bake(f, Vector3(10, 0, 0), 0.3)
	var behind := _at(d, 21, 15)
	assert_almost_eq(behind, minf(2.0 * Drift.LEE_FILL, Drift.DEEPEST) - Drift.LEE_SLOPE, 1e-4,
		"against its lee it fills most of the way up")
	assert_gt(behind, _at(d, 25, 15), "and is shallower further off")
	assert_gt(_at(d, 25, 15), _at(d, 30, 15), "and shallower still")
	assert_almost_eq(_at(d, 40, 15), 0.3 * (1.0 - Drift.SCOUR), 1e-5, "it has run out by 10 heights off")
	assert_almost_eq(_at(d, 5, 5), 0.3 * (1.0 - Drift.SCOUR), 1e-5, "the open is scoured")
	var bank := _at(d, 19, 15)
	assert_almost_eq(bank, 2.0 * Drift.WINDWARD_FILL - Drift.WINDWARD_SLOPE, 1e-4, "a smaller bank on its windward side")
	assert_lt(_at(d, 17, 15), bank, "falling off upwind")
	assert_almost_eq(_at(d, 20, 15), 0.3 * (1.0 - Drift.SCOUR), 1e-5, "its top is scoured too")
	assert_lt(_at(d, 25, 22), _at(d, 25, 15), "past its end the drift falls away sideways")


func test_a_cliff_drifts_no_deeper_than_a_wall() -> void:
	var f := _floor({Rect2i(20, 0, 1, 30): 20.0})
	var d := Drift.bake(f, Vector3(10, 0, 0), 0.3)
	assert_almost_eq(_at(d, 21, 15), Drift.DEEPEST - Drift.LEE_SLOPE, 1e-4, "a 20 m cliff's lee starts as deep as DEEPEST")
	assert_almost_eq(_at(d, 40, 15), 0.3 * (1.0 - Drift.SCOUR), 1e-5,
		"and runs out as soon as a drift that deep would, not across the map")
	assert_lt(_at(d, 19, 15), Drift.DEEPEST, "its windward bank is no deeper")


func test_the_drift_follows_the_wind() -> void:
	var f := _floor({Rect2i(30, 10, 1, 10): 2.0})
	var east := Drift.bake(f, Vector3(10, 0, 0))
	var west := Drift.bake(f, Vector3(-10, 0, 0))
	assert_gt(_at(east, 31, 15), 1.0, "east of it in an east wind")
	assert_almost_eq(_at(west, 29, 15), _at(east, 31, 15), 1e-4, "west of it, as deep, in a west wind")
	assert_almost_eq(_at(west, 31, 15), _at(east, 29, 15), 1e-4, "and the bank swaps sides")


func test_a_light_wind_drifts_less() -> void:
	var f := _floor({Rect2i(20, 10, 1, 10): 2.0})
	var breeze := _at(Drift.bake(f, Vector3(Drift.CALM, 0, 0)), 21, 15)
	var mid := _at(Drift.bake(f, Vector3((Drift.CALM + Drift.DRIFTING) * 0.5, 0, 0)), 21, 15)
	var gale := _at(Drift.bake(f, Vector3(Drift.DRIFTING * 2.0, 0, 0)), 21, 15)
	assert_almost_eq(breeze, 0.3, 1e-5, "none at CALM")
	assert_gt(mid, breeze)
	assert_gt(gale, mid)


func test_the_wind_blows_under_a_roof_on_posts() -> void:
	# A roof 3 m up over open air, x 20..25: it drifts nothing, and none lies under it.
	var f := _floor({}, {Rect2i(20, 10, 6, 10): 3.0})
	var d := Drift.bake(f, Vector3(10, 0, 0), 0.3)
	var bare := 0.3 * (1.0 - Drift.SCOUR)
	assert_almost_eq(_at(d, 27, 15), bare, 1e-5, "nothing in its lee")
	assert_almost_eq(_at(d, 22, 15), bare, 1e-5, "its top is scoured like the open")


func test_a_slanted_wind_drifts_both_sides_alike() -> void:
	# A pillar two cells square in a wind at 45 degrees: the drift is as deep either side of the
	# line downwind. (One cell square is turned to the wind lopsidedly, by up to a tenth.)
	var f := _floor({Rect2i(20, 15, 2, 2): 2.0})
	var d := Drift.bake(f, Vector3(10, 0, 10))
	assert_gt(_at(d, 23, 18), 0.5, "downwind of it")
	assert_almost_eq(_at(d, 24, 18), _at(d, 23, 19), 0.05, "as deep either side")


func test_a_wind_off_the_grid_drifts_as_far() -> void:
	# The same wall in a wind 22 degrees off its square: the drift runs as far downwind of it.
	var f := _floor({Rect2i(20, 5, 1, 20): 2.0})
	var dir := Vector3(cos(0.38), 0, sin(0.38))
	var square := Drift.bake(f, Vector3(10, 0, 0))
	var slanted := Drift.bake(f, dir * 10.0)
	var off := Vector2(21, 15) + Vector2(dir.x, dir.z) * 6.0
	assert_almost_eq(_at(slanted, roundi(off.x), roundi(off.y)), _at(square, 27, 15), 0.15,
		"6 m downwind, as deep as straight behind it in a square wind")
