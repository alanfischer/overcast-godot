extends "res://tests/suite.gd"

const Weather = preload("res://addons/overcast/overcast_weather.gd")
const SkyScript = preload("res://addons/overcast/overcast_sky.gd")
const RainFloor = preload("res://addons/overcast/overcast_rain_floor.gd")
const Globals = preload("res://addons/overcast/overcast_globals.gd")
const Live = preload("res://addons/overcast/rain_floor_live.gd")
const Cycle = preload("res://addons/overcast/overcast_cycle.gd")


## A weather that draws and plays as on a client, though the suite runs headless.
func _weather() -> Weather:
	var w := Weather.new()
	w.presenting = true
	return w


class FakeSky extends SkyScript:
	var flashes := 0
	var flash := Color.BLACK

	func set_flash(color: Color, dir: Vector3) -> void:
		super(color, dir)
		flashes += 1
		flash = color


## A floor 4 m by 2 m from (-2, -1): the west half roofed at 3 m, the east half open to 0.
func _roofed_floor() -> RainFloor:
	var img := Image.create_empty(4, 2, false, Image.FORMAT_RF)
	for y in 2:
		for x in 4:
			img.set_pixel(x, y, Color(3.0 if x < 2 else 0.0, 0, 0))
	return RainFloor.create(img, Vector3(-2, 0, -1), Vector2(4, 2), 10.0)


func test_rain_past_a_downpour_only_adds_drops() -> void:
	var w := _weather()
	for rain in [1.0, 2.0, 6.0]:
		assert_almost_eq(Weather.heaviness(rain), 1.0, 1e-6, "rain %s is a downpour" % rain)
		for i in 20:
			var gap := w.strike_gap(rain)
			assert_true(gap >= w.strike_gap_heavy.x and gap <= w.strike_gap_heavy.y,
				"rain %s waits a downpour's gap between strikes (got %.1f)" % [rain, gap])
	assert_eq(Weather.heaviness(0.0), 0.0, "dry is dry")
	w.free()


func test_the_floor_is_read_from_its_min_corner() -> void:
	var w := _weather()
	w.rain_floor = _roofed_floor()
	assert_eq(w.floor_at(Vector3(-1.5, 0, -0.5)), 3.0, "the min corner's cell is the roof")
	assert_eq(w.floor_at(Vector3(1.5, 0, 0.5)), 0.0, "the far cell is open")
	assert_eq(w.floor_at(Vector3(2.5, 0, 0.0)), INF, "off the floor, no rain at any height")
	w.free()


func test_rain_can_fall_past_the_floors_edges() -> void:
	var w := _weather()
	_keep(w)
	w.rain_floor = _roofed_floor()
	_root().add_child(w)
	assert_eq(Globals.value("overcast_rain_beyond_floor"), false, "by default no rain falls off the floor")
	w.rain_beyond_floor = true
	assert_eq(w.floor_at(Vector3(2.5, 0, 0.0)), -INF, "on, it falls all the way down there")
	assert_eq(w.floor_at(Vector3(-1.5, 0, -0.5)), 3.0, "and the roof still keeps it off")
	assert_eq(Globals.value("overcast_rain_beyond_floor"), true, "so the shaders say")
	_root().remove_child(w)
	assert_eq(Globals.value("overcast_rain_beyond_floor"), false, "and gone, it leaves the default")


func test_rain_sounds_muffled_under_the_roof() -> void:
	var w := _weather()
	assert_eq(w.rain_exposure(Vector3.ZERO), 1.0, "no floor: in the open everywhere")
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RF)
	img.fill(Color(0, 0, 0))
	for y in range(28, 36):
		for x in range(28, 36):
			img.set_pixel(x, y, Color(3, 0, 0))  # an 8 m roof at 3 m in the middle of 64 m
	w.rain_floor = RainFloor.create(img, Vector3(-32, 0, -32), Vector2(64, 64))
	var under := w.rain_exposure(Vector3(0, 1.5, 0))
	var open := w.rain_exposure(Vector3(-14, 1.5, -14))
	assert_lt(under, 0.6, "under the roof most of the rain is out of reach (%.2f)" % under)
	assert_gt(open, 0.9, "out in the open it is all around (%.2f)" % open)
	w.free()


func test_rain_closes_the_sky_over_and_times_strikes() -> void:
	var w := _weather()
	_keep(w)
	var sky := FakeSky.new({"drawing": false})
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


func test_the_rain_reaches_wet_ground_through_the_globals() -> void:
	var w := _weather()
	_keep(w)
	w.rain_floor = _roofed_floor()
	_root().add_child(w)
	assert_eq(Globals.value("overcast_has_rain_floor"), true, "the floor goes to every shader")
	assert_eq(Globals.value("overcast_rain_floor"), w._live.texture, "as the texture covers stamp")
	assert_eq(Globals.value("overcast_rain_top"), 10.0, "with its top")
	w.rain = 1.0
	w.settle()
	w._process(0.1)
	assert_eq(Globals.value("overcast_wetness"), 1.0, "a settled downpour has soaked the ground")
	assert_eq(Globals.value("overcast_puddles"), 1.0, "and filled the puddles")
	w.wet_ground = false
	w._process(w.dry_time)
	assert_eq(Globals.value("overcast_wetness"), 0.0, "with wet ground off it dries")
	_root().remove_child(w)
	assert_eq(Globals.value("overcast_has_rain_floor"), false, "gone, it leaves no floor behind")
	assert_eq(Globals.value("overcast_wetness"), 0.0, "and no wet ground")


