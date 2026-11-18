@tool
class_name OvercastSky
extends ShaderMaterial
## The Overcast sky, as a material: put it on a Sky in a WorldEnvironment (New OvercastSky), and
## give it a shader built on sky.gdshaderinc to draw it on something else. Its look is the
## shader's parameters, as they are by day; time_of_day takes them through dusk to night. The
## cloud layer's settings are the properties below, and its globals follow whichever sky last
## started drawing. Storm and lightning come in from an OvercastWeather (set_weather, set_flash).
##
##     var sky := OvercastSky.new({"cloud_amount": 0.4, "sun_dir": OvercastSky.sun_dir_of($Sun)})
##     $WorldEnvironment.environment = sky.make_environment()

const _Clouds = preload("res://addons/overcast/overcast_clouds.gd")
const _Ephemeris = preload("res://addons/overcast/overcast_ephemeris.gd")
const _SkyShader = preload("res://addons/overcast/shaders/sky.gdshader")
const _LutShader = preload("res://addons/overcast/shaders/atmosphere_lut.gdshader")
## The air's light, drawn into a texture this size whenever the sun or the air changes.
const _LUT_SIZE := Vector2i(256, 128)
## How far the sun's height (the sine of it) moves before the air's light is summed again.
const _AIR_SUN_STEP := 0.002

## Cloud cover once a storm has closed the sky over.
const _STORM_COVER := 0.97
## Shader parameters the cloud layer follows.
## Shader parameters the ground's light follows: the cover, shadows and veil.
const _COVER_UNIFORMS := [&"cloud_amount", &"cloud_sheet", &"mid_cloud_amount", &"mid_cloud_sheet",
	&"cirrus_amount", &"cirrus_sheet"]
## What set_clouds takes from an OvercastConditions: this sky's name, then the conditions'.
const _CLOUD_FIELDS := [[&"cloud_amount", &"low_cover"], [&"cloud_height", &"low_base"],
	[&"cloud_sheet", &"low_sheet"], [&"cloud_towering", &"towering"],
	[&"mid_cloud_amount", &"mid_cover"], [&"mid_cloud_height", &"mid_base"],
	[&"mid_cloud_sheet", &"mid_sheet"], [&"cirrus_amount", &"high_cover"],
	[&"cirrus_height", &"high_base"], [&"cirrus_sheet", &"high_sheet"]]
## How much of the sun's light a full middle layer takes off the ground, evenly, as altocumulus
## and as altostratus; and a full cirrostratus. Too high and broken for their shadows to show.
const _MID_VEIL := Vector2(0.45, 0.7)
const _HIGH_VEIL := 0.12
## Shader parameters the air's light, taken once here for the whole sky, follows.
const _AIR_UNIFORMS := [&"atmosphere", &"atmosphere_haze", &"atmosphere_exposure"]
## Set by the weather, straight on the RenderingServer, so a storm previewed in the editor is never
## saved with the sky.
const _TRANSIENT := [&"storm", &"snowy", &"flash_color", &"flash_dir"]
## What a new sky starts with where the shader's own default is not the one wanted, or where the
## code reads the value back.
const DEFAULTS := {
	"sun_dir": Vector3(0.45, 0.55, -0.70),
	"cloud_amount": 0.45,
	"horizon_color": Color(0.62, 0.70, 0.82),
	"dusk_color": Color(1.0, 0.48, 0.24),
	"night_horizon_color": Color(0.06, 0.07, 0.12),
	"atmosphere": 1.0,
	"atmosphere_haze": 1.0,
	"atmosphere_exposure": 20.0,
}
## The light the sky puts on a scene (scene_light) at the height of dusk and at full night, as a
## linear multiplier on daylight.
const DUSK_LIGHT := Color(0.95, 0.55, 0.32)
const MOON_LIGHT := Color(0.12, 0.14, 0.24)
## A moonless night's light, as a share of moon_light.
const STARLIGHT := 0.55
## The noon sun's height (sine) the hour-keyed rules for night, dusk and moonlight were tuned
## under: a placed sky takes the sun's and moon's real heights as shares of it.
const _NOON_HEIGHT := 0.55
## The Milky Way's pole as the sky shader draws it, where a placed sky turns the galaxy's.
const _STAR_POLE := Vector3(0.48, 0.36, 0.8)

## Whether this sky draws the cloud layer, and so shades the ground under its clouds. Only one sky
## does at a time: turning one on takes the layer, turning the owner off clears the shadows.
@export var drawing := true:
	set(on):
		drawing = on
		_started = true
		_sync_layer()
## Hours, 0 to 24: noon is the day as the shader parameters have it, the sun sets at 18 and rises
## at 6, and night is full from 20 to 4.
@export_range(0.0, 24.0, 0.05, "suffix:h") var time_of_day := 12.0:
	set(hours):
		time_of_day = fposmod(hours, 24.0) if hours != 24.0 else 24.0
		_moved()
## The sun crosses the sky with the time: up at 6, at sun_dir at noon, down at 18, and the moon
## along the same arc behind it (moon_phase). Off, both stay at sun_dir, for a sun baked into the
## lighting. OvercastWeather turns its `sun` light to follow.
@export var sun_follows_time := true:
	set(on):
		sun_follows_time = on
		_moved()
