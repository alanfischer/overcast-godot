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
	sky.set_drawing(true)
	assert_ne(Clouds._volume, null, "built once a sky draws")
	Clouds.set_volumetric(false)
	sky.set_drawing(false)


func test_a_storm_closes_the_sky_and_deepens_the_shadow() -> void:
	var sky := SkyScript.new({"cloud_amount": 0.3})
	sky.set_drawing(true)
	assert_almost_eq(_global("overcast_cover"), 0.3, 1e-6, "fair weather: the sky's own cover")
	assert_almost_eq(_global("overcast_shadow"), SkyScript.CLOUD_SHADOW, 1e-6, "and the fair shadow")
	sky.set_storm(1.0)
	assert_almost_eq(_global("overcast_cover"), SkyScript.STORM_COVER, 1e-6, "a storm closes it over")
	assert_almost_eq(_global("overcast_shadow"), SkyScript.STORM_SHADOW, 1e-6, "and shades harder")
	assert_eq(sky.material.get_shader_parameter("storm"), 1.0, "the sky draws the storm")
	sky.set_drawing(false)
	assert_eq(_global("overcast_shadow"), 0.0, "a sky off screen casts no shadow")


func test_a_cloudless_sky_casts_no_shadow_until_it_storms() -> void:
	var sky := SkyScript.new({"cloud_amount": 0.0})
	sky.set_drawing(true)
	assert_eq(_global("overcast_shadow"), 0.0, "no clouds, no shadow")
	sky.set_storm(0.5)
	assert_gt(_global("overcast_shadow"), 0.0, "storm cloud shades")
	sky.set_drawing(false)


func test_a_sky_off_screen_leaves_the_globals_alone() -> void:
	var shown := SkyScript.new({"cloud_amount": 0.4})
	shown.set_drawing(true)
	var hidden := SkyScript.new({"cloud_amount": 0.9})
	hidden.set_storm(1.0)
	assert_almost_eq(_global("overcast_cover"), 0.4, 1e-6, "the drawing sky keeps the layer")
	shown.set_drawing(false)


func test_horizon_greys_with_the_storm() -> void:
	var sky := SkyScript.new({"horizon_color": Color(0.3, 0.5, 0.9)})
	var clear := sky.horizon_color()
	sky.set_storm(1.0)
	var storm := sky.horizon_color()
	assert_almost_eq(storm.r, storm.b, 1e-6, "a full storm's horizon is grey")
	assert_lt(SkyScript.luma(storm), SkyScript.luma(clear), "and darker than the clear one")


func test_only_the_sky_that_holds_the_layer_lets_it_go() -> void:
	var old := SkyScript.new({"cloud_amount": 0.3})
	old.set_drawing(true)
	var new := SkyScript.new({"cloud_amount": 0.6})
	new.set_drawing(true)
	old.set_drawing(false)
	assert_almost_eq(_global("overcast_cover"), 0.6, 1e-6, "the old sky turning off leaves the new one's clouds")
	old.set_storm(1.0)
	assert_almost_eq(_global("overcast_cover"), 0.6, 1e-6, "and its storm does not reach them")
	new = null  # the last reference: a sky freed while drawing
	assert_eq(_global("overcast_shadow"), 0.0, "takes its shadows with it")
	assert_eq(Clouds._owner, 0, "and leaves the layer free")


func test_set_param_reaches_material_or_layer() -> void:
	var sky := SkyScript.new()
	sky.set_drawing(true)
	sky.set_param("cloud_speed", 0.5)
	assert_almost_eq(_global("overcast_speed"), 0.5, 1e-6, "a layer key moves the global")
	assert_eq(sky.material.get_shader_parameter("cloud_speed"), null, "and stays off the material")
	sky.set_param("horizon_color", Color.RED)
	assert_eq(sky.material.get_shader_parameter("horizon_color"), Color.RED, "a uniform goes on the material")
	assert_eq(sky.params["horizon_color"], Color.RED, "and into params, which horizon_color() reads")
	sky.set_drawing(false)