func test_wetness_set_from_outside_is_drawn() -> void:
	var w := _weather()
	_keep(w)
	w.rain_floor = _roofed_floor()
	_root().add_child(w)
	w.soaks = false
	w.wetness = 0.5
	w._process(0.1)
	assert_almost_eq(Globals.value("overcast_wetness"), 0.5, 1.0 / 255.0, "a server's wetness is drawn")
	w.wetness = 0.0
	w._process(0.1)
	assert_eq(Globals.value("overcast_wetness"), 0.0, "and dry again when it says so, with nothing falling")


func test_wet_ground_comes_round_to_a_turned_wind_as_it_soaks() -> void:
	var w := _weather()
	_keep(w)
	w.rain_floor = _roofed_floor()
	_root().add_child(w)
	w.wind = Vector3(9, 0, 0)
	w._process(0.1)
	var east: Vector2 = Globals.value("overcast_rain_slant")
	assert_eq(Globals.value("overcast_ground_slant"), Vector4(east.x, east.y, east.x, east.y),
		"dry, the ground takes the wind's slant at once")
	assert_eq(Globals.value("overcast_ground_shift"), 1.0, "with nothing to fade")
	w.rain = 1.0
	w.settle()
	w._process(0.1)
	east = Globals.value("overcast_rain_slant")  # drops fall faster in a downpour
	w.wind = Vector3(-9, 0, 0)
	w._process(0.1)
	var west: Vector2 = Globals.value("overcast_rain_slant")
	assert_eq(Globals.value("overcast_ground_slant"), Vector4(east.x, east.y, west.x, west.y),
		"wet, it fades from the old slant to the new")
	assert_lt(Globals.value("overcast_ground_shift"), 0.1, "beginning now")
	w._process(w.soak_time * 0.5)
	assert_almost_eq(Globals.value("overcast_ground_shift"), 0.5, 0.01, "half round in half the soak")
	w.wind = Vector3(0, 0, 9)
	w._process(0.1)
	assert_eq(Globals.value("overcast_ground_slant"), Vector4(east.x, east.y, west.x, west.y),
		"a wind that turns again waits for this turn to finish")
	w._process(w.soak_time)
	w._process(0.1)
	var north: Vector2 = Globals.value("overcast_rain_slant")
	assert_eq(Globals.value("overcast_ground_slant"), Vector4(west.x, west.y, north.x, north.y),
		"then turns to it")
	w._process(w.soak_time)
	assert_eq(Globals.value("overcast_ground_shift"), 1.0, "and comes all the way round")
	_root().remove_child(w)
	assert_eq(Globals.value("overcast_ground_shift"), 1.0, "gone, it leaves the default")
	assert_eq(Globals.value("overcast_ground_slant"), Vector4.ZERO, "slant and all")


func test_a_wind_still_turning_retargets_a_turn_just_begun() -> void:
	var w := _weather()
	_keep(w)
	w.rain_floor = _roofed_floor()
	_root().add_child(w)
	w.rain = 1.0
	w.settle()
	w._process(0.1)
	var calm: Vector4 = Globals.value("overcast_ground_slant")
	for speed in [1.0, 4.0, 9.0]:
		w.wind = Vector3(speed, 0, 0)
		w._process(0.05)
	var slant: Vector2 = Globals.value("overcast_rain_slant")
	assert_eq(Globals.value("overcast_ground_slant"), Vector4(calm.z, calm.w, slant.x, slant.y),
		"a wind swept up over a few frames is followed to where it ends")


func test_snow_falls_as_flakes_and_lies() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	var seeds: Array[int] = []
	w.struck.connect(func(s: int) -> void: seeds.append(s))
	w.rain = 1.0
	w.snow = 1.0
	assert_eq(w.rainfall(), 0.0, "all of it falls as snow")
	assert_eq(w._drops.multimesh.visible_instance_count, 0, "no drops")
	assert_eq(w._flakes.multimesh.visible_instance_count, w.flakes_heavy, "a blizzard's flakes")
	for i in int(w.snow_time * 10.0) + 10:
		w._process(0.1)
	assert_true(w._flakes.visible and not w._drops.visible, "the flakes are drawn, the drops not")
	assert_almost_eq(w.storm, 1.0, 1e-6, "a blizzard closes the sky over as a downpour does")
	assert_eq(seeds.size(), 0, "and does not thunder")
	assert_eq(Globals.value("overcast_snow_cover"), 1.0, "in snow_time it has covered the ground")
	assert_eq(Globals.value("overcast_wetness"), 0.0, "which stays dry under it")
	assert_false(w._rain_audio.playing, "and quiet")
	w.rain = 0.0
	w._process(w.melt_time * 0.5)
	assert_almost_eq(Globals.value("overcast_snow_cover"), 0.5, 0.01, "once it stops, it melts")
	assert_gt(Globals.value("overcast_wetness"), 0.0, "and wets the ground it lay on")
	w.rain = 1.0
	w.snow = 0.0
	w._process(w.melt_time / 8.0)
	assert_eq(Globals.value("overcast_snow_cover"), 0.0, "rain washes the rest away fast")
	_root().remove_child(w)
	assert_eq(Globals.value("overcast_snow_cover"), 0.0, "and gone, it leaves none behind")


## 30 m by 20 m of open ground at 0, a cell a metre, with a wall 2 m high across it at x 10.
func _walled_floor() -> RainFloor:
	var img := Image.create_empty(30, 20, false, Image.FORMAT_RF)
	img.fill_rect(Rect2i(10, 4, 1, 12), Color(2.0, 0, 0))
	return RainFloor.create(img, Vector3.ZERO, Vector2(30, 20), 10.0)


