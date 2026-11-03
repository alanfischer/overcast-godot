extends "res://tests/suite.gd"

const Weather = preload("res://addons/overcast/overcast_weather.gd")


class FakeSky:
	var storm := 0.0
	var flashes := 0

	func set_storm(amount: float) -> void:
		storm = amount

	func set_flash(_color: Color, _dir: Vector3) -> void:
		flashes += 1

	func horizon_color() -> Color:
		return Color(0.5, 0.5, 0.5)


## A floor 4 m by 2 m from (-2, -1): the west half roofed at 3 m, the east half open to 0.
func _roofed_floor() -> Dictionary:
	var img := Image.create_empty(4, 2, false, Image.FORMAT_RF)
	for y in 2:
		for x in 4:
			img.set_pixel(x, y, Color(3.0 if x < 2 else 0.0, 0, 0))
	return {"image": img, "origin": Vector3(-2, 0, -1), "size": Vector2(4, 2), "top": 10.0}


func test_rain_past_a_downpour_only_adds_drops() -> void:
	for rain in [1.0, 2.0, 6.0]:
		assert_almost_eq(Weather.heaviness(rain), 1.0, 1e-6, "rain %s is a downpour" % rain)
		for i in 20:
			var gap := Weather.strike_gap(rain)
			assert_true(gap >= Weather.STRIKE_GAP_HEAVY.x and gap <= Weather.STRIKE_GAP_HEAVY.y,
				"rain %s waits a downpour's gap between strikes (got %.1f)" % [rain, gap])
	assert_eq(Weather.heaviness(0.0), 0.0, "dry is dry")


func test_the_floor_is_read_from_its_min_corner() -> void:
	var w := Weather.new()
	w.set_rain_floor(_roofed_floor())
	assert_eq(w.floor_at(Vector3(-1.5, 0, -0.5)), 3.0, "the min corner's cell is the roof")
	assert_eq(w.floor_at(Vector3(1.5, 0, 0.5)), 0.0, "the far cell is open")
	assert_eq(w.floor_at(Vector3(2.5, 0, 0.0)), INF, "off the floor, no rain at any height")
	w.free()


func test_rain_sounds_muffled_under_the_roof() -> void:
	var w := Weather.new()
	assert_eq(w.rain_exposure(Vector3.ZERO), 1.0, "no floor: in the open everywhere")
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RF)
	img.fill(Color(0, 0, 0))
	for y in range(28, 36):
		for x in range(28, 36):
			img.set_pixel(x, y, Color(3, 0, 0))  # an 8 m roof at 3 m in the middle of 64 m
	w.set_rain_floor({"image": img, "origin": Vector3(-32, 0, -32), "size": Vector2(64, 64)})
	var under := w.rain_exposure(Vector3(0, 1.5, 0))
	var open := w.rain_exposure(Vector3(-14, 1.5, -14))
	assert_lt(under, 0.6, "under the roof most of the rain is out of reach (%.2f)" % under)
	assert_gt(open, 0.9, "out in the open it is all around (%.2f)" % open)
	w.free()


func test_rain_closes_the_sky_over_and_times_strikes() -> void:
	var w := Weather.new()
	_keep(w)
	var sky := FakeSky.new()
	w.sky = sky
	_root().add_child(w)
	var seeds: Array[int] = []
	w.struck.connect(func(s: int) -> void: seeds.append(s))
	w.rain = 1.0
	for i in 600:
		w._process(0.1)
	assert_almost_eq(sky.storm, 1.0, 1e-6, "a minute of downpour closes the sky over")
	assert_gt(seeds.size(), 2, "and lightning strikes (%d)" % seeds.size())
	w.rain = 0.0
	for i in 100:
		w._process(0.1)
	assert_almost_eq(sky.storm, 0.0, 1e-6, "and it clears once the rain stops")


func test_only_the_timing_peer_strikes() -> void:
	var w := Weather.new()
	_keep(w)
	w.times_strikes = false
	_root().add_child(w)
	var seeds: Array[int] = []
	w.struck.connect(func(s: int) -> void: seeds.append(s))
	w.rain = 1.0
	for i in 600:
		w._process(0.1)
	assert_eq(seeds.size(), 0, "a peer that does not time strikes waits to be told")


func test_wet_materials_are_found_by_their_shader() -> void:
	var wet := Shader.new()
	wet.code = 'shader_type spatial;\n#include "res://addons/overcast/shaders/wet.gdshaderinc"\nvoid fragment() {}'
	var dry := Shader.new()
	dry.code = "shader_type spatial;\nvoid fragment() {}"
	var root := Node3D.new()
	for shader in [wet, dry]:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mi.mesh.surface_set_material(0, mat)
		root.add_child(mi)
	var w := Weather.new()
	w.add_wet_materials(root, func(_mi: MeshInstance3D) -> float: return 0.4)
	assert_eq(w._wet_mats.size(), 1, "only the material that takes rain")
	assert_almost_eq(w._wet_mats[0].get_shader_parameter("puddle_scale"), 0.4, 1e-6, "pooling as asked")
	w.free()
	root.free()


