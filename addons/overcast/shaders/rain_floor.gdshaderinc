#ifndef OVERCAST_RAIN_FLOOR_GDSHADERINC
#define OVERCAST_RAIN_FLOOR_GDSHADERINC
// Where rain stops: per column, the height rain falls to before something catches it (a roof, the
// ground), in a texture whose min-X/min-Z corner sits at overcast_rain_floor_origin. Globals that
// OvercastWeather sets (OvercastGlobals).
global uniform bool overcast_has_rain_floor;  // without one, rain falls everywhere
global uniform bool overcast_rain_beyond_floor;  // whether it falls off the floor's edges
global uniform sampler2D overcast_rain_floor : filter_nearest;
global uniform vec3 overcast_rain_floor_origin;
global uniform vec2 overcast_rain_floor_size;
global uniform float overcast_rain_top;  // no rain above this
// Metres the wind carries rain sideways per metre it falls (OvercastWeather, from its steady wind).
global uniform vec2 overcast_rain_slant;

// The open air under what catches rain, per column: x the underside of the roof, y the ground under
// it; none where they are equal (OvercastRainFloor.under). Unset, there is none anywhere, and all
// that is under the floor is solid.
global uniform sampler2D overcast_rain_under : filter_nearest;

// Wind-driven rain comes down a slanted line. It reaches a point if, walking up that line toward
// the wind, it meets nothing solid: under a roof it may blow, in past its edge, but not down
// through it. Walked in RAIN_SLANT_TAPS steps up to RAIN_SLANT_UP metres up, and never more than
// RAIN_SLANT_REACH sideways; where the steps fall wanders over the ground, so the edge of a wind
// shadow is ragged, as a drift's is, not stepped. Under cover, it thins to 1/e for every
// RAIN_SHELTER_DEPTH metres it had to blow in from the edge, and further in than the walk reaches
// none comes at all.
// Through an open shelter and out the other side it loses nothing: only the roof stops it.
// The steps are closer than a rain floor cell (at its default 0.5 m), so a wall one cell thick is
// not stepped over.
const int RAIN_SLANT_TAPS = 7;
const float RAIN_SLANT_UP = 5.0;
const float RAIN_SLANT_REACH = 3.0;
const float RAIN_SHELTER_DEPTH = 3.0;
#include "res://addons/overcast/shaders/noise.gdshaderinc"

// Where world point p falls on the rain floor.
vec2 rain_floor_uv(vec3 p) {
	return (p.xz - overcast_rain_floor_origin.xz) / overcast_rain_floor_size;
}

bool rain_floor_covers(vec2 uv) {
	return uv.x >= 0.0 && uv.y >= 0.0 && uv.x < 1.0 && uv.y < 1.0;
}

// Whether nothing is straight above world point p to catch rain: everywhere with no floor, and off
// it only with overcast_rain_beyond_floor. Wind aside: for the haze's march, which takes many.
bool rain_open_above(vec3 p) {
	if (!overcast_has_rain_floor) {
		return true;
	}
	vec2 uv = rain_floor_uv(p);
	if (!rain_floor_covers(uv)) {
		return overcast_rain_beyond_floor;
	}
	return p.y > textureLod(overcast_rain_floor, uv, 0.0).r;
}

// Where q is for rain slanting through it: in the open (over whatever catches rain there), in the
// air under cover, or in something solid. `roofed`: whether q's column has air under cover at all.
const int RAIN_OPEN = 0;
const int RAIN_SHELTERED = 1;
const int RAIN_SOLID = 2;
int rain_place(vec3 q, out bool roofed) {
	roofed = false;
	vec2 uv = rain_floor_uv(q);
	if (!rain_floor_covers(uv)) {
		return RAIN_OPEN;  // the slant only adds what is there to catch it
	}
	vec2 gap = textureLod(overcast_rain_under, uv, 0.0).rg;
	roofed = gap.x > gap.y;
	if (q.y > textureLod(overcast_rain_floor, uv, 0.0).r) {
		return RAIN_OPEN;
	}
	return q.y > gap.y && q.y < gap.x ? RAIN_SHELTERED : RAIN_SOLID;
}

// Whether the slanted line from `a` (in the air under cover) to `b` (in the open) came out past the
// roof's edge rather than up through the roof: looked at between them, where it would be in the
// roof if it went through it.
bool rain_slant_exits(vec3 a, vec3 b) {
	for (int i = 1; i <= 2; i++) {
		bool roofed;
		int at = rain_place(mix(a, b, float(i) / 3.0), roofed);
		if (at == RAIN_SOLID || (at == RAIN_OPEN && roofed)) {
			return false;
		}
	}
	return true;
}

