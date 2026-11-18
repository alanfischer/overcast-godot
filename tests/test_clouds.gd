extends "res://tests/suite.gd"

const Clouds = preload("res://addons/overcast/overcast_clouds.gd")
const SkyScript = preload("res://addons/overcast/overcast_sky.gd")
const Globals = preload("res://addons/overcast/overcast_globals.gd")


func _global(name: String) -> Variant:
	return Globals.value(name)


func test_the_project_declares_every_global() -> void:
	assert_true(Globals.declared(), "project.godot carries GLOBALS in overcast_globals.gd")
	Globals.declare()  # declared already: must not complain or add twice
	assert_true(Globals.declared(), "still declared")


func test_noise_tiles_in_two_channels() -> void:
	var tex := Clouds._noise_texture()
	assert_eq(tex.get_width(), 512, "512 wide")
	assert_eq(tex.get_image().get_format(), Image.FORMAT_RG8, "perlin in r, worley in g")
	assert_true(tex == Clouds._noise_texture(), "made once")


func test_volume_is_built_only_for_a_drawing_sky() -> void:
	assert_eq(Clouds._owner, 0, "no sky is drawing yet")
	Clouds.set_volumetric(true)
	assert_eq(_global("overcast_volumetric"), 1.0, "switched on")
	assert_eq(Clouds._volume, null, "but not built with no sky drawing")
	var sky := SkyScript.new()
	sky.drawing = true
	assert_ne(Clouds._volume, null, "built once a sky draws")
	Clouds.set_volumetric(false)
	sky.drawing = false


func test_a_storm_closes_the_sky_and_deepens_the_shadow() -> void:
	var sky := SkyScript.new({"cloud_amount": 0.3})
	sky.drawing = true
	assert_almost_eq(_global("overcast_cover"), 0.3, 1e-6, "fair weather: the sky's own cover")
	assert_almost_eq(_global("overcast_shadow"), sky.cloud_shadow, 1e-6, "and the fair shadow")
	sky.set_weather(1.0, sky.snowy)
	assert_almost_eq(_global("overcast_cover"), SkyScript._STORM_COVER, 1e-6, "a storm closes it over")
	assert_almost_eq(_global("overcast_shadow"), sky.storm_shadow, 1e-6, "and shades harder")
	assert_eq(sky.storm, 1.0, "the sky draws the storm")
	sky.drawing = false
	assert_eq(_global("overcast_shadow"), 0.0, "a sky off screen casts no shadow")


func test_a_cloudless_sky_casts_no_shadow_until_it_storms() -> void:
	var sky := SkyScript.new({"cloud_amount": 0.0})
	sky.drawing = true
	assert_eq(_global("overcast_shadow"), 0.0, "no clouds, no shadow")
	sky.set_weather(0.5, sky.snowy)
	assert_gt(_global("overcast_shadow"), 0.0, "storm cloud shades")
	sky.drawing = false


func test_a_sky_off_screen_leaves_the_globals_alone() -> void:
	var shown := SkyScript.new({"cloud_amount": 0.4})
	shown.drawing = true
	var hidden := SkyScript.new({"cloud_amount": 0.9, "drawing": false})
	hidden.set_weather(1.0, hidden.snowy)
	assert_almost_eq(_global("overcast_cover"), 0.4, 1e-6, "the drawing sky keeps the layer")
	shown.drawing = false


func test_horizon_greys_with_the_storm() -> void:
	var sky := SkyScript.new({"horizon_color": Color(0.3, 0.5, 0.9)})
	var clear := sky.horizon_now()
	sky.set_weather(1.0, sky.snowy)
	var storm := sky.horizon_now()
	assert_almost_eq(storm.r, storm.b, 1e-6, "a full storm's horizon is grey")
	assert_lt(SkyScript._luma(storm), SkyScript._luma(clear), "and darker than the clear one")


