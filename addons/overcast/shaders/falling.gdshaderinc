#ifndef OVERCAST_FALLING_GDSHADERINC
#define OVERCAST_FALLING_GDSHADERINC
// What raindrops and snowflakes share: a MultiMesh of quads with no transforms, each instance
// hashing its own place in a box around the camera that wraps as the camera moves, so they stay
// put in the world and every one of them is in view, at whatever height the camera is. One below
// the rain floor (a roof, the ground it would already have hit) is not drawn, which keeps them out
// of the rooms under a roof.
#include "res://addons/overcast/shaders/rain_floor.gdshaderinc"

uniform vec3 box = vec3(36.0, 24.0, 36.0);
// How far the wind has carried them all, wrapped into the box (OvercastWeather integrates it, so a
// gust that changes the wind moves them on from where they are).
uniform vec3 drift = vec3(0.0);
// Drawn over the rain haze (rain_haze.gdshader), which would haze one by the distance to the wall
// behind it; this hazes it by its own.
uniform float haze_density = 0.0;

vec4 overcast_fall_hash(uint n) {
	uvec4 v = uvec4(n) * uvec4(1597334677u, 3812015801u, 2798796415u, 1979697957u);
	v = (v.yzwx ^ (v >> 15u)) * uvec4(2246822519u, 3266489917u, 668265263u, 374761393u);
	v ^= v >> 13u;
	return vec4(v) / 4294967295.0;
}

// Where `start` (a point in the unit box) has fallen to after falling `fallen` metres and drifting
// with the wind, wrapped into the box around `cam`.
vec3 overcast_fall_place(vec3 start, float fallen, vec3 cam) {
	vec3 p = start * box + drift - vec3(0.0, fallen, 0.0);
	return cam + mod(p - cam + box * 0.5, box) - box * 0.5;
}

// How much of one at `p` to draw: faded out toward the faces of the box, where they wrap, right at
// the lens, by the haze, and not at all below the rain floor (tested at `floor_p`).
float overcast_fall_fade(vec3 p, vec3 cam, vec3 floor_p) {
	vec3 rel = p - cam;
	float dist = length(rel);
	float fade = smoothstep(box.x * 0.5, box.x * 0.3, length(rel.xz))
		* smoothstep(box.y * 0.5, box.y * 0.35, abs(rel.y))
		* smoothstep(0.2, 1.0, dist)
		* exp(-haze_density * dist);
	if (fade > 0.0 && !rain_falls_at(floor_p)) {
		fade = 0.0;
	}
	return fade;
}

// `world_size` at distance `dist`, widened to at least a pixel, and the alpha that keeps what it
// shows the same: one thinner than a pixel shimmers.
vec2 overcast_fall_pixel(float world_size, float dist, mat4 projection, vec2 viewport) {
	float pixel = dist * 2.0 / (projection[1][1] * viewport.y);
	float w = max(world_size, pixel);
	return vec2(w, world_size / w);
}
#endif
