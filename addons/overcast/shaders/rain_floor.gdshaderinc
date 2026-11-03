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
#endif
