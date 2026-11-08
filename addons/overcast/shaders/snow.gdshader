// Snowflakes, placed by falling.gdshaderinc: slow, swaying, each a soft disc facing the camera.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

// The flakes in the light on them, already in the renderer's output space (OvercastWeather).
uniform vec3 color = vec3(0.95, 0.96, 1.0);
uniform float opacity = 0.8;
uniform float flash = 0.0;
// Metres each flake wanders either side of its line, and how fast (radians per second).
uniform float sway = 0.35;
uniform float sway_rate = 1.3;
uniform float flake_size = 0.025;
// The darkest flake, as a share of `color`: a flake turned edge-on, or against a bright sky,
// reads grey.
uniform float dim = 0.45;
#include "res://addons/overcast/shaders/falling.gdshaderinc"

varying float fade;
varying float shade;
// How out of focus: a flake right by the eye is a big soft blur, not a sharp dot.
varying float blur;

void vertex() {
	vec4 h = overcast_fall_hash(uint(INSTANCE_ID) + 1u);
	vec4 g = overcast_fall_hash(uint(INSTANCE_ID) + 0x9e3779b9u);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 p = overcast_fall_place(h.xyz, fallen * mix(0.7, 1.3, h.w), cam);
	float t = TIME * sway_rate * mix(0.6, 1.4, g.x);
	p.xz += sway * mix(0.4, 1.0, g.y) * vec2(sin(t + g.z * TAU), cos(t * 0.73 + g.w * TAU));
	fade = overcast_fall_fade(p, cam, p);
	float k = fract(g.z * 13.0);
	// Tumbling, a flake catches the light and loses it.
	float tumble = 0.5 + 0.5 * sin(TIME * mix(2.0, 7.0, h.w) + g.x * TAU);
	shade = mix(dim, 1.0, k * k) * mix(0.75, 1.0, tumble);
	blur = 0.0;
	if (fade <= 0.0) {
		VERTEX = vec3(0.0);
	} else {
		vec3 view = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
		float dist = length(view);
		blur = 1.0 - smoothstep(0.5, 2.5, dist);
		// Most flakes are small; a few are clumps several times their size.
		float size = flake_size * mix(0.5, 2.2, g.y * g.y * g.y) * (1.0 + 2.5 * blur);
		vec2 w = overcast_fall_pixel(size, dist, PROJECTION_MATRIX, VIEWPORT_SIZE);
		// A disc's coverage goes as its area; a blurred one spreads the same light wider.
		fade *= w.y * w.y / mix(1.0, 4.0, blur);
		VERTEX = view + vec3(VERTEX.xy * w.x, 0.0);
	}
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = color * mix(shade, 1.0, blur);
	ALPHA = min(opacity * (1.0 + flash) * fade * smoothstep(1.0, mix(0.2, 0.0, blur), r), 1.0);
}
