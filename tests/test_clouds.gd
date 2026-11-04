extends "res://tests/suite.gd"

const Clouds = preload("res://addons/overcast/overcast_clouds.gd")
const SkyScript = preload("res://addons/overcast/overcast_sky.gd")


func _global(name: String) -> Variant:
	return Clouds.value(name)


func test_the_project_declares_every_global() -> void:
	assert_true(Clouds.declared(), "project.godot carries OvercastClouds.GLOBALS")
	Clouds.declare()  # declared already: must not complain or add twice
	assert_true(Clouds.declared(), "still declared")


func test_noise_tiles_in_two_channels() -> void:
	var tex := Clouds.noise()
	assert_eq(tex.get_width(), 512, "512 wide")
	assert_eq(tex.get_image().get_format(), Image.FORMAT_RG8, "perlin in r, worley in g")
	assert_true(tex == Clouds.noise(), "made once")


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
	sky.storm = 1.0
	assert_almost_eq(_global("overcast_cover"), SkyScript.STORM_COVER, 1e-6, "a storm closes it over")
	assert_almost_eq(_global("overcast_shadow"), sky.storm_shadow, 1e-6, "and shades harder")
	assert_eq(sky.storm, 1.0, "the sky draws the storm")
	sky.drawing = false
	assert_eq(_global("overcast_shadow"), 0.0, "a sky off screen casts no shadow")


func test_a_cloudless_sky_casts_no_shadow_until_it_storms() -> void:
	var sky := SkyScript.new({"cloud_amount": 0.0})
	sky.drawing = true
	assert_eq(_global("overcast_shadow"), 0.0, "no clouds, no shadow")
	sky.storm = 0.5
	assert_gt(_global("overcast_shadow"), 0.0, "storm cloud shades")
	sky.drawing = false


func test_a_sky_off_screen_leaves_the_globals_alone() -> void:
	var shown := SkyScript.new({"cloud_amount": 0.4})
	shown.drawing = true
	var hidden := SkyScript.new({"cloud_amount": 0.9, "drawing": false})
	hidden.storm = 1.0
	assert_almost_eq(_global("overcast_cover"), 0.4, 1e-6, "the drawing sky keeps the layer")
	shown.drawing = false


func test_horizon_greys_with_the_storm() -> void:
	var sky := SkyScript.new({"horizon_color": Color(0.3, 0.5, 0.9)})
	var clear := sky.horizon_now()
	sky.storm = 1.0
	var storm := sky.horizon_now()
	assert_almost_eq(storm.r, storm.b, 1e-6, "a full storm's horizon is grey")
	assert_lt(SkyScript.luma(storm), SkyScript.luma(clear), "and darker than the clear one")


func test_only_the_sky_that_holds_the_layer_lets_it_go() -> void:
	var old := SkyScript.new({"cloud_amount": 0.3})
	old.drawing = true
	var new := SkyScript.new({"cloud_amount": 0.6})
	new.drawing = true
	old.drawing = false
	assert_almost_eq(_global("overcast_cover"), 0.6, 1e-6, "the old sky turning off leaves the new one's clouds")
	old.storm = 1.0
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
	assert_eq(loaded.shader, SkyScript.SkyShader, "on the sky shader")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))



func test_a_storm_and_a_flash_are_not_saved_with_the_sky() -> void:
	var sky := SkyScript.new({"drawing": false})
	sky.storm = 0.8
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
	assert_lt(SkyScript.luma(sky.horizon_now()), 0.05, "and the horizon haze fades into is dark")
	sky.time_of_day = 12.0
	assert_eq(sky.get_shader_parameter("night_amount"), 0.0, "noon again")
	assert_gt(SkyScript.luma(sky.horizon_now()), 0.3, "and a bright horizon")
	sky.time_of_day = 18.0
	var h := sky.horizon_now()
	assert_gt(h.r, h.b, "a sunset horizon is warm")
	sky.time_of_day = 26.0
	assert_almost_eq(sky.time_of_day, 2.0, 1e-6, "time wraps round the clock")


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