func test_only_the_sky_that_holds_the_layer_lets_it_go() -> void:
	var old := SkyScript.new({"cloud_amount": 0.3})
	old.drawing = true
	var new := SkyScript.new({"cloud_amount": 0.6})
	new.drawing = true
	old.drawing = false
	assert_almost_eq(_global("overcast_cover"), 0.6, 1e-6, "the old sky turning off leaves the new one's clouds")
	old.set_weather(1.0, old.snowy)
	assert_almost_eq(_global("overcast_cover"), 0.6, 1e-6, "and its storm does not reach them")
	new = null  # the last reference: a sky freed while drawing
	assert_eq(_global("overcast_shadow"), 0.0, "takes its shadows with it")
	assert_eq(Clouds._owner, 0, "and leaves the layer free")


func test_the_layer_follows_its_settings_and_the_inspector() -> void:
	var sky := SkyScript.new()
	sky.drawing = true
	sky.cloud_speed = 0.5
	assert_almost_eq(_global("overcast_speed"), 0.5, 1e-6, "a layer setting moves the global")
	sky.set("shader_parameter/sun_dir", Vector3(0, 2, 0))
	assert_vec3_almost_eq(_global("overcast_sun_dir"), Vector3.UP, 1e-6, "an inspector edit to the sun moves it too")
	assert_vec3_almost_eq(sky.sun_dir, Vector3.UP, 1e-6, "normalized on the material")
	sky.cloud_amount = 0.2
	assert_almost_eq(_global("overcast_cover"), 0.2, 1e-6, "and so does the cloud amount")
	sky.apply({"horizon_color": Color.RED})
	assert_eq(sky.get_shader_parameter("horizon_color"), Color.RED, "apply sets a uniform by name")
	sky.drawing = false


func test_a_saved_sky_loads_with_its_settings() -> void:
	var sky := SkyScript.new({"cloud_amount": 0.25, "cloud_scale": 3.0, "drawing": false, "time_of_day": 19.5})
	var path := "user://overcast_test_sky.tres"
	assert_eq(ResourceSaver.save(sky, path), OK, "it saves")
	var loaded: SkyScript = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_almost_eq(loaded.cloud_amount, 0.25, 1e-6, "its look")
	assert_almost_eq(loaded.cloud_scale, 3.0, 1e-6, "its layer")
	assert_false(loaded.drawing, "whether it draws")
	assert_almost_eq(loaded.time_of_day, 19.5, 1e-6, "and its time of day")
	assert_almost_eq(loaded.get_shader_parameter("night_amount"), SkyScript.night_at(19.5), 1e-6, "which the shader is told")
	assert_eq(loaded.shader, SkyScript._SkyShader, "on the sky shader")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))



func test_a_storm_and_a_flash_are_not_saved_with_the_sky() -> void:
	var sky := SkyScript.new({"drawing": false})
	sky.set_weather(0.8, sky.snowy)
	sky.set_flash(Color.WHITE, Vector3.UP)
	var path := "user://overcast_test_storm.tres"
	assert_eq(ResourceSaver.save(sky, path), OK, "it saves")
	var text := FileAccess.get_file_as_string(path)
	var set_by_weather := RegEx.create_from_string("(storm|flash_\\w+) = (?!null)")
	assert_eq(set_by_weather.search(text), null, "without the weather's storm or flash")
	var old := SkyScript.new({"drawing": false})
	old.set_shader_parameter("storm", 0.8)  # as an older version saved it
	assert_eq(ResourceSaver.save(old, path), OK, "an old sky saves")
	var loaded: SkyScript = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.get_shader_parameter("storm"), null, "and loads with its stale storm dropped")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_layer_takes_its_height() -> void:
	var sky := SkyScript.new()
	sky.drawing = true
	assert_almost_eq(_global("overcast_height"), 100.0, 1e-3, "100 m by default: 1500 real, shrunk")
	sky.cloud_height = 6000.0
	assert_almost_eq(_global("overcast_height"), 400.0, 1e-3, "and the shaders follow a higher layer")
	sky.world_scale = 1.0
	assert_almost_eq(_global("overcast_height"), 6000.0, 1e-3, "at its real height in a world at real size")
	sky.drawing = false

