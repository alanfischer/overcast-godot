@tool
class_name OvercastSky
extends ShaderMaterial
## The Overcast sky, as a material: put it on a Sky in a WorldEnvironment (New OvercastSky), and
## give it a shader built on sky.gdshaderinc to draw it on something else. Its look is the
## shader's parameters, as they are by day; time_of_day takes them through dusk to night. The
## cloud layer's settings are the properties below, and its globals follow whichever sky last
## started drawing. Storm and lightning come in from an OvercastWeather.
##
##     var sky := OvercastSky.new({"cloud_amount": 0.4, "sun_dir": OvercastSky.sun_dir_of($Sun)})
##     $WorldEnvironment.environment = sky.make_environment()

const Clouds = preload("res://addons/overcast/overcast_clouds.gd")
const SkyShader = preload("res://addons/overcast/shaders/sky.gdshader")

## Cloud cover once a storm has closed the sky over.
const STORM_COVER := 0.97
## Shader parameters the cloud layer follows.
const LAYER_UNIFORMS := [&"sun_dir", &"cloud_amount"]
## Set by the weather, straight on the RenderingServer, so a storm previewed in the editor is never
## saved with the sky.
const TRANSIENT := [&"storm", &"snowy", &"flash_color", &"flash_dir"]
## What a new sky starts with where the shader's own default is not the one wanted, or where the
## code reads the value back.
const DEFAULTS := {
	"sun_dir": Vector3(0.45, 0.55, -0.70),
	"cloud_amount": 0.45,
	"horizon_color": Color(0.62, 0.70, 0.82),
	"dusk_color": Color(1.0, 0.48, 0.24),
	"night_horizon_color": Color(0.06, 0.07, 0.12),
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
## How far the sky has closed over for rain, 0 to 1. OvercastWeather drives it.
var storm := 0.0:
	set(amount):
		storm = amount
		RenderingServer.material_set_param(get_rid(), &"storm", amount)
		_push_weather()
## How much of the storm is snow, 0 to 1: a pale sky rather than a dark one. OvercastWeather drives
## it.
var snowy := 0.0:
	set(amount):
		snowy = amount
		RenderingServer.material_set_param(get_rid(), &"snowy", amount)
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


## `params` are shader parameters or properties by name (see apply); `sky_shader` for a sky drawn
## on something other than a Godot Sky.
func _init(params: Dictionary = {}, sky_shader: Shader = null) -> void:
	# Loading sets the shader and its parameters before the script, whose attaching runs this:
	# what is there already was saved, and stays.
	if sky_shader:
		shader = sky_shader
	elif shader == null:
		shader = SkyShader
	for key in DEFAULTS:
		if get_shader_parameter(key) == null:
			set("shader_parameter/" + key, DEFAULTS[key])
	for key in TRANSIENT:  # saved by an older version
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
		Clouds._release(_id)


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
	if not key in LAYER_UNIFORMS:
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
	var sun := sun_at(noon, time_of_day)
	return -sun if night > 0.5 else sun


func _sync_light() -> void:
	set_shader_parameter("light_dir", light_dir())
	_sync_layer()


func _sync_layer() -> void:
	if not _started:
		return
	if drawing:
		Clouds._claim(_id, light_dir(), cloud_height, cloud_scale, cloud_speed, cloud_softness)
		_push_weather()
	else:
		Clouds._release(_id)


## Light the sky from within, brightest toward `dir` (world space); black puts it out.
func set_flash(color: Color, dir: Vector3) -> void:
	RenderingServer.material_set_param(get_rid(), &"flash_color", Vector3(color.r, color.g, color.b))
	RenderingServer.material_set_param(get_rid(), &"flash_dir", dir)


func _push_weather() -> void:
	if not _started or not drawing:
		return
	var amount: float = cloud_amount
	var casting := maxf(amount, storm) > 0.0
	Clouds._set_weather(_id, lerpf(amount, STORM_COVER, storm),
		lerpf(cloud_shadow, storm_shadow, storm) if casting else 0.0)


## The colour the sky draws at the horizon right now, linear, flash aside: what rain haze fades
## into. Follows the shader's storm greying, in the space that shader works in on this renderer.
func horizon_now() -> Color:
	var linear := renderer_is_linear()
	var h := _shader_space(param("horizon_color"), linear)
	# As the shader's, at a glow halfway round from the sun.
	h = h.lerp(_shader_space(param("dusk_color"), linear), dusk * 0.725 * 0.8)
	h = h.lerp(_shader_space(param("night_horizon_color"), linear), night)
	var grey := luma(h) * lerpf(0.55, 1.0, snowy)
	var col := h.lerp(Color(grey, grey, grey), storm)
	return col if linear else col.srgb_to_linear()


## A source_color as the shader sees it on this renderer.
static func _shader_space(c: Color, linear: bool) -> Color:
	return c.srgb_to_linear() if linear else c


static func luma(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


static var _linear := -1


## gl_compatibility shades in the colours' own space; the RD renderers in linear. Fixed at startup.
static func renderer_is_linear() -> bool:
	if _linear < 0:
		_linear = 1 if RenderingServer.get_current_rendering_method() != "gl_compatibility" else 0
	return _linear == 1
