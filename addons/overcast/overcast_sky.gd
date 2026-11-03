class_name OvercastSky
extends RefCounted
## One sky: the material that draws it (shaders/sky.gdshader, or any shader built on
## sky.gdshaderinc), its settings, and the cloud layer's globals, which follow it. Storm and
## lightning come in through set_storm and set_flash, usually from an OvercastWeather.
##
##     var sky := OvercastSky.new({"cloud_amount": 0.4, "sun_dir": $Sun.basis.z})
##     $WorldEnvironment.environment = sky.make_environment()

const Clouds = preload("res://addons/overcast/overcast_clouds.gd")
const SkyShader = preload("res://addons/overcast/shaders/sky.gdshader")

## How much of the sun's share of the light a cloud overhead takes off the ground, in fair weather
## and under a full storm's deck.
const CLOUD_SHADOW := 0.65
const STORM_SHADOW := 0.88
## Cloud cover once a storm has closed the sky over.
const STORM_COVER := 0.97

## The sky's settings: sky.gdshaderinc's uniforms by name, plus the cloud layer's cloud_scale,
## cloud_speed and cloud_softness. Colours are sRGB.
var params: Dictionary
var material: ShaderMaterial
## How far the sky has closed over for rain, 0 to 1.
var storm := 0.0
## Whether this sky is on screen: its clouds then shade the ground. See set_drawing.
var drawing := false


## `params` over defaults(); `shader` for a sky drawn on something other than a Godot Sky.
func _init(sky_params: Dictionary = {}, shader: Shader = null) -> void:
	params = defaults()
	params.merge(sky_params, true)
	material = ShaderMaterial.new()
	material.shader = shader if shader else SkyShader
	for key in params:
		material.set_shader_parameter(key, params[key])
	material.set_shader_parameter("sun_dir", (params["sun_dir"] as Vector3).normalized())


static func defaults() -> Dictionary:
	return {
		"zenith_color": Color(0.25, 0.42, 0.70),
		"horizon_color": Color(0.62, 0.70, 0.82),
		"ground_color": Color(0.18, 0.17, 0.16),
		"horizon_falloff": 1.1,
		"sun_dir": Vector3(0.45, 0.55, -0.70),
		"sun_color": Color(1.0, 0.96, 0.82),
		"sun_size": 0.012,
		"sun_energy": 2.2,
		"sun_glow_exp": 320.0,
		"sun_glow_energy": 0.35,
		"sun_halo_energy": 0.25,
		"sun_halo_exp": 6.0,
		"cloud_amount": 0.45,
		"cloud_color": Color(1.0, 1.0, 1.0),
		"cloud_scale": 2.2,
		"cloud_speed": 0.035,
		"cloud_softness": 0.1,
		"cirrus_amount": 0.5,
		"star_amount": 0.0,
		"star_color": Color(1.0, 1.0, 1.0),
	}


## Sun direction (unit, toward the sun) for a DirectionalLight3D, which shines along its -Z.
static func sun_dir_of(light: DirectionalLight3D) -> Vector3:
	return light.global_basis.z.normalized()


## An Environment that draws this sky as its background.
func make_environment() -> Environment:
	var sky := Sky.new()
	sky.sky_material = material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	set_drawing(true)
	return env


## On screen or off. Only one sky draws clouds at a time, since the layer is global: the last one
## turned on owns it, and turning one off clears the shadows.
func set_drawing(on: bool) -> void:
	drawing = on
	if on:
		Clouds.set_layer(params["sun_dir"], params["cloud_scale"], params["cloud_speed"],
			params["cloud_softness"])
		_push_weather()
	else:
		Clouds.clear()


## 0 clear, 1 a dark overcast deck.
func set_storm(amount: float) -> void:
	storm = amount
	material.set_shader_parameter("storm", amount)
	_push_weather()


## Light the sky from within, brightest toward `dir` (world space); black puts it out.
func set_flash(color: Color, dir: Vector3) -> void:
	material.set_shader_parameter("flash_color", Vector3(color.r, color.g, color.b))
	material.set_shader_parameter("flash_dir", dir)


func _push_weather() -> void:
	if not drawing:
		return
	var amount: float = params["cloud_amount"]
	var casting := maxf(amount, storm) > 0.0
	Clouds.set_weather(lerpf(amount, STORM_COVER, storm),
		lerpf(CLOUD_SHADOW, STORM_SHADOW, storm) if casting else 0.0)


## The colour the sky draws at the horizon right now, linear, flash aside: what rain haze fades
## into. Follows the shader's storm greying, in the space that shader works in on this renderer.
func horizon_color() -> Color:
	var art: Color = params["horizon_color"]
	var linear := renderer_is_linear()
	var h := art.srgb_to_linear() if linear else art
	var grey := luma(h) * 0.55
	var col := h.lerp(Color(grey, grey, grey), storm)
	return col if linear else col.srgb_to_linear()


static func luma(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


## gl_compatibility shades in the colours' own space; the RD renderers in linear.
static func renderer_is_linear() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"