func test_snow_drifts_behind_a_wall_in_a_wind() -> void:
	var w := _weather()
	_keep(w)
	w.rain_floor = _walled_floor()
	_root().add_child(w)
	w.rain = 1.0
	w.snow = 1.0
	w.wind = Vector3(10, 0, 0)
	w.settle()
	w.bake_drifts()
	var drifts: MeshInstance3D = w.get_node("SnowDrifts")
	assert_true(drifts.top_level, "drawn in the world, wherever the weather is")
	assert_true(drifts.visible, "while the snow lies")
	var mesh: ArrayMesh = drifts.mesh
	assert_true(mesh != null, "a heap behind the wall")
	var lee: float = w.snow_depth_at(Vector3(11.5, 0, 10.5))
	assert_gt(lee - Weather.DRIFT_LAYER, 0.8, "heaped deep against its lee (%s m of snow)" % lee)
	assert_true(mesh.custom_aabb.end.y >= lee - Weather.DRIFT_LAYER, "and its bounds reach the top of the heap")
	assert_eq(Globals.value("overcast_has_snow_field"), true, "the field goes to every shader")
	assert_eq(Globals.value("overcast_snow_field"), w._field.texture, "as its texture")
	w.rain = 0.0
	for i in 100:
		w._process(w.melt_time / 50.0)
	assert_false(drifts.visible, "melted, nothing is drawn")
	assert_eq(w.snow_depth_at(Vector3(11.5, 0, 10.5)), 0.0, "and none lies")


func test_snow_drifts_bake_off_the_main_thread_as_the_wind_turns() -> void:
	var w := _weather()
	_keep(w)
	w.rain_floor = _walled_floor()
	_root().add_child(w)
	w.rain = 1.0
	w.snow = 1.0
	w.settle()
	for i in 200:
		w._process(0.05)
		if w._drift_task < 0 and w.has_node("SnowDrifts"):
			break
		OS.delay_msec(5)
	assert_true(w.has_node("SnowDrifts"), "baked for the floor once snow lies")
	assert_eq(w.get_node("SnowDrifts").mesh, null, "in a calm nothing heaps up past the even layer")
	w.wind = Vector3(10, 0, 0)
	w._process(0.05)
	assert_eq(w._drift_task, -1, "a new wind waits to hold")
	for i in 400:
		w._process(0.05)
		if w._drift_task < 0 and w.get_node("SnowDrifts").mesh != null:
			break
		OS.delay_msec(5)
	assert_true(w.get_node("SnowDrifts").mesh != null, "then the drifts are baked again for it")


func test_the_snow_comes_round_to_a_turned_wind() -> void:
	var w := _weather()
	_keep(w)
	w.rain_floor = _walled_floor()
	_root().add_child(w)
	w.rain = 1.0
	w.snow = 1.0
	w.wind = Vector3(10, 0, 0)
	w.settle()
	w.bake_drifts()
	var east := Vector3(11.5, 0, 10.5)
	var west := Vector3(8.5, 0, 10.5)
	var deep: float = w.snow_depth_at(east)
	assert_gt(deep, w.snow_depth_at(west) + 0.5, "drifted in the east wind's lee")
	w.wind = Vector3(-10, 0, 0)
	for i in 400:
		w._process(0.05)
		if w._drift_task < 0 and w._drift_wind.x < 0.0:
			break
		OS.delay_msec(5)
	assert_eq(w._drift_task, -1, "baked again for the west wind")
	var uvs: PackedVector2Array = w.get_node("SnowDrifts").mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var has := {}
	for uv in uvs:
		has[uv] = true
	assert_true(has.has(Vector2(11, 10)) and has.has(Vector2(8, 10)),
		"the mesh reaches over the old drift and the new")
	for i in 100:
		w._process(w.snow_time / 100.0)
	assert_lt(w.snow_depth_at(east), deep - 0.5, "the old drift worn down")
	assert_gt(w.snow_depth_at(west), deep - 0.3, "and the new one heaped up, as the snow settles")


func test_snowless_boxes_hold_for_every_floor() -> void:
	var w := _weather()
	_keep(w)
	w.add_snowless(AABB(Vector3(20, -1, 0), Vector3(5, 2, 20)))
	w.rain_floor = _walled_floor()
	_root().add_child(w)
	w.rain = 1.0
	w.snow = 1.0
	w.settle()
	assert_eq(w.snow_depth_at(Vector3(22.5, 0, 10.5)), 0.0, "a box given before the floor keeps it bare")
	assert_gt(w.snow_depth_at(Vector3(15.5, 0, 10.5)), 0.0, "and only there")
	w.add_snowless(AABB(Vector3(0, -1, 0), Vector3(5, 2, 20)))
	assert_eq(w.snow_depth_at(Vector3(2.5, 0, 10.5)), 0.0, "one given after it at once")


## A blast melts the snow where it lands, and the snow settling fills it in again.
func test_a_melt_digs_out_the_snow() -> void:
	var w := _weather()
	_keep(w)
	w.rain_floor = _walled_floor()
	_root().add_child(w)
	w.rain = 1.0
	w.snow = 1.0
	w.settle()
	var at := Vector3(20.5, 0.1, 10.5)
	w.melt(at, 2.0)
	assert_eq(w.snow_depth_at(at), 0.0, "bare where it struck")
	for i in 100:
		w._process(w.snow_time / 50.0)
	assert_almost_eq(w.snow_depth_at(at), Weather.DRIFT_LAYER, 1e-4, "snowed over again")
	var headless := Weather.new()
	headless.presenting = false
	_keep(headless)
	headless.rain_floor = _walled_floor()
	_root().add_child(headless)
	headless.melt(at, 2.0)
	assert_eq(headless._field, null, "a peer that draws nothing keeps no snow to melt")
	headless.rain = 1.0
	headless.snow = 1.0
	headless.settle()
	assert_almost_eq(headless.snow_depth_at(at), Weather.DRIFT_LAYER, 1e-6, "but says how deep it lies, evenly")