## Where the moon is in its month: new at 0, in the sky with the sun and dark; full at 0.5, up all
## night; a waxing crescent and half before that, waning after. It follows the sun across the sky by
## this share of a day, lit from the sun's side, and its light on the scene goes by how much of it
## is lit and how high it stands.
@export_range(0.0, 1.0, 0.01) var moon_phase := 0.5:
	set(v):
		moon_phase = v
		_moved()
@export_group("Place")
## On, the sun, moon and stars stand where they do from `latitude` and `longitude` on `date` at
## time_of_day, local time `utc_offset` hours ahead of UTC, and the moon's phase is the date's:
## sun_dir, sun_follows_time and moon_phase go unused. Off, the sun keeps its arc through sun_dir.
@export var placed := false:
	set(on):
		placed = on
		_moved()
## Degrees, north positive.
@export_range(-90.0, 90.0, 0.001, "suffix:°") var latitude := 51.48:
	set(v):
		latitude = v
		_moved()
## Degrees, east positive.
@export_range(-180.0, 180.0, 0.001, "suffix:°") var longitude := 0.0:
	set(v):
		longitude = v
		_moved()
## YYYY-MM-DD. time_of_day does not roll it over: for a clock that runs past midnight, set
## unix_time.
@export var date := "2026-06-21":
	set(v):
		date = v
		_moved()
@export_range(-12.0, 14.0, 0.25, "suffix:h") var utc_offset := 0.0:
	set(v):
		utc_offset = v
		_moved()
## Degrees the world's north is turned from -Z, clockwise seen from above.
@export_range(-180.0, 180.0, 0.1, "suffix:°") var north := 0.0:
	set(v):
		north = v
		_moved()
@export_group("Scene light")
## The light this sky puts on a scene (scene_light) at the height of dusk and at full night.
@export var dusk_light := DUSK_LIGHT
@export var moon_light := MOON_LIGHT
@export_group("Cloud layer")
## The cloud's base, real metres: drawn world_scale times this over the scene's origin.
@export_range(100.0, 15000.0, 10.0, "or_greater", "suffix:m") var cloud_height := 1500.0:
	set(v):
		cloud_height = v
		_sync_heights()
		_sync_layer()
## World metres per real metre, for the clouds, their shadows and the lightning: 1 for a world
## at real size. The default puts the clouds 100 m up, for levels a few dozen metres across,
## where real ones would shade the whole level at once.
@export_range(0.001, 1.0, 0.001, "or_greater") var world_scale := 1.0 / 15.0:
	set(v):
		world_scale = v
		_sync_layer()
## Noise units per cloud height: bigger is smaller clouds.
@export_range(0.25, 8.0, 0.01) var cloud_scale := 2.2:
	set(v):
		cloud_scale = v
		_sync_layer()
## The wind the clouds ride, m/s at their real height (y is ignored), while no weather says
## otherwise (set_wind).
@export var wind_aloft := Vector3(-10.0, 0.0, -3.5):
	set(v):
		wind_aloft = v
		_sync_drift()
## How many times faster than life the clouds go: 1 is real, which in a game can look still.
@export_range(0.0, 20.0, 0.1, "or_greater") var cloud_speedup := 1.0:
	set(v):
		cloud_speedup = v
		_sync_drift()
@export_range(0.0, 0.5, 0.01) var cloud_softness := 0.1:
	set(v):
		cloud_softness = v
		_sync_layer()
## How much of the sun's share of the light a cloud overhead takes off the ground, in fair weather
## and under a full storm's deck.
@export_range(0.0, 1.0, 0.01) var cloud_shadow := 0.65:
	set(v):
		cloud_shadow = v
		_push_weather()
@export_range(0.0, 1.0, 0.01) var storm_shadow := 0.88:
	set(v):
		storm_shadow = v
		_push_weather()
@export_group("Higher cloud")
## The middle layer's base, real metres: altocumulus, a sheet of small puffs in rows. How much of
## it there is is mid_cloud_amount.
@export_range(2000.0, 8000.0, 10.0, "or_greater", "suffix:m") var mid_cloud_height := 4000.0:
	set(v):
		mid_cloud_height = v
		_sync_heights()
## The cirrus' base, real metres. How much of it there is is the shader's cirrus_amount.
@export_range(5000.0, 15000.0, 10.0, "or_greater", "suffix:m") var cirrus_height := 9000.0:
	set(v):
		cirrus_height = v
		_sync_heights()

## 0 by day to 1 at full night, at time_of_day.
var night: float:
	get:
		return _night_of(_now["sun_height"])
## How far into the warm light of a sunset or sunrise, 0 to 1, at time_of_day.
var dusk: float:
	get:
		return _dusk_of(_now["sun_height"])
## The moment a placed sky shows, Unix seconds (UTC): its date and time_of_day. Setting it sets
## both.
var unix_time: float:
	get:
		return Time.get_unix_time_from_datetime_string(date) + (time_of_day - utc_offset) * 3600.0
	set(t):
		var local := t + utc_offset * 3600.0
		var day := floorf(local / 86400.0) * 86400.0
		date = Time.get_date_string_from_unix_time(int(day))
		time_of_day = (local - day) / 3600.0
