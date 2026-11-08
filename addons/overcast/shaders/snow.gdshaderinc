#ifndef OVERCAST_SNOW_GDSHADERINC
#define OVERCAST_SNOW_GDSHADERINC
// Lying snow. Include in a surface shader and call overcast_snow_pbr (or overcast_snow, for a
// shader that lights itself) from fragment(), after any wetting: it settles and melts with
// OvercastWeather's snow, through a global, with nothing to register. It lands where rain does, so
// the ground under a roof stays bare, and only on what faces up: a dusting in patches first, then
// a layer over all of it. Where the sun reaches it, it glitters (overcast_snow_glint).
global uniform float overcast_snow_cover;  // 0 bare, 1 all covered
// Metres of snow per rain floor cell (OvercastSnowField): drifted, scoured and melted where it is.
// Without one, the snow lies as overcast_snow_cover says everywhere.
global uniform bool overcast_has_snow_field;
global uniform sampler2D overcast_snow_field : filter_nearest;
uniform float snow_scale : hint_range(0.0, 1.0) = 1.0;  // how readily this surface holds snow
#include "res://addons/overcast/shaders/rain_floor.gdshaderinc"
#include "res://addons/overcast/shaders/noise.gdshaderinc"

// The even layer a calm leaves (OvercastWeather.DRIFT_LAYER): this deep, the ground is all under it.
const float OVERCAST_SNOW_LAYER = 0.3;

// Metres of snow at world xz, blended between the four cells around it.
float overcast_snow_depth(vec2 xz) {
	ivec2 res = textureSize(overcast_snow_field, 0);
	vec2 texel = (xz - overcast_rain_floor_origin.xz) / overcast_rain_floor_size * vec2(res) - 0.5;
	ivec2 c = ivec2(floor(texel));
	vec2 f = fract(texel);
	vec4 d;
	for (int i = 0; i < 4; i++) {
		d[i] = texelFetch(overcast_snow_field, clamp(c + ivec2(i % 2, i / 2), ivec2(0), res - 1), 0).r;
	}
	return mix(mix(d.x, d.y, f.x), mix(d.z, d.w, f.x), f.y);
}

// How far the snow at world_pos has settled, 0 to 1: the field's depth over the even layer, or
// overcast_snow_cover off it.
float overcast_snow_lying(vec3 world_pos) {
	if (!overcast_has_snow_field || !rain_floor_covers(rain_floor_uv(world_pos))) {
		return overcast_snow_cover;
	}
	return clamp(overcast_snow_depth(world_pos.xz) / OVERCAST_SNOW_LAYER, 0.0, 1.0);
}

const vec3 OVERCAST_SNOW_ALBEDO = vec3(0.8, 0.82, 0.85);
// Glints: one candidate per cell of this many per metre (across the ground), of which this share
// catch the light at some angle; how big, in cells, and how bright.
const float OVERCAST_GLINT_CELLS = 40.0;
const float OVERCAST_GLINT_SHARE = 0.6;
const float OVERCAST_GLINT_POWER = 250.0;
const float OVERCAST_GLINT_SIZE = 0.35;
const float OVERCAST_GLINT_BRIGHT = 40.0;

// How much of the surface at world_pos is under snow, 0 to 1: a thin dusting while it settles,
// all of it once it lies deep.
float overcast_snow_amount(vec3 world_pos, vec3 world_normal) {
	if (overcast_snow_cover <= 0.0 || world_normal.y < 0.4) {
		return 0.0;
	}
	// Steeper holds less, but only gently past the cutoff, so the noise and not the mesh's facets
	// draws the edges of the patches.
	float slope = smoothstep(0.4, 0.55, world_normal.y) * mix(0.8, 1.0, smoothstep(0.55, 0.9, world_normal.y));
	vec2 q = world_pos.xz;
	// Asked a wandering way off, so where cover keeps it off the edge is ragged, blown in here and
	// short there, not the roof's outline.
	vec2 warp = vec2(overcast_vnoise(q * 0.9 + 5.3), overcast_vnoise(q * 0.9 + 11.7)) - 0.5;
	vec3 off = vec3(warp.x * 0.9, rain_slope_lift(world_normal, abs(warp) * 0.9), warp.y * 0.9);
	float s = overcast_snow_lying(world_pos) * snow_scale * slope
		* rain_reaches(world_pos + world_normal * 0.02 + off);
	if (s <= 0.0) {
		return 0.0;
	}
	float n = overcast_vnoise(q * 0.45) * 0.6 + overcast_vnoise(q * 1.9) * 0.3
		+ overcast_vnoise(q * 8.0) * 0.1;
	// Half settled, the high half of the noise is under snow; fully settled, all of it.
	float cover = clamp((s * 1.6 - 1.0 + n) * 5.0, 0.0, 1.0);
	return cover * mix(0.55, 1.0, smoothstep(0.2, 0.9, s));
}

