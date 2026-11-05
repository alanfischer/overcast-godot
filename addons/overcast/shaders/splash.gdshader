// Where the rain lands: each instance a splash, a ring spreading on the ground under droplets
// thrown up and falling back, then lands again somewhere else. Its mesh is two quads: one upright
// for the droplets, one flat (UV2.x 1) for the ring. Placed on the rain floor, so splashes are on roofs and the
// open ground and never under cover, in a box around the camera that wraps as it moves (box.xz;
// falling.gdshaderinc), fixed in the world while each one lasts.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

// As the drops': lit, in the renderer's output space (OvercastWeather).
uniform vec3 color = vec3(0.75, 0.8, 0.9);
uniform float opacity = 0.6;
uniform float flash = 0.0;
// Seconds between one instance's splashes, and how long each lasts.
uniform float period = 0.6;
uniform float life = 0.22;
// Metres across a splash's droplets at their widest, how high they fly, and how wide its ring
// spreads.
uniform float spread = 0.22;
uniform float height = 0.11;
uniform float ring = 0.3;
#include "res://addons/overcast/shaders/falling.gdshaderinc"
#include "res://addons/overcast/shaders/wet.gdshaderinc"

const int DROPLETS = 7;

varying float fade;
varying float age;
varying float seed;
// Standing water there: only that rings.
varying float pool;

void vertex() {
	uint id = uint(INSTANCE_ID);
	vec4 h = overcast_fall_hash(id + 3u);
	float t = TIME / period + h.w;
	float cycle = floor(t);
	age = fract(t) * period / life;
	vec4 r = overcast_fall_hash(id * 7919u + uint(int(cycle)) * 104729u + 11u);
	seed = r.z;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec2 xz = cam.xz + mod(r.xy * box.xz - cam.xz + box.xz * 0.5, box.xz) - box.xz * 0.5;
	fade = 0.0;
	pool = 0.0;
	vec3 p = vec3(xz.x, 0.0, xz.y);
	if (age < 1.0 && overcast_has_rain_floor) {
		vec2 uv = rain_floor_uv(p);
		if (rain_floor_covers(uv)) {
			p.y = textureLod(overcast_rain_floor, uv, 0.0).r;
			pool = overcast_wet_amount(p, vec3(0.0, 1.0, 0.0)).y;
			vec3 rel = p - cam;
			float dist = length(rel);
			fade = smoothstep(box.x * 0.5, box.x * 0.3, length(rel.xz)) * exp(-haze_density * dist)
				* step(p.y, overcast_rain_top) * mix(0.6, 1.0, r.w)
				* rain_reaches_air(p + vec3(0.0, 0.05, 0.0));
		}
	}
	if (fade <= 0.0) {
		VERTEX = vec3(0.0);
	} else {
		float s = mix(0.7, 1.3, r.w);
		vec3 world;
		if (UV2.x > 0.5) {
			// Nothing to ring on dry ground: a zero-area quad.
			world = pool <= 0.0 ? p : p + vec3(VERTEX.x, 0.0, VERTEX.z) * ring * s + vec3(0.0, 0.01, 0.0);
		} else {
			// Upright, turned to face the camera about the vertical.
			vec3 to_cam = cam - p;
			vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam + vec3(1e-4, 0.0, 0.0)));
			world = p + side * VERTEX.x * spread * s + vec3(0.0, (VERTEX.y + 0.5) * height * s + 0.005, 0.0);
		}
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	}
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = 0.0;
	if (UV2.x > 0.5) {
		// The ring: spreading fast, then slowing, thinning and fading as it goes.
		float rad = sqrt(age) * 0.9;
		float d = abs(length(q) - rad);
		a = smoothstep(0.06 + 0.06 * age, 0.0, d) * (1.0 - age) * 0.8 * pool;
		ALBEDO = color;
		ALPHA = min(a, 1.0) * opacity * (1.0 + flash) * fade;
	}
	// x across, -1 to 1; y up from the ground, 0 to 1.
	q.y = 1.0 - UV.y;
	// Droplets thrown up, rising and falling back.
	for (int i = 0; i < DROPLETS; i++) {
		float fi = float(i);
		float k1 = fract(seed * 13.7 + fi * 0.618);
		float k2 = fract(seed * 7.3 + fi * 0.382);
		float out_x = cos(k1 * TAU) * mix(0.4, 1.0, k2);
		float up = mix(0.45, 1.0, k1 * k2);
		vec2 c = vec2(out_x * age, up * 4.0 * age * (1.0 - age));
		float rad = mix(0.09, 0.045, age);
		a += smoothstep(rad, rad * 0.3, length((q - c) * vec2(1.0, height / spread * 2.0)))
			* step(0.0, c.y);
	}
	if (UV2.x <= 0.5) {
		ALBEDO = color;
		ALPHA = min(a, 1.0) * opacity * (1.0 + flash) * fade * (1.0 - age * age);
	}
}
