#ifndef OVERCAST_WET_GDSHADERINC
#define OVERCAST_WET_GDSHADERINC
// Wet ground. Include in a surface shader and call overcast_wet_pbr (or overcast_wet, for a shader
// that lights itself) from fragment(): it soaks and dries with OvercastWeather's rain, through
// globals, with nothing to register. Where the wet has frozen it is glazed: glossy, pale and
// unrippled.
global uniform float overcast_wetness;  // 0 dry, 1 soaked
global uniform float overcast_puddles;  // how far flat ground has pooled
#ifndef OVERCAST_RAIN_SKY  // snow.gdshaderinc reads it too
#define OVERCAST_RAIN_SKY
global uniform vec3 overcast_rain_sky;  // the sky colour wet surfaces reflect, sRGB
#endif
global uniform float overcast_rainfall;  // how hard it is raining now, 0 to 1: what ripples puddles
global uniform float overcast_ice;  // how much of the wet ground has frozen, where no ice field says
// How much has frozen per rain floor cell (OvercastIceField): thawed and frozen where it is.
global uniform bool overcast_has_ice_field;
global uniform sampler2D overcast_ice_field : filter_nearest;
uniform float puddle_scale : hint_range(0.0, 1.0) = 1.0;  // how readily this surface pools: earth does, planks drain
#include "res://addons/overcast/shaders/rain_floor.gdshaderinc"
#include "res://addons/overcast/shaders/noise.gdshaderinc"

// Ripples: rings spreading where drops land on standing water. One ring at a time per cell of a
// grid this many per metre, in a few offset layers, each ring OVERCAST_RIPPLE_LIFE seconds.
const float OVERCAST_RIPPLE_CELLS = 3.0;
const int OVERCAST_RIPPLE_LAYERS = 3;
const float OVERCAST_RIPPLE_LIFE = 0.7;
// Wavelength of the rings and how far they tilt the water, and the radius (in cells) they reach.
const float OVERCAST_RIPPLE_WAVE = 40.0;
const float OVERCAST_RIPPLE_TILT = 0.35;
const float OVERCAST_RIPPLE_REACH = 0.32;

const vec3 OVERCAST_ICE_TINT = vec3(0.86, 0.93, 1.0);
const vec3 OVERCAST_FROST = vec3(0.75, 0.82, 0.9);

// How much ice glazes the ground at world_pos, 0 to 1 (as overcast_wetness is), blended between
// the four cells around it; overcast_ice off the field.
float overcast_ice_lying(vec3 world_pos) {
	vec2 uv = rain_floor_uv(world_pos);
	if (!overcast_has_ice_field || !rain_floor_covers(uv)) {
		return overcast_ice;
	}
	return rain_floor_blend(overcast_ice_field, uv);
}

// Pale frost in the ice at world_pos, 0 to 1: blotches and fine streaks, so a glaze reads as one.
float overcast_ice_frost(vec3 world_pos) {
	vec2 q = world_pos.xz;
	float blotch = smoothstep(0.35, 0.75, overcast_vnoise(q * 0.9 + 7.3));
	float streak = smoothstep(0.55, 0.85, overcast_vnoise(q * vec2(6.0, 1.5) + 2.1));
	return clamp(0.35 + 0.45 * blotch + 0.3 * streak, 0.0, 1.0);
}

