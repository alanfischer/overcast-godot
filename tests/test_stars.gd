extends "res://tests/suite.gd"

const SkyScript = preload("res://addons/overcast/overcast_sky.gd")
const Ephemeris = preload("res://addons/overcast/overcast_ephemeris.gd")
const Bake = preload("res://tools/bake_stars.gd")


## The catalogue's entry for the star at right ascension `ra`, declination `dec` (degrees, J2000).
func _texel_at(ra: float, dec: float) -> Color:
	var img: Image = load("res://addons/overcast/stars.res")
	var uv := Bake.octahedral(SkyScript._galaxy_turn * Ephemeris.radec(ra, dec)) * img.get_width()
	return img.get_pixel(int(uv.x), int(uv.y))


func test_the_catalogue_holds_the_stars_where_they_are() -> void:
	var img: Image = load("res://addons/overcast/stars.res")
	assert_eq(img.get_format(), Image.FORMAT_RGBA8, "positions, magnitude and colour in a texel")
	var polaris := _texel_at(37.95, 89.26)
	assert_almost_eq((1.0 - polaris.b) * 255.0 / 25.0 - 2.0, 2.0, 0.05, "Polaris, magnitude 2")
	var sirius := _texel_at(101.29, -16.72)
	assert_almost_eq((1.0 - sirius.b) * 255.0 / 25.0 - 2.0, -1.46, 0.05, "Sirius, the brightest")
	var betelgeuse := _texel_at(88.79, 7.41)
	var rigel := _texel_at(78.63, -8.2)
	assert_gt(betelgeuse.a, rigel.a + 0.1, "Betelgeuse redder than Rigel")
	assert_eq(_texel_at(37.95, 80.0).b, 0.0, "and dark sky between")


func test_a_sky_draws_them_without_saving_them() -> void:
	var sky := SkyScript.new()
	assert_ne(SkyScript._catalogue, null, "the catalogue is loaded for it")
	assert_eq(SkyScript._catalogue.get_width(), 1024, "whole")
	assert_eq(sky.get_shader_parameter("star_catalogue"), null, "but not a parameter that saves")
