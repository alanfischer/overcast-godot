// The air's light over the whole sky for one sun, into a small texture the sky samples
// (OvercastSky draws it when the sun or the air changes): x is the bearing from the sun, 0 toward
// it to 1 away; y runs from the zenith at the top to level at the bottom, squared so the horizon
// gets the rows. sRGB, so eight bits hold the dusk.
shader_type canvas_item;

#include "res://addons/overcast/shaders/atmosphere.gdshaderinc"
#include "res://addons/overcast/shaders/color_space.gdshaderinc"

uniform float sun_height = 0.5;   // sine of the sun's elevation
uniform float haze = 1.0;
uniform float gain = 20.0;
uniform float dark = 0.0;

void fragment() {
	float bearing = UV.x * PI;
	float v = 1.0 - UV.y;
	float up = v * v;
	float level = sqrt(max(1.0 - up * up, 0.0));
	vec3 dir = vec3(cos(bearing) * level, up, sin(bearing) * level);
	vec3 sun = vec3(sqrt(max(1.0 - sun_height * sun_height, 0.0)), sun_height, 0.0);
	COLOR = vec4(overcast_to_srgb(atmo_seen(atmo_sky(dir, sun, haze), gain, dark)), 1.0);
}
