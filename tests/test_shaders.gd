extends "res://tests/suite.gd"
## Every shader compiles against the declared globals: a shader that fails to compile draws grey
## or nothing, and says so only in the log.

const SHADERS := {
	"res://addons/overcast/shaders/sky.gdshader": ["zenith_color", "storm", "flash_color", "cloud_amount"],
	"res://addons/overcast/shaders/rain.gdshader": ["color", "box", "velocity", "haze_density"],
	"res://addons/overcast/shaders/snow.gdshader": ["color", "box", "velocity", "haze_density", "flake_size", "opacity", "flash"],
	"res://addons/overcast/shaders/rain_haze.gdshader": ["density", "haze_color", "gust_noise", "linear_output"],
}


func test_shaders_declare_what_the_scripts_set() -> void:
	for path in SHADERS:
		var shader: Shader = load(path)
		assert_ne(shader, null, "%s loads" % path)
		if shader == null:
			continue
		var declared := {}
		for u in shader.get_shader_uniform_list():
			declared[u["name"]] = true
		for name in SHADERS[path]:
			assert_true(declared.has(name), "%s declares %s" % [path.get_file(), name])


## The includes, as a game's own shader would take them.
func test_includes_compile_into_a_surface_shader() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
#include "res://addons/overcast/shaders/clouds.gdshaderinc"
#include "res://addons/overcast/shaders/wet.gdshaderinc"
#include "res://addons/overcast/shaders/snow.gdshaderinc"
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 lit = vec3(0.5) * cloud_sunlight(world_pos);
	vec3 albedo = vec3(0.5);
	overcast_wet(lit, albedo, world_pos, vec3(0.0, 1.0, 0.0), NORMAL, VIEW);
	float roughness = 0.8;
	float specular = 0.5;
	vec2 wet = overcast_wet_pbr(albedo, roughness, specular, world_pos, vec3(0.0, 1.0, 0.0));
	overcast_snow(lit, albedo, world_pos, vec3(0.0, 1.0, 0.0));
	overcast_snow_pbr(albedo, roughness, specular, world_pos, vec3(0.0, 1.0, 0.0));
	ALBEDO = lit + albedo * wet.x;
	ROUGHNESS = roughness;
}
"""
	var names := _uniform_names(shader)
	assert_eq(names, ["puddle_scale", "snow_scale"],
		"it compiles, and all it takes of its own is how readily it pools and holds snow")
