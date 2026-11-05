// Raindrop streaks, placed by falling.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

// The drops as seen: their colour in the light on them (the sky's, darkened at night and lit by
// lightning), already in the renderer's output space. OvercastWeather works it out once a frame.
uniform vec3 color = vec3(0.75, 0.8, 0.9);
uniform float opacity = 0.4;
// Lightning lights the drops against a world it lights just as much; they stand out by thickening.
uniform float flash = 0.0;
uniform vec3 velocity = vec3(0.0, -9.0, 0.0);
uniform float streak_length = 0.4;
uniform float width = 0.006;
#include "res://addons/overcast/shaders/falling.gdshaderinc"

varying float fade;

void vertex() {
	vec4 h = overcast_fall_hash(uint(INSTANCE_ID) + 1u);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 vel = velocity * mix(0.85, 1.15, h.w);
	vec3 p = overcast_fall_place(h.xyz, vel * TIME, cam);
	fade = overcast_fall_fade(p, cam, p - vec3(0.0, streak_length * 0.5, 0.0));
	if (fade <= 0.0) {
		VERTEX = vec3(0.0);  // nothing to see: a zero-area quad, which draws no pixels at all
	} else {
		vec3 rel = p - cam;
		vec2 w = overcast_fall_pixel(width, length(rel), PROJECTION_MATRIX, VIEWPORT_SIZE);
		fade *= w.y;
		vec3 axis = normalize(vel);
		vec3 side = normalize(cross(axis, rel + vec3(1e-4)));
		vec3 world = p + side * VERTEX.x * w.x + axis * VERTEX.y * streak_length;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	}
}

void fragment() {
	// Brightest toward the head, tapering off to the tail and soft across.
	float along = UV.y;
	float profile = smoothstep(0.0, 0.25, along) * smoothstep(1.0, 0.6, along);
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = color;
	ALPHA = min(opacity * (1.0 + flash) * fade * profile * mix(0.5, 1.0, across), 1.0);
}
