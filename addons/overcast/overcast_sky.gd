@tool
class_name OvercastSky
extends ShaderMaterial
## The Overcast sky, as a material: put it on a Sky in a WorldEnvironment (New OvercastSky), and
## give it a shader built on sky.gdshaderinc to draw it on something else. Its look is the
## shader's parameters; the cloud layer's are the properties below. The layer's globals follow
## whichever sky last started drawing. Storm and lightning come in from an OvercastWeather.
##
##     var sky := OvercastSky.new({"cloud_amount": 0.4, "sun_dir": OvercastSky.sun_dir_of($Sun)})
##     $WorldEnvironment.environment = sky.make_environment()

const Clouds = preload("res://addons/overcast/overcast_clouds.gd")
const SkyShader = preload("res://addons/overcast/shaders/sky.gdshader")

## Cloud cover once a storm has closed the sky over.
const STORM_COVER := 0.97
## Shader parameters the cloud layer follows.
const LAYER_UNIFORMS := [&"sun_dir", &"cloud_amount"]
## What a new sky starts with where the shader's own default is not the one wanted, or where the
## code reads the value back.
const DEFAULTS := {
	"sun_dir": Vector3(0.45, 0.55, -0.70),
	"cloud_amount": 0.45,
	"horizon_color": Color(0.62, 0.70, 0.82),
}

## Whether this sky draws the cloud layer, and so shades the ground under its clouds. Only one sky
## does at a time: turning one on takes the layer, turning the owner off clears the shadows.
@export var drawing := true:
	set(on):
		drawing = on
		_started = true
		_sync_layer()
@export_group("Cloud layer")
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

## How far the sky has closed over for rain, 0 to 1. OvercastWeather drives it.
var storm := 0.0:
	set(amount):
		storm = amount
		set_shader_parameter("storm", amount)
		_push_weather()
## Direction toward the sun, world space. Set it here or through the inspector, not with
## set_shader_parameter, or the clouds' shadows will not follow.
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
	apply(params)
	# A loaded sky has its settings only once loading is done; one made in code may be turned off
	# before it ever draws.
	_start.call_deferred()


func _start() -> void:
	_started = true
	_sync_layer()


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
	_sync_layer()
	return true


## A shader parameter, or the shader's own default for one never set.
func param(key: StringName) -> Variant:
	var v = get_shader_parameter(key)
	if v == null and shader:
		v = RenderingServer.shader_get_parameter_default(shader.get_rid(), key)
	return v


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


func _sync_layer() -> void:
	if not _started:
		return
	if drawing:
		Clouds._claim(_id, sun_dir, cloud_scale, cloud_speed, cloud_softness)
		_push_weather()
	else:
		Clouds._release(_id)


## Light the sky from within, brightest toward `dir` (world space); black puts it out.
func set_flash(color: Color, dir: Vector3) -> void:
	set_shader_parameter("flash_color", Vector3(color.r, color.g, color.b))
	set_shader_parameter("flash_dir", dir)


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
	var art: Color = param("horizon_color")
	var linear := renderer_is_linear()
	var h := art.srgb_to_linear() if linear else art
	var grey := luma(h) * 0.55
	var col := h.lerp(Color(grey, grey, grey), storm)
	return col if linear else col.srgb_to_linear()


static func luma(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


static var _linear := -1


## gl_compatibility shades in the colours' own space; the RD renderers in linear. Fixed at startup.
static func renderer_is_linear() -> bool:
	if _linear < 0:
		_linear = 1 if RenderingServer.get_current_rendering_method() != "gl_compatibility" else 0
	return _linear == 1
