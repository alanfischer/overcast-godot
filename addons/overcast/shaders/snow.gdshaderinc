#ifndef OVERCAST_SNOW_GDSHADERINC
#define OVERCAST_SNOW_GDSHADERINC
// Lying snow. Include in a surface shader and call overcast_snow_pbr (or overcast_snow, for a
// shader that lights itself) from fragment(), after any wetting: it settles and melts with
// OvercastWeather's snow, through a global, with nothing to register. It lands where rain does, so
// the ground under a roof stays bare, and only on what faces up: patches first, then all of it.
global uniform float overcast_snow_cover;  // 0 bare, 1 all covered
uniform float snow_scale : hint_range(0.0, 1.0) = 1.0;  // how readily this surface holds snow
#include "res://addons/overcast/shaders/rain_floor.gdshaderinc"
#include "res://addons/overcast/shaders/noise.gdshaderinc"

const vec3 OVERCAST_SNOW_ALBEDO = vec3(0.9, 0.92, 0.95);

// How much of the surface at world_pos is under snow, 0 to 1.
float overcast_snow_amount(vec3 world_pos, vec3 world_normal) {
	if (overcast_snow_cover <= 0.0 || world_normal.y < 0.4) {
		return 0.0;
	}
	// Steeper holds less, but only gently past the cutoff, so the noise and not the mesh's facets
	// draws the edges of the patches.
	float slope = smoothstep(0.4, 0.55, world_normal.y) * mix(0.8, 1.0, smoothstep(0.55, 0.9, world_normal.y));
	float s = overcast_snow_cover * snow_scale * slope * rain_reaches(world_pos + world_normal * 0.02);
	if (s <= 0.0) {
		return 0.0;
	}
	vec2 q = world_pos.xz;
	float n = overcast_vnoise(q * 0.45) * 0.6 + overcast_vnoise(q * 1.9) * 0.3
		+ overcast_vnoise(q * 8.0) * 0.1;
	// Half settled, the high half of the noise is under snow; fully settled, all of it.
	return clamp((s * 1.6 - 1.0 + n) * 5.0, 0.0, 1.0);
}

// For Godot's own lighting: white, rough and dull where it lies. Returns overcast_snow_amount.
float overcast_snow_pbr(inout vec3 albedo, inout float roughness, inout float specular,
		vec3 world_pos, vec3 world_normal) {
	float k = overcast_snow_amount(world_pos, world_normal);
	albedo = mix(albedo, OVERCAST_SNOW_ALBEDO, k);
	roughness = mix(roughness, 0.75, k);
	specular = mix(specular, 0.35, k);
	return k;
}

// For a shader that lights itself (a lightmap): `lit_srgb` is the surface's lit colour and
// `albedo` its base colour, in the renderer's native space (linear, but sRGB on
// gl_compatibility). The snow takes the light the surface was given: lit over base.
void overcast_snow(inout vec3 lit_srgb, inout vec3 albedo, vec3 world_pos, vec3 world_normal) {
	float k = overcast_snow_amount(world_pos, world_normal);
	if (k <= 0.0) {
		return;
	}
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 base = albedo;
	vec3 white = OVERCAST_SNOW_ALBEDO;
#else
	vec3 base = pow(max(albedo, vec3(0.0)), vec3(1.0 / 2.2));
	vec3 white = pow(OVERCAST_SNOW_ALBEDO, vec3(2.2));
#endif
	// A dark texel says little about its light; the floor keeps it from reading as none.
	vec3 light = min(lit_srgb / max(base, vec3(0.08)), vec3(4.0));
	lit_srgb = min(mix(lit_srgb, OVERCAST_SNOW_ALBEDO * light, k), vec3(1.0));
	albedo = mix(albedo, white, k);
}
#endif
