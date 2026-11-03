#ifndef OVERCAST_WET_GDSHADERINC
#define OVERCAST_WET_GDSHADERINC
// Wet ground: include in a surface shader and call overcast_wet from fragment(). OvercastWeather
// finds every material whose shader declares `wetness` (OvercastWeather.add_wet_materials) and
// soaks and dries it with the rain.
uniform float wetness = 0.0;      // 0 dry, 1 soaked
uniform float puddles = 0.0;      // how far flat ground has pooled
uniform float puddle_scale = 1.0;  // how readily this surface pools: earth does, planks drain
uniform vec3 rain_sky = vec3(0.0);  // the sky colour wet surfaces reflect, sRGB
#include "res://addons/overcast/shaders/rain_floor.gdshaderinc"

float overcast_wet_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float overcast_wet_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(overcast_wet_hash(i), overcast_wet_hash(i + vec2(1.0, 0.0)), f.x),
		mix(overcast_wet_hash(i + vec2(0.0, 1.0)), overcast_wet_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 1 where rain reaches world point p, 0 under cover. The floor's four cells around p are blended,
// so a roof's shadow on the ground is not drawn as a staircase. Everywhere, with no floor baked.
float rain_reaches(vec3 p) {
	if (!has_floor) {
		return 1.0;
	}
	vec2 uv = rain_floor_uv(p);
	if (!rain_floor_covers(uv)) {
		return 0.0;
	}
	ivec2 res = textureSize(rain_floor, 0);
	vec2 texel = uv * vec2(res) - 0.5;
	ivec2 cell = ivec2(floor(texel));
	vec2 f = fract(texel);
	vec4 reach;
	for (int i = 0; i < 4; i++) {
		ivec2 c = clamp(cell + ivec2(i % 2, i / 2), ivec2(0), res - 1);
		// Fully wet at the height rain stops, drying over the quarter metre below it.
		reach[i] = clamp((p.y - texelFetch(rain_floor, c, 0).r) * 4.0 + 1.0, 0.0, 1.0);
	}
	return mix(mix(reach.x, reach.y, f.x), mix(reach.z, reach.w, f.x), f.y);
}

// Wet is darker, and reflects the sky: a damp surface at grazing angles only (water's Fresnel,
// F0 0.02), a puddle as a mirror-flat layer of water over a darker floor. A ceiling stays dry; a
// wall asks about the air half a metre out from it, and takes less. `lit_srgb` is the surface's
// lit colour and `albedo` its base colour; normal_view and view are NORMAL and VIEW.
void overcast_wet(inout vec3 lit_srgb, inout vec3 albedo, vec3 world_pos, vec3 world_normal,
		vec3 normal_view, vec3 view) {
	if (wetness <= 0.0 || world_normal.y < -0.3) {
		return;
	}
	float reach = world_normal.y > 0.3 ? rain_reaches(world_pos + world_normal * 0.02)
		: rain_reaches(world_pos + world_normal * 0.5) * 0.6;
	float wet = wetness * reach;
	if (wet <= 0.0) {
		return;
	}
	float pool = 0.0;
	if (world_normal.y > 0.95) {
		float n = overcast_wet_noise(world_pos.xz * 0.55) * 0.7 + overcast_wet_noise(world_pos.xz * 2.3) * 0.3;
		float edge = mix(1.05, 0.55, puddles * puddle_scale);
		pool = smoothstep(edge, edge + 0.05, n) * reach;
	}
	float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(normal_view, view), 0.0, 1.0), 5.0);
	// A puddle shows the floor under it darker and the sky over it brighter than its Fresnel alone
	// would: the sky it reflects is far brighter than anything the light puts on the ground.
	float dark = mix(1.0, 0.6, wet) * mix(1.0, 0.6, pool);
	float mirror = mix(wet * 0.5 * fresnel, max(fresnel * 2.0, 0.1), pool);
	lit_srgb = min(lit_srgb * dark + rain_sky * mirror, vec3(1.0));
	albedo *= dark;
}
#endif