func test_a_passing_sky_gives_the_layer_back() -> void:
	var sky := SkyScript.new({"cloud_amount": 0.3})
	sky.drawing = true
	var passing := SkyScript.new({"cloud_amount": 0.7})
	passing.drawing = true
	assert_almost_eq(_global("overcast_cover"), 0.7, 1e-6, "the newer sky takes the layer")
	passing = null
	assert_eq(Clouds._owner, sky.get_instance_id(), "freed, it hands the layer back")
	assert_almost_eq(_global("overcast_cover"), 0.3, 1e-6, "with the older sky's clouds")
	var off := SkyScript.new({"cloud_amount": 0.5})
	off.drawing = true
	off.drawing = false
	assert_almost_eq(_global("overcast_cover"), 0.3, 1e-6, "and so does one turned off")
	sky.drawing = false
	assert_eq(Clouds._owner, 0, "with none left drawing, nobody holds it")
	assert_eq(_global("overcast_shadow"), 0.0, "and nothing casts a shadow")


func test_the_day_runs_noon_to_dusk_to_night() -> void:
	assert_eq(SkyScript.night_at(12.0), 0.0, "noon is day")
	assert_eq(SkyScript.dusk_at(12.0), 0.0, "with no sunset in it")
	assert_almost_eq(SkyScript.night_at(0.0), 1.0, 1e-6, "midnight is full night")
	assert_almost_eq(SkyScript.night_at(21.0), 1.0, 1e-6, "and so is nine")
	assert_gt(SkyScript.dusk_at(18.0), 0.9, "six is sunset")
	assert_gt(SkyScript.dusk_at(6.0), 0.9, "as six in the morning is sunrise")
	assert_lt(SkyScript.night_at(18.0), 0.1, "and it is not dark yet")
	assert_eq(SkyScript.scene_light_at(12.0), Color.WHITE, "daylight is the scene as lit")
	assert_true(SkyScript.scene_light_at(0.0).is_equal_approx(SkyScript.MOON_LIGHT), "midnight is moonlight")
	var dusk := SkyScript.scene_light_at(18.0)
	assert_gt(dusk.r, dusk.b, "sunset light is warm")


func test_the_sky_follows_its_time() -> void:
	var sky := SkyScript.new({"drawing": false, "time_of_day": 22.0})
	assert_almost_eq(sky.get_shader_parameter("night_amount"), 1.0, 1e-6, "the shader is told it is night")
	assert_lt(SkyScript._luma(sky.horizon_now()), 0.05, "and the horizon haze fades into is dark")
	sky.time_of_day = 12.0
	assert_eq(sky.get_shader_parameter("night_amount"), 0.0, "noon again")
	assert_gt(SkyScript._luma(sky.horizon_now()), 0.3, "and a bright horizon")
	sky.time_of_day = 18.0
	var h := sky.horizon_now()
	assert_gt(h.r, h.b, "a sunset horizon is warm")
	sky.time_of_day = 26.0
	assert_almost_eq(sky.time_of_day, 2.0, 1e-6, "time wraps round the clock")


func test_the_air_scatters_blue_overhead_and_red_at_sunset() -> void:
	var noon_sun := Vector3(0.0, 0.8, -0.6)
	var zenith := SkyScript._air_sky(Vector3.UP, noon_sun, 1.0)
	assert_gt(zenith.b, zenith.r * 2.0, "a clear noon sky is blue overhead")
	var level := SkyScript._air_sky(Vector3(1.0, 0.0, 0.0), noon_sun, 1.0)
	assert_gt(SkyScript._luma(level), SkyScript._luma(zenith), "and brighter and paler level")
	var low_sun := Vector3(0.0, 0.03, -1.0).normalized()
	var glow := SkyScript._air_sky(Vector3(0.0, 0.0, -1.0), low_sun, 1.0)
	assert_gt(glow.r, glow.b * 3.0, "under a setting sun the horizon is red")
	var ground := Vector3(0.0, SkyScript._AIR_GROUND + SkyScript._AIR_VIEWER, 0.0)
	var sunlight := SkyScript._air_sunlight(ground, low_sun, 1.0)
	assert_gt(sunlight.x, sunlight.z * 3.0, "and its light reddened")
	var set_sun := Vector3(0.0, -0.05, -1.0).normalized()
	assert_eq(SkyScript._air_sunlight(ground, set_sun, 1.0), Vector3.ZERO, "the ground is in shadow once it sets")
	var high := Vector3(0.0, SkyScript._AIR_GROUND + 20e3, 0.0)
	assert_gt(SkyScript._air_sunlight(high, set_sun, 1.0).x, 0.0, "though the air high up is still lit")