## Whether the sun and moon move with the time: placed, or following it.
var sun_moves: bool:
	get:
		return _now["moves"]
## How far the sky has closed over for rain, 0 to 1 (set_weather).
var storm: float:
	get:
		return _storm
## How much of the storm is snow, 0 to 1: a pale sky rather than a dark one (set_weather).
var snowy: float:
	get:
		return _snowy
## Direction toward the sun, world space: where it is at noon when it follows the time. Set it here
## or through the inspector, not with set_shader_parameter, or the clouds' shadows will not follow.
var sun_dir: Vector3:
	get:
		return get_shader_parameter("sun_dir")
	set(v):
		set("shader_parameter/sun_dir", v)
## How cloudy a fair day is. As sun_dir, set it here or through the inspector.
var cloud_amount: float:
	get:
		return get_shader_parameter("cloud_amount")
	set(v):
		set("shader_parameter/cloud_amount", v)
## How far the cloud layer is spread into a sheet: 0 heaped cumulus, 0.5 stratocumulus, 1 stratus.
## As cloud_amount, set it here or through the inspector: the ground's shadows follow it.
var cloud_sheet: float:
	get:
		return _float_param(&"cloud_sheet")
	set(v):
		set("shader_parameter/cloud_sheet", v)
## How much of the middle layer there is, 0 to 1. As cloud_amount, set it here or through the
## inspector: the ground's light follows it.
var mid_cloud_amount: float:
	get:
		return _float_param(&"mid_cloud_amount")
	set(v):
		set("shader_parameter/mid_cloud_amount", v)
## How far the middle layer is spread into altostratus, 0 to 1.
var mid_cloud_sheet: float:
	get:
		return _float_param(&"mid_cloud_sheet")
	set(v):
		set("shader_parameter/mid_cloud_sheet", v)
## How much cirrus there is, and how far it is spread into cirrostratus, 0 to 1 each.
var cirrus_amount: float:
	get:
		return _float_param(&"cirrus_amount")
	set(v):
		set("shader_parameter/cirrus_amount", v)
var cirrus_sheet: float:
	get:
		return _float_param(&"cirrus_sheet")
	set(v):
		set("shader_parameter/cirrus_sheet", v)
## Thunderheads round the horizon: towering cumulus as it rises, cumulonimbus with anvils toward
## 1. Overhead, a thunderstorm is the storm deck (set_weather).
var cloud_towering: float:
	get:
		return _float_param(&"cloud_towering")
	set(v):
		set("shader_parameter/cloud_towering", v)
## How much of the sun's light the cloud over the low layer, and fog under it, take off the
## ground, evenly, 0 to 1.
var veil: float:
	get:
		var mid := mid_cloud_amount * lerpf(_MID_VEIL.x, _MID_VEIL.y, mid_cloud_sheet)
		var high := cirrus_amount * cirrus_sheet * _HIGH_VEIL
		var above := (1.0 - (1.0 - mid) * (1.0 - high)) * (1.0 - storm)
		# Fog fills the air to the cloud's base: the sun comes through that much of it, slanting.
		var fog := 1.0 - exp(-_mist * cloud_height * world_scale / maxf(light_dir().y, 0.1))
		return 1.0 - (1.0 - above) * (1.0 - fog)

## Kept for releasing the cloud layer as the sky is freed, when `self` is no longer to hand.
var _id := get_instance_id()
var _started := false
var _told_wind := Vector3.INF
var _storm := 0.0
var _snowy := 0.0
var _mist := 0.0
## The air's light level across the sun's bearing, linear, as _sync_air last took it.
var _air_horizon := Color.BLACK
## The viewport atmosphere_lut.gdshader draws in, and what it holds; none until the air lights a sky.
var _lut := {}
var _air_inputs := []
## Where the sun and moon stand now and what follows from it (_sky_now).
var _now := {}
## The air's light on each cloud layer, as _sync_air last took it, and what it went by.
var _layer_inputs := []
## What set_clouds last set, so a sky followed every frame is only set on a change.
var _clouds := {}
## The noon sky's zenith, by haze: what the eye adapts against.
static var _air_noon_zenith := {}
## The noon sun on the ground, by haze: what the air's light on the scene is measured against.
static var _air_noon_light := {}
## Turns the galaxy's real pole to where the sky shader draws the Milky Way.
static var _galaxy_turn := Basis(Quaternion(
	_Ephemeris.radec(_Ephemeris.GALACTIC_POLE.x, _Ephemeris.GALACTIC_POLE.y), _STAR_POLE.normalized()))


## `params` are shader parameters or properties by name (see apply); `sky_shader` for a sky drawn
## on something other than a Godot Sky.
func _init(params: Dictionary = {}, sky_shader: Shader = null) -> void:
	# Loading sets the shader and its parameters before the script, whose attaching runs this:
	# what is there already was saved, and stays.
	if sky_shader:
		shader = sky_shader
	elif shader == null:
		shader = _SkyShader
	for key in DEFAULTS:
		if get_shader_parameter(key) == null:
			set("shader_parameter/" + key, DEFAULTS[key])
	for key in _TRANSIENT:  # saved by an older version
		if get_shader_parameter(key) != null:
			set_shader_parameter(key, null)
	time_of_day = time_of_day
	_sync_heights()
	apply(params)
	# A loaded sky has its settings only once loading is done; one made in code may be turned off
	# before it ever draws.
	_start.call_deferred()


