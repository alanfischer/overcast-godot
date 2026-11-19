extends "res://tests/suite.gd"

const Ephemeris = preload("res://addons/overcast/overcast_ephemeris.gd")


var _solar: Resource = load("res://addons/overcast/solar_system.tres")


## Reference positions from PyEphem (VSOP87 and ELP, refraction off), to a tenth of a degree.
func _check(unix: float, lat: float, lon: float, sun: Vector2, moon: Vector2, phase: float, what: String) -> void:
	var sky: Dictionary = _solar.sky_at(unix, lat, lon)
	var sun_off := rad_to_deg(sky["sun"].angle_to(_toward(sun.x, sun.y)))
	var moon_off := rad_to_deg(sky["moon"].angle_to(_toward(moon.x, moon.y)))
	assert_lt(sun_off, 0.05, what + ": the sun")
	assert_lt(moon_off, 0.15, what + ": the moon")
	assert_almost_eq(sky["phase"], phase, 0.002, what + ": the moon's phase")


func test_the_sun_and_moon_stand_where_they_do() -> void:
	_check(1782043200, 51.4769, 0.0, Vector2(61.958, 179.113), Vector2(2.138, 93.796), 0.2363, "Greenwich, midsummer noon")
	_check(1797811200, 51.4769, 0.0, Vector2(-61.956, 1.065), Vector2(42.108, 248.897), 0.3810, "Greenwich, midwinter midnight")
	_check(1782079200, 69.65, 18.96, Vector2(3.453, 349.425), Vector2(0.366, 259.310), 0.2501, "Tromsø, the midnight sun")
	_check(1797849000, 69.65, 18.96, Vector2(-3.115, 177.199), Vector2(5.845, 34.383), 0.3974, "Tromsø, the polar night's noon")
	_check(1794880800, -33.87, 151.21, Vector2(74.431, 342.152), Vector2(11.252, 100.248), 0.2374, "Sydney, the noon sun to the north")
	_check(1795532400, 40.0, -74.0, Vector2(24.812, 153.463), Vector2(-21.529, 336.276), 0.5002, "New York, a full moon set")


func test_north_turns_the_sky() -> void:
	var sky: Dictionary = _solar.sky_at(1782043200, 51.4769, 0.0)
	var turned: Dictionary = _solar.sky_at(1782043200, 51.4769, 0.0, 90.0)
	assert_almost_eq(_altaz(turned["sun"]).x, _altaz(sky["sun"]).x, 1e-6, "as high as before")
	assert_vec3_almost_eq(turned["sun"], sky["sun"].rotated(Vector3.UP, -PI * 0.5), 1e-6, "turned clockwise seen from above")


func test_the_stars_turn_about_the_pole() -> void:
	for hours in [0.0, 6.0, 13.5]:
		var unix: float = 1797811200 + hours * 3600.0
		var sky: Dictionary = _solar.sky_at(unix, 51.4769, 0.0)
		var pole := _toward(51.4769, 0.0)
		# The stars are J2000's: the pole of date, precessed back, stands at the latitude.
		var of_date: Basis = Ephemeris.precession(Ephemeris.days(unix)) * sky["stars"]
		assert_vec3_almost_eq(of_date * pole, Vector3(0, 0, 1), 1e-6, "the pole stands at the latitude, due north")
		var sun_among_stars: Vector3 = of_date * sky["sun"]
		assert_almost_eq(rad_to_deg(asin(sun_among_stars.z)), -23.43, 0.05, "and midwinter's sun is as far south as it goes")


func test_the_clock_is_universal_time() -> void:
	assert_almost_eq(Ephemeris.days(946684800), 1.0, 1e-9, "2000-01-01 is day one")
	var greenwich := Ephemeris.sidereal(1782043200, 0.0)
	assert_almost_eq(Ephemeris.sidereal(1782043200, 90.0), fposmod(greenwich + 90.0, 360.0), 1e-9, "east is later")
	var next_day := Ephemeris.sidereal(1782043200 + 86400, 0.0)
	assert_almost_eq(fposmod(next_day - greenwich, 360.0), 0.9856, 0.001, "the stars gain a degree a day")


func test_the_stars_precess_from_j2000() -> void:
	var p := Ephemeris.precession(Ephemeris.days(Time.get_unix_time_from_datetime_string("2026-01-01T00:00:00")))
	var equator: Vector3 = p * Ephemeris.radec(90.0, 0.0)
	assert_almost_eq(rad_to_deg(atan2(equator.y, equator.x)) - 90.0, 80.0 / 240.0, 0.005,
		"at 6h on the equator, 3.07 s of right ascension a year")
	var polaris: Vector3 = p * Ephemeris.radec(37.95, 89.264)
	assert_almost_eq(rad_to_deg(asin(polaris.z)), 89.371, 0.003, "Polaris nearer the pole, +89°22'")
