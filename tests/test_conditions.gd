extends "res://tests/suite.gd"

const Weather = preload("res://addons/overcast/overcast_weather.gd")
const SkyScript = preload("res://addons/overcast/overcast_sky.gd")
const Conditions = preload("res://addons/overcast/overcast_conditions.gd")
const Globals = preload("res://addons/overcast/overcast_globals.gd")


func test_conditions_blend_between_two() -> void:
	var a := Conditions.new()
	var b := Conditions.new()
	b.mid_cover = 0.8
	b.rain = 1.0
	b.temperature = -10.0
	b.wind = Vector3(4.0, 0.0, 0.0)
	var half := Conditions.blend(a, b, 0.5)
	assert_almost_eq(half.mid_cover, 0.4, 1e-6, "cover halfway")
	assert_almost_eq(half.temperature, 0.0, 1e-6, "and the temperature")
	assert_vec3_almost_eq(half.wind, Vector3(2.0, 0.0, 0.0), 1e-6, "and the wind")
	assert_almost_eq(a.mid_cover, 0.0, 1e-6, "a new one, the two left as they were")


func test_the_weather_and_its_sky_follow_the_conditions() -> void:
	var w := Weather.new()
	_keep(w)
	var sky := SkyScript.new({"drawing": false})
	w.sky = sky
	w.cycle = true
	_root().add_child(w)
	var c := Conditions.new()
	c.rain = 0.6
	c.temperature = -4.0
	c.wind = Vector3(3.0, 0.0, 1.0)
	c.low_cover = 0.2
	c.mid_cover = 0.7
	c.mid_base = 5000.0
	c.high_cover = 0.9
	c.high_base = 11000.0
	c.low_sheet = 0.5
	c.towering = 0.8
	c.mid_sheet = 1.0
	c.high_sheet = 0.6
	w.conditions = c
	w._process(0.1)
	assert_eq(w.rain, 0.6, "it rains as they say, the showers overridden")
	assert_eq(w.temperature, -4.0, "as cold")
	assert_vec3_almost_eq(w.wind, c.wind, 1e-6, "with their wind")
	assert_vec3_almost_eq(w.wind_aloft(), c.wind * 2.0, 1e-6, "twice as hard aloft, with none given")
	c.wind_aloft = Vector3(0.0, 0.0, -12.0)
	c.gustiness = 0.8
	w._process(0.1)
	assert_vec3_almost_eq(w.wind_aloft(), c.wind_aloft, 1e-6, "or theirs")
	assert_eq(w.gustiness, 0.8, "and their gusts")
	assert_almost_eq(w.snow_share, 1.0, 1e-6, "snow at -4 by the weather's own reckoning")
	c.snow_share = 0.25
	c.visibility = 400.0
	w._process(0.1)
	assert_eq(w.snow_share, 0.25, "or by theirs")
	assert_eq(w.visibility, 400.0, "fog as they say")
	assert_almost_eq(w.mist(), 3.912 / 400.0 - 3.912 / 20000.0, 1e-9, "thick as that")
	assert_almost_eq(sky.cloud_amount, 0.2, 1e-6, "the sky takes the low cloud")
	assert_almost_eq(sky.mid_cloud_amount, 0.7, 1e-6, "the middle")
	assert_eq(sky.mid_cloud_height, 5000.0, "at its height")
	assert_almost_eq(sky.param(&"cirrus_amount"), 0.9, 1e-6, "and the cirrus")
	assert_eq(sky.cirrus_height, 11000.0, "at its own")
	assert_almost_eq(sky.cloud_sheet, 0.5, 1e-6, "stratocumulus")
	assert_almost_eq(sky.cloud_towering, 0.8, 1e-6, "thunderheads")
	assert_almost_eq(sky.mid_cloud_sheet, 1.0, 1e-6, "altostratus")
	assert_almost_eq(sky.cirrus_sheet, 0.6, 1e-6, "and cirrostratus")


func test_higher_cloud_veils_the_sun() -> void:
	var sky := SkyScript.new()
	sky.drawing = true
	sky._start()
	assert_eq(Globals.value("overcast_veil"), 0.0, "no middle layer, nothing taken off")
	sky.mid_cloud_amount = 1.0
	assert_gt(sky.veil, 0.3, "a full one dims the sun")
	assert_almost_eq(Globals.value("overcast_veil"), sky.veil, 1e-6, "on the ground too")
	var puffs := sky.veil
	sky.mid_cloud_sheet = 1.0
	assert_gt(sky.veil, puffs, "spread into altostratus it takes more")
	sky.mid_cloud_amount = 0.0
	assert_eq(sky.veil, 0.0, "cirrus takes nothing")
	sky.cirrus_amount = 1.0
	sky.cirrus_sheet = 1.0
	assert_gt(sky.veil, 0.0, "cirrostratus a little")
	assert_lt(sky.veil, 0.2, "only a little")
	sky.mid_cloud_amount = 1.0
	sky.set_weather(1.0, 0.0)
	assert_eq(sky.veil, 0.0, "under a storm's deck it is the deck that shades")
	sky.set_weather(0.0, 0.0, 3.912 / 300.0)
	sky.mid_cloud_amount = 0.0
	sky.cirrus_amount = 0.0
	assert_gt(sky.veil, 0.7, "300 m fog under a 100 m base takes most of the sun")
	assert_almost_eq(Globals.value("overcast_veil"), sky.veil, 1e-6, "off the ground too")
	sky.drawing = false
	assert_eq(Globals.value("overcast_veil"), 0.0, "and none once the sky lets go")


func test_the_higher_layers_ride_at_their_share_of_the_low_one() -> void:
	var sky := SkyScript.new({"drawing": false, "cloud_height": 2000.0, "mid_cloud_height": 5000.0})
	var names := _uniform_names(sky.shader)
	for u in [&"mid_cloud_amount", &"mid_cloud_rise", &"cirrus_rise", &"atmosphere_mid_light", &"atmosphere_high_light",
			&"cloud_sheet", &"mid_cloud_sheet", &"cirrus_sheet", &"cloud_towering"]:
		assert_true(names.has(u), "the sky shader takes %s" % u)
	assert_eq(sky.get_shader_parameter(&"mid_cloud_rise"), null, "the rises are not saved with the sky")


func test_higher_cloud_keeps_the_sun_longer() -> void:
	var set_sun := Vector3(0.0, -0.035, -1.0).normalized()
	var low := SkyScript.cloud_light_at(set_sun, 1.0, 1500.0).length()
	var mid := SkyScript.cloud_light_at(set_sun, 1.0, 4000.0).length()
	var high := SkyScript.cloud_light_at(set_sun, 1.0, 9000.0).length()
	assert_gt(mid, low, "with the sun two degrees down, the middle layer still has it")
	assert_gt(high, mid, "and the cirrus more")


func test_the_layer_spreads_into_a_sheet_on_the_ground_too() -> void:
	var sky := SkyScript.new()
	sky.drawing = true
	sky._start()
	assert_eq(Globals.value("overcast_sheet"), 0.0, "cumulus")
	sky.cloud_sheet = 1.0
	assert_eq(Globals.value("overcast_sheet"), 1.0, "stratus, which the shadows read as the sky does")
	sky.drawing = false
	assert_eq(Globals.value("overcast_sheet"), 0.0, "and back once the sky lets go")