func _start() -> void:
	_started = true
	_sync_light()


## A sky must let go of the cloud layer it holds, or its clouds' shadows outlive it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_Clouds._release(_id)
		_free_lut(_lut)  # static: a RefCounted's own methods are out of reach by now


## Shader parameters and properties by name, at once. An unknown name is an error rather than a
## setting that silently does nothing.
func apply(params: Dictionary) -> void:
	var uniforms := {}
	for u in shader.get_shader_uniform_list():
		uniforms[StringName(u["name"])] = true
	for key in params:
		if uniforms.has(StringName(key)):
			set("shader_parameter/" + key, params[key])
		elif key in self:
			set(key, params[key])
		else:
			push_error("OvercastSky has no '%s'" % key)


## The inspector and set() come through here: the layer follows the parameters it reads.
func _set(property: StringName, value: Variant) -> bool:
	if not String(property).begins_with("shader_parameter/"):
		return false
	var key := StringName(String(property).trim_prefix("shader_parameter/"))
	if key in _AIR_UNIFORMS:
		set_shader_parameter(key, value)
		_sync_air()
		return true
	if key == &"sun_dir":
		set_shader_parameter(key, (value as Vector3).normalized())
		_moved()
		return true
	if key in _COVER_UNIFORMS:
		set_shader_parameter(key, value)
		_push_weather()
		return true
	return false


func _float_param(key: StringName) -> float:
	var v = param(key)
	return v if v is float else 0.0


## A shader parameter, or the shader's own default for one never set.
func param(key: StringName) -> Variant:
	var v = get_shader_parameter(key)
	if v == null and shader:
		v = RenderingServer.shader_get_parameter_default(shader.get_rid(), key)
	return v


## How high the sun would be at `hours`, -1 at midnight to 1 at noon.
static func _elevation(hours: float) -> float:
	return -cos(TAU * hours / 24.0)


static func night_at(hours: float) -> float:
	return _night_of(_elevation(hours))


static func dusk_at(hours: float) -> float:
	return _dusk_of(_elevation(hours))


## By the sun's height as a share of noon's, below the horizon too.
static func _night_of(height: float) -> float:
	return 1.0 - smoothstep(-0.45, 0.05, height)


static func _dusk_of(height: float) -> float:
	return 1.0 - smoothstep(0.0, 0.35, absf(height + 0.05))


## Where the sun and moon stand now: from the place, along the day's arc, or fixed at sun_dir.
## sun_height and moon_height are shares of the noon height night, dusk and moonlight go by.
func _sky_now() -> Dictionary:
	var noon: Vector3 = (param(&"sun_dir") as Vector3).normalized()
	if placed:
		var at := _Ephemeris.sky_at(unix_time, latitude, longitude, north)
		return {"sun": at["sun"], "moon": at["moon"], "lit_from": at["sun"], "phase": at["phase"],
			"moves": true, "sun_height": at["sun"].y / _NOON_HEIGHT,
			"moon_height": at["moon"].y / _NOON_HEIGHT, "stars": _galaxy_turn * at["stars"]}
	var hours := time_of_day
	if sun_follows_time:
		var sun := sun_at(noon, hours)
		var moon := moon_at(noon, hours, moon_phase)
		# The stars turn with the sun: back to where they stood at noon.
		return {"sun": sun, "moon": moon, "lit_from": _lit_from(moon, sun, moon_phase),
			"phase": moon_phase, "moves": true, "sun_height": _elevation(hours),
			"moon_height": _elevation(hours - 24.0 * moon_phase),
			"stars": Basis(_arc_axis(noon), -_arc_turn(hours))}
	return {"sun": noon, "moon": noon, "lit_from": _lit_from(noon, noon, moon_phase),
		"phase": moon_phase, "moves": false, "sun_height": _elevation(hours), "moon_height": 1.0,
		"stars": Basis.IDENTITY}


## The time, date, place or way of keeping time has changed: the sun and moon go with it.
func _moved() -> void:
	_now = _sky_now()
	set_shader_parameter("dusk_amount", dusk)
	set_shader_parameter("night_amount", night)
	_sync_light()


## The light the sky puts on a scene now, as a linear multiplier on daylight: white by day, warm
## at dusk, moonlight at night. For a sun's light_color, a lightmap's sky share, the weather's
## sky_light.
func scene_light() -> Color:
	return _scene_light_of(dusk, night, _moonlight(), dusk_light, moon_light)


## `moon` is a night under a full moon high up; with less of one, down to STARLIGHT of it.
static func scene_light_at(hours: float, phase := 0.5, dusk_tint := DUSK_LIGHT, moon := MOON_LIGHT) -> Color:
	return _scene_light_of(dusk_at(hours), night_at(hours), moonlight_at(hours, phase), dusk_tint, moon)


static func _scene_light_of(dusk_amount: float, night_amount: float, moonlight: float, dusk_tint: Color, moon: Color) -> Color:
	var night_light := moon * lerpf(STARLIGHT, 1.0, moonlight)
	return Color.WHITE.lerp(dusk_tint, dusk_amount).lerp(Color(night_light, 1.0), night_amount)


