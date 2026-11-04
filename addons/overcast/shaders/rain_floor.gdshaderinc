#ifndef OVERCAST_RAIN_FLOOR_GDSHADERINC
#define OVERCAST_RAIN_FLOOR_GDSHADERINC
// Where rain stops: per column, the height rain falls to before something catches it (a roof, the
// ground), in a texture whose min-X/min-Z corner sits at overcast_rain_floor_origin. Globals that
// OvercastWeather sets (OvercastGlobals).
global uniform bool overcast_has_rain_floor;  // without one, rain falls everywhere
global uniform sampler2D overcast_rain_floor : filter_nearest;
global uniform vec3 overcast_rain_floor_origin;
global uniform vec2 overcast_rain_floor_size;
global uniform float overcast_rain_top;  // no rain above this

// Where world point p falls on the rain floor.
vec2 rain_floor_uv(vec3 p) {
	return (p.xz - overcast_rain_floor_origin.xz) / overcast_rain_floor_size;
}

// Off the floor no rain falls.
bool rain_floor_covers(vec2 uv) {
	return uv.x >= 0.0 && uv.y >= 0.0 && uv.x < 1.0 && uv.y < 1.0;
}

// Whether rain falling past world point p has not yet been caught: everywhere with no floor,
// nowhere off it.
bool rain_falls_at(vec3 p) {
	if (!overcast_has_rain_floor) {
		return true;
	}
	vec2 uv = rain_floor_uv(p);
	return rain_floor_covers(uv) && p.y > textureLod(overcast_rain_floor, uv, 0.0).r;
}
#endif