func test_a_snow_storm_greys_the_sky_pale() -> void:
	var w := _weather()
	_keep(w)
	var sky := FakeSky.new({"drawing": false})
	w.sky = sky
	_root().add_child(w)
	w.rain = 1.0
	w.settle()
	w._process(0.1)
	var dark := SkyScript.luma(sky.horizon_now())
	w.snow = 1.0
	for i in 100:
		w._process(0.1)
	assert_eq(sky.snowy, 1.0, "the sky follows the snow")
	assert_gt(SkyScript.luma(sky.horizon_now()), dark * 1.5, "paler at the horizon than a rain storm's")
	assert_eq(w._haze_base(sky, Color.WHITE), sky.horizon_now(), "and the haze fades into it")


func test_sleet_is_some_of_each() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain = 1.0
	w.snow = 0.25
	assert_almost_eq(w.rainfall(), 0.75, 1e-6, "three quarters rain")
	assert_almost_eq(w.snowfall(), 0.25, 1e-6, "a quarter snow")
	assert_gt(w._drops.multimesh.visible_instance_count, 0, "drops")
	assert_gt(w._flakes.multimesh.visible_instance_count, 0, "and flakes")
	w.settle()
	assert_eq(w._snow_lying, 0.0, "mostly rain, so it does not lie")
	w.snow = 0.75
	w.settle()
	assert_eq(w._snow_lying, 1.0, "mostly snow, so it does")
	w.lying_snow = false
	w._process(w.melt_time)
	assert_eq(Globals.value("overcast_snow_cover"), 0.0, "unless lying snow is off")


func test_a_headless_peer_answers_with_its_covers() -> void:
	var w := Weather.new()
	w.presenting = false
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _open_floor()
	var lift := _platform(Vector3(-6, 3, -6))
	w.add_cover(lift, AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2)))
	assert_almost_eq(w.floor_at(Vector3(-6, 0, -6)), 3.1, 1e-4, "a server sees the lift keep rain off")
	lift.global_position = Vector3(6, 3, 6)
	assert_eq(w.floor_at(Vector3(-6, 0, -6)), 0.0, "and sees it move on, asked again")
	assert_eq(w._live.texture, null, "with no texture to upload")


func test_a_headless_peer_soaks_and_dries_the_ground() -> void:
	var w := Weather.new()
	w.presenting = false
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _roofed_floor()
	w.rain = 1.0
	w._process(w.soak_time / 2.0)
	assert_almost_eq(w.wetness, 0.5, 1e-4, "a server soaks the ground as a client does")
	w.rain = 0.0
	w._process(w.dry_time / 4.0)
	assert_almost_eq(w.wetness, 0.25, 1e-4, "and dries it")
	w.wetness = 2.0
	assert_eq(w.wetness, 1.0, "set from another peer, it is held to 0..1")
	w._process(w.dry_time / 2.0)
	assert_almost_eq(w.wetness, 0.5, 1e-4, "and dries on from there")
	w.soaks = false
	w.rain = 1.0
	w.wetness = 0.25
	w._process(w.soak_time)
	assert_eq(w.wetness, 0.25, "with soaks off it holds what it was set to")


func test_rain_falls_on_open_ground_and_not_under_the_roof() -> void:
	var w := Weather.new()
	w.presenting = false
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _roofed_floor()
	assert_true(w.rains_on(Vector3(1, 0, 0)), "open ground takes rain")
	assert_true(w.rains_on(Vector3(1, -0.9, 0)), "as does ground a little under the floor: a slope")
	assert_false(w.rains_on(Vector3(-1, 0, 0)), "ground under the roof does not")
	assert_true(w.rains_on(Vector3(-1, 3, 0)), "the roof does")
	assert_false(w.rains_on(Vector3(5, 0, 0)), "nor off the floor")
	w.rain_beyond_floor = true
	assert_true(w.rains_on(Vector3(5, 0, 0)), "unless rain falls beyond it")


func test_the_rain_takes_the_skys_light() -> void:
	var w := _weather()
	_keep(w)
	var sky := FakeSky.new({"drawing": false, "time_of_day": 0.0})
	w.sky = sky
	_root().add_child(w)
	assert_eq(w.scene_light(sky), sky.scene_light(), "the sky's light at midnight")
	w.light_from_sky = false
	w.sky_light = Color(0.5, 0.5, 0.5)
	assert_eq(w.scene_light(sky), Color(0.5, 0.5, 0.5), "or the game's own")


func test_the_area_is_the_nodes_own() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.area = AABB(Vector3(-1, 0, -1), Vector3(2, 1, 2))
	w.position = Vector3(10, 0, 0)
	assert_eq(w.world_area(), AABB(Vector3(9, 0, -1), Vector3(2, 1, 2)), "it moves with the node")


func test_it_says_what_it_is_missing() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	var warnings := w._get_configuration_warnings()
	assert_eq(warnings.size(), 2, "no sky and no rain floor: %s" % [warnings])
	w.sky = FakeSky.new({"drawing": false})
	w.rain_floor = _open_floor()
	assert_eq(w._get_configuration_warnings().size(), 0, "given both, nothing")


## Fully featured out of the box: rain and thunder sound with nothing set.
func test_it_brings_its_own_rain_and_thunder() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	var stream: AudioStream = w._rain_audio.stream
	assert_ne(stream, null, "its own rain")
	assert_true(stream != null and stream.loop, "which loops without a gap")
	assert_ne(Weather._sound("thunder"), null, "and its own thunder")
	assert_eq(w.rain_stream, null, "left unset, so a scene saved in the editor keeps none")