## Fully featured out of the box: rain and thunder sound with nothing set.
func test_it_brings_its_own_rain_and_thunder() -> void:
	var w := Weather.new()
	_keep(w)
	_root().add_child(w)
	assert_ne(w.rain_stream, null, "its own rain")
	assert_true(w.rain_stream != null and w.rain_stream.loop, "which loops without a gap")
	assert_ne(w.thunder_stream, null, "and its own thunder")


## Open ground at 0, 20 m square in 1 m cells, with a 4 m roof at 5 m over its middle.
func _open_floor() -> Dictionary:
	var img := Image.create_empty(20, 20, false, Image.FORMAT_RF)
	img.fill(Color(0, 0, 0))
	for y in range(8, 12):
		for x in range(8, 12):
			img.set_pixel(x, y, Color(5, 0, 0))
	return {"image": img, "origin": Vector3(-10, 0, -10), "size": Vector2(20, 20)}


func _platform(at: Vector3) -> Node3D:
	var node := Node3D.new()
	_root().add_child(node)
	_keep(node)
	node.global_position = at
	return node


func test_a_moving_cover_keeps_the_rain_off_under_it() -> void:
	var w := Weather.new()
	_keep(w)
	_root().add_child(w)
	w.set_rain_floor(_open_floor())
	var lift := _platform(Vector3(-6, 3, -6))
	w.add_cover(lift, AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2)))  # a 2 m deck, top at +0.1
	w._update_covers()
	assert_almost_eq(w.floor_at(Vector3(-6, 0, -6)), 3.1, 0.026, "rain lands on the deck")
	assert_eq(w.floor_at(Vector3(-6, 0, -3.5)), 0.0, "beside it, on the ground")
	lift.global_position = Vector3(6, 3, 6)
	w._update_covers()
	assert_eq(w.floor_at(Vector3(-6, 0, -6)), 0.0, "where it was is open again")
	assert_almost_eq(w.floor_at(Vector3(6, 0, 6)), 3.1, 0.026, "and where it went is covered")
	lift.visible = false
	w._update_covers()
	assert_eq(w.floor_at(Vector3(6, 0, 6)), 0.0, "hidden, it covers nothing")
	lift.visible = true
	w._update_covers()
	assert_almost_eq(w.floor_at(Vector3(6, 0, 6)), 3.1, 0.026, "shown again, it does")
	lift.free()
	w._update_covers()
	assert_eq(w.floor_at(Vector3(6, 0, 6)), 0.0, "a freed cover lets the rain back")
	assert_eq(w._covers.size(), 0, "and is let go of")


func test_covers_leave_roofs_and_each_other_alone() -> void:
	var w := Weather.new()
	_keep(w)
	_root().add_child(w)
	w.set_rain_floor(_open_floor())
	var box := AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2))
	var under_roof := _platform(Vector3(0, 2, 0))
	w.add_cover(under_roof, box)
	var a := _platform(Vector3(-5, 3, 5))
	var b := _platform(Vector3(-4, 4, 5))
	w.add_cover(a, box)
	w.add_cover(b, box)
	w._update_covers()
	assert_eq(w.floor_at(Vector3(0, 0, 0)), 5.0, "a lift under a roof leaves the roof where rain stops")
	assert_almost_eq(w.floor_at(Vector3(-4.5, 0, 5)), 4.1, 0.026, "where two overlap, the higher catches it")
	b.global_position = Vector3(5, 4, -5)
	w._update_covers()
	assert_almost_eq(w.floor_at(Vector3(-4.5, 0, 5)), 3.1, 0.026, "the one that stayed is still stamped")
	w.remove_cover(a)
	assert_eq(w.floor_at(Vector3(-5, 0, 5)), 0.0, "removed by hand, open again")


func test_covers_restamp_only_for_a_step_that_shows() -> void:
	var w := Weather.new()
	_keep(w)
	_root().add_child(w)
	w.set_rain_floor(_open_floor())
	var lift := _platform(Vector3(-6.5, 3, -6.5))
	w.add_cover(lift, AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2)))
	w._update_covers()
	var uploads := [0]
	w._floor_tex.changed.connect(func() -> void: uploads[0] += 1)
	lift.global_position += Vector3(0.2, 0.01, 0.2)  # inside the same cells, under a step up
	w._update_covers()
	assert_eq(uploads[0], 0, "a nudge within a cell uploads nothing")
	lift.global_position += Vector3(1.0, 0.0, 0.0)
	w._update_covers(0.01)
	assert_eq(uploads[0], 0, "and a real move waits out the interval")
	w._update_covers(w.COVER_EVERY)
	assert_gt(uploads[0], 0, "then lands")
