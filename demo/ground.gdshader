// The demo's ground and buildings: lit by the sun, shaded by the clouds overhead, wet in the rain
// and white in the snow. Your own shaders take the same includes.
shader_type spatial;

#include "res://addons/overcast/shaders/clouds.gdshaderinc"
#include "res://addons/overcast/shaders/wet.gdshaderinc"
#include "res://addons/overcast/shaders/snow.gdshaderinc"

uniform vec3 color : source_color = vec3(0.4, 0.5, 0.3);
varying vec3 world_pos;
varying vec3 world_normal;
varying vec2 glint;  // the snow, and overcast_snow_footprint

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 albedo = color;
	float roughness = 0.9;
	float specular = 0.5;
	overcast_wet_pbr(albedo, roughness, specular, world_pos, world_normal);
	float snow = overcast_snow_pbr(albedo, roughness, specular, world_pos, world_normal);
	glint = vec2(snow, overcast_snow_footprint(world_pos));
	NORMAL = overcast_snow_normal(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, snow);
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}

void light() {
	// The clouds take their share off the sun, and only the sun.
	float shade = LIGHT_IS_DIRECTIONAL ? cloud_sunlight(world_pos) : 1.0;
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI * shade;
	SPECULAR_LIGHT += lit * ATTENUATION * LIGHT_COLOR * shade
		* overcast_snow_glint(world_pos, glint.x, glint.y, NORMAL, VIEW, LIGHT);
}
