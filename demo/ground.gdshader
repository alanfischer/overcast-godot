// The demo's ground and buildings: lit by the sun, shaded by the clouds overhead, wet in the rain
// and white in the snow. Your own shaders take the same includes.
shader_type spatial;

#include "res://addons/overcast/shaders/clouds.gdshaderinc"
#include "res://addons/overcast/shaders/wet.gdshaderinc"
#include "res://addons/overcast/shaders/snow.gdshaderinc"

uniform vec3 color : source_color = vec3(0.4, 0.5, 0.3);
// The field's ground (textures/CREDITS.md), laid across the world from above. Untextured
// surfaces are `color`.
uniform bool textured = false;
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 2.0;  // metres the texture spans, as photographed

varying vec3 world_pos;
varying vec3 world_normal;
varying vec2 glint;  // the snow, and overcast_snow_footprint

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (textured) {
		UV = world_pos.xz / tile;
		// Across the ground: the texture's right is +X, its up -Z.
		TANGENT = vec3(1.0, 0.0, 0.0);
		BINORMAL = vec3(0.0, 0.0, -1.0);
	}
}

// The ground texture at `uv`, and again turned and three times as big, mixed by a slow noise: one
// texture repeated every two metres across a field shows its grid from any height.
vec4 ground_sample(sampler2D tex, vec2 uv, float k) {
	vec2 big = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv / 3.1 + vec2(0.37, 0.71);
	return mix(texture(tex, uv), texture(tex, big), k);
}

void fragment() {
	vec3 albedo = color;
	float roughness = 0.9;
	if (textured) {
		float k = smoothstep(0.3, 0.7, overcast_vnoise(world_pos.xz * 0.08));
		// Patches of the field greener or browner, drier or lusher, over tens of metres.
		float lush = overcast_vnoise(world_pos.xz * 0.03 + 7.0);
		albedo = ground_sample(ground_albedo, UV, k).rgb * mix(vec3(1.08, 1.0, 0.85), vec3(0.9, 1.05, 0.9), lush);
		roughness = ground_sample(ground_roughness, UV, k).r;
		NORMAL_MAP = ground_sample(ground_normal, UV, k).rgb;
	}
	float specular = 0.5;
	vec2 wet = overcast_wet_pbr(albedo, roughness, specular, world_pos, world_normal);
	NORMAL = overcast_wet_normal(NORMAL, mat3(VIEW_MATRIX), world_pos, wet);
	float snow = overcast_snow_pbr(albedo, roughness, specular, world_pos, world_normal);
	glint = vec2(snow, overcast_snow_footprint(world_pos));
	NORMAL = overcast_snow_normal(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, snow);
	if (textured) {
		// Water fills the bumps and snow buries them.
		NORMAL_MAP_DEPTH = (1.0 - wet.y) * (1.0 - snow);
	}
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