## Sun direction (unit, toward the sun) for a DirectionalLight3D, which shines along its -Z.
static func sun_dir_of(light: DirectionalLight3D) -> Vector3:
	return light.global_basis.z.normalized()


## An Environment that draws this sky as its background, lighting the scene with it.
func make_environment() -> Environment:
	var sky := Sky.new()
	sky.sky_material = self
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	drawing = true
	return env


## Where the sun is at `hours`, on an arc through `noon` (unit, toward it) that meets the horizon
## at 6 and 18: it turns about the level line toward noon's sun, as on an equinox.
static func sun_at(noon: Vector3, hours: float) -> Vector3:
	return noon.normalized().rotated(_arc_axis(noon), _arc_turn(hours))


## The level line the sky turns about, and how far it has turned from noon at `hours`.
static func _arc_axis(noon: Vector3) -> Vector3:
	var flat := Vector3(noon.x, 0.0, noon.z)
	return flat.normalized() if flat.length() > 1e-4 else Vector3.RIGHT


static func _arc_turn(hours: float) -> float:
	return TAU * (hours - 12.0) / 24.0


## Where the moon is at `hours`, `phase` through its month: on the sun's arc, that share of a day
## behind it.
static func moon_at(noon: Vector3, hours: float, phase: float) -> Vector3:
	return sun_at(noon, hours - 24.0 * phase)


## How much of the moon's face is lit at `phase`, 0 new to 1 full.
static func moon_lit(phase: float) -> float:
	return 0.5 - 0.5 * cos(TAU * phase)


## The moon's light on the scene at `hours`, 0 to 1 for a full moon well up: by how much of it is
## lit, and nothing from one below the horizon.
static func moonlight_at(hours: float, phase: float) -> float:
	return _moonlight_of(phase, _elevation(hours - 24.0 * phase))


## By the moon's height as a share of the noon sun's.
static func _moonlight_of(phase: float, height: float) -> float:
	return moon_lit(phase) * smoothstep(-0.05, 0.25, height)


func _moonlight() -> float:
	return _moonlight_of(_now["phase"], _now["moon_height"])


## Where the moon is in its month now: moon_phase, or the date's when placed.
func phase() -> float:
	return _now["phase"]


## Toward the moon now. At sun_dir when the sun does not follow the time.
func moon_dir() -> Vector3:
	return _now["moon"]


## Toward what lights the sky now: the sun by day and the moon by night, even one that has set.
## Both at sun_dir when the sun does not follow the time.
func light_dir() -> Vector3:
	return _now["sun"] if night <= 0.5 else _now["moon"]


## How strongly what light_dir points at shines, 0 to 1.
func light_strength() -> float:
	return _strength_of(night, _moonlight()) if _now["moves"] else 1.0


## Toward what lights the scene at `hours`: the sun, or once night is half in, the moon.
static func light_dir_at(noon: Vector3, hours: float, phase: float) -> Vector3:
	return sun_at(noon, hours) if night_at(hours) <= 0.5 else moon_at(noon, hours, phase)


## How strongly light_dir_at's light shines, 0 to 1. The moon takes over with night half in, from
## nothing rather than switching on, and shines by its moonlight_at.
static func light_strength_at(hours: float, phase: float) -> float:
	return _strength_of(night_at(hours), moonlight_at(hours, phase))


static func _strength_of(night_amount: float, moonlight: float) -> float:
	return 1.0 if night_amount <= 0.5 else smoothstep(0.5, 0.8, night_amount) * moonlight


## The direction the moon's face is lit from: round from the moon toward the sun by its phase, so
## the bright limb points at the sun whatever arc the two are on.
static func _lit_from(moon: Vector3, sun: Vector3, phase: float) -> Vector3:
	var across := moon.cross(sun)
	if across.length() < 1e-3:
		across = moon.cross(Vector3.UP if absf(moon.y) < 0.99 else Vector3.RIGHT)
	return moon.rotated(across.normalized(), PI * (1.0 - absf(2.0 * phase - 1.0)))


func _sync_light() -> void:
	set_shader_parameter("light_dir", light_dir())
	set_shader_parameter("light_strength", light_strength())
	set_shader_parameter("moon_dir", moon_dir())
	set_shader_parameter("moon_lit_from", _now["lit_from"])
	set_shader_parameter("moonlight", _moonlight())
	set_shader_parameter("star_basis", _now["stars"])
	_sync_air()
	_sync_layer()


## How far the sky is the air's light: none from a sky shader without the uniform.
func _air() -> float:
	return _float_param(&"atmosphere")


## Where the sun really is now, below the horizon too: what lights the air.
func _air_sun() -> Vector3:
	return _now["sun"]