// Lying snow's colour at world_pos: not one flat white, but packed and drifted a little brighter
// here and duller there, over metres.
vec3 overcast_snow_albedo(vec3 world_pos) {
	vec2 q = world_pos.xz;
	return OVERCAST_SNOW_ALBEDO * (0.93 + 0.1 * overcast_vnoise(q * 0.3 + 3.1) + 0.04 * overcast_vnoise(q * 1.7));
}

// For Godot's own lighting: white, rough and dull where it lies. Returns overcast_snow_amount.
// Bend NORMAL with overcast_snow_normal and add overcast_snow_glint in light() for the rest.
float overcast_snow_pbr(inout vec3 albedo, inout float roughness, inout float specular,
		vec3 world_pos, vec3 world_normal) {
	float k = overcast_snow_amount(world_pos, world_normal);
	albedo = mix(albedo, overcast_snow_albedo(world_pos), k);
	roughness = mix(roughness, 0.75, k);
	specular = mix(specular, 0.35, k);
	return k;
}

// Snow fills the hollows and rounds the bumps: the normal turns toward `up` (the same space as
// `normal`) as it lies deeper.
vec3 overcast_snow_normal(vec3 normal, vec3 up, float k) {
	return normalize(mix(normal, up, k * 0.6));
}

// How many glint cells a pixel spans at world_pos. Call from fragment(), outside any branch (it
// takes derivatives), and pass it to light() with the snow amount.
float overcast_snow_footprint(vec3 world_pos) {
	return length(fwidth(world_pos.xz)) * OVERCAST_GLINT_CELLS;
}

// A grain of snow at world_pos turned just so, flashing as the eye or the light moves: a
// multiplier on the light's colour, for SPECULAR_LIGHT. `k` is the snow there and `footprint`
// overcast_snow_footprint; `normal`, `view` and `light` share a space (light()'s NORMAL, VIEW and
// LIGHT).
float overcast_snow_glint(vec3 world_pos, float k, float footprint, vec3 normal, vec3 view,
		vec3 light) {
	// Where a pixel spans many cells, glints would only shimmer.
	float reach = smoothstep(4.0, 2.0, footprint);
	if (k <= 0.0 || reach <= 0.0) {
		return 0.0;
	}
	// Cells across the ground, which is what snow lies on; each glint a point at a spot of its own
	// in its cell.
	vec2 q = world_pos.xz * OVERCAST_GLINT_CELLS;
	vec3 cell = vec3(floor(q), 0.0);
	if (overcast_hash13(cell) > OVERCAST_GLINT_SHARE) {
		return 0.0;
	}
	vec2 spot = vec2(overcast_hash13(cell + 47.3), overcast_hash13(cell + 61.9)) * 0.6 + 0.2;
	// A point smaller than a pixel is widened to one, dimmer, as the drops are.
	float size = clamp(footprint * 0.5, OVERCAST_GLINT_SIZE, 0.5);
	float point = smoothstep(size, 0.0, length(fract(q) - spot)) * pow(OVERCAST_GLINT_SIZE / size, 2.0);
	if (point <= 0.0) {
		return 0.0;
	}
	vec3 tilt = vec3(overcast_hash13(cell + 17.1), overcast_hash13(cell + 31.7),
		overcast_hash13(cell + 5.3)) - 0.5;
	vec3 facet = normalize(normal + tilt * 1.2);
	float g = pow(max(dot(facet, normalize(view + light)), 0.0), OVERCAST_GLINT_POWER);
	return g * point * reach * k * OVERCAST_GLINT_BRIGHT;
}

// For a shader that lights itself (a lightmap): `lit_srgb` is the surface's lit colour and
// `albedo` its base colour, in the renderer's native space (linear, but sRGB on
// gl_compatibility); normal_view and view are NORMAL and VIEW.
// The snow takes the light the surface was given: lit over base. It has no light's direction, so
// its glints catch the eye's and are as bright as the light there.
void overcast_snow(inout vec3 lit_srgb, inout vec3 albedo, vec3 world_pos, vec3 world_normal,
		vec3 normal_view, vec3 view) {
	float footprint = overcast_snow_footprint(world_pos);  // before any branch
	float k = overcast_snow_amount(world_pos, world_normal);
	if (k <= 0.0) {
		return;
	}
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 base = albedo;
	vec3 white = overcast_snow_albedo(world_pos);
#else
	vec3 base = pow(max(albedo, vec3(0.0)), vec3(1.0 / 2.2));
	vec3 white = pow(overcast_snow_albedo(world_pos), vec3(2.2));
#endif
	// A dark texel says little about its light; the floor keeps it from reading as none.
	vec3 light = min(lit_srgb / max(base, vec3(0.08)), vec3(4.0));
	float glint = overcast_snow_glint(world_pos, k, footprint, normal_view, view, view);
	// Only direct light glints: what a lightmap gives past the ambient's share.
	float direct = smoothstep(0.5, 1.2, dot(light, vec3(0.333)));
	lit_srgb = min(mix(lit_srgb, overcast_snow_albedo(world_pos) * light, k) + glint * direct * 0.04, vec3(1.0));
	albedo = mix(albedo, white, k);
}
#endif