## Open ground at 0, 20 m square in 1 m cells, with a 4 m roof at 5 m over its middle.
func _open_floor() -> RainFloor:
	var img := Image.create_empty(20, 20, false, Image.FORMAT_RF)
	img.fill(Color(0, 0, 0))
	for y in range(8, 12):
		for x in range(8, 12):
			img.set_pixel(x, y, Color(5, 0, 0))
	return RainFloor.create(img, Vector3(-10, 0, -10), Vector2(20, 20))


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
	w.rain_floor = _open_floor()
	var lift := _platform(Vector3(-6, 3, -6))
	w.add_cover(lift, AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2)))  # a 2 m deck, top at +0.1
	w._live.update()
	assert_almost_eq(w.floor_at(Vector3(-6, 0, -6)), 3.1, 1e-4, "rain lands on the deck")
	assert_eq(w.floor_at(Vector3(-6, 0, -3.5)), 0.0, "beside it, on the ground")
	lift.global_position = Vector3(6, 3, 6)
	w._live.update()
	assert_eq(w.floor_at(Vector3(-6, 0, -6)), 0.0, "where it was is open again")
	assert_almost_eq(w.floor_at(Vector3(6, 0, 6)), 3.1, 1e-4, "and where it went is covered")
	lift.visible = false
	w._live.update()
	assert_eq(w.floor_at(Vector3(6, 0, 6)), 0.0, "hidden, it covers nothing")
	lift.visible = true
	w._live.update()
	assert_almost_eq(w.floor_at(Vector3(6, 0, 6)), 3.1, 1e-4, "shown again, it does")
	lift.free()
	w._live.update()
	assert_eq(w.floor_at(Vector3(6, 0, 6)), 0.0, "a freed cover lets the rain back")
	assert_eq(w._live.covers.size(), 0, "and is let go of")


func test_covers_leave_roofs_and_each_other_alone() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _open_floor()
	var box := AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2))
	var under_roof := _platform(Vector3(0, 2, 0))
	w.add_cover(under_roof, box)
	var a := _platform(Vector3(-5, 3, 5))
	var b := _platform(Vector3(-4, 4, 5))
	w.add_cover(a, box)
	w.add_cover(b, box)
	w._live.update()
	assert_eq(w.floor_at(Vector3(0, 0, 0)), 5.0, "a lift under a roof leaves the roof where rain stops")
	assert_almost_eq(w.floor_at(Vector3(-4.5, 0, 5)), 4.1, 1e-4, "where two overlap, the higher catches it")
	b.global_position = Vector3(5, 4, -5)
	w._live.update()
	assert_almost_eq(w.floor_at(Vector3(-4.5, 0, 5)), 3.1, 1e-4, "the one that stayed is still stamped")
	w.remove_cover(a)
	assert_eq(w.floor_at(Vector3(-5, 0, 5)), 0.0, "removed by hand, open again")


func test_adding_a_cover_again_lets_go_of_its_old_stamp() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _open_floor()
	var box := AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2))
	var lift := _platform(Vector3(-6, 3, -6))
	w.add_cover(lift, box)
	w._live.update()
	lift.global_position = Vector3(6, 3, 6)
	w.add_cover(lift, box)
	w._live.update()
	assert_eq(w.floor_at(Vector3(-6, 0, -6)), 0.0, "where it was is open again")
	assert_almost_eq(w.floor_at(Vector3(6, 0, 6)), 3.1, 1e-4, "and it covers where it is")
	assert_true(w.has_cover(lift), "still one cover")


func test_the_sun_is_let_go_of_as_it_was() -> void:
	var first := DirectionalLight3D.new()
	first.light_energy = 2.0
	first.rotation = Vector3(-0.5, 0.3, 0.0)
	var basis := first.basis
	_keep(first)
	_root().add_child(first)
	var second := DirectionalLight3D.new()
	_keep(second)
	_root().add_child(second)
	var w := _weather()
	_keep(w)
	w.sky = FakeSky.new({"drawing": false})
	w.sun = first
	_root().add_child(w)
	w.rain = 1.0
	w.settle()
	w._process(0.1)
	assert_lt(first.light_energy, 2.0, "the storm dims the sun")
	assert_false(first.basis.is_equal_approx(basis), "and it turns with the time")
	w.sun = second
	assert_almost_eq(first.light_energy, 2.0, 1e-6, "replaced, it gets its own light back")
	assert_true(first.basis.is_equal_approx(basis), "and its own direction")
	w._process(0.1)
	assert_lt(second.light_energy, 1.0, "the new sun is dimmed from its own light")
	_root().remove_child(w)
	assert_almost_eq(second.light_energy, 1.0, 1e-6, "and let go of when the weather leaves")
	_root().add_child(w)


func test_setting_the_cycle_back_plans_it_afresh() -> void:
	var reference := Cycle.new(77)
	var t := 0.0
	while reference.rain_at(t) <= 0.05:
		t += 5.0
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.cycle = true
	w.cycle_seed = 77
	w.cycle_time = t + 5000.0
	w._process(0.0)
	w.cycle_time = t
	w._process(0.0)
	assert_almost_eq(w.rain, Cycle.new(77).rain_at(t), 1e-6, "back in time, the shower that was there")
	assert_gt(w.rain, 0.0, "is raining")


func test_covers_restamp_only_for_a_step_that_shows() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _open_floor()
	var lift := _platform(Vector3(-6.5, 3, -6.5))
	w.add_cover(lift, AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2)))
	w._live.update()
	var uploads := [0]
	w._live.texture.changed.connect(func() -> void: uploads[0] += 1)
	lift.global_position += Vector3(0.2, 0.01, 0.2)  # inside the same cells, under a step up
	w._live.update()
	assert_eq(uploads[0], 0, "a nudge within a cell uploads nothing")
	lift.global_position += Vector3(1.0, 0.0, 0.0)
	w._live.update(0.01)
	assert_eq(uploads[0], 0, "and a real move waits out the interval")
	w._live.update(Live.COVER_EVERY)
	assert_gt(uploads[0], 0, "then lands")