func _sync_air() -> void:
	var haze = param("atmosphere_haze")
	var exposure = param("atmosphere_exposure")
	# DEFAULTS go in one at a time: the rest may not be there yet.
	if _air() <= 0.0 or not haze is float or not exposure is float:
		return
	var sun := _air_sun()
	RenderingServer.material_set_param(get_rid(), &"atmosphere_sun", sun)
	# Only when what they depend on has moved enough to see: the sun's height, not its bearing.
	var height := snappedf(sun.y, _AIR_SUN_STEP)
	var layers := [height, haze, cloud_height, mid_cloud_height, cirrus_height]
	if layers != _layer_inputs:
		_layer_inputs = layers
		for layer in [[&"atmosphere_cloud_light", cloud_height], [&"atmosphere_mid_light", mid_cloud_height],
				[&"atmosphere_high_light", cirrus_height]]:
			RenderingServer.material_set_param(get_rid(), layer[0], cloud_light_at(sun, haze, layer[1]))
	# The sums are a few thousand steps, and the texture a few million.
	var inputs := [height, haze, exposure]
	if inputs == _air_inputs:
		return
	_air_inputs = inputs
	var air := air_at(sun, haze, exposure)
	_air_horizon = air["atmosphere_horizon"]
	for key in air:
		if key != &"atmosphere_gain" and key != &"atmosphere_dark":
			RenderingServer.material_set_param(get_rid(), key, air[key])
	_draw_lut(sun.y, haze, air["atmosphere_gain"], air["atmosphere_dark"])


## The sky samples the air's light rather than summing it per pixel: on sky brushes that cost
## more than the rest of the frame.
func _draw_lut(sun_height: float, haze: float, gain: float, dark: float) -> void:
	var rs := RenderingServer
	if _lut.is_empty():
		var viewport := rs.viewport_create()
		rs.viewport_set_size(viewport, _LUT_SIZE.x, _LUT_SIZE.y)
		rs.viewport_set_disable_3d(viewport, true)
		rs.viewport_set_active(viewport, true)
		var canvas := rs.canvas_create()
		rs.viewport_attach_canvas(viewport, canvas)
		var item := rs.canvas_item_create()
		rs.canvas_item_set_parent(item, canvas)
		rs.canvas_item_add_rect(item, Rect2(Vector2.ZERO, _LUT_SIZE), Color.WHITE)
		var material := rs.material_create()
		rs.material_set_shader(material, _LutShader.get_rid())
		rs.canvas_item_set_material(item, material)
		_lut = {"viewport": viewport, "canvas": canvas, "item": item, "material": material}
		rs.material_set_param(get_rid(), &"atmosphere_lut", rs.viewport_get_texture(viewport))
	var material: RID = _lut["material"]
	rs.material_set_param(material, &"sun_height", sun_height)
	rs.material_set_param(material, &"haze", haze)
	rs.material_set_param(material, &"gain", gain)
	rs.material_set_param(material, &"dark", dark)
	rs.viewport_set_update_mode(_lut["viewport"], RenderingServer.VIEWPORT_UPDATE_ONCE)


static func _free_lut(lut: Dictionary) -> void:
	for key in ["item", "material", "canvas", "viewport"]:
		if lut.has(key):
			RenderingServer.free_rid(lut[key])


## The air's light the whole sky shares, by the shader parameter it goes to, for a sun at `sun`
## (unit, below the horizon too).
static func air_at(sun: Vector3, haze: float, exposure: float) -> Dictionary:
	var level := Vector3(sun.x, 0.0, sun.z)
	level = level.normalized().rotated(Vector3.UP, PI * 0.5) if level.length() > 1e-4 else Vector3.RIGHT
	# The eye opens up as the light fails, so dusk has colour rather than black; up to a point.
	var zenith := _air_sky(Vector3.UP, sun, haze)
	if not _air_noon_zenith.has(haze):
		_air_noon_zenith[haze] = _air_sky(Vector3.UP, Vector3(0.0, 0.7, 0.7), haze)
	var noon_zenith: Color = _air_noon_zenith[haze]
	var adapt := clampf(sqrt(_luma(noon_zenith) / maxf(_luma(zenith), 1e-9)), 1.0, _AIR_ADAPT)
	var gain := exposure * adapt
	var dark := clampf(log(adapt) / log(_AIR_ADAPT), 0.0, 1.0) * 0.6
	# Level and across the sun's bearing: between the glow under it and the shadow opposite.
	var horizon := _air_sky(level, sun, haze)
	var ground := Vector3(0.0, _AIR_GROUND + _AIR_VIEWER, 0.0)
	return {
		&"atmosphere_sun": sun,
		&"atmosphere_gain": gain,
		&"atmosphere_dark": dark,
		&"atmosphere_zenith": _air_seen(zenith, gain, dark),
		&"atmosphere_horizon": _air_seen(horizon, gain, dark),
		&"atmosphere_light": _air_toward_eye(_air_sunlight(ground, sun, haze) / _noon_light(haze)),
	}


## The sun's light on cloud `height` real metres up, for a sun at `sun` (unit, below the horizon
## too), as the noon sun's on the ground: a sunset's colours, and the earth's shadow after it.
static func cloud_light_at(sun: Vector3, haze: float, height: float) -> Vector3:
	var p := Vector3(0.0, _AIR_GROUND + height, 0.0)
	return _air_toward_eye(_air_sunlight(p, sun, haze) / _noon_light(haze))


static func _noon_light(haze: float) -> Vector3:
	if not _air_noon_light.has(haze):
		_air_noon_light[haze] = _air_sunlight(Vector3(0.0, _AIR_GROUND + _AIR_VIEWER, 0.0), Vector3.UP, haze)
	return _air_noon_light[haze]


