// Dust the wind lifts off dry ground, placed by falling.gdshaderinc: motes carried along with it,
// eddying, thickest near the ground and streaked by their speed.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

// The dust in the light on it, already in the renderer's output space (OvercastWeather).
uniform vec3 color = vec3(0.6, 0.53, 0.43);
uniform float opacity = 0.7;
uniform float flash = 0.0;
// How much is up, 0 to 1: a mote shows once it passes the mote's own share.
uniform float amount = 0.0;
// Horizontal, m/s: what streaks them (`drift` is what carries them).
uniform vec3 wind = vec3(0.0);
uniform float mote_size = 0.02;
// Metres each mote eddies about its line, and how fast (radians per second).
uniform float eddy = 0.6;
uniform float eddy_rate = 2.0;
// Seconds a mote's motion is smeared over: how long a streak a fast one draws.
uniform float smear = 0.015;
// It thins to 1/e every this many metres over the ground.
uniform float lift = 2.5;
// The share of them that are wisps: soft puffs of fine dust metres across, low to the ground.
uniform float wisps = 0.15;
uniform float wisp_opacity = 0.3;
#include "res://addons/overcast/shaders/falling.gdshaderinc"

varying float fade;
varying float wisp;

void vertex() {
	vec4 h = overcast_fall_hash(uint(INSTANCE_ID) + 1u);
	vec4 g = overcast_fall_hash(uint(INSTANCE_ID) + 0x9e3779b9u);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	wisp = step(fract(g.z * 7.0), wisps);
	vec3 p = overcast_fall_place(h.xyz, 0.0, cam);
	float t = TIME * eddy_rate * mix(0.6, 1.4, g.x) * mix(1.0, 0.3, wisp);
	vec3 swirl = vec3(sin(t + g.z * TAU), 0.5 * sin(t * 1.31 + g.y * TAU), cos(t * 0.77 + g.w * TAU));
	p += eddy * mix(0.3, 1.0, g.y) * mix(1.0, 3.0, wisp) * swirl;
	fade = overcast_fall_fade(p, cam, p) * smoothstep(g.w, g.w + 0.15, amount * 1.15);
	if (fade > 0.0 && overcast_has_rain_floor) {
		vec2 uv = rain_floor_uv(p);
		if (rain_floor_covers(uv)) {
			float over = max(p.y - textureLod(overcast_rain_floor, uv, 0.0).r, 0.0);
			fade *= exp(-over / (lift * mix(1.0, 0.5, wisp)));
		}
	}
	if (fade <= 0.0) {
		VERTEX = vec3(0.0);
	} else {
		vec3 rel = p - cam;
		float dist = length(rel);
		float speed = length(wind);
		vec3 axis = speed > 0.01 ? wind / speed : vec3(1.0, 0.0, 0.0);
		vec3 side = normalize(cross(axis, rel + vec3(1e-4)));
		vec3 up = normalize(cross(side, axis));
		vec3 world;
		if (wisp > 0.0) {
			// Facing the eye as far as it can while drawn out along the wind.
			float size = mix(1.5, 4.0, g.x);
			fade *= wisp_opacity / opacity * smoothstep(1.0, 4.0, dist);
			world = p + side * VERTEX.x * size + axis * VERTEX.y * size * mix(1.5, 3.0, h.w);
		} else {
			float size = mote_size * mix(0.5, 2.0, g.x * g.x);
			vec2 w = overcast_fall_pixel(size, dist, PROJECTION_MATRIX, VIEWPORT_SIZE);
			fade *= w.y * smoothstep(0.5, 2.0, dist);
			float len = max(w.x, speed * smear * mix(0.7, 1.3, h.w));
			world = p + side * VERTEX.x * w.x + axis * VERTEX.y * len;
		}
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	}
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float shape;
	if (wisp > 0.0) {
		shape = exp(-3.0 * dot(q, q));
	} else {
		shape = (1.0 - abs(q.x)) * smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.7, UV.y);
	}
	ALBEDO = color;
	ALPHA = min(opacity * (1.0 + flash) * fade * shape, 1.0);
}
