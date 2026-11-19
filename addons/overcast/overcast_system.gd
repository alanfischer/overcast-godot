@tool
class_name OvercastSystem
extends Resource
## A star, the planets and moons that go round it, and the world among them the sky is seen from
## (`home`). OvercastSky takes its sun, moon, stars and planets from one: solar_system.tres, the
## real one seen from Earth, unless it is given another. Make your own, or add to a copy of it.
##
## The home world's first moon is the sky's moon, the one that lights the night. Everything else
## is drawn where it stands: far planets as points as bright as they are, near ones as discs.

const _Ephemeris = preload("res://addons/overcast/overcast_ephemeris.gd")
const _Body = preload("res://addons/overcast/overcast_body.gd")
const AU := 1.495978707e8
const SUN_RADIUS := 696000.0
## Earth's moon, as the sky's moon_size draws it.
const MOON_RADIUS := 1737.4
const MOON_DISTANCE := 384400.0
## The ecliptic's tilt to Earth's equator at J2000: the star catalogue's frame from the ecliptic.
const OBLIQUITY := 23.4393
const _GM_SUN := 1.32712440018e11  # km³/s²
const _GM_EARTH := 398600.4418
const _EARTH_RADIUS := 6378.14

## km.
@export_range(1.0, 1e8, 1.0, "or_greater", "suffix:km") var star_radius := SUN_RADIUS
## In suns: what the planets' periods follow when they give none.
@export_range(0.0, 100.0, 0.001, "or_greater") var star_mass := 1.0
@export var bodies: Array[_Body] = []
## The name of the body the sky is seen from.
@export var home := "Earth"


## The body called `body_name`, a planet or a moon; null if none is.
func find(body_name: String) -> _Body:
	for b in _all():
		if b.name == body_name:
			return b
	return null


## Every body, planets before their moons.
func _all() -> Array[_Body]:
	var out: Array[_Body] = []
	for b in bodies:
		if b:
			out.append(b)
			for m in b.moons:
				if m:
					out.append(m)
	return out


## Where `body` is `d` days from the epoch: km from the star, in the ecliptic frame.
func position(body: _Body, d: float) -> Vector3:
	return _positions(d)[body]


func _positions(d: float) -> Dictionary:
	var at := {}
	for b in bodies:
		if b:
			at[b] = _orbit(b, d, null)
			for m in b.moons:
				if m:
					at[m] = at[b] + _orbit(m, d, b)
	return at


## Where `body` stands about what it orbits (`parent`, or the star), km, ecliptic.
func _orbit(body: _Body, d: float, parent: _Body) -> Vector3:
	if body.corrections == _Body.Corrections.MOON:
		var sun := _Ephemeris._sun(d)
		return _Ephemeris._moon(d, sun)["ecl"] * _EARTH_RADIUS
	var n := deg_to_rad(body.node + body.node_rate * d)
	var w := deg_to_rad(body.periapsis + body.periapsis_rate * d)
	var i := deg_to_rad(body.inclination)
	var e := body.eccentricity
	var a := body.distance
	var m := fposmod(body.mean_anomaly + 360.0 / _period(body, parent) * d, 360.0)
	var ea := _Ephemeris._kepler(m, e)
	var xv := a * (cos(ea) - e)
	var yv := a * sqrt(1.0 - e * e) * sin(ea)
	var r := sqrt(xv * xv + yv * yv)
	var u := atan2(yv, xv) + w
	var p := r * Vector3(cos(n) * cos(u) - sin(n) * sin(u) * cos(i),
		sin(n) * cos(u) + cos(n) * sin(u) * cos(i), sin(u) * sin(i))
	if body.corrections >= _Body.Corrections.JUPITER:
		p = _perturbed(p, body.corrections, d)
	return p


## Days for one orbit: the body's own, or Kepler's from the mass it goes round.
func _period(body: _Body, parent: _Body) -> float:
	if body.period > 0.0:
		return body.period
	var gm := parent.mass * _GM_EARTH if parent else star_mass * _GM_SUN
	return TAU * sqrt(pow(body.distance, 3.0) / maxf(gm, 1e-9)) / 86400.0


