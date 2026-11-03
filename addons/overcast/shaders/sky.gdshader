// The Overcast sky as a Godot Sky: put it on a Sky's ShaderMaterial in a WorldEnvironment. Its
// parameters are sky.gdshaderinc's; OvercastSky sets them and the cloud globals.
shader_type sky;

#include "res://addons/overcast/shaders/sky.gdshaderinc"

void sky() {
	float storm_cover;
	float storm_body;
	// The radiance cubemap is ambient and reflections: no clouds there, which keeps the march out of
	// a pass that runs six times over.
	vec3 col = overcast_sky(EYEDIR, POSITION, FRAGCOORD.xy, !AT_CUBEMAP_PASS, storm_cover, storm_body);
	col = overcast_sky_flash(col, EYEDIR, storm_cover, storm_body);
	COLOR = overcast_dither(col, FRAGCOORD.xy);
}