## Triangles for a flat rectangle at height y, corners a and b on X/Z, in the cover's frame.
func _quad(a: Vector2, b: Vector2, y: float) -> PackedVector3Array:
	var p := [Vector3(a.x, y, a.y), Vector3(b.x, y, a.y), Vector3(b.x, y, b.y), Vector3(a.x, y, b.y)]
	return PackedVector3Array([p[0], p[1], p[2], p[0], p[2], p[3]])


func _covered(w: Node3D) -> Array[int]:
	var cells: Array[int] = []
	for i in w._live.heights.size():
		if w._live.heights[i] != w._live.baked[i]:
			cells.append(i)
	return cells


func test_a_turned_beam_covers_its_diagonal_not_its_bounds() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _open_floor()
	var beam := _platform(Vector3(-5, 3, 5))
	beam.rotation.y = PI / 4
	w.add_cover(beam, _quad(Vector2(-4, -0.25), Vector2(4, 0.25), 0.0))  # 8 m by 0.5 m
	w._live.update()
	var cells := _covered(w)
	assert_gt(cells.size(), 8, "it lands all along its length (%d cells)" % cells.size())
	assert_lt(cells.size(), 30, "and not over the 6 m square around it a box would (%d)" % cells.size())
	assert_almost_eq(w.floor_at(Vector3(-5, 0, 5)), 3.0, 1e-4, "at its height")


func test_an_l_shape_leaves_its_corner_open() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _open_floor()
	var roof := _platform(Vector3(-5, 3, -5))
	var tris := _quad(Vector2(-3, -3), Vector2(3, -1), 0.0)  # along the top
	tris.append_array(_quad(Vector2(-3, -1), Vector2(-1, 3), 0.0))  # down the left
	w.add_cover(roof, tris)
	w._live.update()
	assert_almost_eq(w.floor_at(Vector3(-7.5, 0, -2.5)), 3.0, 1e-4, "under the leg")
	assert_eq(w.floor_at(Vector3(-3, 0, -3)), 0.0, "the inside corner stays open")


func test_a_pitched_roof_stops_rain_at_its_slope() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _open_floor()
	var shed := _platform(Vector3(5, 3, -5))
	# Eaves at 3 m along x = -3, rising to 5 m along x = +3.
	var a := Vector3(-3, 0, -3)
	var b := Vector3(3, 2, -3)
	var c := Vector3(3, 2, 3)
	var d := Vector3(-3, 0, 3)
	w.add_cover(shed, PackedVector3Array([a, b, c, a, c, d]))
	w._live.update()
	var low := w.floor_at(Vector3(2.5, 0, -5))
	var high := w.floor_at(Vector3(7.5, 0, -5))
	assert_lt(low, 3.6, "near the eaves rain stops low (%.2f)" % low)
	assert_gt(high, 4.4, "near the ridge, high (%.2f)" % high)


func test_a_cover_defaults_to_its_own_meshes() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _open_floor()
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
	w._live.update()
	assert_almost_eq(w.floor_at(Vector3(5, 0, 5)), 3.1, 1e-4, "the top of its own mesh")


func test_a_cover_that_only_slides_reuses_its_raster() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _open_floor()
	var train := _platform(Vector3(-12, 3, 5))  # starts half off the floor's west edge
	w.add_cover(train, _quad(Vector2(-2, -0.5), Vector2(2, 0.5), 0.0))
	w._live.update()
	var first: Transform3D = w._live.covers[train].raster_xform
	assert_almost_eq(w.floor_at(Vector3(-9.5, 0, 5)), 3.0, 1e-4, "the part on the floor covers")
	train.global_position = Vector3(4, 4, 5)
	w._live.update()
	assert_eq(w._live.covers[train].raster_xform, first, "a slide is the same raster moved")
	assert_almost_eq(w.floor_at(Vector3(2.5, 0, 5)), 4.0, 1e-4, "all of it, once on the floor")
	assert_almost_eq(w.floor_at(Vector3(5.5, 0, 5)), 4.0, 1e-4, "both ends")
	assert_eq(w.floor_at(Vector3(-9.5, 0, 5)), 0.0, "and gone from where it was")
	train.rotation.y = PI / 2
	w._live.update()
	assert_ne(w._live.covers[train].raster_xform, first, "a turn rasterizes it afresh")
	assert_almost_eq(w.floor_at(Vector3(4, 0, 6.5)), 4.0, 1e-4, "now lying north-south")
	assert_eq(w.floor_at(Vector3(5.5, 0, 5)), 0.0, "and no longer east-west")


func test_turning_covers_share_out_the_work() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _open_floor()
	var spinners: Array[Node3D] = []
	for i in 6:
		var s := _platform(Vector3(-7.5 + i * 3, 3, -7.5))
		w.add_cover(s, _quad(Vector2(-1, -0.2), Vector2(1, 0.2), 0.0))
		spinners.append(s)
	w._live.update()
	for s in spinners:
		s.rotation.y = PI / 2
	w.cover_budget_usec = 0  # out of time after the first
	var turned := func() -> int:
		var n := 0
		for s in spinners:
			if w._live.covers[s].xform.basis.is_equal_approx(s.global_transform.basis):
				n += 1
		return n
	w._live.update()
	assert_eq(turned.call(), 1, "one turns per tick when the budget is spent")
	w._live.update()
	assert_eq(turned.call(), 2, "the next tick, the next one")
	for i in 4:
		w._live.update()
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


