class_name OvercastEphemeris
extends Object
## The arithmetic of the sky, after Paul Schlyter: orbits from their elements, the moon's
## disturbances, sidereal time, precession, and the turn from the sky's frames to the world's. Unix
## times are seconds UTC; latitude and longitude degrees, north and east positive. About an
## arcminute for the sun, a few for the moon; no refraction. OvercastSystem puts it together.
##
## The world is Godot's: up +Y, north -Z turned clockwise seen from above by `north` degrees.

## The galaxy's north pole, right ascension and declination in degrees.
const GALACTIC_POLE := Vector2(192.86, 27.13)
## Earth's equatorial radius, km: Schlyter's unit for the moon's distance.
const EARTH_RADIUS := 6378.14


## Days from 2000 Jan 0.0 UT, as Schlyter counts them.
static func days(unix: float) -> float:
	return unix / 86400.0 - 10956.0


## The tilt of Earth's equator to the ecliptic `d` days in, degrees.
static func obliquity(d: float) -> float:
	return 23.4393 - 3.563e-7 * d


## J2000 equatorial to the equator and equinox of `d` days in (IAU 1976): the frame the sun and
## sidereal time here are in, the pole wandering about 0.35° a quarter century.
static func precession(d: float) -> Basis:
	var t := d / 36525.0
	var arcsec := PI / 648000.0
	var zeta := (2306.2181 + (0.30188 + 0.017998 * t) * t) * t * arcsec
	var z := (2306.2181 + (1.09468 + 0.018203 * t) * t) * t * arcsec
	var theta := (2004.3109 - (0.42665 + 0.041833 * t) * t) * t * arcsec
	return Basis(Vector3.BACK, z) * Basis(Vector3.UP, -theta) * Basis(Vector3.BACK, zeta)


## Local sidereal time, degrees: the right ascension standing on the meridian.
static func sidereal(unix: float, longitude: float) -> float:
	var ut := fposmod(unix / 3600.0, 24.0)
	var d := days(unix)
	var sun_mean := 356.0470 + 0.9856002585 * d + 282.9404 + 4.70935e-5 * d
	return fposmod(sun_mean + 180.0 + ut * 15.0 + longitude, 360.0)


## The observer's place, equatorial, in Earth radii from its centre.
static func observer(lst: float, latitude: float) -> Vector3:
	var lat := deg_to_rad(latitude)
	var geocentric := lat - deg_to_rad(0.1924) * sin(2.0 * lat)
	var rho := 0.99833 + 0.00167 * cos(2.0 * lat)
	return rho * radec(lst, rad_to_deg(geocentric))


## Equatorial to world, under the sky at local sidereal time `lst` (degrees).
static func to_world(lst: float, latitude: float, north: float) -> Basis:
	var t := deg_to_rad(lst)
	var p := deg_to_rad(latitude)
	# Columns: where the equatorial axes land in east, north, up.
	var enu := Basis(
		Vector3(-sin(t), -sin(p) * cos(t), cos(p) * cos(t)),
		Vector3(cos(t), -sin(p) * sin(t), cos(p) * sin(t)),
		Vector3(0.0, cos(p), sin(p)))
	return Basis(bearing(90.0, north), bearing(0.0, north), Vector3.UP) * enu


## The world's way toward compass bearing `degrees` (clockwise from north), its north turned
## `north` degrees from -Z, clockwise seen from above.
static func bearing(degrees: float, north := 0.0) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, -deg_to_rad(north + degrees))


## A place on an ellipse about its focus, in the frame its angles are measured in: `node`,
## `periapsis` (from the node), `inclination` and mean anomaly `m` in degrees, `a` the semi-major
## axis in any unit, which the place comes back in.
static func ellipse(node: float, periapsis: float, inclination: float, a: float, e: float, m: float) -> Vector3:
	var ea := _kepler(m, e)
	var xv := a * (cos(ea) - e)
	var yv := a * sqrt(1.0 - e * e) * sin(ea)
	var u := atan2(yv, xv) + deg_to_rad(periapsis)
	var n := deg_to_rad(node)
	var i := deg_to_rad(inclination)
	return sqrt(xv * xv + yv * yv) * Vector3(cos(n) * cos(u) - sin(n) * sin(u) * cos(i),
		sin(n) * cos(u) + cos(n) * sin(u) * cos(i), sin(u) * sin(i))


## The moon about Earth `d` days in: ecliptic of date, km, its largest disturbances by the sun
## included.
static func moon(d: float) -> Vector3:
	var n := 125.1228 - 0.0529538083 * d
	var w := 318.0634 + 0.1643573223 * d
	var m := fposmod(115.3654 + 13.0649929509 * d, 360.0)
	var p := ellipse(n, w, 5.1454, 60.2666, 0.054900, m)
	var r := p.length()
	var lon := rad_to_deg(atan2(p.y, p.x))
	var lat := rad_to_deg(asin(p.z / r))
	var ms := deg_to_rad(356.0470 + 0.9856002585 * d)
	var mm := deg_to_rad(m)
	var lm := deg_to_rad(m + w + n)
	var dd := lm - deg_to_rad(356.0470 + 0.9856002585 * d + 282.9404 + 4.70935e-5 * d)
	var f := lm - deg_to_rad(n)
	lon += -1.274 * sin(mm - 2 * dd) + 0.658 * sin(2 * dd) - 0.186 * sin(ms) \
		- 0.059 * sin(2 * mm - 2 * dd) - 0.057 * sin(mm - 2 * dd + ms) + 0.053 * sin(mm + 2 * dd) \
		+ 0.046 * sin(2 * dd - ms) + 0.041 * sin(mm - ms) - 0.035 * sin(dd) - 0.031 * sin(mm + ms) \
		- 0.015 * sin(2 * f - 2 * dd) + 0.011 * sin(mm - 4 * dd)
	lat += -0.173 * sin(f - 2 * dd) - 0.055 * sin(mm - f - 2 * dd) - 0.046 * sin(mm + f - 2 * dd) \
		+ 0.033 * sin(f + 2 * dd) + 0.017 * sin(2 * mm + f)
	r += -0.58 * cos(mm - 2 * dd) - 0.46 * cos(2 * dd)
	return radec(lon, lat) * r * EARTH_RADIUS


## The eccentric anomaly (radians) for mean anomaly `m` (degrees).
static func _kepler(m: float, e: float) -> float:
	var mr := deg_to_rad(m)
	var ea := mr + e * sin(mr) * (1.0 + e * cos(mr))
	for _i in 3:
		ea -= (ea - e * sin(ea) - mr) / (1.0 - e * cos(ea))
	return ea


## Unit: toward longitude (or right ascension) and latitude (or declination) given in degrees.
static func radec(ra: float, dec: float) -> Vector3:
	var a := deg_to_rad(ra)
	var b := deg_to_rad(dec)
	return Vector3(cos(b) * cos(a), cos(b) * sin(a), sin(b))
