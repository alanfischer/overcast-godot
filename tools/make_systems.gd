extends SceneTree
## Writes addons/overcast/solar_system.tres, the real solar system seen from Earth, and
## demo/giant_moon.tres, a world of one's own: a moon of a ringed giant.
##   godot --headless --path . -s res://tools/make_systems.gd
##
## Orbits: Paul Schlyter's elements ("How to compute planetary positions"), epoch 2000 Jan 0.0 UT,
## ecliptic of date. Poles: IAU WGCCRE 2015, J2000 right ascension and declination, taken the way
## each turns (right hand), so Venus' and Uranus' point south of the ecliptic. Sizes, albedos
## and masses: NASA's planetary fact sheets, but Mercury's albedo is the one its absolute
## magnitude, -0.36, gives. Mars' moons: their mean orbits about Mars' equator.

const Body = preload("res://addons/overcast/overcast_body.gd")
const System = preload("res://addons/overcast/overcast_system.gd")


func _initialize() -> void:
	var s: Resource = System.new()
	s.home = "Earth"
	var moon := _body("Moon", System.MOON_RADIUS, 0.0123, 0.12, Color(0.82, 0.86, 1.0), 708.7, 269.99, 66.54)
	moon.corrections = Body.Corrections.MOON
	moon.distance = System.MOON_DISTANCE
	moon.period = 27.321582
	var earth := _planet("Earth", [0.0, 0.0, 0.0, 102.9404, 4.70935e-5, 1.0, 0.016709, 356.0470, 0.9856002585],
		6371.0, 1.0, 0.434, Color(0.65, 0.78, 1.0), 24.0, 0.0, 90.0)
	earth.corrections = Body.Corrections.EARTH
	earth.moons.assign([moon])
	var mars := _planet("Mars", [49.5574, 2.11081e-5, 1.8497, 286.5016, 2.92961e-5, 1.523688, 0.093405, 18.6021, 0.5240207766],
		3389.5, 0.107, 0.170, Color(1.0, 0.62, 0.42), 24.6597, 317.681, 52.887)
	mars.moons.assign([_moon_of(mars, "Phobos", 9376.0, 0.0151, 0.31891, 11.1, 0.071),
		_moon_of(mars, "Deimos", 23463.2, 0.00033, 1.26244, 6.2, 0.068)])
	var jupiter := _planet("Jupiter", [100.4542, 2.76854e-5, 1.3030, 273.8777, 1.64505e-5, 5.20256, 0.048498, 19.8950, 0.0830853001],
		69911.0, 317.8, 0.538, Color(0.96, 0.89, 0.76), 9.9259, 268.057, 64.495)
	jupiter.corrections = Body.Corrections.JUPITER
	jupiter.bands = 0.6
	var saturn := _planet("Saturn", [113.6634, 2.38980e-5, 2.4886, 339.3939, 2.97661e-5, 9.55475, 0.055546, 316.9670, 0.0334442282],
		58232.0, 95.2, 0.499, Color(0.96, 0.88, 0.68), 10.656, 40.589, 83.537)
	saturn.corrections = Body.Corrections.SATURN
	saturn.bands = 0.3
	saturn.rings_inner = 74500.0
	saturn.rings_outer = 136780.0
	var uranus := _planet("Uranus", [74.0005, 1.3978e-5, 0.7733, 96.6612, 3.0565e-5, 19.18171, 0.047318, 142.5905, 0.011725806],
		25362.0, 14.5, 0.488, Color(0.72, 0.9, 0.95), 17.24, 77.311, 15.175)
	uranus.corrections = Body.Corrections.URANUS
	var mercury := _planet("Mercury", [48.3313, 3.24587e-5, 7.0047, 29.1241, 1.01444e-5, 0.387098, 0.205635, 168.6562, 4.0923344368],
			2439.7, 0.0553, 0.106, Color(0.78, 0.74, 0.70), 4222.6, 281.01, 61.45)
	mercury.phase_dimming = 0.027
	s.bodies.assign([
		mercury,
		_planet("Venus", [76.6799, 2.46590e-5, 3.3946, 54.8910, 1.38374e-5, 0.723330, 0.006773, 48.0052, 1.6021302244],
			6051.8, 0.815, 0.689, Color(1.0, 0.97, 0.88), 2802.0, 92.76, -67.16),
		earth, mars, jupiter, saturn, uranus,
		_planet("Neptune", [131.7806, 3.0173e-5, 1.7700, 272.8461, -6.027e-6, 30.05826, 0.008606, 260.2471, 0.005995147],
			24622.0, 17.1, 0.442, Color(0.5, 0.64, 1.0), 16.11, 299.36, 43.46),
	])
	var err := ResourceSaver.save(s, "res://addons/overcast/solar_system.tres")
	print("solar_system.tres: ", error_string(err))
	var err2 := ResourceSaver.save(_giant_moon(), "res://demo/giant_moon.tres")
	print("giant_moon.tres: ", error_string(err2))
	quit(0 if err == OK and err2 == OK else 1)


