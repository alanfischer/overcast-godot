#ifndef OVERCAST_ATMOSPHERE_GDSHADERINC
#define OVERCAST_ATMOSPHERE_GDSHADERINC
// The air's own light: sunlight scattered by molecules (Rayleigh) and haze (Mie) and filtered by
// ozone, once, on an Earth-sized planet, for a viewer just over the ground. Linear, per unit of
// sunlight. OvercastSky runs the same sums on the CPU (_air_*), so keep the two in step.

const float ATMO_GROUND = 6360e3;
const float ATMO_TOP = 6460e3;
const float ATMO_VIEWER = 200.0;
const vec3 ATMO_RAYLEIGH = vec3(5.802e-6, 13.558e-6, 33.1e-6);
const float ATMO_RAYLEIGH_H = 8000.0;
const float ATMO_MIE = 3.996e-6;   // per unit of haze
const float ATMO_MIE_H = 1200.0;
const float ATMO_MIE_G = 0.8;
const vec3 ATMO_OZONE = vec3(0.650e-6, 1.881e-6, 0.085e-6);
const int ATMO_VIEW_STEPS = 48;
// Light scattered more than once, crudely: an even glow at each point, as strong as the sunlight
// a few kilometres over it, which stays lit a while after the point itself is in shadow, and blue
// from having been scattered by the air on its way.
const float ATMO_MULTI = 0.6;
const vec3 ATMO_MULTI_TINT = vec3(0.42, 0.64, 1.0);
const float ATMO_MULTI_UP = 6000.0;

// Rayleigh, Mie and ozone density at height h, each 1 at its peak.
vec3 atmo_density(float h) {
	return vec3(exp(-h / ATMO_RAYLEIGH_H), exp(-h / ATMO_MIE_H), max(0.0, 1.0 - abs(h - 25e3) / 15e3));
}

vec3 atmo_extinction(vec3 dens, float haze) {
	return ATMO_RAYLEIGH * dens.x + vec3(ATMO_MIE * 1.11 * haze * dens.y) + ATMO_OZONE * dens.z;
}

// How far along d (unit) from o, inside the sphere of radius r about the planet's centre, until
// it leaves.
float atmo_exit(vec3 o, vec3 d, float r) {
	float b = dot(o, d);
	return -b + sqrt(max(b * b - dot(o, o) + r * r, 0.0));
}

// Optical depth from height h (in scale heights) out along a ray at cos `mu` from the zenith,
// in vertical columns from the ground: Schüler's approximation to the Chapman function. `x` is the
// planet's radius in scale heights. Exact where marching would starve, on grazing rays.
float atmo_chapman(float x, float h, float mu) {
	float c = sqrt(x + h);
	if (mu >= 0.0) {
		return c / (c * mu + 1.0) * exp(-h);
	}
	float x0 = sqrt(1.0 - mu * mu) * (x + h);
	return 2.0 * sqrt(x0) * exp(x - x0) - c / (1.0 - c * mu) * exp(-h);
}

// The sunlight left at p after the air between it and the sun: none where the planet is between.
vec3 atmo_sunlight(vec3 p, vec3 sun, float haze) {
	float r = length(p);
	float mu = dot(p, sun) / r;
	if (mu < 0.0 && r * r * (1.0 - mu * mu) < ATMO_GROUND * ATMO_GROUND) {
		return vec3(0.0);
	}
	float h = r - ATMO_GROUND;
	vec3 depth = ATMO_RAYLEIGH * ATMO_RAYLEIGH_H * atmo_chapman(ATMO_GROUND / ATMO_RAYLEIGH_H, h / ATMO_RAYLEIGH_H, mu)
		+ vec3(ATMO_MIE * 1.11 * haze * ATMO_MIE_H * atmo_chapman(ATMO_GROUND / ATMO_MIE_H, h / ATMO_MIE_H, mu));
	// Ozone, a layer 25 km up holding 15 km of it at peak density: the column times the slant
	// it is crossed at, below it once and, from above on a falling ray, twice.
	float r_oz = ATMO_GROUND + 25e3;
	float s2 = (1.0 - mu * mu) * r * r / (r_oz * r_oz);
	float slant = s2 < 1.0 ? 1.0 / max(sqrt(1.0 - s2), 0.04) : 0.0;
	slant *= r < r_oz ? 1.0 : (mu < 0.0 ? 2.0 : 0.0);
	depth += ATMO_OZONE * 15e3 * slant;
	return exp(-depth);
}

float atmo_rayleigh_phase(float c) {
	return 3.0 / (16.0 * PI) * (1.0 + c * c);
}

float atmo_mie_phase(float c) {
	float g = ATMO_MIE_G;
	float k = 3.0 / (8.0 * PI) * (1.0 - g * g) / (2.0 + g * g);
	return k * (1.0 + c * c) / pow(1.0 + g * g - 2.0 * g * c, 1.5);
}

// The light the air sends back along `dir` (unit, at or above the horizon) toward `sun` (unit).
vec3 atmo_sky(vec3 dir, vec3 sun, float haze) {
	vec3 o = vec3(0.0, ATMO_GROUND + ATMO_VIEWER, 0.0);
	float len = atmo_exit(o, dir, ATMO_TOP);
	vec3 trans = vec3(1.0);
	vec3 ray = vec3(0.0);
	vec3 mie = vec3(0.0);
	vec3 multi = vec3(0.0);
	float prev = 0.0;
	for (int i = 0; i < ATMO_VIEW_STEPS; i++) {
		// Packed toward the viewer, where the air is thick.
		float f = (float(i) + 1.0) / float(ATMO_VIEW_STEPS);
		float t = len * f * f;
		float dt = t - prev;
		vec3 p = o + dir * (t - dt * 0.5);
		prev = t;
		vec3 dens = atmo_density(length(p) - ATMO_GROUND);
		vec3 step_trans = exp(-atmo_extinction(dens, haze) * dt);
		vec3 seen = trans * sqrt(step_trans) * dt;
		vec3 lit = seen * atmo_sunlight(p, sun, haze);
		vec3 glow = seen * atmo_sunlight(p * (1.0 + ATMO_MULTI_UP / length(p)), sun, haze);
		ray += lit * dens.x;
		mie += lit * dens.y;
		multi += glow * (ATMO_RAYLEIGH * dens.x + vec3(ATMO_MIE * haze * dens.y));
		trans *= step_trans;
	}
	float c = dot(dir, sun);
	return ray * ATMO_RAYLEIGH * atmo_rayleigh_phase(c) + mie * ATMO_MIE * haze * atmo_mie_phase(c)
		+ multi * ATMO_MULTI_TINT * ATMO_MULTI / (4.0 * PI);
}

// Light from atmo_sky as the eye takes it: `gain` (exposure, raised as the light fails), rolled
// off so a bright horizon stays coloured, and toward a pale blue the dimmer it is seen.
vec3 atmo_seen(vec3 light, float gain, float dark) {
	vec3 c = 1.0 - exp(-light * gain);
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return mix(c, luma * vec3(0.6, 0.8, 1.35), dark);
}
#endif
