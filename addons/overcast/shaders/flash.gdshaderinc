#ifndef OVERCAST_FLASH_GDSHADERINC
#define OVERCAST_FLASH_GDSHADERINC
// Lightning on a sky (OvercastSky.set_flash): lit from within, brightest toward flash_dir (world
// space). Black is no flash. Any sky can take it, a cubemap one included.
uniform vec3 flash_color = vec3(0.0);
uniform vec3 flash_dir = vec3(0.0, 1.0, 0.0);

// Clouds have something to light and open sky only a glow, so the flash multiplies, then adds.
vec3 overcast_flash(vec3 col, vec3 eye_dir) {
	if (flash_color == vec3(0.0)) {
		return col;
	}
	float toward = max(dot(eye_dir, normalize(flash_dir)), 0.0);
	col *= vec3(1.0) + flash_color * (1.0 + 3.0 * pow(toward, 3.0));
	return col + flash_color * (0.3 + 0.9 * pow(toward, 4.0));
}
#endif