## A world that is the moon of a ringed giant, as Jupiter is far from the sun, keeping one face to
## it so the giant hangs in its sky; a sister moon goes round inside its orbit.
func _giant_moon() -> Resource:
	var giant: Resource = Body.new()
	giant.name = "Giant"
	giant.distance = 5.2 * System.AU
	giant.mean_anomaly = 40.0
	giant.radius = 65000.0
	giant.mass = 300.0
	giant.albedo = 0.5
	giant.color = Color(0.95, 0.8, 0.62)
	giant.bands = 0.7
	giant.rings_inner = 85000.0
	giant.rings_outer = 150000.0
	giant.rings_color = Color(0.9, 0.85, 0.75, 0.75)
	giant.axial_tilt = 12.0
	giant.tilt_toward = 30.0
	giant.day = 10.0
	var home: Resource = Body.new()
	home.name = "Home"
	home.distance = 1.6e6
	home.inclination = 20.0
	home.node = 120.0
	home.radius = 5000.0
	home.mass = 0.05
	# Its axis the orbit's own, and its day the orbit: one face to the giant.
	home.axial_tilt = 20.0
	home.tilt_toward = 30.0
	var sister: Resource = Body.new()
	sister.name = "Sister"
	sister.distance = 700000.0
	sister.inclination = 12.0
	sister.node = 120.0
	sister.mean_anomaly = 200.0
	sister.radius = 2600.0
	sister.albedo = 0.4
	sister.color = Color(0.85, 0.82, 0.78)
	giant.moons.assign([home, sister])
	var s: Resource = System.new()
	s.bodies.assign([giant])
	s.home = "Home"
	home.day = s._period(home, giant) * 24.0
	return s


## e: [node, node a day, inclination, periapsis, periapsis a day, AU, eccentricity, mean anomaly,
## mean anomaly a day].
func _planet(n: String, e: Array, radius: float, mass: float, albedo: float, color: Color,
		day: float, pole_ra: float, pole_dec: float) -> Resource:
	var b := _body(n, radius, mass, albedo, color, day, pole_ra, pole_dec)
	b.node = e[0]
	b.node_rate = e[1]
	b.inclination = e[2]
	b.periapsis = e[3]
	b.periapsis_rate = e[4]
	b.distance = e[5] * System.AU
	b.eccentricity = e[6]
	b.mean_anomaly = e[7]
	b.period = 360.0 / e[8]
	return b


func _body(n: String, radius: float, mass: float, albedo: float, color: Color, day: float,
		pole_ra: float, pole_dec: float) -> Resource:
	var b: Resource = Body.new()
	b.name = n
	b.radius = radius
	b.mass = mass
	b.albedo = albedo
	b.color = color
	b.day = day
	# The pole from J2000 equatorial to the ecliptic.
	var eq := OvercastEphemeris.radec(pole_ra, pole_dec)
	var ecl := Basis(Vector3.RIGHT, -deg_to_rad(System.OBLIQUITY)) * eq
	b.axial_tilt = rad_to_deg(acos(clampf(ecl.z, -1.0, 1.0)))
	b.tilt_toward = fposmod(rad_to_deg(atan2(ecl.y, ecl.x)), 360.0)
	return b


## A moon on its planet's equator.
func _moon_of(planet: Resource, n: String, km: float, e: float, days: float, radius: float,
		albedo: float) -> Resource:
	var m: Resource = Body.new()
	m.name = n
	m.distance = km
	m.eccentricity = e
	m.period = days
	m.inclination = planet.axial_tilt
	m.node = fposmod(planet.tilt_toward + 90.0, 360.0)
	m.radius = radius
	m.mass = 0.0
	m.albedo = albedo
	m.phase_dimming = 0.03
	m.color = Color(0.6, 0.55, 0.5)
	m.day = days * 24.0
	m.axial_tilt = planet.axial_tilt
	m.tilt_toward = planet.tilt_toward
	return m
