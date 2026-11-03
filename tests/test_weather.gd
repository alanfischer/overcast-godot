extends "res://tests/suite.gd"

const Weather = preload("res://addons/overcast/overcast_weather.gd")


## A weather that draws and plays as on a client, though the suite runs headless.
func _weather() -> Weather:
	var w := Weather.new()
	w._presenting = true
	return w


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
	var w := _weather()
	w.set_rain_floor(_roofed_floor())
	assert_eq(w.floor_at(Vector3(-1.5, 0, -0.5)), 3.0, "the min corner's cell is the roof")
	assert_eq(w.floor_at(Vector3(1.5, 0, 0.5)), 0.0, "the far cell is open")
	assert_eq(w.floor_at(Vector3(2.5, 0, 0.0)), INF, "off the floor, no rain at any height")
	w.free()


func test_rain_sounds_muffled_under_the_roof() -> void:
	var w := _weather()
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
	var w := _weather()
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
	var w := _weather()
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
	var w := _weather()
	w.add_wet_materials(root, func(_mi: MeshInstance3D) -> float: return 0.4)
	assert_eq(w._wet_mats.size(), 1, "only the material that takes rain")
	assert_almost_eq(w._wet_mats[0].get_shader_parameter("puddle_scale"), 0.4, 1e-6, "pooling as asked")
	w.free()
	root.free()


## Fully featured out of the box: rain and thunder sound with nothing set.
func test_it_brings_its_own_rain_and_thunder() -> void:
	var w := _weather()
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
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.set_rain_floor(_open_floor())
	var lift := _platform(Vector3(-6, 3, -6))
	w.add_cover(lift, AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2)))  # a 2 m deck, top at +0.1
	w._update_covers()
	assert_almost_eq(w.floor_at(Vector3(-6, 0, -6)), 3.1, 1e-4, "rain lands on the deck")
	assert_eq(w.floor_at(Vector3(-6, 0, -3.5)), 0.0, "beside it, on the ground")
	lift.global_position = Vector3(6, 3, 6)
	w._update_covers()
	assert_eq(w.floor_at(Vector3(-6, 0, -6)), 0.0, "where it was is open again")
	assert_almost_eq(w.floor_at(Vector3(6, 0, 6)), 3.1, 1e-4, "and where it went is covered")
	lift.visible = false
	w._update_covers()
	assert_eq(w.floor_at(Vector3(6, 0, 6)), 0.0, "hidden, it covers nothing")
	lift.visible = true
	w._update_covers()
	assert_almost_eq(w.floor_at(Vector3(6, 0, 6)), 3.1, 1e-4, "shown again, it does")
	lift.free()
	w._update_covers()
	assert_eq(w.floor_at(Vector3(6, 0, 6)), 0.0, "a freed cover lets the rain back")
	assert_eq(w._covers.size(), 0, "and is let go of")


func test_covers_leave_roofs_and_each_other_alone() -> void:
	var w := _weather()
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
	assert_almost_eq(w.floor_at(Vector3(-4.5, 0, 5)), 4.1, 1e-4, "where two overlap, the higher catches it")
	b.global_position = Vector3(5, 4, -5)
	w._update_covers()
	assert_almost_eq(w.floor_at(Vector3(-4.5, 0, 5)), 3.1, 1e-4, "the one that stayed is still stamped")
	w.remove_cover(a)
	assert_eq(w.floor_at(Vector3(-5, 0, 5)), 0.0, "removed by hand, open again")


func test_covers_restamp_only_for_a_step_that_shows() -> void:
	var w := _weather()
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


## Triangles for a flat rectangle at height y, corners a and b on X/Z, in the cover's frame.
func _quad(a: Vector2, b: Vector2, y: float) -> PackedVector3Array:
	var p := [Vector3(a.x, y, a.y), Vector3(b.x, y, a.y), Vector3(b.x, y, b.y), Vector3(a.x, y, b.y)]
	return PackedVector3Array([p[0], p[1], p[2], p[0], p[2], p[3]])


func _covered(w: Node3D) -> Array[int]:
	var cells: Array[int] = []
	for i in w._heights.size():
		if w._heights[i] != w._baked[i]:
			cells.append(i)
	return cells


func test_a_turned_beam_covers_its_diagonal_not_its_bounds() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.set_rain_floor(_open_floor())
	var beam := _platform(Vector3(-5, 3, 5))
	beam.rotation.y = PI / 4
	w.add_cover(beam, _quad(Vector2(-4, -0.25), Vector2(4, 0.25), 0.0))  # 8 m by 0.5 m
	w._update_covers()
	var cells := _covered(w)
	assert_gt(cells.size(), 8, "it lands all along its length (%d cells)" % cells.size())
	assert_lt(cells.size(), 30, "and not over the 6 m square around it a box would (%d)" % cells.size())
	assert_almost_eq(w.floor_at(Vector3(-5, 0, 5)), 3.0, 1e-4, "at its height")


func test_an_l_shape_leaves_its_corner_open() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.set_rain_floor(_open_floor())
	var roof := _platform(Vector3(-5, 3, -5))
	var tris := _quad(Vector2(-3, -3), Vector2(3, -1), 0.0)  # along the top
	tris.append_array(_quad(Vector2(-3, -1), Vector2(-1, 3), 0.0))  # down the left
	w.add_cover(roof, tris)
	w._update_covers()
	assert_almost_eq(w.floor_at(Vector3(-7.5, 0, -2.5)), 3.0, 1e-4, "under the leg")
	assert_eq(w.floor_at(Vector3(-3, 0, -3)), 0.0, "the inside corner stays open")