func test_it_finds_the_scene_sky_by_itself() -> void:
	var w := _weather()
	_keep(w)
	var sky := SkyScript.new({"drawing": false})
	var holder := _keep(WorldEnvironment.new())
	holder.environment = sky.make_environment()
	sky.drawing = false
	_root().add_child(holder)
	_root().add_child(w)
	assert_eq(w.current_sky(), sky, "the environment's sky, with none set")
	w.rain = 1.0
	w.settle()
	w._process(0.0)
	assert_almost_eq(sky.storm, 1.0, 1e-6, "and storms it")
	var own := SkyScript.new({"drawing": false})
	w.sky = own
	assert_eq(w.current_sky(), own, "a sky set by hand wins")
	w._process(0.0)
	assert_almost_eq(own.storm, 1.0, 1e-6, "and is brought up to the storm at once")


func test_showers_drive_the_rain() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.cycle_seed = 1234
	w.cycle = true
	w.cycle_speed = 60.0
	var wet := 0
	for i in 600:
		w._process(0.5)
		if w.rain > 0.0:
			wet += 1
	var reference := preload("res://addons/overcast/overcast_cycle.gd").new(1234)
	assert_almost_eq(w.rain, reference.rain_at(w.cycle_time), 1e-6, "the cycle's rain on its seed")
	assert_gt(wet, 0, "it rains some of the time (%d of 600)" % wet)
	assert_lt(wet, 600, "and not all of it")


func test_clearing_the_floor_lets_rain_fall_everywhere() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain_floor = _roofed_floor()
	w.rain_floor = null
	assert_eq(w.floor_at(Vector3(-1.5, 0, -0.5)), -INF, "no floor, no roof")
	assert_eq(w.rain_exposure(Vector3.ZERO), 1.0, "and the rain all around")


func test_the_sun_light_turns_with_the_sky() -> void:
	var w := _weather()
	_keep(w)
	var sun := DirectionalLight3D.new()
	_keep(sun)
	_root().add_child(sun)
	w.sun = sun
	var noon := Vector3(0.0, 0.8, -0.6).normalized()
	var sky := SkyScript.new({"drawing": false, "sun_dir": noon, "time_of_day": 9.0})
	w.sky = sky
	_root().add_child(w)
	w._process(0.0)
	assert_vec3_almost_eq(SkyScript.sun_dir_of(sun), SkyScript.sun_at(noon, 9.0), 1e-4, "the light comes from the sun")
	sky.time_of_day = 23.0
	w._process(0.0)
	assert_vec3_almost_eq(SkyScript.sun_dir_of(sun), sky.light_dir(), 1e-4, "and from the moon at night")
	assert_lt(sun.light_color.get_luminance(), 0.3, "in moonlight")
	sky.sun_follows_time = false
	var before := sun.global_basis
	sky.time_of_day = 9.0
	w._process(0.0)
	assert_true(sun.global_basis.is_equal_approx(before), "a sun that does not follow the time is left where it is")


func test_lying_snow_comes_back_with_the_weather() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain = 1.0
	w.snow = 1.0
	w.settle()
	w._process(0.1)
	assert_eq(Globals.value("overcast_snow_cover"), 1.0, "settled snow lies")
	_root().remove_child(w)
	assert_eq(Globals.value("overcast_snow_cover"), 0.0, "gone, it takes its snow")
	_root().add_child(w)
	w._process(0.1)
	assert_eq(Globals.value("overcast_snow_cover"), 1.0, "back, it brings it again")


func test_a_strike_dies_with_the_weather() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var drawn := [0]
	var w := _weather()
	w.bolt_drawer = func(_p: PackedVector3Array, _w: float, _b: float, _f: float) -> void: drawn[0] += 1
	_root().add_child(w)
	w.strike(7)
	await tree.create_timer(0.3).timeout
	var strokes: int = drawn[0]
	assert_gt(strokes, 0, "its strokes are drawn in turn")
	assert_eq(w.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer and n not in [w._rain_audio, w._wind_audio]).size(), 1,
		"and its thunder is on the way")
	drawn[0] = 0
	w.strike(7)
	w.free()
	await tree.create_timer(0.3).timeout
	assert_eq(drawn[0], 0, "freed, nothing of the strike is left to fire")


func test_a_sky_is_let_go_of_clear() -> void:
	var w := _weather()
	_keep(w)
	var sky := FakeSky.new({"drawing": false})
	var flashes: Array[float] = []
	w.flash_changed.connect(func(k: float) -> void: flashes.append(k))
	w.sky = sky
	_root().add_child(w)
	w.rain = 1.0
	w.snow = 0.4
	w.settle()
	w.strike(3)
	w._process(0.01)
	assert_gt(sky.storm, 0.9, "the storm is on the sky")
	assert_ne(sky.flash, Color.BLACK, "and so is the flash")
	_root().remove_child(w)
	assert_eq(sky.storm, 0.0, "gone, the weather takes its storm")
	assert_eq(sky.snowy, 0.0, "and its snow")
	assert_eq(sky.flash, Color.BLACK, "and its flash")
	assert_eq(flashes[-1], 0.0, "which ends on 0 for the scene's light too")
	_root().add_child(w)
	w._process(0.01)
	assert_gt(sky.storm, 0.9, "back, it brings them again")
	var other := FakeSky.new({"drawing": false})
	w.sky = other
	w._process(0.01)
	assert_eq(sky.storm, 0.0, "a sky swapped out is let go of clear")
	assert_gt(other.storm, 0.9, "and the new one takes the storm")


func test_the_moon_comes_up_from_nothing() -> void:
	var w := _weather()
	_keep(w)
	var sun := DirectionalLight3D.new()
	_keep(sun)
	_root().add_child(sun)
	w.sun = sun
	var sky := SkyScript.new({"drawing": false})
	w.sky = sky
	_root().add_child(w)
	for from in [17.0, 4.0]:
		var worst := 0.0
		var last := -1.0
		for i in 241:
			sky.time_of_day = from + i * 3.0 / 240.0  # a step under a minute of game time
			w._process(0.0)
			var light := sun.light_color.get_luminance()
			if last >= 0.0:
				worst = maxf(worst, absf(light - last))
			last = light
		assert_lt(worst, 0.03, "the sun's light never jumps between %d:00 and %d:00 (%.3f)" % [from, from + 3, worst])


