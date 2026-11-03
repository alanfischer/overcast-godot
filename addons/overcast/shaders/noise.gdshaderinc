#ifndef OVERCAST_NOISE_GDSHADERINC
#define OVERCAST_NOISE_GDSHADERINC

float overcast_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float overcast_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Smoothed value noise, one octave.
float overcast_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(overcast_hash12(i), overcast_hash12(i + vec2(1.0, 0.0)), f.x),
		mix(overcast_hash12(i + vec2(0.0, 1.0)), overcast_hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}
#endif
