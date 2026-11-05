#ifndef OVERCAST_STANDARD_GDSHADERINC
#define OVERCAST_STANDARD_GDSHADERINC
// A StandardMaterial3D's look, shaded by the clouds, wetted by the rain and covered by the snow:
// what OvercastMaterials converts one to. Godot's own lighting, redone in light() so the clouds can
// take their share off the sun. OvercastMaterials writes the render_mode and the OV_ switches
// above the include.
#include "res://addons/overcast/shaders/clouds.gdshaderinc"
#include "res://addons/overcast/shaders/wet.gdshaderinc"
#include "res://addons/overcast/shaders/snow.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
#ifdef OV_ALBEDO_TEXTURE
uniform sampler2D texture_albedo : source_color, OV_FILTER, OV_REPEAT;
#endif
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
#ifdef OV_METALLIC_TEXTURE
uniform sampler2D texture_metallic : hint_default_white, OV_FILTER, OV_REPEAT;
uniform vec4 metallic_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
#endif
#ifdef OV_ROUGHNESS_TEXTURE
uniform sampler2D texture_roughness : hint_default_white, OV_FILTER, OV_REPEAT;
uniform vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
#endif
#ifdef OV_NORMAL
uniform sampler2D texture_normal : hint_roughness_normal, OV_FILTER, OV_REPEAT;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
#endif
#ifdef OV_EMISSION
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;
uniform sampler2D texture_emission : source_color, hint_default_black, OV_FILTER, OV_REPEAT;
#endif
#ifdef OV_AO
uniform sampler2D texture_ambient_occlusion : hint_default_white, OV_FILTER, OV_REPEAT;
uniform vec4 ao_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float ao_light_affect : hint_range(0.0, 1.0) = 0.0;
#endif
#ifdef OV_ALPHA_SCISSOR
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
#endif
#ifdef OV_ALPHA_HASH
uniform float alpha_hash_scale = 1.0;
#endif
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

varying vec3 ov_world_pos;
// The snow, and how many glint cells a pixel spans, for light()'s glints.
varying vec2 ov_glint;
// light() has no SPECULAR to build the reflectance from.
varying float ov_specular;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
#ifdef OV_VERTEX_COLOR_SRGB
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)),
			COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
#endif
	ov_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 albedo_tex = vec4(1.0);
#ifdef OV_ALBEDO_TEXTURE
	albedo_tex = texture(texture_albedo, UV);
#endif
#ifdef OV_VERTEX_COLOR
	albedo_tex *= COLOR;
#endif
	vec3 alb = albedo.rgb * albedo_tex.rgb;
	float metal = metallic;
#ifdef OV_METALLIC_TEXTURE
	metal *= dot(texture(texture_metallic, UV), metallic_texture_channel);
#endif
	float rough = roughness;
#ifdef OV_ROUGHNESS_TEXTURE
	rough *= dot(texture(texture_roughness, UV), roughness_texture_channel);
#endif
	float spec = specular;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	overcast_wet_pbr(alb, rough, spec, ov_world_pos, world_normal);
	float snow = overcast_snow_pbr(alb, rough, spec, ov_world_pos, world_normal);
	metal *= 1.0 - snow;
	ov_glint = vec2(snow, overcast_snow_footprint(ov_world_pos));
	NORMAL = overcast_snow_normal(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, snow);
	ALBEDO = alb;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = spec;
	ov_specular = spec;
#ifdef OV_NORMAL
	NORMAL_MAP = texture(texture_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale * (1.0 - snow);  // snow smooths over the bumps
#endif
#ifdef OV_EMISSION
	vec3 emission_tex = texture(texture_emission, UV).rgb;
#ifdef OV_EMISSION_MULTIPLY
	EMISSION = emission.rgb * emission_tex * emission_energy;
#else
	EMISSION = (emission.rgb + emission_tex) * emission_energy;
#endif
#endif
#ifdef OV_AO
	AO = mix(dot(texture(texture_ambient_occlusion, UV), ao_texture_channel), 1.0, snow);
	AO_LIGHT_AFFECT = ao_light_affect;
#endif
#ifdef OV_ALPHA
	ALPHA = albedo.a * albedo_tex.a;
#endif
#ifdef OV_ALPHA_SCISSOR
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
#endif
#ifdef OV_ALPHA_HASH
	ALPHA_HASH_SCALE = alpha_hash_scale;
#endif
}

float ov_schlick(float u) {
	float m = 1.0 - u;
	float m2 = m * m;
	return m2 * m2 * m;
}

// Godot's light_compute (scene.glsl, scene_forward_lights_inc.glsl), the clouds aside.
void light() {
	float cNdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 light = LIGHT_COLOR * ATTENUATION;
	// Where the sun lights nothing, there is nothing for a cloud to take.
	if (LIGHT_IS_DIRECTIONAL && cNdotL > 0.0) {
		light *= cloud_sunlight(ov_world_pos);
	}
	float cNdotV = max(dot(NORMAL, VIEW), 1e-4);
	vec3 H = normalize(VIEW + LIGHT);
	float cLdotH = clamp(dot(LIGHT, H), 0.0, 1.0);
	if (METALLIC < 1.0) {
#ifdef OV_LAMBERT
		float diffuse = cNdotL * (1.0 / PI);
#else
		float fd90 = 2.0 * cLdotH * cLdotH * ROUGHNESS - 0.5;
		float diffuse = (1.0 / PI) * (1.0 + fd90 * ov_schlick(cNdotV)) * (1.0 + fd90 * ov_schlick(cNdotL)) * cNdotL;
#endif
		DIFFUSE_LIGHT += light * diffuse;
	}
#ifndef OV_NO_SPECULAR
	if (ROUGHNESS > 0.0) {
		float cNdotH = clamp(dot(NORMAL, H), 0.0, 1.0);
		float a = ROUGHNESS * ROUGHNESS;
		float ah = cNdotH * a;
		float k = a / (1.0 - cNdotH * cNdotH + ah * ah);
		float D = k * k * (1.0 / PI);
		float G = 0.5 / mix(2.0 * cNdotL * cNdotV, cNdotL + cNdotV, a);
		vec3 f0 = mix(vec3(0.16 * ov_specular * ov_specular), ALBEDO, METALLIC);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		float f90 = clamp(50.0 * f0.g, 0.0, 1.0);
#else
		float f90 = clamp(dot(f0, vec3(50.0 * 0.33)), METALLIC, 1.0);
#endif
		vec3 F = f0 + (f90 - f0) * ov_schlick(cLdotH);
		SPECULAR_LIGHT += cNdotL * D * F * G * light * SPECULAR_AMOUNT;
	}
#endif
	SPECULAR_LIGHT += light * cNdotL * overcast_snow_glint(ov_world_pos, ov_glint.x, ov_glint.y, NORMAL, VIEW, LIGHT);
}
#endif
