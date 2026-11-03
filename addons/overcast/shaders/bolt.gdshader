// A lightning stroke: a strip along the bolt's points, turned to face the camera, with a white-hot
// core inside a soft blue glow. NORMAL carries the bolt's direction at each point and UV.x the side
// of the strip (-1 or 1), so the vertex shader can widen it across the view.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform vec3 color : source_color = vec3(0.85, 0.9, 1.0);
uniform float width = 2.2;
uniform float brightness = 1.0;

void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 along = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - p;
	vec3 side = normalize(cross(along, to_cam) + vec3(1e-5));
	// Never thinner than a couple of pixels, or a distant bolt flickers away.
	float pixel = length(to_cam) * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	p += side * UV.x * max(width * 0.5, pixel * 2.0);
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	float a = 1.0 - abs(UV.x);
	float core = smoothstep(0.65, 0.95, a);
	float glow = a * a;
	ALBEDO = (color * glow * 0.8 + vec3(core) * 1.5) * brightness;
}
