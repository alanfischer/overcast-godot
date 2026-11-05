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

// Where world point p falls on the rain floor.
vec2 rain_floor_uv(vec3 p) {
	return (p.xz - overcast_rain_floor_origin.xz) / overcast_rain_floor_size;
}

bool rain_floor_covers(vec2 uv) {
	return uv.x >= 0.0 && uv.y >= 0.0 && uv.x < 1.0 && uv.y < 1.0;
}

// Whether rain falling past world point p has not yet been caught: everywhere with no floor, and
// off it only with overcast_rain_beyond_floor.
bool rain_falls_at(vec3 p) {
	if (!overcast_has_rain_floor) {
		return true;
	}
	vec2 uv = rain_floor_uv(p);
	if (!rain_floor_covers(uv)) {
		return overcast_rain_beyond_floor;
	}
	return p.y > textureLod(overcast_rain_floor, uv, 0.0).r;
}

// 1 where rain reaches world point p, 0 under cover. The floor's four cells around p are blended,
// so a roof's shadow on the ground is not drawn as a staircase. Everywhere, with no floor.
float rain_reaches(vec3 p) {
	if (!overcast_has_rain_floor) {
		return 1.0;
	}
	vec2 uv = rain_floor_uv(p);
	if (!rain_floor_covers(uv)) {
		return overcast_rain_beyond_floor ? 1.0 : 0.0;
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
#endif
