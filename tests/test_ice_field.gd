extends "res://tests/suite.gd"

const RainFloor = preload("res://addons/overcast/overcast_rain_floor.gd")
const Ice = preload("res://addons/overcast/overcast_ice_field.gd")


## 10 m by 8 m of ground at 0, a cell a metre.
func _floor() -> RainFloor:
	var img := Image.create_empty(10, 8, false, Image.FORMAT_RF)
	return RainFloor.create(img, Vector3.ZERO, Vector2(10, 8), 10.0)


func _run_for(f: Ice, seconds: float, freezing: bool, glaze: float, rate: float, dt := 0.05) -> void:
	for i in roundi(seconds / dt):
		f.step(dt, freezing, glaze, rate)


func test_ice_freezes_up_to_the_glaze_and_comes_to_rest() -> void:
	var f := Ice.new(_floor(), true)
	assert_true(f.resting(), "nothing to do on dry ground")
	_run_for(f, 2.5, true, 0.5, 0.1)
	assert_almost_eq(f.ice_at(Vector3(5, 0, 4)), 0.25, 0.03, "a quarter of a glaze in a quarter of the time")
	_run_for(f, 5.0, true, 0.5, 0.1)
	assert_almost_eq(f.ice_at(Vector3(5, 0, 7)), 0.5, 1e-6, "up to the glaze and no further")
	_run_for(f, 1.0, true, 0.5, 0.1)
	assert_true(f.resting(), "at rest")
	assert_almost_eq(f.image.get_pixel(5, 4).r, 0.5, 1e-6, "what the shaders read")


func test_more_ice_than_the_glaze_holds_while_freezing_and_thaws_after() -> void:
	var f := Ice.new(_floor(), false)
	f.heat(Vector3(5.5, 0, 4.5), 1.5, -1.0, 1.0)
	_run_for(f, 5.0, true, 0.2, 0.1)
	assert_almost_eq(f.ice_at(Vector3(5, 0, 4)), 1.0, 1e-6, "held")
	_run_for(f, 5.0, false, 0.2, 0.1)
	assert_almost_eq(f.ice_at(Vector3(5, 0, 4)), 0.5, 0.02, "half thawed")


func test_ice_keeps_off_a_pool_and_takes_up_only_its_own_floor() -> void:
	var f := Ice.new(_floor(), false)
	f.keep_off([AABB(Vector3(0, -1, 0), Vector3(3, 2, 8))])
	f.fill(1.0)
	assert_eq(f.ice_at(Vector3(1, 0, 4)), 0.0, "none on the pool's bed")
	assert_eq(f.ice_at(Vector3(5, 0, 4)), 1.0, "beside it, frozen over")
	var cells := f.cells()
	cells[4 * 10 + 5] = 51
	cells[4 * 10 + 1] = 255
	f.set_cells(cells)
	assert_almost_eq(f.ice_at(Vector3(5, 0, 4)), 0.2, 1e-6, "another peer's cells")
	assert_eq(f.ice_at(Vector3(1, 0, 4)), 0.0, "but not on the pool")
	f.set_cells(PackedByteArray([1, 2, 3]))
	assert_almost_eq(f.ice_at(Vector3(5, 0, 4)), 0.2, 1e-6, "cells for some other floor ignored")
