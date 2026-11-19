@tool
class_name OvercastBody
extends Resource
## A planet or moon of an OvercastSystem: how it goes round what it orbits, how big and bright it
## is, and how it turns. A planet orbits the system's star; a body in a planet's `moons` orbits
## that planet. Orbits are laid in the ecliptic (the plane of the home world's orbit for a world
## of your own), angles in degrees, at the epoch 2000 Jan 0.0 UT.

enum Corrections {
	NONE,
	## The real bodies' largest disturbances (Schlyter): the moon by the sun, and Jupiter, Saturn
	## and Uranus by each other. Earth is the real one, turned by sidereal time and precession.
	EARTH, MOON, JUPITER, SATURN, URANUS,
}

@export var name := ""

@export_group("Orbit")
## The orbit's semi-major axis, km.
@export_range(0.0, 1e10, 1.0, "or_greater", "suffix:km") var distance := 1.496e8
@export_range(0.0, 0.99, 0.000001) var eccentricity := 0.0
## Tilt of the orbit from the ecliptic.
@export_range(-180.0, 180.0, 0.0001, "suffix:°") var inclination := 0.0
## Longitude of the ascending node.
@export_range(0.0, 360.0, 0.0001, "suffix:°") var node := 0.0
## Argument of periapsis, from the node.
@export_range(0.0, 360.0, 0.0001, "suffix:°") var periapsis := 0.0
## Mean anomaly at the epoch.
@export_range(0.0, 360.0, 0.0001, "suffix:°") var mean_anomaly := 0.0
## Days for one orbit. 0 takes it from what it orbits: the star's mass, or the planet's.
@export_range(0.0, 1e6, 0.0001, "or_greater", "suffix:days") var period := 0.0
## How fast the node and periapsis wander, degrees a day.
@export var node_rate := 0.0
@export var periapsis_rate := 0.0
@export var corrections := Corrections.NONE

@export_group("Body")
@export_range(0.0, 1e6, 0.1, "or_greater", "suffix:km") var radius := 6371.0
## In Earth masses: what its moons' periods follow when they give none.
@export_range(0.0, 1e5, 0.0001, "or_greater") var mass := 1.0
## How much of the light falling on it comes back (geometric albedo): with the radius, how bright.
@export_range(0.0, 1.0, 0.001) var albedo := 0.3
## How fast it dims as less of it is lit, magnitudes a degree of phase angle: about 0.03 for a dark,
## rough rock. 0 dims as a smooth sphere does.
@export_range(0.0, 0.1, 0.001) var phase_dimming := 0.0
@export var color := Color(1.0, 1.0, 1.0)
## Stripes along its latitudes, as on a gas giant: 0 none.
@export_range(0.0, 1.0, 0.01) var bands := 0.0
## Rings about its equator, from the planet's centre, km. 0 for none.
@export_range(0.0, 1e7, 1.0, "or_greater", "suffix:km") var rings_inner := 0.0
@export_range(0.0, 1e7, 1.0, "or_greater", "suffix:km") var rings_outer := 0.0
## Alpha is how much of the light behind the rings they hold back.
@export var rings_color := Color(0.85, 0.78, 0.65, 0.8)

@export_group("Turning")
## Hours from one noon to the next, standing on it. A tilt past 90° turns it backward.
@export var day := 24.0
## How far its north pole leans from the ecliptic's.
@export_range(0.0, 180.0, 0.001, "suffix:°") var axial_tilt := 23.44
## The ecliptic longitude the north pole leans toward.
@export_range(0.0, 360.0, 0.001, "suffix:°") var tilt_toward := 90.0

@export_group("")
## Its moons, OvercastBodies. Typed by hint: a script typing an array of itself is never freed.
@export_custom(PROPERTY_HINT_TYPE_STRING, "%d/%d:OvercastBody" % [TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE])
var moons: Array[Resource] = []


## The pole, a unit vector in the ecliptic frame (x the equinox, z the ecliptic's north).
func pole() -> Vector3:
	var t := deg_to_rad(axial_tilt)
	var l := deg_to_rad(tilt_toward)
	return Vector3(sin(t) * cos(l), sin(t) * sin(l), cos(t))
