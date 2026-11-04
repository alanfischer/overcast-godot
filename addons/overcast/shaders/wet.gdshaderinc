#ifndef OVERCAST_WET_GDSHADERINC
#define OVERCAST_WET_GDSHADERINC
// Wet ground. Include in a surface shader and call overcast_wet_pbr (or overcast_wet, for a shader
// that lights itself) from fragment(): it soaks and dries with OvercastWeather's rain, through
// globals, with nothing to register.
global uniform float overcast_wetness;  // 0 dry, 1 soaked
global uniform float overcast_puddles;  // how far flat ground has pooled
global uniform vec3 overcast_rain_sky;  // the sky colour wet surfaces reflect, sRGB
uniform float puddle_scale : hint_range(0.0, 1.0) = 1.0;  // how readily this surface pools: earth does, planks drain
#include "res://addons/overcast/shaders/rain_floor.gdshaderinc"
#include "res://addons/overcast/shaders/noise.gdshaderinc"

// 1 where rain reaches world point p, 0 under cover. The floor's four cells around p are blended,
// so a roof's shadow on the ground is not drawn as a staircase. Everywhere, with no floor.
float rain_reaches(vec3 p) {
	if (!overcast_has_rain_floor) {
		return 1.0;
	}
	vec2 uv = rain_floor_uv(p);
	if (!rain_floor_covers(uv)) {
		return 0.0;
	}
	ivec2 res = textureSize(overcast_rain_floor, 0);
	vec2 texel = uv * vec2(res) - 0.5;
	ivec2 cell = ivec2(floor(texel));
	vec2 f = fract(texel);
	vec4 reach;
	for (int i = 0; i < 4; i++) {
		ivec2 c = clamp(cell + ivec2(i % 2, i / 2), ivec2(0), res - 1);
		// Fully wet at the height rain stops, drying over the quarter metre below it.
		reach[i] = clamp((p.y - texelFetch(overcast_rain_floor, c, 0).r) * 4.0 + 1.0, 0.0, 1.0);
	}
	return mix(mix(reach.x, reach.y, f.x), mix(reach.z, reach.w, f.x), f.y);
}

// How wet the surface at world_pos is (x), and how much of it is puddle (y). A ceiling stays dry;
// a wall asks about the air half a metre out from it, and takes less.
vec2 overcast_wet_amount(vec3 world_pos, vec3 world_normal) {
	if (overcast_wetness <= 0.0 || world_normal.y < -0.3) {
		return vec2(0.0);
	}
	float reach = world_normal.y > 0.3 ? rain_reaches(world_pos + world_normal * 0.02)
		: rain_reaches(world_pos + world_normal * 0.5) * 0.6;
	float wet = overcast_wetness * reach;
	float pool = 0.0;
	if (wet > 0.0 && world_normal.y > 0.95) {
		float n = overcast_vnoise(world_pos.xz * 0.55) * 0.7 + overcast_vnoise(world_pos.xz * 2.3) * 0.3;
		float edge = mix(1.05, 0.55, overcast_puddles * puddle_scale);
		pool = smoothstep(edge, edge + 0.05, n) * reach;
	}
	return vec2(wet, pool);
}

// For Godot's own lighting: darker albedo and a smoother surface, so the scene's reflections (the
// sky's radiance) give the sheen and a puddle its mirror. Call after setting all three (SPECULAR
// is 0.5 by default). A puddle reflects more than water's Fresnel would, as overcast_wet does: the
// sky is far brighter than the ground. Returns overcast_wet_amount.
vec2 overcast_wet_pbr(inout vec3 albedo, inout float roughness, inout float specular, vec3 world_pos,
		vec3 world_normal) {
	vec2 w = overcast_wet_amount(world_pos, world_normal);
	albedo *= mix(1.0, 0.6, w.x) * mix(1.0, 0.6, w.y);
	roughness = mix(mix(roughness, min(roughness, 0.3), w.x), 0.02, w.y);
	specular = mix(specular, 0.8, w.y);
	return w;
}

// For a shader that lights itself (a lightmap): wet is darker, and reflects overcast_rain_sky, a
// damp surface at grazing angles only (water's Fresnel, F0 0.02), a puddle as a mirror-flat layer
// over a darker floor. `lit_srgb` is the surface's lit colour and `albedo` its base colour;
// normal_view and view are NORMAL and VIEW.
void overcast_wet(inout vec3 lit_srgb, inout vec3 albedo, vec3 world_pos, vec3 world_normal,
		vec3 normal_view, vec3 view) {
	vec2 w = overcast_wet_amount(world_pos, world_normal);
	if (w.x <= 0.0) {
		return;
	}
	float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(normal_view, view), 0.0, 1.0), 5.0);
	// A puddle shows the floor under it darker and the sky over it brighter than its Fresnel alone
	// would: the sky it reflects is far brighter than anything the light puts on the ground.
	float dark = mix(1.0, 0.6, w.x) * mix(1.0, 0.6, w.y);
	float mirror = mix(w.x * 0.5 * fresnel, max(fresnel * 2.0, 0.1), w.y);
	lit_srgb = min(lit_srgb * dark + overcast_rain_sky * mirror, vec3(1.0));
	albedo *= dark;
}
#endif
