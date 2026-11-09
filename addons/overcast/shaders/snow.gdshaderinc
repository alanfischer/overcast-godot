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
#ifndef OVERCAST_RAIN_SKY
#define OVERCAST_RAIN_SKY
global uniform vec3 overcast_rain_sky;  // the sky's colour, sRGB: what snow in the shade takes
#endif
#ifndef OVERCAST_SUN_DIR
#define OVERCAST_SUN_DIR
global uniform vec3 overcast_sun_dir;  // unit, toward the sun
#endif
#include "res://addons/overcast/shaders/rain_floor.gdshaderinc"
#include "res://addons/overcast/shaders/noise.gdshaderinc"

// The even layer a calm leaves (OvercastWeather.DRIFT_LAYER): this deep, the ground is all under it.
const float OVERCAST_SNOW_LAYER = 0.3;

// Metres of snow at world xz, blended between the four cells around it.
float overcast_snow_depth(vec2 xz) {
	return rain_floor_blend(overcast_snow_field, (xz - overcast_rain_floor_origin.xz) / overcast_rain_floor_size);
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

// A texture's dark is mostly its cracks and hollows, which a dusting fills first: how far the
// ground's brightness moves the snow's edge, and the brightness that leaves it where it is.
const float OVERCAST_SNOW_HOLLOWS = 1.2;
const float OVERCAST_SNOW_GROUND = 0.4;
// Centimetre grain only the edge feels, so it frays where it runs out.
const float OVERCAST_SNOW_FRAY = 0.5;

// Where the snow at world_pos lies, as (height, settled). Height is 0 at its edge, and over
// OVERCAST_SNOW_EDGE the ground is all under it; below 0 the ground shows. Settled is how far it
// has settled there, 0 to 1. (-1, 0) where none can lie. `ground` is the brightness of what it lies
// on (sRGB; OVERCAST_SNOW_GROUND if unknown).
vec2 overcast_snow_height(vec3 world_pos, vec3 world_normal, float ground) {
	if (overcast_snow_cover <= 0.0 || world_normal.y < 0.4) {
		return vec2(-1.0, 0.0);
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
		return vec2(-1.0, 0.0);
	}
	float n = overcast_vnoise(q * 0.45) * 0.6 + overcast_vnoise(q * 1.9) * 0.3
		+ overcast_vnoise(q * 8.0) * 0.1;
	float fray = (overcast_vnoise(q * 22.0) - 0.5) * OVERCAST_SNOW_FRAY;
	// Half settled, the high half of the noise is under snow; fully settled, all of it.
	float hollow = (OVERCAST_SNOW_GROUND - ground) * OVERCAST_SNOW_HOLLOWS;
	return vec2(s * 1.6 - 1.0 + n + fray + hollow, s);
}

const float OVERCAST_SNOW_EDGE = 0.3;

// How much of the surface is under snow, 0 to 1, from overcast_snow_height: a thin dusting while
// it settles, all of it once it lies deep.
float overcast_snow_amount(vec2 height) {
	float thin = mix(0.55, 1.0, smoothstep(0.2, 0.9, height.y));
	return clamp(height.x / OVERCAST_SNOW_EDGE, 0.0, 1.0) * thin;
}

// The brightness overcast_snow_height takes, of a base colour in the renderer's native space.
float overcast_snow_ground(vec3 albedo) {
	float b = dot(albedo, vec3(0.333));
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return b;
#else
	return pow(b, 1.0 / 2.2);
#endif
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
	float ground = overcast_snow_ground(albedo);
	float k = overcast_snow_amount(overcast_snow_height(world_pos, world_normal, ground));
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

// The snow's surface, in metres over the ground: a lip as deep as this at its edge, and lumps this
// high over its top, rising and falling over metres.
const float OVERCAST_SNOW_LIP = 0.04;
const float OVERCAST_SNOW_LUMPS = 0.15;
// How much of the sky's colour the snow in the shade takes past its brightness (1 = as it is), and
// how much of the sun's the snow in the sun keeps: a map's sun is often painted yellow.
const float OVERCAST_SNOW_SKY_TINT = 1.5;
const float OVERCAST_SNOW_SUN_TINT = 0.35;
// Snow lit by a sky over more snow takes more of it: the light goes back and forth between the
// snow and the cloud base. How much more, with all the ground around under it.
const float OVERCAST_SNOW_BOUNCE = 0.45;
// How much the lumps show in the shade: an overcast sky is still brightest around the sun.
const float OVERCAST_SNOW_SHADE_RELIEF = 0.3;
// How far round from the sun snow still takes some of it, as a cosine.
const float OVERCAST_SNOW_WRAP = 0.3;
// Snow brighter than this rolls off toward white instead of clipping.
const float OVERCAST_SNOW_KNEE = 0.75;
// The ground right beside the lip, in its shade.
const float OVERCAST_SNOW_FOOT = 0.85;
const vec3 OVERCAST_LUMA = vec3(0.2126, 0.7152, 0.0722);

// world_normal bent by a height field over the surface, from its screen derivatives (Mikkelsen's
// bump mapping). Call outside any branch.
vec3 overcast_snow_bump(vec3 world_pos, vec3 world_normal, float height) {
	vec3 dx = dFdx(world_pos);
	vec3 dy = dFdy(world_pos);
	vec3 r1 = cross(dy, world_normal);
	vec3 r2 = cross(world_normal, dx);
	float det = dot(dx, r1);
	vec3 grad = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	return normalize(abs(det) * world_normal - grad);
}

// For a shader that lights itself (a lightmap): `lit_srgb` is the surface's lit colour, `albedo`
// its base colour in the renderer's native space (linear, but sRGB on gl_compatibility), and
// `light` the light it was lit with (lit_srgb before any clamp, over the base); `outdoor` is how
// much of that light came from the sun and sky, not lamps (0 if unknown). normal_view and view are
// NORMAL and VIEW. The snow takes that light, but in the sky's colour where it lies in the shade
// and whiter in the sun, and its lumps and edges catch the sun from overcast_sun_dir. Its glints
// catch the eye's and are as bright as the light there.
void overcast_snow(inout vec3 lit_srgb, inout vec3 albedo, vec3 light, float outdoor,
		vec3 world_pos, vec3 world_normal, vec3 normal_view, vec3 view) {
	if (overcast_snow_cover <= 0.0) {
		return;
	}
	// Everything that takes derivatives first, before any branch that differs across a pixel quad.
	float footprint = overcast_snow_footprint(world_pos);
	vec2 h = overcast_snow_height(world_pos, world_normal, overcast_snow_ground(albedo));
	vec2 q = world_pos.xz;
	float lumps = overcast_vnoise(q * 0.7 + 2.9) * 0.7 + overcast_vnoise(q * 2.3 + 8.1) * 0.3;
	float surface = OVERCAST_SNOW_LIP * smoothstep(0.0, OVERCAST_SNOW_EDGE, h.x)
		+ OVERCAST_SNOW_LUMPS * lumps;
	vec3 bumped = overcast_snow_bump(world_pos, world_normal, surface);
	float k = overcast_snow_amount(h);
	// The ground just off the edge lies in the lip's shade.
	float foot = smoothstep(-0.15, 0.0, h.x) * (1.0 - k) * smoothstep(0.0, 0.3, h.y);
	lit_srgb *= mix(1.0, OVERCAST_SNOW_FOOT, foot);
	if (k <= 0.0) {
		return;
	}
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 white = overcast_snow_albedo(world_pos);
#else
	vec3 white = pow(overcast_snow_albedo(world_pos), vec3(2.2));
#endif
	// Only direct light glints, and lights the lumps: what a lightmap gives past the ambient's share.
	float direct = smoothstep(0.5, 1.2, dot(light, vec3(0.333)));
	vec3 open_light = light * clamp(outdoor, 0.0, 1.0);
	float bright = dot(open_light, OVERCAST_LUMA)
		* (1.0 + OVERCAST_SNOW_BOUNCE * overcast_snow_cover * (1.0 - direct));
	float sky_luma = dot(overcast_rain_sky, OVERCAST_LUMA);
	vec3 shade_tint = vec3(1.0);
	if (sky_luma > 0.01) {
		shade_tint = max(mix(vec3(1.0), overcast_rain_sky / sky_luma, OVERCAST_SNOW_SKY_TINT), vec3(0.0));
	}
	vec3 sun_tint = mix(vec3(1.0), open_light / max(bright, 1e-4), OVERCAST_SNOW_SUN_TINT);
	vec3 sun = normalize(overcast_sun_dir);
	// Wrapped: light scatters through snow, so a lump turned from a low sun is not black.
	float facing = clamp((dot(bumped, sun) + OVERCAST_SNOW_WRAP)
		/ max(dot(world_normal, sun) + OVERCAST_SNOW_WRAP, 0.1), 0.5, 1.5);
	float relief = mix(OVERCAST_SNOW_SHADE_RELIEF, 0.7, direct);
	vec3 on_snow = bright * mix(shade_tint, sun_tint, direct) * mix(1.0, facing, relief)
		+ (light - open_light);
	float glint = overcast_snow_glint(world_pos, k, footprint, normal_view, view, view);
	vec3 lit = overcast_snow_albedo(world_pos) * on_snow;
	// Rolled off toward white, not clipped, so snow in the sun still shows its lumps.
	float span = 1.0 - OVERCAST_SNOW_KNEE;
	vec3 rolled = OVERCAST_SNOW_KNEE + span * (1.0 - exp((OVERCAST_SNOW_KNEE - lit) / span));
	lit = mix(lit, rolled, step(OVERCAST_SNOW_KNEE, lit));
	lit_srgb = min(mix(lit_srgb, lit, k) + glint * direct * 0.04, vec3(1.0));
	albedo = mix(albedo, white, k);
}
#endif