// How much of the rain slanting in on the wind reaches p, 0 to 1, by the walk described above.
float rain_slant_reach(vec3 p) {
	bool roofed;
	int was = rain_place(p, roofed);
	if (was == RAIN_SOLID) {
		return 0.0;
	}
	float len = length(overcast_rain_slant);
	float up = min(RAIN_SLANT_UP, RAIN_SLANT_REACH / max(len, 1e-4));
	float wander = 0.15 + 0.7 * overcast_vnoise(p.xz * 1.3);
	float under = 0.0;  // metres sideways it blew in under cover to reach p
	bool inside = was == RAIN_SHELTERED;  // p is under cover, and the walk has not come out yet
	vec3 last = p;
	float last_s = 0.0;
	for (int i = 0; i < RAIN_SLANT_TAPS; i++) {
		float s = up * (float(i) + wander) / float(RAIN_SLANT_TAPS);
		vec3 q = p + vec3(-overcast_rain_slant.x * s, s, -overcast_rain_slant.y * s);
		int now = rain_place(q, roofed);
		if (now == RAIN_SOLID) {
			return 0.0;
		}
		if (was == RAIN_SHELTERED && now == RAIN_OPEN && (roofed || !rain_slant_exits(last, q))) {
			return 0.0;  // down through the roof
		}
		if (inside) {
			under += (s - last_s) * len;
			inside = now == RAIN_SHELTERED;
		}
		was = now;
		last = q;
		last_s = s;
	}
	if (inside) {
		return 0.0;  // under cover as far as the wind carries it: none comes this far in
	}
	return exp(-under / RAIN_SHELTER_DEPTH);
}

// How much of the rain reaches world point p in the air, 0 to 1: everywhere with no floor, off it
// only with overcast_rain_beyond_floor, else straight down or, in wind, along its slant.
float rain_reaches_air(vec3 p) {
	if (!overcast_has_rain_floor) {
		return 1.0;
	}
	vec2 uv = rain_floor_uv(p);
	if (!rain_floor_covers(uv)) {
		return overcast_rain_beyond_floor ? 1.0 : 0.0;
	}
	if (overcast_rain_slant == vec2(0.0)) {
		return p.y > textureLod(overcast_rain_floor, uv, 0.0).r ? 1.0 : 0.0;
	}
	return rain_slant_reach(p);
}

// Whether rain falling past world point p, slanted by the wind, has not yet been caught.
bool rain_falls_at(vec3 p) {
	return rain_reaches_air(p) > 0.0;
}

// 1 where nothing straight above world point p catches rain, 0 under cover; `off` off the floor.
// The floor's four cells around p are blended, so a roof's shadow on the ground is not drawn as a
// staircase.
float rain_open_blend(vec3 p, float off) {
	vec2 uv = rain_floor_uv(p);
	if (!rain_floor_covers(uv)) {
		return off;
	}
	ivec2 res = textureSize(overcast_rain_floor, 0);
	vec2 texel = uv * vec2(res) - 0.5;
	ivec2 cell = ivec2(floor(texel));
	vec2 f = fract(texel);
	vec4 reach;
	for (int i = 0; i < 4; i++) {
		ivec2 c = clamp(cell + ivec2(i % 2, i / 2), ivec2(0), res - 1);
		// All of it at the height rain stops, none a quarter metre below.
		reach[i] = clamp((p.y - texelFetch(overcast_rain_floor, c, 0).r) * 4.0 + 1.0, 0.0, 1.0);
	}
	return mix(mix(reach.x, reach.y, f.x), mix(reach.z, reach.w, f.x), f.y);
}

// 1 where rain reaches world point p on a surface, 0 under cover; in wind, along its slant, so it
// blows in under eaves and open shelters and leaves a dry lee. Everywhere, with no floor.
float rain_reaches(vec3 p) {
	if (!overcast_has_rain_floor) {
		return 1.0;
	}
	if (overcast_rain_slant == vec2(0.0)) {
		return rain_open_blend(p, overcast_rain_beyond_floor ? 1.0 : 0.0);
	}
	vec2 uv = rain_floor_uv(p);
	if (!rain_floor_covers(uv)) {
		return overcast_rain_beyond_floor ? 1.0 : 0.0;
	}
	return rain_slant_reach(p);
}
#endif
