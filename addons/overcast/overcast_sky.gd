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
const _SkyShader = preload("res://addons/overcast/shaders/sky.gdshader")
const _LutShader = preload("res://addons/overcast/shaders/atmosphere_lut.gdshader")
## The air's light, drawn into a texture this size whenever the sun or the air changes.
const _LUT_SIZE := Vector2i(256, 128)

## Cloud cover once a storm has closed the sky over.
const _STORM_COVER := 0.97
## Shader parameters the cloud layer follows.
const _LAYER_UNIFORMS := [&"sun_dir", &"cloud_amount"]
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
		set_shader_parameter("dusk_amount", dusk)
		set_shader_parameter("night_amount", night)
		_sync_light()
## The sun crosses the sky with the time: up at 6, at sun_dir at noon, down at 18, and the moon
## along the same arc at night. Off, both stay at sun_dir, for a sun baked into the lighting.
## OvercastWeather turns its `sun` light to follow.
@export var sun_follows_time := true:
	set(on):
		sun_follows_time = on
		_sync_light()
@export_group("Scene light")
## The light this sky puts on a scene (scene_light) at the height of dusk and at full night.
@export var dusk_light := DUSK_LIGHT
@export var moon_light := MOON_LIGHT
@export_group("Cloud layer")
## Metres over the scene's origin. Tuned for levels a few dozen metres across at 100; the clouds
## and lightning scale with it, so a bigger world raises it.
@export_range(10.0, 5000.0, 1.0, "or_greater", "suffix:m") var cloud_height := 100.0:
	set(v):
		cloud_height = v
		_sync_layer()
## Noise units per cloud height: bigger is smaller clouds.
@export_range(0.25, 8.0, 0.01) var cloud_scale := 2.2:
	set(v):
		cloud_scale = v
		_sync_layer()
## Noise units per second.
@export_range(0.0, 0.5, 0.001) var cloud_speed := 0.035:
	set(v):
		cloud_speed = v
		_sync_layer()
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

## 0 by day to 1 at full night, at time_of_day.
var night: float:
	get:
		return night_at(time_of_day)
## How far into the warm light of a sunset or sunrise, 0 to 1, at time_of_day.
var dusk: float:
	get:
		return dusk_at(time_of_day)
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

## Kept for releasing the cloud layer as the sky is freed, when `self` is no longer to hand.
var _id := get_instance_id()
var _started := false
var _storm := 0.0
var _snowy := 0.0
## The air's light level across the sun's bearing, linear, as _sync_air last took it.
var _air_horizon := Color.BLACK
## The viewport atmosphere_lut.gdshader draws in, and what it holds; none until the air lights a sky.
var _lut := {}
var _air_inputs := []
## The noon sky's zenith, by haze: what the eye adapts against.
static var _air_noon_zenith := {}


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
	if not key in _LAYER_UNIFORMS:
		return false
	if value is Vector3:
		value = (value as Vector3).normalized()
	set_shader_parameter(key, value)
	_sync_light()
	return true


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
	return 1.0 - smoothstep(-0.45, 0.05, _elevation(hours))


static func dusk_at(hours: float) -> float:
	return 1.0 - smoothstep(0.0, 0.35, absf(_elevation(hours) + 0.05))


## The light the sky puts on a scene now, as a linear multiplier on daylight: white by day, warm
## at dusk, moonlight at night. For a sun's light_color, a lightmap's sky share, the weather's
## sky_light.
func scene_light() -> Color:
	return scene_light_at(time_of_day, dusk_light, moon_light)


static func scene_light_at(hours: float, dusk_tint := DUSK_LIGHT, moon := MOON_LIGHT) -> Color:
	return Color.WHITE.lerp(dusk_tint, dusk_at(hours)).lerp(moon, night_at(hours))


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
	var flat := Vector3(noon.x, 0.0, noon.z)
	var axis := flat.normalized() if flat.length() > 1e-4 else Vector3.RIGHT
	return noon.normalized().rotated(axis, TAU * (hours - 12.0) / 24.0)


