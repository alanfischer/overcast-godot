#ifndef OVERCAST_DRIFT_GDSHADERINC
#define OVERCAST_DRIFT_GDSHADERINC
// Drifted snow's shape (OvercastSnowDrift.surface_mesh), for drift.gdshader or a game's own drift
// shader: call overcast_drift from vertex() and discard thinner than OVERCAST_DRIFT_THIN in
// fragment(), where the ground's own snow is.
#include "res://addons/overcast/shaders/snow.gdshaderinc"

const float OVERCAST_DRIFT_THIN = 0.02;

// The top of the snow on cell c, ground and all.
float overcast_drift_top(ivec2 c) {
	return texelFetch(overcast_rain_floor, c, 0).r + texelFetch(overcast_snow_field, c, 0).r;
}

// Raises `vertex` by the snow its field cell (`uv`, in texels) holds over the even layer, and turns
// `normal` to the slope of the snow's top round that cell; a neighbour on other ground (a wall, a
// drop) is taken as level with it. Returns how thick the drift is there. In the mesh's own space,
// which lies in the world (the drifts are top level).
float overcast_drift(inout vec3 vertex, inout vec3 normal, vec2 uv) {
	ivec2 res = textureSize(overcast_snow_field, 0);
	ivec2 c = ivec2(uv);
	float thick = max(texelFetch(overcast_snow_field, c, 0).r - OVERCAST_SNOW_LAYER, 0.0);
	vertex.y += thick;
	vec2 cell = overcast_rain_floor_size / vec2(res);
	float jump = 1.5 * max(cell.x, cell.y);
	float y = overcast_drift_top(c);
	float e[4];
	ivec2 dirs[4] = ivec2[](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	for (int i = 0; i < 4; i++) {
		float t = overcast_drift_top(clamp(c + dirs[i], ivec2(0), res - 1));
		e[i] = abs(t - y) <= jump ? t : y;
	}
	normal = normalize(vec3(-(e[0] - e[1]) / (2.0 * cell.x), 1.0, -(e[2] - e[3]) / (2.0 * cell.y)));
	return thick;
}
#endif