// The slope rain's ripples put on standing water at world xz: d(height)/dx, d(height)/dz.
vec2 overcast_ripple_slope(vec2 xz) {
	vec2 slope = vec2(0.0);
	for (int layer = 0; layer < OVERCAST_RIPPLE_LAYERS; layer++) {
		float fl = float(layer);
		vec2 q = xz * OVERCAST_RIPPLE_CELLS + fl * vec2(0.37, 0.61);
		vec2 cell = floor(q);
		float t = TIME / OVERCAST_RIPPLE_LIFE + overcast_hash12(cell + fl * 17.31);
		float cycle = floor(t);
		float age = fract(t);
		// Each turn of the cell may or may not have a drop land in it, by how hard it is raining.
		vec2 k = cell + vec2(mod(cycle, 997.0) * 0.731, fl * 5.17);
		if (overcast_hash12(k) > overcast_rainfall) {
			continue;
		}
		vec2 centre = 0.35 + 0.3 * vec2(overcast_hash12(k + 3.1), overcast_hash12(k + 7.7));
		vec2 d = fract(q) - centre;
		float r = length(d);
		float x = (r - age * OVERCAST_RIPPLE_REACH) * OVERCAST_RIPPLE_WAVE;
		float env = exp(-x * x * 0.3) * (1.0 - age) * (1.0 - age);
		slope += d / max(r, 1e-3) * cos(x) * env;
	}
	return slope;
}

// How wet the surface at world_pos is (x), how much of it is puddle (y), and of the wet, the share
// frozen (z). A ceiling stays dry; a wall asks about the air a cell and a half out from it (clear
// of the cells the wall's top is in, even on the diagonal), and takes less.
vec3 overcast_wet_ice(vec3 world_pos, vec3 world_normal) {
	if (overcast_wetness <= 0.0 || world_normal.y < -0.3) {
		return vec3(0.0);
	}
	vec2 cell = rain_floor_cell();
	float reach = world_normal.y > 0.3
		? rain_reaches(world_pos + world_normal * 0.02 + vec3(0.0, rain_slope_lift(world_normal, vec2(0.0)), 0.0))
		: rain_reaches(world_pos + world_normal * 1.5 * max(cell.x, cell.y)) * 0.6;
	float ice = overcast_ice_lying(world_pos);
	float most = max(overcast_wetness, ice);
	float wet = most * reach;
	float pool = 0.0;
	if (wet > 0.0 && world_normal.y > 0.95) {
		float n = overcast_vnoise(world_pos.xz * 0.55) * 0.7 + overcast_vnoise(world_pos.xz * 2.3) * 0.3;
		float edge = mix(1.05, 0.55, overcast_puddles * puddle_scale);
		pool = smoothstep(edge, edge + 0.05, n) * reach;
	}
	return vec3(wet, pool, ice / most);
}

// How wet the surface at world_pos is (x), and how much of it is puddle (y).
vec2 overcast_wet_amount(vec3 world_pos, vec3 world_normal) {
	return overcast_wet_ice(world_pos, world_normal).xy;
}

// How much rain's ripples brighten (over 1) or dim the reflection on standing water at world_pos,
// `pool` deep; `footprint` is length(fwidth(world_pos.xz)), taken outside any branch. The rings'
// slopes catch more of the sky on one side and less on the other, whatever sky it is.
float overcast_ripple_shine(vec3 world_pos, float pool, float footprint) {
	if (overcast_rainfall <= 0.0 || pool <= 0.0) {
		return 1.0;
	}
	vec2 s = overcast_ripple_slope(world_pos.xz) * pool
		* smoothstep(0.15, 0.05, footprint * OVERCAST_RIPPLE_CELLS);
	return clamp(1.0 + (s.x + s.y) * 1.2, 0.2, 2.5);
}

// For Godot's own lighting: darker albedo and a smoother surface, so the scene's reflections (the
// sky's radiance) give the sheen and a puddle its mirror, rippled while it rains. Call from
// fragment(), outside any branch (it takes derivatives), after setting all three (SPECULAR is 0.5
// by default). A puddle reflects more than water's Fresnel would, as overcast_wet does: the sky is
// far brighter than the ground. Ice is paler, smoother and unrippled. Returns how wet (x) and how
// much open puddle, unfrozen, the rain ripples (y), for overcast_wet_normal.
vec2 overcast_wet_pbr(inout vec3 albedo, inout float roughness, inout float specular, vec3 world_pos,
		vec3 world_normal) {
	float footprint = length(fwidth(world_pos.xz));
	vec3 w = overcast_wet_ice(world_pos, world_normal);
	float ice = w.z * w.x;
	vec3 glazed = ice > 0.0
		? mix(albedo * OVERCAST_ICE_TINT, OVERCAST_FROST, 0.35 * overcast_ice_frost(world_pos)) : albedo;
	albedo *= mix(1.0, 0.6, w.x) * mix(1.0, 0.6, w.y);
	albedo = mix(albedo, glazed, ice);
	roughness = mix(mix(mix(roughness, min(roughness, 0.3), w.x), 0.02, w.y), 0.04, ice);
	float shine = mix(overcast_ripple_shine(world_pos, w.y, footprint), 1.0, w.z);
	specular = clamp(mix(mix(specular, 1.0, w.y), 0.9, ice) * shine, 0.0, 1.0);
	return vec2(w.x, w.y * (1.0 - w.z));
}