## Toward what lights the sky now: the sun by day and the moon, opposite it, by night. Both at
## sun_dir when the sun does not follow the time.
func light_dir() -> Vector3:
	var noon: Vector3 = sun_dir
	if not sun_follows_time:
		return noon.normalized()
	return light_toward(sun_at(noon, time_of_day), night)


## How strongly what light_dir points at shines, 0 to 1.
func light_strength() -> float:
	return light_strength_of(night) if sun_follows_time else 1.0


## What lights the scene with the sun at `sun` and `night` in: the sun, or once night is half in,
## the moon opposite it.
static func light_toward(sun: Vector3, night_amount: float) -> Vector3:
	return -sun if night_amount > 0.5 else sun


## How strongly light_toward's light shines, 0 to 1. The moon takes over by then already above
## the horizon, so it comes up from nothing rather than switching on.
static func light_strength_of(night_amount: float) -> float:
	return 1.0 if night_amount <= 0.5 else smoothstep(0.5, 0.8, night_amount)


func _sync_light() -> void:
	set_shader_parameter("light_dir", light_dir())
	set_shader_parameter("light_strength", light_strength())
	_sync_air()
	_sync_layer()


## How far the sky is the air's light: none from a sky shader without the uniform.
func _air() -> float:
	var v = param("atmosphere")
	return v if v is float else 0.0


## Where the sun really is now, below the horizon too: what lights the air.
func _air_sun() -> Vector3:
	var noon: Vector3 = sun_dir
	return sun_at(noon, time_of_day) if sun_follows_time else noon.normalized()


func _sync_air() -> void:
	var haze = param("atmosphere_haze")
	var exposure = param("atmosphere_exposure")
	# DEFAULTS go in one at a time: the rest may not be there yet.
	if _air() <= 0.0 or not haze is float or not exposure is float:
		return
	var sun := _air_sun()
	# The sums are a few thousand steps: only when what they depend on moved.
	var inputs := [sun, haze, exposure]
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
	var clouds := Vector3(0.0, _AIR_GROUND + _AIR_CLOUDS, 0.0)
	var noon := _air_sunlight(ground, Vector3.UP, haze)
	return {
		&"atmosphere_sun": sun,
		&"atmosphere_gain": gain,
		&"atmosphere_dark": dark,
		&"atmosphere_zenith": _air_seen(zenith, gain, dark),
		&"atmosphere_horizon": _air_seen(horizon, gain, dark),
		&"atmosphere_light": _air_toward_eye(_air_sunlight(ground, sun, haze) / noon),
		&"atmosphere_cloud_light": _air_toward_eye(_air_sunlight(clouds, sun, haze) / noon),
	}


# atmosphere.gdshaderinc's sums, for the few directions the whole sky shares.
const _AIR_GROUND := 6360e3
const _AIR_TOP := 6460e3
const _AIR_VIEWER := 200.0
const _AIR_CLOUDS := 2000.0
const _AIR_RAYLEIGH := Vector3(5.802e-6, 13.558e-6, 33.1e-6)
const _AIR_MIE := 3.996e-6
const _AIR_MIE_G := 0.8
const _AIR_OZONE := Vector3(0.650e-6, 1.881e-6, 0.085e-6)
const _AIR_VIEW_STEPS := 16
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


func _sync_layer() -> void:
	if not _started:
		return
	if drawing:
		_Clouds._claim(_id, light_dir(), cloud_height, cloud_scale, cloud_speed, cloud_softness)
		_push_weather()
	else:
		_Clouds._release(_id)


## The weather's say over the sky: OvercastWeather calls these, and a sky with no weather can be
## told by hand. How far it has closed over for rain (`storm`), and how much of that is snow
## (`snowy`, a pale sky rather than a dark one), 0 to 1 each.
func set_weather(storm_amount: float, snowy_amount: float) -> void:
	_storm = storm_amount
	_snowy = snowy_amount
	RenderingServer.material_set_param(get_rid(), &"storm", storm_amount)
	RenderingServer.material_set_param(get_rid(), &"snowy", snowy_amount)
	_push_weather()


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
		lerpf(cloud_shadow, storm_shadow, storm) if casting else 0.0)


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
