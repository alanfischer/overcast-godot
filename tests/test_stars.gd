extends "res://tests/suite.gd"

const SkyScript = preload("res://addons/overcast/overcast_sky.gd")
const Ephemeris = preload("res://addons/overcast/overcast_ephemeris.gd")
const Bake = preload("res://tools/bake_stars.gd")


## The catalogue's entry for the star at right ascension `ra`, declination `dec` (degrees, J2000).
func _texel_at(ra: float, dec: float) -> Color:
	var img: Image = _catalogue()
	var uv := Bake.octahedral(SkyScript._galaxy_turn * Ephemeris.radec(ra, dec)) * img.get_width()
	return img.get_pixel(int(uv.x), int(uv.y))


func _catalogue() -> Image:
	return load("res://addons/overcast/stars.res")


func test_the_catalogue_holds_the_stars_where_they_are() -> void:
	var img := _catalogue()
	assert_eq(img.get_format(), Image.FORMAT_RGBA8, "positions, magnitude and colour in a texel")
	var polaris := _texel_at(37.95, 89.26)
	assert_almost_eq(Bake.magnitude(polaris), 2.0, 0.05, "Polaris, magnitude 2")
	var sirius := _texel_at(101.29, -16.72)
	assert_almost_eq(Bake.magnitude(sirius), -1.46, 0.05, "Sirius, the brightest")
	var betelgeuse := _texel_at(88.79, 7.41)
	var rigel := _texel_at(78.63, -8.2)
	assert_gt(betelgeuse.a, rigel.a + 0.1, "Betelgeuse redder than Rigel")
	assert_eq(_texel_at(37.95, 80.0).b, 0.0, "and dark sky between")


func test_a_sky_draws_them_without_saving_them() -> void:
	var sky := SkyScript.new({"time_of_day": 23.0})
	sky._start()
	assert_false(sky._stars_bound, "headless, nothing drawn, nothing loaded")
	assert_eq(SkyScript._star_catalogue().get_width(), 1024, "the catalogue whole when it is")
	assert_eq(sky.get_shader_parameter("star_catalogue"), null, "and never a parameter that saves")
