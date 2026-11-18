class_name OvercastEphemeris
extends Object
## Where the sun and moon stand and how the stars are turned, at a Unix time (seconds, UTC) from a
## latitude and longitude (degrees, north and east positive). Paul Schlyter's method: about an
## arcminute for the sun, a few for the moon, the moon's parallax included; no refraction.
##
## The world is Godot's: up +Y, north -Z turned clockwise seen from above by `north` degrees.

## The galaxy's north pole, right ascension and declination in degrees.
const GALACTIC_POLE := Vector2(192.86, 27.13)


## Days from 2000 Jan 0.0 UT, as Schlyter counts them.
static func days(unix: float) -> float:
	return unix / 86400.0 - 10956.0


## The sun and moon, world space, and the stars' turn, at `unix` from the place given.
## sun and moon: unit, toward them. phase: the moon's, 0 new, 0.5 full, waxing between.
## stars: takes a world direction to one fixed among the stars (equatorial, +Z the celestial pole).
static func sky_at(unix: float, latitude: float, longitude: float, north := 0.0) -> Dictionary:
	var d := days(unix)
	var sun := _sun(d)
	var moon := _moon(d, sun)
	var lst := sidereal(unix, longitude)
	var to_world := _to_world(lst, latitude, north)
	var near_moon: Vector3 = moon["at"] - observer(lst, latitude)
	return {
		"sun": to_world * _equatorial(sun["lon"], 0.0, d),
		"moon": to_world * near_moon.normalized(),
		"phase": fposmod(moon["lon"] - sun["lon"], 360.0) / 360.0,
		"stars": to_world.transposed(),
	}


## Local sidereal time, degrees: the right ascension standing on the meridian.
static func sidereal(unix: float, longitude: float) -> float:
	var d := days(unix)
	var sun_mean := 356.0470 + 0.9856002585 * d + 282.9404 + 4.70935e-5 * d
	var ut := fposmod(unix / 3600.0, 24.0)
	return fposmod(sun_mean + 180.0 + ut * 15.0 + longitude, 360.0)


## The observer's place, equatorial, in Earth radii from its centre.
static func observer(lst: float, latitude: float) -> Vector3:
	var lat := deg_to_rad(latitude)
	var geocentric := lat - deg_to_rad(0.1924) * sin(2.0 * lat)
	var rho := 0.99833 + 0.00167 * cos(2.0 * lat)
	var t := deg_to_rad(lst)
	return rho * Vector3(cos(geocentric) * cos(t), cos(geocentric) * sin(t), sin(geocentric))


## Equatorial to world, under the sky at local sidereal time `lst` (degrees).
static func _to_world(lst: float, latitude: float, north: float) -> Basis:
	var t := deg_to_rad(lst)
	var p := deg_to_rad(latitude)
	# Columns: where the equatorial axes land in east, north, up.
	var enu := Basis(
		Vector3(-sin(t), -sin(p) * cos(t), cos(p) * cos(t)),
		Vector3(cos(t), -sin(p) * sin(t), cos(p) * sin(t)),
		Vector3(0.0, cos(p), sin(p)))
	var north_w := Vector3.FORWARD.rotated(Vector3.UP, -deg_to_rad(north))
	var east_w := north_w.rotated(Vector3.UP, -PI * 0.5)
	return Basis(east_w, north_w, Vector3.UP) * enu


## Ecliptic longitude and latitude (degrees) to a unit equatorial vector, d days in.
static func _equatorial(lon: float, lat: float, d: float) -> Vector3:
	var l := deg_to_rad(lon)
	var b := deg_to_rad(lat)
	var ecl := deg_to_rad(23.4393 - 3.563e-7 * d)
	var v := Vector3(cos(b) * cos(l), cos(b) * sin(l), sin(b))
	return Vector3(v.x, v.y * cos(ecl) - v.z * sin(ecl), v.y * sin(ecl) + v.z * cos(ecl))


## The sun's ecliptic longitude (lon), mean anomaly (m) and mean longitude (l), degrees.
static func _sun(d: float) -> Dictionary:
	var w := 282.9404 + 4.70935e-5 * d
	var e := 0.016709 - 1.151e-9 * d
	var m := fposmod(356.0470 + 0.9856002585 * d, 360.0)
	var ea := _kepler(m, e)
	var v := rad_to_deg(atan2(sqrt(1.0 - e * e) * sin(ea), cos(ea) - e))
	return {"lon": fposmod(v + w, 360.0), "m": m, "l": fposmod(m + w, 360.0)}


## The moon: ecliptic longitude (lon, degrees) and its place equatorial in Earth radii (at).
static func _moon(d: float, sun: Dictionary) -> Dictionary:
	var n := 125.1228 - 0.0529538083 * d
	var i := 5.1454
	var w := 318.0634 + 0.1643573223 * d
	var a := 60.2666
	var e := 0.054900
	var m := fposmod(115.3654 + 13.0649929509 * d, 360.0)
	var ea := _kepler(m, e)
	var xv := a * (cos(ea) - e)
	var yv := a * sqrt(1.0 - e * e) * sin(ea)
	var r := sqrt(xv * xv + yv * yv)
	var vw := atan2(yv, xv) + deg_to_rad(w)
	var nr := deg_to_rad(n)
	var ir := deg_to_rad(i)
	var xh := cos(nr) * cos(vw) - sin(nr) * sin(vw) * cos(ir)
	var yh := sin(nr) * cos(vw) + cos(nr) * sin(vw) * cos(ir)
	var zh := sin(vw) * sin(ir)
	var lon := rad_to_deg(atan2(yh, xh))
	var lat := rad_to_deg(atan2(zh, sqrt(xh * xh + yh * yh)))
	# The largest perturbations, by the sun's pull.
	var ms := deg_to_rad(sun["m"])
	var mm := deg_to_rad(m)
	var lm := deg_to_rad(m + w + n)
	var dd := lm - deg_to_rad(sun["l"])
	var f := lm - nr
	lon += -1.274 * sin(mm - 2 * dd) + 0.658 * sin(2 * dd) - 0.186 * sin(ms) \
		- 0.059 * sin(2 * mm - 2 * dd) - 0.057 * sin(mm - 2 * dd + ms) + 0.053 * sin(mm + 2 * dd) \
		+ 0.046 * sin(2 * dd - ms) + 0.041 * sin(mm - ms) - 0.035 * sin(dd) - 0.031 * sin(mm + ms) \
		- 0.015 * sin(2 * f - 2 * dd) + 0.011 * sin(mm - 4 * dd)
	lat += -0.173 * sin(f - 2 * dd) - 0.055 * sin(mm - f - 2 * dd) - 0.046 * sin(mm + f - 2 * dd) \
		+ 0.033 * sin(f + 2 * dd) + 0.017 * sin(2 * mm + f)
	r += -0.58 * cos(mm - 2 * dd) - 0.46 * cos(2 * dd)
	return {"lon": fposmod(lon, 360.0), "at": _equatorial(lon, lat, d) * r}


## The eccentric anomaly (radians) for mean anomaly `m` (degrees).
static func _kepler(m: float, e: float) -> float:
	var mr := deg_to_rad(m)
	var ea := mr + e * sin(mr) * (1.0 + e * cos(mr))
	for _i in 3:
		ea -= (ea - e * sin(ea) - mr) / (1.0 - e * cos(ea))
	return ea


## Unit, equatorial: toward right ascension and declination given in degrees.
static func radec(ra: float, dec: float) -> Vector3:
	var a := deg_to_rad(ra)
	var b := deg_to_rad(dec)
	return Vector3(cos(b) * cos(a), cos(b) * sin(a), sin(b))
