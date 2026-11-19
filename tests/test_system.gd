extends "res://tests/suite.gd"

const Ephemeris = preload("res://addons/overcast/overcast_ephemeris.gd")
const Body = preload("res://addons/overcast/overcast_body.gd")
const System = preload("res://addons/overcast/overcast_system.gd")
const SkyScript = preload("res://addons/overcast/overcast_sky.gd")
const SOLAR = "res://addons/overcast/solar_system.tres"

const PLANETS := ["Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]


func _toward(alt: float, az: float) -> Vector3:
	var a := deg_to_rad(alt)
	var z := deg_to_rad(az)
	return Vector3(cos(a) * sin(z), sin(a), -cos(a) * cos(z))


func _body(sky: Dictionary, n: String) -> Dictionary:
	for b in sky["bodies"]:
		if b["body"].name == n:
			return b
	return {}


## JPL Horizons, airless apparent azimuth and elevation, and magnitude, per planet in PLANETS order.
func _check(unix: float, lat: float, lon: float, want: Array, what: String) -> void:
	var sky: Dictionary = load(SOLAR).sky_at(unix, lat, lon)
	for i in PLANETS.size():
		var b := _body(sky, PLANETS[i])
		var off := rad_to_deg(b["dir"].angle_to(_toward(want[i][1], want[i][0])))
		assert_lt(off, 0.05, "%s: %s within 3'" % [what, PLANETS[i]])
		assert_almost_eq(b["magnitude"], want[i][2], 0.6, "%s: %s about as bright" % [what, PLANETS[i]])


func test_the_planets_stand_where_they_do() -> void:
	_check(1782043200, 51.4769, 0.0, [[136.647243, 53.705724, 0.925], [117.403773, 44.145926, -4.025],
		[235.591579, 45.997860, 1.266], [130.454118, 51.275562, -1.826], [261.128644, 11.124724, 0.812],
		[226.479957, 52.007170, 5.818], [266.519008, 3.382301, 7.774]], "Greenwich, midsummer noon")
	_check(1797897600, 51.4769, 0.0, [[13.862511, -62.177412, -0.881], [63.059817, -35.509461, -4.675],
		[98.386256, 20.917714, 0.100], [106.681355, 29.635360, -2.341], [264.436093, 5.552339, 0.698],
		[228.344267, 51.243670, 5.611], [268.452917, 0.439737, 7.750]], "Greenwich, midwinter midnight")
	_check(1795003200, -33.87, 151.21, [[189.134760, -44.109939, -0.332], [169.360097, -45.894132, -4.857],
		[94.916786, -33.603544, 0.586], [95.084047, -32.129601, -2.106], [327.465027, 50.465398, 0.548],
		[35.067054, 26.817183, 5.600], [317.615332, 48.440421, 7.710]], "Sydney, a November night")
	_check(2214183600, 40.0, -74.0, [[330.423117, -57.633706, 1.641], [336.891199, -64.623776, -3.890],
		[255.186561, 58.382089, -0.042], [117.693944, 31.471396, -2.454], [111.519576, 21.027463, 0.550],
		[202.853204, 69.474319, 5.451], [284.735713, -1.286185, 7.789]], "New York, 2040")


func test_from_earth_it_is_the_sky_the_ephemeris_gives() -> void:
	var system: Resource = load(SOLAR)
	for unix in [1782043200.0, 1797897600.0, 2214183600.0]:
		var sky: Dictionary = system.sky_at(unix, 51.4769, 0.0)
		var plain := Ephemeris.sky_at(unix, 51.4769, 0.0)
		assert_lt(rad_to_deg(sky["sun"].angle_to(plain["sun"])), 0.01, "the sun")
		assert_lt(rad_to_deg(sky["moon"].angle_to(plain["moon"])), 0.01, "the moon")
		assert_almost_eq(sky["phase"], plain["phase"], 1e-4, "its phase")
		assert_true((sky["stars"] as Basis).is_equal_approx(plain["stars"]), "the stars")
		assert_almost_eq(sky["sun_scale"], 1.0, 0.02, "the sun as big as ever, give or take the year")
		assert_almost_eq(sky["moon_scale"], 1.0, 0.08, "the moon too, give or take its month")


## A world of one's own: a star, a home planet with a long day and two moons, and a giant near it.
func _made() -> Resource:
	var home := Body.new()
	home.name = "Home"
	home.distance = System.AU
	home.period = 400.0
	home.day = 30.0
	home.axial_tilt = 10.0
	var near := Body.new()
	near.name = "Near"
	near.distance = 300000.0
	near.period = 20.0
	near.radius = 1500.0
	var far := Body.new()
	far.name = "Far"
	far.distance = 900000.0
	far.radius = 600.0
	far.mean_anomaly = 120.0
	home.moons.assign([near, far])
	var giant := Body.new()
	giant.name = "Giant"
	giant.distance = 1.3 * System.AU
	giant.radius = 70000.0
	giant.mass = 300.0
	var s := System.new()
	s.bodies.assign([home, giant])
	s.home = "Home"
	return s


func test_a_world_of_ones_own_turns_with_its_day() -> void:
	var s := _made()
	# Day 0 is midnight on longitude 0; noon half a 30-hour day on.
	var midnight: Dictionary = s.sky_at(Ephemeris.days(0.0) * -86400.0, 0.0, 0.0)
	var noon: Dictionary = s.sky_at((15.0 / 24.0 - Ephemeris.days(0.0)) * 86400.0, 0.0, 0.0)
	assert_lt(midnight["sun"].y, -0.9, "the sun under foot at midnight")
	assert_gt(noon["sun"].y, 0.9, "and overhead at noon on the equator (tilted 10°)")
	var next: Dictionary = s.sky_at((30.0 / 24.0 - Ephemeris.days(0.0)) * 86400.0, 0.0, 0.0)
	assert_lt(next["sun"].y, -0.9, "midnight again a whole 30 hours on")


func test_a_world_of_ones_own_has_its_moons_and_neighbours() -> void:
	var s := _made()
	var sky: Dictionary = s.sky_at(0.0, 30.0, 0.0)
	var near: Resource = s.find("Near")
	assert_gt(sky["moon_scale"], 0.5, "its first moon is the sky's moon")
	var names := []
	for b in sky["bodies"]:
		names.append(b["body"].name)
	assert_true("Far" in names and "Giant" in names, "the rest are drawn")
	assert_false("Home" in names or "Near" in names, "not the world underfoot nor the sky's moon")
	# An orbit of 20 days round a world going round its star in 400: new to new in 21.05.
	var month := 1.0 / (1.0 / 20.0 - 1.0 / 400.0)
	var phases := []
	for day in [0.0, month * 0.5, month]:
		phases.append(s.sky_at(day * 86400.0, 30.0, 0.0)["phase"])
	assert_almost_eq(fposmod(phases[2] - phases[0] + 0.5, 1.0) - 0.5, 0.0, 0.01, "back where it was a month on")
	assert_almost_eq(fposmod(phases[1] - phases[0], 1.0), 0.5, 0.03, "and half round in half the time")
	# Kepler: the giant's year from the star's mass, at 1.3 AU about 1.48 years.
	assert_almost_eq(s._period(s.find("Giant"), null), 365.25 * pow(1.3, 1.5), 1.0, "a year by Kepler")
	assert_true(near != null, "found by name")


func test_a_world_with_no_moon_has_none_in_its_sky() -> void:
	var s := _made()
	s.find("Home").moons.clear()
	assert_eq(s.sky_at(0.0, 0.0, 0.0)["moon_scale"], 0.0, "nothing to draw or to light the night")


func test_magnitude_by_size_and_albedo() -> void:
	var venus: Resource = load(SOLAR).find("Venus")
	# At 1 AU from the sun and the eye, full: its absolute magnitude, -4.4.
	assert_almost_eq(System.magnitude(venus, System.AU, System.AU, 0.0), -4.4, 0.1, "Venus' H")
	var half := System.magnitude(venus, System.AU, System.AU, PI * 0.5)
	assert_gt(half, -4.4 + 0.8, "dimmer half lit")


func test_a_sky_draws_its_system() -> void:
	var sky = SkyScript.new()
	sky.placed = true
	var names := []
	for b in sky._now["bodies"]:
		names.append(b["body"].name)
	assert_true("Venus" in names and "Saturn" in names and "Phobos" in names, "the solar system by default")
	assert_false("Earth" in names or "Moon" in names, "but not the world underfoot or the moon")
	sky.system = _made()
	assert_gt(sky._now["moon_scale"], 0.0, "a world of one's own, with its moon")
	sky.system.find("Home").moons.clear()
	sky.system = sky.system
	sky.unix_time = 0.0
	assert_eq(sky._now["moon_scale"], 0.0, "and without one")
	assert_eq(sky.get_shader_parameter("moonlight"), 0.0, "no moonlight on a moonless world")
