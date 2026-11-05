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

// Wind-driven rain comes down a slanted line: it is caught by anything upwind that stands above
// that line, as though all the floor holds were solid down to the ground (a roof walled in), so
// rain never reaches in under a roof. Tested at RAIN_SLANT_TAPS points up to RAIN_SLANT_UP metres
// up the line, and never more than RAIN_SLANT_REACH sideways; where the taps fall wanders over the
// ground, so the edge of a wind shadow is ragged, as a drift's is, not stepped.
const int RAIN_SLANT_TAPS = 3;
const float RAIN_SLANT_UP = 5.0;
const float RAIN_SLANT_REACH = 6.0;
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

// Tap `i` up the slanted line rain came down to reach p.
vec3 rain_slant_point(vec3 p, int i) {
	float up = min(RAIN_SLANT_UP, RAIN_SLANT_REACH / max(length(overcast_rain_slant), 1e-4));
	float s = up * (float(i) + 0.15 + 0.7 * overcast_vnoise(p.xz * 1.3)) / float(RAIN_SLANT_TAPS);
	return p + vec3(-overcast_rain_slant.x * s, s, -overcast_rain_slant.y * s);
}

// Whether rain falling past world point p, slanted by the wind, has not yet been caught. Up the
// slant, off the floor counts as open: the slant only adds what is there to catch it.
bool rain_falls_at(vec3 p) {
	if (!rain_open_above(p)) {
		return false;
	}
	if (overcast_has_rain_floor && overcast_rain_slant != vec2(0.0)) {
		for (int i = 0; i < RAIN_SLANT_TAPS; i++) {
			vec3 q = rain_slant_point(p, i);
			vec2 uv = rain_floor_uv(q);
			if (rain_floor_covers(uv) && q.y <= textureLod(overcast_rain_floor, uv, 0.0).r) {
				return false;
			}
		}
	}
	return true;
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

// 1 where rain reaches world point p, 0 under cover, the wind's slant included. Everywhere, with
// no floor.
float rain_reaches(vec3 p) {
	if (!overcast_has_rain_floor) {
		return 1.0;
	}
	float open = rain_open_blend(p, overcast_rain_beyond_floor ? 1.0 : 0.0);
	if (open > 0.0 && overcast_rain_slant != vec2(0.0)) {
		for (int i = 0; i < RAIN_SLANT_TAPS; i++) {
			open *= rain_open_blend(rain_slant_point(p, i), 1.0);
		}
	}
	return open;
}
#endif