func test_a_pitched_roof_stops_rain_at_its_slope() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.set_rain_floor(_open_floor())
	var shed := _platform(Vector3(5, 3, -5))
	# Eaves at 3 m along x = -3, rising to 5 m along x = +3.
	var a := Vector3(-3, 0, -3)
	var b := Vector3(3, 2, -3)
	var c := Vector3(3, 2, 3)
	var d := Vector3(-3, 0, 3)
	w.add_cover(shed, PackedVector3Array([a, b, c, a, c, d]))
	w._update_covers()
	var low := w.floor_at(Vector3(2.5, 0, -5))
	var high := w.floor_at(Vector3(7.5, 0, -5))
	assert_lt(low, 3.6, "near the eaves rain stops low (%.2f)" % low)
	assert_gt(high, 4.4, "near the ridge, high (%.2f)" % high)


func test_a_cover_defaults_to_its_own_meshes() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.set_rain_floor(_open_floor())
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false  # moved by hand here, not by a physics step
	_root().add_child(body)
	_keep(body)
	body.global_position = Vector3(5, 3, 5)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2, 0.2, 2)
	mi.mesh = mesh
	body.add_child(mi)
	var rider := AnimatableBody3D.new()  # another mover parked on it is not part of it
	var rider_mesh := MeshInstance3D.new()
	rider_mesh.mesh = BoxMesh.new()
	rider_mesh.position.y = 5.0
	rider.add_child(rider_mesh)
	body.add_child(rider)
	w.add_cover(body)
	w._update_covers()
	assert_almost_eq(w.floor_at(Vector3(5, 0, 5)), 3.1, 1e-4, "the top of its own mesh")


func test_a_cover_that_only_slides_reuses_its_raster() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.set_rain_floor(_open_floor())
	var train := _platform(Vector3(-12, 3, 5))  # starts half off the floor's west edge
	w.add_cover(train, _quad(Vector2(-2, -0.5), Vector2(2, 0.5), 0.0))
	w._update_covers()
	var first: Transform3D = w._covers[train].raster_xform
	assert_almost_eq(w.floor_at(Vector3(-9.5, 0, 5)), 3.0, 1e-4, "the part on the floor covers")
	train.global_position = Vector3(4, 4, 5)
	w._update_covers()
	assert_eq(w._covers[train].raster_xform, first, "a slide is the same raster moved")
	assert_almost_eq(w.floor_at(Vector3(2.5, 0, 5)), 4.0, 1e-4, "all of it, once on the floor")
	assert_almost_eq(w.floor_at(Vector3(5.5, 0, 5)), 4.0, 1e-4, "both ends")
	assert_eq(w.floor_at(Vector3(-9.5, 0, 5)), 0.0, "and gone from where it was")
	train.rotation.y = PI / 2
	w._update_covers()
	assert_ne(w._covers[train].raster_xform, first, "a turn rasterizes it afresh")
	assert_almost_eq(w.floor_at(Vector3(4, 0, 6.5)), 4.0, 1e-4, "now lying north-south")
	assert_eq(w.floor_at(Vector3(5.5, 0, 5)), 0.0, "and no longer east-west")


func test_turning_covers_share_out_the_work() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.set_rain_floor(_open_floor())
	var spinners: Array[Node3D] = []
	for i in 6:
		var s := _platform(Vector3(-7.5 + i * 3, 3, -7.5))
		w.add_cover(s, _quad(Vector2(-1, -0.2), Vector2(1, 0.2), 0.0))
		spinners.append(s)
	w._update_covers()
	for s in spinners:
		s.rotation.y = PI / 2
	w.cover_budget_usec = 0  # out of time after the first
	var turned := func() -> int:
		var n := 0
		for s in spinners:
			if w._covers[s].xform.basis.is_equal_approx(s.global_transform.basis):
				n += 1
		return n
	w._update_covers()
	assert_eq(turned.call(), 1, "one turns per tick when the budget is spent")
	w._update_covers()
	assert_eq(turned.call(), 2, "the next tick, the next one")
	for i in 4:
		w._update_covers()
	assert_eq(turned.call(), 6, "and none is left behind")


func test_settle_goes_straight_to_the_weather_rain_is_heading_for() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain = 1.0
	w.settle()
	assert_almost_eq(w.storm, 1.0, 1e-6, "a downpour's sky, closed over")
	assert_eq(w._wetness, 1.0, "the ground soaked")
	assert_almost_eq(w._puddles, 1.0, 1e-6, "and pooled")
	w.rain = 0.0
	w.settle()
	assert_eq(w.storm, 0.0, "dry: clear")
	assert_eq(w._wetness, 0.0, "and dry ground")


func test_a_dedicated_server_times_strikes_and_draws_nothing() -> void:
	var w := Weather.new()  # as the headless suite finds it: no one to draw for
	_keep(w)
	_root().add_child(w)
	var seeds: Array[int] = []
	w.struck.connect(func(s: int) -> void: seeds.append(s))
	w.rain = 1.0
	for i in 600:
		w._process(0.1)
	assert_gt(seeds.size(), 2, "strikes are still timed (%d), for the peers that draw them" % seeds.size())
	assert_eq(w.get_child_count(), 0, "and nothing is built to draw or play them here")