func test_a_sky_lit_by_the_air_keeps_its_haze_in_step() -> void:
	var sky := SkyScript.new({"drawing": false, "atmosphere": 1.0, "time_of_day": 12.0})
	var noon := sky.horizon_now()
	assert_gt(SkyScript._luma(noon), 0.3, "a bright horizon at noon")
	assert_gt(noon.b, noon.r, "and a cool one")
	sky.time_of_day = 18.0
	var dusk := sky.horizon_now()
	assert_gt(dusk.r, dusk.b, "warm at sunset")
	sky.time_of_day = 0.0
	assert_lt(SkyScript._luma(sky.horizon_now()), 0.05, "and dark at night")


func test_clouds_catch_the_sun_after_the_ground_loses_it() -> void:
	var gone := SkyScript.air_at(Vector3(0.0, -0.02, -1.0).normalized(), 1.0, 20.0)
	assert_eq(gone["atmosphere_light"], Vector3.ZERO, "the sun has set on the ground")
	var light: Vector3 = gone["atmosphere_cloud_light"]
	assert_gt(light.x, light.z * 2.0, "but still reaches the clouds, red")
	var midnight := SkyScript.air_at(Vector3.DOWN, 1.0, 20.0)
	assert_eq(midnight["atmosphere_cloud_light"], Vector3.ZERO, "and not at midnight")
	var dusk_gain: float = gone["atmosphere_gain"]
	assert_gt(dusk_gain, SkyScript.air_at(Vector3.UP, 1.0, 20.0)["atmosphere_gain"], "the eye opens up at dusk")


func test_the_sun_crosses_the_sky_with_the_time() -> void:
	var noon := Vector3(0.3, 0.8, -0.5).normalized()
	assert_vec3_almost_eq(SkyScript.sun_at(noon, 12.0), noon, 1e-5, "at noon it is where sun_dir says")
	assert_almost_eq(SkyScript.sun_at(noon, 6.0).y, 0.0, 1e-5, "it rises at six")
	assert_almost_eq(SkyScript.sun_at(noon, 18.0).y, 0.0, 1e-5, "and sets at six")
	assert_lt(SkyScript.sun_at(noon, 18.0).dot(SkyScript.sun_at(noon, 6.0)), 0.0, "on the other side of the sky")
	assert_gt(SkyScript.sun_at(noon, 9.0).y, 0.0, "up all morning")
	assert_lt(SkyScript.sun_at(noon, 0.0).y, 0.0, "and below the ground at midnight")
	var sky := SkyScript.new({"drawing": false, "sun_dir": noon, "time_of_day": 0.0})
	assert_gt(sky.light_dir().y, 0.0, "at night the moon is up instead")
	assert_vec3_almost_eq(sky.get_shader_parameter("light_dir"), sky.light_dir(), 1e-5, "and the shader draws it there")
	sky.sun_follows_time = false
	assert_vec3_almost_eq(sky.light_dir(), noon, 1e-5, "a baked sun stays put, and so does its moon")
	assert_vec3_almost_eq(sky.sun_dir, noon, 1e-5, "and sun_dir is never moved")


