#ifndef OVERCAST_RAIN_FLOOR_GDSHADERINC
#define OVERCAST_RAIN_FLOOR_GDSHADERINC
// Where rain stops: per column, the height rain falls to before something catches it (a roof, the
// ground), in a texture whose min-X/min-Z corner sits at rain_floor_origin. OvercastRainFloor bakes
// one; OvercastWeather hands it to every shader that includes this.
uniform bool has_floor = false;  // without one, rain falls everywhere
uniform sampler2D rain_floor : filter_nearest;
uniform vec3 rain_floor_origin;
uniform vec2 rain_floor_size = vec2(1.0);

// Where world point p falls on the rain floor.
vec2 rain_floor_uv(vec3 p) {
	return (p.xz - rain_floor_origin.xz) / rain_floor_size;
}

// Off the floor no rain falls.
bool rain_floor_covers(vec2 uv) {
	return uv.x >= 0.0 && uv.y >= 0.0 && uv.x < 1.0 && uv.y < 1.0;
}

// Whether rain falling past world point p has not yet been caught: everywhere with no floor,
// nowhere off it.
bool rain_falls_at(vec3 p) {
	if (!has_floor) {
		return true;
	}
	vec2 uv = rain_floor_uv(p);
	return rain_floor_covers(uv) && p.y > textureLod(rain_floor, uv, 0.0).r;
}
#endif