// Bends `normal` by the ripples rain makes on the puddles, for Godot's own lighting to catch in its
// reflections. Call from fragment(), outside any branch (it takes derivatives), with `wet` as
// overcast_wet_pbr returned it; `world_to_normal` takes world directions into the space `normal`
// is in: mat3(VIEW_MATRIX) for NORMAL.
vec3 overcast_wet_normal(vec3 normal, mat3 world_to_normal, vec3 world_pos, vec2 wet) {
	// Too small to see from here, the rings would only shimmer.
	float footprint = length(fwidth(world_pos.xz)) * OVERCAST_RIPPLE_CELLS;
	float k = wet.y * smoothstep(0.15, 0.05, footprint);
	if (k <= 0.0 || overcast_rainfall <= 0.0) {
		return normal;
	}
	vec2 s = overcast_ripple_slope(world_pos.xz) * k * OVERCAST_RIPPLE_TILT;
	return normalize(normal + world_to_normal * vec3(-s.x, 0.0, -s.y));
}

// For a shader that lights itself (a lightmap): wet is darker, and reflects overcast_rain_sky, a
// damp surface at grazing angles only (water's Fresnel, F0 0.02), a puddle as a mirror-flat layer
// over a darker floor, a glaze as a paler, glossier layer. `lit_srgb` is the surface's lit colour,
// `albedo` its base colour and `light` the light it was lit with (lit_srgb before any clamp, over
// the base); normal_view and view are NORMAL and VIEW.
void overcast_wet(inout vec3 lit_srgb, inout vec3 albedo, vec3 light, vec3 world_pos,
		vec3 world_normal, vec3 normal_view, vec3 view) {
	float footprint = length(fwidth(world_pos.xz));  // before any branch
	vec3 w = overcast_wet_ice(world_pos, world_normal);
	if (w.x <= 0.0) {
		return;
	}
	float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(normal_view, view), 0.0, 1.0), 5.0);
	// A puddle shows the floor under it darker and the sky over it brighter than its Fresnel alone
	// would: the sky it reflects is far brighter than anything the light puts on the ground.
	float ice = w.z;
	float dark = mix(1.0, 0.6, w.x) * mix(1.0, 0.6, w.y);
	float mirror = mix(w.x * 0.5 * fresnel, max(fresnel * 2.0, 0.1), w.y);
	mirror *= mix(overcast_ripple_shine(world_pos, w.y, footprint), 1.0, ice);
	vec3 lit = lit_srgb * dark;
	if (ice > 0.0) {
		// Ice keeps the floor's light, frosted pale in patches, and shines all over as a puddle does.
		vec3 frost = OVERCAST_FROST * min(light, vec3(2.0));
		vec3 glazed = mix(lit_srgb * OVERCAST_ICE_TINT, frost, 0.35 * overcast_ice_frost(world_pos));
		lit = mix(lit, glazed, ice * w.x);
		mirror = mix(mirror, max(fresnel * 2.0, 0.2), ice);
	}
	lit_srgb = min(lit + overcast_rain_sky * mirror, vec3(1.0));
	albedo *= mix(dark, 1.0, ice * w.x);
}
#endif