# atmosphere.gdshaderinc's sums, for the few directions the whole sky shares.
const _AIR_GROUND := 6360e3
const _AIR_TOP := 6460e3
const _AIR_VIEWER := 200.0
const _AIR_RAYLEIGH := Vector3(5.802e-6, 13.558e-6, 33.1e-6)
const _AIR_MIE := 3.996e-6
const _AIR_MIE_G := 0.8
const _AIR_OZONE := Vector3(0.650e-6, 1.881e-6, 0.085e-6)
const _AIR_VIEW_STEPS := 48
const _AIR_MULTI := 0.6
const _AIR_MULTI_TINT := Vector3(0.42, 0.64, 1.0)
## How far the eye opens up for a failing light.
const _AIR_ADAPT := 40.0
const _AIR_MULTI_UP := 6000.0


## A low sun's light keeps most of its colour but not all its dimming: the eye makes up some of it.
static func _air_toward_eye(light: Vector3) -> Vector3:
	var luma := _luma709(light)
	return light.lerp(Vector3.ONE * luma, 0.2) / sqrt(maxf(luma, 1e-6))


static func _air_seen(light: Color, gain: float, dark: float) -> Color:
	var c := Color(1.0 - exp(-light.r * gain), 1.0 - exp(-light.g * gain), 1.0 - exp(-light.b * gain))
	var luma := _luma709(Vector3(c.r, c.g, c.b))
	return c.lerp(Color(0.6, 0.8, 1.35) * luma, dark)


## Luma by Rec. 709, as atmosphere.gdshaderinc weighs the air's light.
static func _luma709(c: Vector3) -> float:
	return c.dot(Vector3(0.2126, 0.7152, 0.0722))


static func _air_density(h: float) -> Vector3:
	return Vector3(exp(-h / 8000.0), exp(-h / 1200.0), maxf(0.0, 1.0 - absf(h - 25e3) / 15e3))


static func _air_extinction(dens: Vector3, haze: float) -> Vector3:
	return _AIR_RAYLEIGH * dens.x + Vector3.ONE * (_AIR_MIE * 1.11 * haze * dens.y) + _AIR_OZONE * dens.z


static func _air_exit(o: Vector3, d: Vector3, r: float) -> float:
	var b := o.dot(d)
	return -b + sqrt(maxf(b * b - o.dot(o) + r * r, 0.0))


static func _vexp(v: Vector3) -> Vector3:
	return Vector3(exp(v.x), exp(v.y), exp(v.z))


static func _air_chapman(x: float, h: float, mu: float) -> float:
	var c := sqrt(x + h)
	if mu >= 0.0:
		return c / (c * mu + 1.0) * exp(-h)
	var x0 := sqrt(1.0 - mu * mu) * (x + h)
	return 2.0 * sqrt(x0) * exp(x - x0) - c / (1.0 - c * mu) * exp(-h)


static func _air_sunlight(p: Vector3, sun: Vector3, haze: float) -> Vector3:
	var r := p.length()
	var mu := p.dot(sun) / r
	if mu < 0.0 and r * r * (1.0 - mu * mu) < _AIR_GROUND * _AIR_GROUND:
		return Vector3.ZERO
	var h := r - _AIR_GROUND
	var depth := _AIR_RAYLEIGH * (8000.0 * _air_chapman(_AIR_GROUND / 8000.0, h / 8000.0, mu)) \
		+ Vector3.ONE * (_AIR_MIE * 1.11 * haze * 1200.0 * _air_chapman(_AIR_GROUND / 1200.0, h / 1200.0, mu))
	var r_oz := _AIR_GROUND + 25e3
	var s2 := (1.0 - mu * mu) * r * r / (r_oz * r_oz)
	var slant := 1.0 / maxf(sqrt(1.0 - s2), 0.04) if s2 < 1.0 else 0.0
	slant *= 1.0 if r < r_oz else (2.0 if mu < 0.0 else 0.0)
	depth += _AIR_OZONE * 15e3 * slant
	return _vexp(-depth)


static func _air_sky(dir: Vector3, sun: Vector3, haze: float) -> Color:
	var o := Vector3(0.0, _AIR_GROUND + _AIR_VIEWER, 0.0)
	var length := _air_exit(o, dir, _AIR_TOP)
	var trans := Vector3.ONE
	var ray := Vector3.ZERO
	var mie := Vector3.ZERO
	var multi := Vector3.ZERO
	var prev := 0.0
	for i in _AIR_VIEW_STEPS:
		var f := (i + 1.0) / _AIR_VIEW_STEPS
		var t := length * f * f
		var dt := t - prev
		var p := o + dir * (t - dt * 0.5)
		prev = t
		var dens := _air_density(p.length() - _AIR_GROUND)
		var step_trans := _vexp(-_air_extinction(dens, haze) * dt)
		var half := Vector3(sqrt(step_trans.x), sqrt(step_trans.y), sqrt(step_trans.z))
		var seen := trans * half * dt
		var lit := seen * _air_sunlight(p, sun, haze)
		var glow := seen * _air_sunlight(p * (1.0 + _AIR_MULTI_UP / p.length()), sun, haze)
		ray += lit * dens.x
		mie += lit * dens.y
		multi += glow * (_AIR_RAYLEIGH * dens.x + Vector3.ONE * (_AIR_MIE * haze * dens.y))
		trans *= step_trans
	var c := dir.dot(sun)
	var g := _AIR_MIE_G
	var rayleigh_phase := 3.0 / (16.0 * PI) * (1.0 + c * c)
	var mie_phase := 3.0 / (8.0 * PI) * (1.0 - g * g) / (2.0 + g * g) * (1.0 + c * c) \
		/ pow(1.0 + g * g - 2.0 * g * c, 1.5)
	var v := ray * _AIR_RAYLEIGH * rayleigh_phase + mie * (_AIR_MIE * haze * mie_phase) \
		+ multi * _AIR_MULTI_TINT * (_AIR_MULTI / (4.0 * PI))
	return Color(v.x, v.y, v.z)


