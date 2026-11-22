// The air's light over the whole sky, into a small texture the sky samples (OvercastSky draws it
// when the sun or the air changes): for the step below the sun's height in the top half, the step
// above in the bottom. x is the bearing from the sun, 0 toward it to 1 away; down each half runs
// the zenith to level, squared so the horizon gets the rows. sRGB, so eight bits hold the dusk.
shader_type canvas_item;

#include "res://addons/overcast/shaders/atmosphere.gdshaderinc"
#include "res://addons/overcast/shaders/color_space.gdshaderinc"

uniform vec2 sun_height = vec2(0.5);   // sine of the sun's elevation, for each half
uniform float haze = 1.0;
uniform vec2 gain = vec2(20.0);
uniform vec2 dark = vec2(0.0);

void fragment() {
	float bearing = UV.x * PI;
	float lower = step(0.5, UV.y);
	float v = 1.0 - (UV.y * 2.0 - lower);
	float up = v * v;
	float level = sqrt(max(1.0 - up * up, 0.0));
	vec3 dir = vec3(cos(bearing) * level, up, sin(bearing) * level);
	float height = mix(sun_height.x, sun_height.y, lower);
	vec3 sun = vec3(sqrt(max(1.0 - height * height, 0.0)), height, 0.0);
	COLOR = vec4(overcast_to_srgb(atmo_seen(atmo_sky(dir, sun, haze), mix(gain.x, gain.y, lower),
		mix(dark.x, dark.y, lower))), 1.0);
}
