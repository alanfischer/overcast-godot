shader_type spatial;
// Drifted snow (OvercastSnowDrift.surface_mesh): the mesh lies on the ground's faces, and each
// vertex rises by the snow the field cells about it hold over the even layer, so drifts heap up,
// shift with the wind and melt as the field does. Thinner than OVERCAST_DRIFT_THIN it is not
// drawn: the ground's own snow is there. A game that lights its world its own way writes its own
// fragment over drift.gdshaderinc's overcast_drift.
#include "res://addons/overcast/shaders/clouds.gdshaderinc"
#include "res://addons/overcast/shaders/drift.gdshaderinc"

// Depth in colour, with a contour every `contour` metres: to tune drifts by.
uniform bool contours = false;
uniform float contour = 0.25;
varying float thick;
varying vec3 world_pos;
varying float footprint;  // overcast_snow_footprint, for light()'s glints

void vertex() {
	thick = overcast_drift(VERTEX, NORMAL, UV, CUSTOM0, UV2.x);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	footprint = overcast_snow_footprint(world_pos);  // before any branch
	if (thick < OVERCAST_DRIFT_THIN) {
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