func test_a_placed_sky_is_the_real_one() -> void:
	# Greenwich, 21 June 2026, 13:00 BST.
	var sky := SkyScript.new({"drawing": false, "placed": true, "latitude": 51.4769, "longitude": 0.0,
		"date": "2026-06-21", "utc_offset": 1.0, "time_of_day": 13.0})
	assert_almost_eq(sky.unix_time, 1782043200.0, 1e-3, "the local clock, back to UTC")
	var sun: Vector3 = sky.light_dir()
	assert_almost_eq(rad_to_deg(asin(sun.y)), 61.96, 0.05, "the sun as high as midsummer puts it")
	assert_gt(sun.z, 0.4, "in the south, -Z being north")
	assert_eq(sky.night, 0.0, "day")
	assert_almost_eq(sky.phase(), 0.236, 0.002, "the moon's phase is the date's")
	assert_vec3_almost_eq(sky.get_shader_parameter("moon_lit_from"), sun, 1e-6, "lit from the sun")
	sky.moon_phase = 0.9
	assert_almost_eq(sky.phase(), 0.236, 0.002, "and moon_phase goes unused")
	sky.north = 180.0
	assert_lt(sky.light_dir().z, -0.4, "north turned round puts the sun the other way")
	sky.north = 0.0
	sky.unix_time = 1782043200.0 + 12 * 3600.0
	assert_eq(sky.date, "2026-06-22", "setting the moment rolls the date over")
	assert_almost_eq(sky.time_of_day, 1.0, 1e-6, "past local midnight")
	assert_gt(sky.night, 0.9, "into the short summer night")
	sky.latitude = 69.65
	sky.longitude = 18.96
	assert_lt(sky.night, 0.1, "which Tromsø does not have")
	sky.unix_time = 1797849000.0  # 21 December, 10:30 UTC
	assert_lt(sky._placed_sky["sun"].y, 0.0, "the polar night's noon: the sun stays down")
	assert_gt(sky.dusk, 0.5, "a long twilight")
	sky.placed = false
	assert_vec3_almost_eq(sky.light_dir(), SkyScript.light_dir_at(sky.sun_dir, sky.time_of_day, sky.moon_phase), 1e-6,
		"off, the arc again")


func test_the_moon_keeps_its_own_time() -> void:
	var noon := Vector3(0.3, 0.8, -0.5).normalized()
	assert_vec3_almost_eq(SkyScript.moon_at(noon, 0.0, 0.5), noon, 1e-5, "a full moon stands at midnight where the sun did at noon")
	assert_vec3_almost_eq(SkyScript.moon_at(noon, 15.0, 0.0), SkyScript.sun_at(noon, 15.0), 1e-5, "a new one keeps the sun's company")
	assert_almost_eq(SkyScript.moon_at(noon, 12.0, 0.25).y, 0.0, 1e-5, "a first quarter rises at noon")
	assert_almost_eq(SkyScript.moon_lit(0.0), 0.0, 1e-6, "new is dark")
	assert_almost_eq(SkyScript.moon_lit(0.25), 0.5, 1e-6, "a quarter is half lit")
	assert_almost_eq(SkyScript.moon_lit(0.5), 1.0, 1e-6, "full is all of it")
	assert_almost_eq(SkyScript.moonlight_at(0.0, 0.5), 1.0, 1e-6, "a full moon lights midnight")
	assert_eq(SkyScript.moonlight_at(0.0, 0.0), 0.0, "a new one does not")
	assert_eq(SkyScript.moonlight_at(3.0, 0.25), 0.0, "nor one that has set")
	var dark := SkyScript.scene_light_at(0.0, 0.0)
	assert_almost_eq(dark.r, SkyScript.MOON_LIGHT.r * SkyScript.STARLIGHT, 1e-6, "which leaves the night to the stars")
	var sky := SkyScript.new({"drawing": false, "sun_dir": noon, "time_of_day": 3.0, "moon_phase": 0.25})
	assert_vec3_almost_eq(sky.light_dir(), SkyScript.moon_at(noon, 3.0, 0.25), 1e-5, "the night's light is wherever the moon is")
	assert_lt(sky.light_dir().y, 0.0, "set or not")
	assert_eq(sky.light_strength(), 0.0, "and a set moon lights nothing")
	assert_vec3_almost_eq(sky.get_shader_parameter("moon_dir"), sky.moon_dir(), 1e-5, "the shader draws it there")
	sky.time_of_day = 20.0
	var from: Vector3 = sky.get_shader_parameter("moon_lit_from")
	assert_almost_eq(from.dot(sky.moon_dir()), 0.0, 1e-4, "a quarter is lit from square on")
	assert_gt(from.dot(SkyScript.sun_at(noon, 20.0)), 0.0, "from the sun's side")
	sky.moon_phase = 0.5
	assert_vec3_almost_eq(sky.get_shader_parameter("moon_lit_from"), -sky.moon_dir(), 1e-4, "and a full one from behind us")
