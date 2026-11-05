@tool
class_name OvercastGlobals
extends Object
## The global shader uniforms every Overcast shader reads: the cloud layer (OvercastClouds) and the
## rain and snow (OvercastWeather). Global, so any shader that includes clouds.gdshaderinc,
## wet.gdshaderinc or snow.gdshaderinc follows the weather with nothing to register. The plugin
## declares them in the project settings.

## name -> [type, default], in project-settings form.
const GLOBALS := {
	"overcast_noise": ["sampler2D", ""],
	"overcast_height": ["float", 100.0],
	"overcast_scale": ["float", 2.2],
	"overcast_speed": ["float", 0.035],
	"overcast_softness": ["float", 0.1],
	"overcast_cover": ["float", 0.0],
	"overcast_shadow": ["float", 0.0],
	"overcast_sun_dir": ["vec3", Vector3(0, 1, 0)],
	"overcast_volumetric": ["float", 0.0],
	"overcast_volume": ["sampler3D", ""],
	"overcast_rain_floor": ["sampler2D", ""],
	"overcast_has_rain_floor": ["bool", false],
	"overcast_rain_beyond_floor": ["bool", false],
	"overcast_rain_floor_origin": ["vec3", Vector3.ZERO],
	"overcast_rain_floor_size": ["vec2", Vector2.ONE],
	"overcast_rain_top": ["float", 1e6],
	"overcast_wetness": ["float", 0.0],
	"overcast_puddles": ["float", 0.0],
	"overcast_rain_sky": ["vec3", Vector3.ZERO],
	"overcast_snow_cover": ["float", 0.0],
}

const _TYPES := {
	"bool": RenderingServer.GLOBAL_VAR_TYPE_BOOL,
	"float": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
	"vec2": RenderingServer.GLOBAL_VAR_TYPE_VEC2,
	"vec3": RenderingServer.GLOBAL_VAR_TYPE_VEC3,
	"sampler2D": RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,
	"sampler3D": RenderingServer.GLOBAL_VAR_TYPE_SAMPLER3D,
}

static var _values := {}


## A global's value as last set here; its default if never set. RenderingServer only reads them
## back in the editor.
static func value(key: String) -> Variant:
	if _values.has(key):
		return _values[key]
	var v = GLOBALS[key][1]
	return null if v is String else v


static func set_value(key: String, v: Variant) -> void:
	_values[key] = v
	RenderingServer.global_shader_parameter_set(key, v)


## Back to the default, as a scene with no weather or sky in it has them.
static func reset(key: String) -> void:
	_values.erase(key)
	RenderingServer.global_shader_parameter_set(key, value(key))


## Whether the globals are declared. A shader that reads an undeclared global fails to compile.
static func declared() -> bool:
	var have := RenderingServer.global_shader_parameter_get_list()
	for key in GLOBALS:
		if not have.has(StringName(key)):
			return false
	return true


## Declare the globals at runtime, for tests and tools. Must run before any Overcast shader loads.
static func declare() -> void:
	var have := RenderingServer.global_shader_parameter_get_list()
	for key in GLOBALS:
		if not have.has(StringName(key)):
			RenderingServer.global_shader_parameter_add(key, _TYPES[GLOBALS[key][0]], value(key))
