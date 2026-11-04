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
	assert_eq(sky.get_shader_parameter("storm"), 1.0, "the sky draws the storm")
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
	var sky := SkyScript.new({"cloud_amount": 0.25, "cloud_scale": 3.0, "drawing": false})
	var path := "user://overcast_test_sky.tres"
	assert_eq(ResourceSaver.save(sky, path), OK, "it saves")
	var loaded: SkyScript = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_almost_eq(loaded.cloud_amount, 0.25, 1e-6, "its look")
	assert_almost_eq(loaded.cloud_scale, 3.0, 1e-6, "its layer")
	assert_false(loaded.drawing, "and whether it draws")
	assert_eq(loaded.shader, SkyScript.SkyShader, "on the sky shader")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

