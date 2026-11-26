// A gust of dust blown out along a cone (OvercastDustCone): the weather's dust (dust.gdshader),
// carried by one jet of air instead of the wind. The cone points down the node's -Z from its
// origin, widening from start_radius to end_radius over `cone_length`; each mote rides out along it,
// fastest at the mouth, and comes round again at the mouth once it reaches the end.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

#include "res://addons/overcast/shaders/falling.gdshaderinc"

// The dust in the light on it, already in the renderer's output space (OvercastDustCone).
uniform vec3 color = vec3(0.6, 0.53, 0.43);
uniform float opacity = 0.7;
// The cone's own transform: a MultiMesh's instances carry none (OvercastDustCone).
uniform mat4 cone_xform = mat4(1.0);
uniform float cone_length = 8.0;
uniform float start_radius = 0.5;
uniform float end_radius = 4.0;
// m/s at the mouth; the motes slow to a third of it by the end.
uniform float speed = 30.0;
// Radians each mote turns about the axis on its way down the cone: a whirl, not a jet.
uniform float twist = 0.0;
// How far (in lengths) the air has carried them, wrapped at 4: each mote rides 3/4 to 6/4 as fast.
uniform float flowed = 0.0;
// Metres down the cone the dust shows between: the front runs out when it starts blowing, the tail
// after it stops, and `reach` is where something stands in the way.
uniform float front = 1e5;
uniform float tail = 0.0;
uniform float reach = 1e5;
uniform float mote_size = 0.015;
uniform float eddy = 0.3;
uniform float eddy_rate = 3.0;
uniform float smear = 0.02;
uniform float wisps = 0.1;
uniform float wisp_opacity = 0.08;

varying float fade;
varying float wisp;

void vertex() {
	vec4 h = overcast_fall_hash(uint(INSTANCE_ID) + 1u);
	vec4 g = overcast_fall_hash(uint(INSTANCE_ID) + 0x9e3779b9u);
	wisp = step(fract(g.z * 7.0), wisps);
	float k = (3.0 + floor(g.x * 3.999)) * 0.25;
	float p = fract(flowed * k + h.x);
	// Out along it at 1.5 - p of the mean: fast at the mouth, a third of that at the end.
	float s = p * 1.5 - 0.5 * p * p;
	float d = s * cone_length;
	float spread = (end_radius - start_radius) / cone_length;
	float r = start_radius + spread * d;
	float a = h.y * TAU + twist * s;
	vec2 out_dir = vec2(cos(a), sin(a));
	vec2 round_dir = vec2(-out_dir.y, out_dir.x);
	float u = sqrt(h.z);
	vec3 local = vec3(out_dir * u * r, -d);
	float t = TIME * eddy_rate * mix(0.6, 1.4, g.y) * mix(1.0, 0.4, wisp);
	vec3 swirl = vec3(sin(t + g.z * TAU), sin(t * 1.31 + g.y * TAU), 0.5 * cos(t * 0.77 + g.w * TAU));
	local += eddy * mix(0.2, 1.0, s) * mix(1.0, 2.0, wisp) * swirl;
	vec3 move = vec3(out_dir * u * spread + round_dir * u * r * twist / cone_length, -1.0)
		* speed / 1.5 * k * (1.5 - p);

	fade = smoothstep(0.0, 0.08, p) * smoothstep(1.0, 0.7, p)
		* smoothstep(front + 0.01, front - 0.5, d) * smoothstep(tail - 0.01, tail + 0.5, d)
		* smoothstep(reach + 0.01, reach - 0.75, d);
	vec3 p_world = (cone_xform * vec4(local, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 rel = p_world - cam;
	float dist = length(rel);
	fade *= exp(-haze_density * dist) * (wisp > 0.0 ? wisp_opacity : opacity);
	if (fade < 1.0 / 255.0) {
		VERTEX = vec3(0.0);
	} else {
		vec3 vel = mat3(cone_xform) * move;
		vec3 axis = normalize(vel + vec3(1e-4, 0.0, 0.0));
		vec3 side = normalize(cross(axis, rel + vec3(1e-4)));
		vec3 world;
		if (wisp > 0.0) {
			float size = mix(0.4, 0.9, g.x) * (0.3 + 0.25 * r);
			fade *= smoothstep(0.8, 2.5, dist);
			world = p_world + side * VERTEX.x * size + axis * VERTEX.y * size * mix(1.5, 2.5, h.w);
		} else {
			float size = mote_size * mix(0.5, 2.0, g.x * g.x);
			vec2 w = overcast_fall_pixel(size, dist, PROJECTION_MATRIX, VIEWPORT_SIZE);
			fade *= w.y * smoothstep(0.3, 1.0, dist);
			float len = max(w.x, length(vel) * smear * mix(0.7, 1.3, h.w));
			world = p_world + side * VERTEX.x * w.x + axis * VERTEX.y * len;
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
	ALPHA = min(fade * shape, 1.0);
}
