// The demo's ground and buildings: lit by the sun, shaded by the clouds overhead, wet in the rain
// and white in the snow. Your own shaders take the same includes.
shader_type spatial;

#include "res://addons/overcast/shaders/clouds.gdshaderinc"
#include "res://addons/overcast/shaders/wet.gdshaderinc"
#include "res://addons/overcast/shaders/snow.gdshaderinc"

uniform vec3 color : source_color = vec3(0.4, 0.5, 0.3);
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 albedo = color;
	float roughness = 0.9;
	float specular = 0.5;
	overcast_wet_pbr(albedo, roughness, specular, world_pos, world_normal);
	overcast_snow_pbr(albedo, roughness, specular, world_pos, world_normal);
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}

void light() {
	// The clouds take their share off the sun, and only the sun.
	float shade = LIGHT_IS_DIRECTIONAL ? cloud_sunlight(world_pos) : 1.0;
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI * shade;
}