func test_the_wind_carries_the_rain_and_gusts() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain = 1.0
	w.wind = Vector3(6.0, 3.0, 0.0)
	w.gustiness = 0.0
	w._process(0.5)
	assert_vec3_almost_eq(w.wind_now(), Vector3(6.0, 0.0, 0.0), 1e-4, "steady, it blows as set, along the ground")
	assert_vec3_almost_eq(w._drop_material.get_shader_parameter("drift"), Vector3(3.0, 0.0, 0.0), 1e-4,
		"and carries the drops with it")
	for i in 100:
		w._process(0.1)
	var drift: Vector3 = w._drop_material.get_shader_parameter("drift")
	assert_true(drift.x >= 0.0 and drift.x < Weather.DROP_BOX.x, "wrapped into their box (%s)" % drift)
	w.gustiness = 1.0
	var speeds: Array[float] = []
	for i in 200:
		w._process(0.05)
		speeds.append(w.wind_now().length())
	assert_lt(speeds.min(), 4.0, "gusts drop it (%.1f)" % speeds.min())
	assert_gt(speeds.max(), 8.0, "and raise it (%.1f)" % speeds.max())


func test_splashes_land_on_the_floor_while_it_rains() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain = 1.0
	w._process(0.1)
	assert_eq(w._splashes.multimesh.visible_instance_count, w.splashes_heavy, "a downpour's splashes")
	assert_false(w._splashes.visible, "but with no floor, nowhere to land")
	w.rain_floor = _roofed_floor()
	w._process(0.1)
	assert_true(w._splashes.visible, "on a floor they show")
	w.snow = 1.0
	w._process(0.1)
	assert_false(w._splashes.visible, "snow does not splash")
	assert_eq(w._splashes.multimesh.visible_instance_count, 0)


func test_the_rainfall_ripples_puddles_through_a_global() -> void:
	var w := _weather()
	_keep(w)
	w.rain_floor = _roofed_floor()
	_root().add_child(w)
	w.rain = 0.5
	w._process(0.1)
	assert_almost_eq(Globals.value("overcast_rainfall"), 0.5, 0.01, "as hard as it is raining now")
	w.rain = 0.0
	w._process(0.1)
	assert_eq(Globals.value("overcast_rainfall"), 0.0, "and stopping at once with it")
	w.rain = 1.0
	w._process(0.1)
	_root().remove_child(w)
	assert_eq(Globals.value("overcast_rainfall"), 0.0, "gone, it leaves no ripples")


func test_snow_with_no_rain_and_no_wind_is_silent() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.rain = 1.0
	w.snow = 1.0
	w._process(0.1)
	assert_false(w._rain_audio.playing, "no rain to hear")
	assert_false(w._wind_audio.playing, "and no wind")
	w.wind = Vector3(3.0, 0.0, 0.0)
	w.gustiness = 0.0
	w._process(0.1)
	assert_false(w._wind_audio.playing, "a breeze is not heard")


func test_only_a_strong_wind_is_heard_and_louder_as_it_blows() -> void:
	var w := _weather()
	_keep(w)
	_root().add_child(w)
	w.gustiness = 0.0
	var volumes: Array[float] = []
	for speed in [10.0, 14.0, 20.0]:
		w.wind = Vector3(0.0, 0.0, speed)
		w._process(0.1)
		assert_true(w._wind_audio.playing, "a %d m/s wind is heard, rain or none" % speed)
		volumes.append(w._wind_audio.volume_db)
	assert_lt(volumes[0], volumes[1], "louder as it blows harder")
	assert_lt(volumes[1], volumes[2])
	assert_almost_eq(volumes[2], Weather.WIND_DB, 0.01, "and no louder than WIND_DB past WIND_LOUD")
	assert_lt(volumes[0], Weather.WIND_DB - 15.0, "a fresh breeze is only faint (%.1f dB)" % volumes[0])
	w.wind = Vector3.ZERO
	w._process(0.1)
	assert_false(w._wind_audio.playing, "still, it stops")
	assert_ne(Weather._sound("wind"), null, "with its own wind loop")


func test_the_wind_is_quieter_under_a_roof() -> void:
	var w := _weather()
	_keep(w)
	# An 80 m field, open but for a 30 m hall at its middle: the sound's sample rings reach 12 m,
	# so the hall's middle hears no open sky, and the field's corner all of it.
	var img := Image.create_empty(80, 80, false, Image.FORMAT_RF)
	for y in 80:
		for x in 80:
			img.set_pixel(x, y, Color(3.0 if absi(x - 40) < 15 and absi(y - 40) < 15 else 0.0, 0, 0))
	w.rain_floor = RainFloor.create(img, Vector3(-40, 0, -40), Vector2(80, 80), 10.0)
	w.listener = _keep(Node3D.new())
	_root().add_child(w.listener)
	_root().add_child(w)
	w.gustiness = 0.0
	w.wind = Vector3(20.0, 0.0, 0.0)
	w.listener.global_position = Vector3(27.0, 1.0, 27.0)  # out in the field
	for i in 40:
		w._process(0.1)
	var open := w._wind_audio.volume_db
	assert_almost_eq(open, Weather.WIND_DB, 0.01, "in the open, at full strength")
	w.listener.global_position = Vector3(0.0, 1.0, 0.0)  # in the hall
	for i in 40:
		w._process(0.1)
	assert_almost_eq(w._wind_audio.volume_db, open + linear_to_db(Weather.WIND_INDOOR_GAIN), 0.01,
		"indoors, WIND_INDOOR_GAIN of it")