## Jupiter, Saturn and Uranus pull each other a little off their ellipses (Schlyter).
static func _perturbed(p: Vector3, which: _Body.Corrections, d: float) -> Vector3:
	var r := p.length()
	var lon := rad_to_deg(atan2(p.y, p.x))
	var lat := rad_to_deg(asin(p.z / r))
	var mj := deg_to_rad(19.8950 + 0.0830853001 * d)
	var ms := deg_to_rad(316.9670 + 0.0334442282 * d)
	var mu := deg_to_rad(142.5905 + 0.011725806 * d)
	var dg := deg_to_rad(1.0)
	match which:
		_Body.Corrections.JUPITER:
			lon += -0.332 * sin(2 * mj - 5 * ms - 67.6 * dg) - 0.056 * sin(2 * mj - 2 * ms + 21 * dg) \
				+ 0.042 * sin(3 * mj - 5 * ms + 21 * dg) - 0.036 * sin(mj - 2 * ms) \
				+ 0.022 * cos(mj - ms) + 0.023 * sin(2 * mj - 3 * ms + 52 * dg) \
				- 0.016 * sin(mj - 5 * ms - 69 * dg)
		_Body.Corrections.SATURN:
			lon += 0.812 * sin(2 * mj - 5 * ms - 67.6 * dg) - 0.229 * cos(2 * mj - 4 * ms - 2 * dg) \
				+ 0.119 * sin(mj - 2 * ms - 3 * dg) + 0.046 * sin(2 * mj - 6 * ms - 69 * dg) \
				+ 0.014 * sin(mj - 3 * ms + 32 * dg)
			lat += -0.020 * cos(2 * mj - 4 * ms - 2 * dg) + 0.018 * sin(2 * mj - 6 * ms - 49 * dg)
		_Body.Corrections.URANUS:
			lon += 0.040 * sin(ms - 2 * mu + 6 * dg) + 0.035 * sin(ms - 3 * mu + 33 * dg) \
				- 0.015 * sin(mj - mu + 20 * dg)
	return _Ephemeris.radec(lon, lat) * r


## The sky from `latitude` and `longitude` (degrees) on the home world at `unix` (seconds, UTC),
## its north turned `north` degrees from -Z. World space, unit vectors toward things:
## sun, and sun_scale (its size against the sun's from Earth);
## moon, phase (0 new, 0.5 full), lit_from (toward the sun from it) and moon_scale (its size against
##   Earth's moon's), moon_scale 0 for a world with none;
## stars: world to J2000 equatorial, the star catalogue's frame;
## bodies: the rest, each {body, dir, size (angular radius, radians), magnitude, lit_from, pole}.
func sky_at(unix: float, latitude: float, longitude: float, north := 0.0) -> Dictionary:
	var d := _Ephemeris.days(unix)
	var at := _positions(d)
	var home_body := find(home)
	if home_body == null:
		push_error("OvercastSystem has no body called '%s'" % home)
		return {}
	var here: Vector3 = at[home_body]
	var view := _view(home_body, here, unix, d, latitude, longitude, north)
	var to_world: Basis = view["to_world"]
	var eye: Vector3 = here + view["offset"]
	var out := {"sun": to_world * (-eye).normalized(), "stars": view["stars"],
		"sun_scale": star_radius / SUN_RADIUS / (here.length() / AU), "bodies": []}

	var moon: _Body = home_body.moons[0] if not home_body.moons.is_empty() else null
	if moon:
		var toward: Vector3 = at[moon] - eye
		var from_home: Vector3 = at[moon] - here
		out["moon"] = to_world * toward.normalized()
		out["phase"] = fposmod(atan2(from_home.y, from_home.x) - atan2(-here.y, -here.x), TAU) / TAU
		out["lit_from"] = to_world * (-at[moon] as Vector3).normalized()
		out["moon_scale"] = moon.radius / MOON_RADIUS / (toward.length() / MOON_DISTANCE)
	else:
		out["moon"] = out["sun"]
		out["phase"] = 0.0
		out["lit_from"] = out["sun"]
		out["moon_scale"] = 0.0

	for b in _all():
		if b == home_body or b == moon:
			continue
		var toward: Vector3 = at[b] - eye
		var dist := toward.length()
		var lit := (-at[b] as Vector3).normalized()
		out["bodies"].append({"body": b, "dir": to_world * (toward / dist),
			"size": asin(minf(b.radius / dist, 1.0)),
			"magnitude": magnitude(b, (at[b] as Vector3).length(), dist, lit.angle_to(-toward)),
			"lit_from": to_world * lit, "pole": to_world * b.pole()})
	return out