## The higher layers ride at their share of the low one's height, as the shader draws them all
## off it; the air lights each at its real height.
func _sync_heights() -> void:
	RenderingServer.material_set_param(get_rid(), &"mid_cloud_rise", mid_cloud_height / cloud_height)
	RenderingServer.material_set_param(get_rid(), &"cirrus_rise", cirrus_height / cloud_height)
	_sync_air()


## The cloud as `conditions` give it: each layer's cover, base and kind, and the thunderheads.
## Cheap to call every frame: only what changed since the last call is set.
func set_clouds(conditions: OvercastConditions) -> void:
	for field in _CLOUD_FIELDS:
		var v = conditions.get(field[1])
		if _clouds.get(field[0]) != v:
			_clouds[field[0]] = v
			set(field[0], v)


func _sync_layer() -> void:
	if not _started:
		return
	if drawing:
		_Clouds._claim(_id, light_dir(), cloud_height * world_scale, cloud_scale, _drift(), cloud_softness)
		_push_weather()
	else:
		_Clouds._release(_id)


## The weather's say over the sky: OvercastWeather calls these, and a sky with no weather can be
## told by hand. How far it has closed over for rain (`storm`), and how much of that is snow
## (`snowy`, a pale sky rather than a dark one), 0 to 1 each; and fog under the cloud, per metre
## (OvercastWeather.mist), which veils the sun.
func set_weather(storm_amount: float, snowy_amount: float, mist := 0.0) -> void:
	_storm = storm_amount
	_snowy = snowy_amount
	_mist = mist
	RenderingServer.material_set_param(get_rid(), &"storm", storm_amount)
	RenderingServer.material_set_param(get_rid(), &"snowy", snowy_amount)
	_push_weather()


## The wind the clouds ride, m/s at their height, over wind_aloft: OvercastWeather's say.
## Vector3.INF hands them back to wind_aloft.
func set_wind(aloft: Vector3) -> void:
	_told_wind = aloft
	_sync_drift()


## Noise units per second the wind carries the pattern; it moves against the noise coordinates.
func _drift() -> Vector2:
	var w := _told_wind if _told_wind.is_finite() else wind_aloft
	return -Vector2(w.x, w.z) * cloud_scale / cloud_height * cloud_speedup


func _sync_drift() -> void:
	if _started and drawing:
		_Clouds._set_drift(_id, _drift())


## Lightning: light the sky from within, brightest toward `dir` (world space); black puts it out.
func set_flash(color: Color, dir: Vector3) -> void:
	RenderingServer.material_set_param(get_rid(), &"flash_color", Vector3(color.r, color.g, color.b))
	RenderingServer.material_set_param(get_rid(), &"flash_dir", dir)


func _push_weather() -> void:
	if not _started or not drawing:
		return
	var amount: float = cloud_amount
	var casting := maxf(amount, storm) > 0.0
	_Clouds._set_weather(_id, lerpf(amount, _STORM_COVER, storm),
		lerpf(cloud_shadow, storm_shadow, storm) if casting else 0.0, veil, cloud_sheet)


## The colour the sky draws at the horizon right now, linear, flash aside: what rain haze fades
## into. Follows the shader's storm greying, in the space that shader works in on this renderer.
func horizon_now() -> Color:
	var linear := _renderer_is_linear()
	var h := _shader_space(param("horizon_color"), linear)
	# As the shader's, at a glow halfway round from the sun.
	h = h.lerp(_shader_space(param("dusk_color"), linear), dusk * 0.725 * 0.8)
	var night_horizon := _shader_space(param("night_horizon_color"), linear)
	h = h.lerp(night_horizon, night)
	var air := _air()
	if air > 0.0:
		var horizon: Color = _air_horizon if linear else _air_horizon.linear_to_srgb()
		h = h.lerp(horizon + night_horizon * night, air)
	var grey := _luma(h) * lerpf(0.55, 1.0, snowy)
	var col := h.lerp(Color(grey, grey, grey), storm)
	return col if linear else col.srgb_to_linear()


## A source_color as the shader sees it on this renderer.
static func _shader_space(c: Color, linear: bool) -> Color:
	return c.srgb_to_linear() if linear else c


static func _luma(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


static var _linear := -1


## gl_compatibility shades in the colours' own space; the RD renderers in linear. Fixed at startup.
static func _renderer_is_linear() -> bool:
	if _linear < 0:
		_linear = 1 if RenderingServer.get_current_rendering_method() != "gl_compatibility" else 0
	return _linear == 1
