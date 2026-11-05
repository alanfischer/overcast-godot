// Snowflakes, placed by falling.gdshaderinc: slow, swaying, each a soft disc facing the camera.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

// The flakes in the light on them, already in the renderer's output space (OvercastWeather).
uniform vec3 color = vec3(0.95, 0.96, 1.0);
uniform float opacity = 0.8;
uniform float flash = 0.0;
uniform vec3 velocity = vec3(0.0, -1.0, 0.0);
// Metres each flake wanders either side of its line, and how fast (radians per second).
uniform float sway = 0.35;
uniform float sway_rate = 1.3;
uniform float flake_size = 0.025;
#include "res://addons/overcast/shaders/falling.gdshaderinc"

varying float fade;

void vertex() {
	vec4 h = overcast_fall_hash(uint(INSTANCE_ID) + 1u);
	vec4 g = overcast_fall_hash(uint(INSTANCE_ID) + 0x9e3779b9u);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 p = overcast_fall_place(h.xyz, velocity * mix(0.7, 1.3, h.w) * TIME, cam);
	float t = TIME * sway_rate * mix(0.6, 1.4, g.x);
	p.xz += sway * mix(0.4, 1.0, g.y) * vec2(sin(t + g.z * TAU), cos(t * 0.73 + g.w * TAU));
	fade = overcast_fall_fade(p, cam, p);
	if (fade <= 0.0) {
		VERTEX = vec3(0.0);
	} else {
		vec3 view = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
		vec2 w = overcast_fall_pixel(flake_size * mix(0.6, 1.4, g.y), length(view), PROJECTION_MATRIX,
			VIEWPORT_SIZE);
		// A disc's coverage goes as its area.
		fade *= w.y * w.y;
		VERTEX = view + vec3(VERTEX.xy * w.x, 0.0);
	}
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = color;
	ALPHA = min(opacity * (1.0 + flash) * fade * smoothstep(1.0, 0.2, r), 1.0);
}
