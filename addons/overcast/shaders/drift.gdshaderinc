#ifndef OVERCAST_DRIFT_GDSHADERINC
#define OVERCAST_DRIFT_GDSHADERINC
// Drifted snow's shape (OvercastSnowDrift.surface_mesh), for drift.gdshader or a game's own drift
// shader: call overcast_drift(VERTEX, NORMAL, UV, CUSTOM0, UV2.x) from vertex() and discard thinner
// than OVERCAST_DRIFT_THIN in fragment(), where the ground's own snow is.
#include "res://addons/overcast/shaders/snow.gdshaderinc"

const float OVERCAST_DRIFT_THIN = 0.02;

// The top of the snow on cell c, ground and all.
float overcast_drift_top(ivec2 c) {
	return texelFetch(overcast_rain_floor, c, 0).r + texelFetch(overcast_snow_field, c, 0).r;
}

// The normal of the snow's top round cell c: a neighbour on other ground (a wall, a drop) is taken
// as level with it.
vec3 overcast_drift_slope(ivec2 c, ivec2 res, vec2 cell) {
	float jump = 1.5 * max(cell.x, cell.y);
	float y = overcast_drift_top(c);
	float e[4];
	ivec2 dirs[4] = ivec2[](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	for (int i = 0; i < 4; i++) {
		float t = overcast_drift_top(clamp(c + dirs[i], ivec2(0), res - 1));
		e[i] = abs(t - y) <= jump ? t : y;
	}
	return normalize(vec3(-(e[0] - e[1]) / (2.0 * cell.x), 1.0, -(e[2] - e[3]) / (2.0 * cell.y)));
}

// Raises `vertex` by the drift on the four field cells about it: `uv` the first of them (in
// texels), `weights` its share of that one's snow, the next on x, on z, and on both (none of a cell
// on other ground). `side` is 0 on the drift's top, whose `normal` turns to the slope of the snow;
// 1 at the top of a drift's side and 2 at its foot, which stays on the ground, both keeping theirs.
// Returns how thick the drift is there. In the mesh's own space, which lies in the world (the
// drifts are top level).
float overcast_drift(inout vec3 vertex, inout vec3 normal, vec2 uv, vec4 weights, float side) {
	ivec2 res = textureSize(overcast_snow_field, 0);
	ivec2 c = ivec2(uv + 0.5);
	vec2 cell = overcast_rain_floor_size / vec2(res);
	float thick = 0.0;
	vec3 slope = vec3(0.0);
	for (int k = 0; k < 4; k++) {
		if (weights[k] > 0.0) {
			ivec2 at = clamp(c + ivec2(k % 2, k / 2), ivec2(0), res - 1);
			thick += weights[k] * max(texelFetch(overcast_snow_field, at, 0).r - OVERCAST_SNOW_LAYER, 0.0);
			if (side < 0.5) {
				slope += weights[k] * overcast_drift_slope(at, res, cell);
			}
		}
	}
	if (side < 1.5) {
		vertex.y += thick;
	}
	if (side < 0.5 && dot(slope, slope) > 0.0) {
		normal = normalize(slope);
	}
	return thick;
}
#endif
