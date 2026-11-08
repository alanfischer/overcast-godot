shader_type spatial;
// Drifted snow (OvercastSnowDrift.surface_mesh): the mesh lies on the ground, and each vertex rises
// by the snow its field cell (UV, in texels) holds over the even layer, so drifts heap up, shift
// with the wind and melt as the field does. Thinner than THIN it is not drawn: the ground's own
// snow is there.
#include "res://addons/overcast/shaders/clouds.gdshaderinc"
#include "res://addons/overcast/shaders/snow.gdshaderinc"

const float THIN = 0.02;
// Depth in colour, with a contour every `contour` metres: to tune drifts by.
uniform bool contours = false;
uniform float contour = 0.25;
varying float thick;
varying vec3 world_pos;
varying float footprint;  // overcast_snow_footprint, for light()'s glints

// The top of the snow on cell c, ground and all.
float drift_top(ivec2 c) {
	return texelFetch(overcast_rain_floor, c, 0).r + texelFetch(overcast_snow_field, c, 0).r;
}

void vertex() {
	ivec2 res = textureSize(overcast_snow_field, 0);
	ivec2 c = ivec2(UV);
	thick = max(texelFetch(overcast_snow_field, c, 0).r - OVERCAST_SNOW_LAYER, 0.0);
	VERTEX.y += thick;
	// The slope of the snow's top round its cell; a neighbour on other ground (a wall, a drop) is
	// taken as level with it.
	vec2 cell = overcast_rain_floor_size / vec2(res);
	float jump = 1.5 * max(cell.x, cell.y);
	float y = drift_top(c);
	float e[4];
	ivec2 dirs[4] = ivec2[](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	for (int i = 0; i < 4; i++) {
		ivec2 o = clamp(c + dirs[i], ivec2(0), res - 1);
		float t = drift_top(o);
		e[i] = abs(t - y) <= jump ? t : y;
	}
	NORMAL = normalize(vec3(-(e[0] - e[1]) / (2.0 * cell.x), 1.0, -(e[2] - e[3]) / (2.0 * cell.y)));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	footprint = overcast_snow_footprint(world_pos);  // before any branch
	if (thick < THIN) {
		discard;
	}
	ALBEDO = overcast_snow_albedo(world_pos);
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
	if (contours) {
		float t = clamp(thick / 1.5, 0.0, 1.0);
		vec3 c = mix(vec3(0.55, 0.65, 0.9), vec3(0.95, 0.85, 0.2), smoothstep(0.0, 0.5, t));
		c = mix(c, vec3(0.9, 0.15, 0.1), smoothstep(0.5, 1.0, t));
		float d = thick / contour;
		float line = 1.0 - smoothstep(0.0, 1.5 * fwidth(d), abs(d - round(d)));
		ALBEDO = mix(c, vec3(0.05), line);
	}
}

// Lit as the ground's snow is (demo/ground.gdshader), so the two meet without a seam: the clouds
// take their share off the sun, and it glints.
void light() {
	float shade = LIGHT_IS_DIRECTIONAL ? cloud_sunlight(world_pos) : 1.0;
	float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI * shade;
	SPECULAR_LIGHT += lit * ATTENUATION * LIGHT_COLOR * shade
		* overcast_snow_glint(world_pos, 1.0, footprint, NORMAL, VIEW, LIGHT);
}