## How the home world turns the sky: `to_world` from the ecliptic, `stars` from world to J2000
## equatorial, and `offset`, the eye from the world's centre, km, ecliptic.
func _view(home_body: _Body, here: Vector3, unix: float, d: float, latitude: float,
		longitude: float, north: float) -> Dictionary:
	if home_body.corrections == _Body.Corrections.EARTH:
		# Earth turns by sidereal time about the equator of date, which precession carries.
		var lst := _Ephemeris.sidereal(unix, longitude)
		var to_eq := Basis(Vector3.RIGHT, deg_to_rad(23.4393 - 3.563e-7 * d))
		var eq_to_world := _Ephemeris._to_world(lst, latitude, north)
		return {"to_world": eq_to_world * to_eq,
			"stars": (eq_to_world * _Ephemeris.precession(d)).transposed(),
			"offset": to_eq.transposed() * _Ephemeris.observer(lst, latitude) * _EARTH_RADIUS}
	# Its equator's frame in the ecliptic: x where the equator rises through the ecliptic.
	var z := home_body.pole()
	var x := Vector3(0.0, 0.0, 1.0).cross(z)
	x = x.normalized() if x.length() > 1e-6 else Vector3.RIGHT
	var to_eq := Basis(x, z.cross(x), z).transposed()
	# Local solar time is the clock: noon at the meridian at 12 on longitude 0, midnight at the epoch.
	var sun := to_eq * (-here).normalized()
	var turned := fposmod(d * 24.0 / home_body.day, 1.0) * 360.0
	var lst := rad_to_deg(atan2(sun.y, sun.x)) + 180.0 + turned + longitude
	var eq_to_world := _Ephemeris._to_world(lst, latitude, north)
	var to_world := eq_to_world * to_eq
	var lat := deg_to_rad(latitude)
	var t := deg_to_rad(lst)
	var up := Vector3(cos(lat) * cos(t), cos(lat) * sin(t), sin(lat))
	return {"to_world": to_world,
		"stars": (to_world * Basis(Vector3.RIGHT, -deg_to_rad(OBLIQUITY))).transposed(),
		"offset": to_eq.transposed() * up * home_body.radius}


## The body's apparent magnitude: `from_star` and `from_eye` km off, lit at `phase_angle`
## (radians, 0 full). Absolute magnitude by its size and albedo; dimmed by phase at its
## phase_dimming, or as a dull sphere.
static func magnitude(body: _Body, from_star: float, from_eye: float, phase_angle: float) -> float:
	var h := 5.0 * log(1329.0 / maxf(2.0 * body.radius * sqrt(maxf(body.albedo, 1e-4)), 1e-6)) / log(10.0)
	var a := clampf(phase_angle, 0.0, PI)
	# A rough rock dims steeply to a crescent: Mercury's own law (Schlyter), scaled to the body's.
	var deg := rad_to_deg(a)
	var phase := body.phase_dimming * (deg + 2.2e-13 / 0.027 * pow(deg, 6.0))
	if body.phase_dimming <= 0.0:
		phase = -2.5 * log(maxf((sin(a) + (PI - a) * cos(a)) / PI, 1e-6)) / log(10.0)
	return h + 5.0 * log(from_star / AU * from_eye / AU) / log(10.0) + phase
