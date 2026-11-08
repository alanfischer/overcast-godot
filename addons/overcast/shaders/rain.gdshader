// Raindrop streaks, placed by falling.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

// The drops as seen: their colour in the light on them (the sky's, darkened at night and lit by
// lightning), already in the renderer's output space. OvercastWeather works it out once a frame.
uniform vec3 color = vec3(0.75, 0.8, 0.9);
uniform float opacity = 0.4;
// Lightning lights the drops against a world it lights just as much; they stand out by thickening.
uniform float flash = 0.0;
uniform float fall_speed = 9.0;
// Horizontal, m/s: what slants the streaks (`drift` is what carries them).
uniform vec3 wind = vec3(0.0);
uniform float streak_length = 0.4;
uniform float width = 0.006;
#include "res://addons/overcast/shaders/falling.gdshaderinc"

varying float fade;

void vertex() {
	vec4 h = overcast_fall_hash(uint(INSTANCE_ID) + 1u);
	vec4 g = overcast_fall_hash(uint(INSTANCE_ID) + 0x9e3779b9u);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	// Most drops are fine, a few are big: those fall faster, and catch more light.
	float size = g.x * g.x * g.x;
	float pace = mix(0.85, 1.2, size) * mix(0.95, 1.05, h.w);
	float speed = fall_speed * pace;
	float len = streak_length * mix(0.75, 1.25, size);
	vec3 p = overcast_fall_place(h.xyz, fallen * pace, cam);
	fade = overcast_fall_fade(p, cam, p - vec3(0.0, len * 0.5, 0.0)) * mix(0.5, 1.8, size);
	if (fade <= 0.0) {
		VERTEX = vec3(0.0);  // nothing to see: a zero-area quad, which draws no pixels at all
	} else {
		vec3 rel = p - cam;
		vec2 w = overcast_fall_pixel(width * mix(0.7, 1.8, size), length(rel), PROJECTION_MATRIX,
			VIEWPORT_SIZE);
		// A drop shows by the sky it refracts, against what is behind it: bright against the
		// ground, hardly at all against the sky itself.
		fade *= w.y * mix(1.0, 0.35, smoothstep(-0.05, 0.5, rel.y / length(rel)));
		// Right by the eye a drop is a blur, not a bar across the view.
		fade *= mix(0.25, 1.0, smoothstep(0.8, 3.0, length(rel)));
		vec3 axis = normalize(vec3(wind.x, -speed, wind.z));
		vec3 side = normalize(cross(axis, rel + vec3(1e-4)));
		vec3 world = p + side * VERTEX.x * w.x + axis * VERTEX.y * len;
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
