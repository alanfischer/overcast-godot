#ifndef OVERCAST_SKY_GDSHADERINC
#define OVERCAST_SKY_GDSHADERINC
// The sky: a gradient, a sun, stars, cirrus and the cloud layer (clouds.gdshaderinc), closing over
// into a storm deck as `storm` rises, and lit from inside by lightning. Shared by sky.gdshader (a
// Godot Sky) and any spatial shader that draws a sky on geometry: call overcast_sky, then
// overcast_sky_flash, then overcast_dither.
//
// Colours are authored in whatever space the caller's art is in: they arrive as source_color, so
// the RD renderers convert them and gl_compatibility does not.

uniform vec3 zenith_color : source_color = vec3(0.25, 0.42, 0.70);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.70, 0.82);
uniform vec3 ground_color : source_color = vec3(0.18, 0.17, 0.16);
// How fast zenith wins over horizon. Low = a broad hazy band, high = colour only at the top.
uniform float horizon_falloff : hint_range(0.2, 4.0) = 1.1;

// Direction TO the sun, world space: at noon, when OvercastSky moves it with the time of day.
uniform vec3 sun_dir = vec3(0.0, 0.6, -0.8);
// Toward what lights the sky now, sun or moon, and how strongly (OvercastSky sets both); sun_dir
// while unset.
uniform vec3 light_dir = vec3(0.0);
uniform float light_strength = 1.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.82);
uniform float sun_size : hint_range(0.002, 0.5) = 0.012;   // angular radius, radians
uniform float sun_energy : hint_range(0.0, 8.0) = 2.2;
uniform float sun_glow_exp : hint_range(1.0, 2048.0) = 320.0;
uniform float sun_glow_energy : hint_range(0.0, 3.0) = 0.35;
// The wide whitish brightening the air puts around the sun, and along the horizon below it.
uniform float sun_halo_energy : hint_range(0.0, 2.0) = 0.25;
uniform float sun_halo_exp : hint_range(1.0, 64.0) = 6.0;

// How cloudy a fair day is; the cover actually drawn is the overcast_cover global, which a storm
// raises (OvercastSky).
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.45;
// How far the cloud layer is spread into a sheet: 0 heaped cumulus, 0.5 stratocumulus, 1 stratus
// (the overcast_sheet global, which OvercastSky sets from it).
uniform float cloud_sheet : hint_range(0.0, 1.0) = 0.0;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
// A thin, streaky layer high over the main one, drifting faster.
uniform float cirrus_amount : hint_range(0.0, 1.0) = 0.5;
// A sheet of small puffs in rows (altocumulus), between the two.
uniform float mid_cloud_amount : hint_range(0.0, 1.0) = 0.0;
// How far each is spread into a smooth veil: the middle layer toward altostratus, the sun behind
// it as through frosted glass; the cirrus toward cirrostratus, milky, with a halo round the sun.
uniform float mid_cloud_sheet : hint_range(0.0, 1.0) = 0.0;
uniform float cirrus_sheet : hint_range(0.0, 1.0) = 0.0;
// Thunderheads round the horizon: towering cumulus as it rises, cumulonimbus with anvils toward 1.
uniform float cloud_towering : hint_range(0.0, 1.0) = 0.0;
// The middle layer's and the cirrus' heights, as multiples of the cloud layer's (OvercastSky).
uniform float mid_cloud_rise = 2.6667;
uniform float cirrus_rise = 6.0;

uniform float star_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 star_color : source_color = vec3(1.0, 1.0, 1.0);
// Takes a view ray back to where it looked at noon, as the stars turn with the sun (OvercastSky
// sets it).
uniform mat3 star_basis = mat3(1.0);

// Time of day (OvercastSky.time_of_day sets the two amounts): the colours above are the day's.
// Toward dusk they warm to dusk_color, low and on the sun's side; at night they give way to these,
// the sun to a moon in its place, and stars come out.
uniform float dusk_amount : hint_range(0.0, 1.0) = 0.0;
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dusk_color : source_color = vec3(1.0, 0.48, 0.24);
uniform vec3 night_zenith_color : source_color = vec3(0.02, 0.03, 0.07);
uniform vec3 night_horizon_color : source_color = vec3(0.06, 0.07, 0.12);
uniform vec3 moon_color : source_color = vec3(0.82, 0.86, 1.0);
uniform float moon_energy : hint_range(0.0, 8.0) = 1.5;
uniform float moon_size : hint_range(0.002, 0.5) = 0.03;   // angular radius, radians
// Toward the moon, the direction its face is lit from (both unit), and its light on the scene,
// 0 to 1: OvercastSky sets all three. Until it does the moon is down.
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 moon_lit_from = vec3(0.0, 1.0, 0.0);
uniform float moonlight = 1.0;
uniform float night_stars : hint_range(0.0, 1.0) = 0.7;

// Rain: 0 is the sky as configured, 1 a full storm — the deck closes over, its clouds go dark and
// heavy, the sky behind them greys, and sun, moon and stars are lost. Everything is relative to
// the sky's own colours, so a storm at night stays a night sky.
uniform float storm : hint_range(0.0, 1.0) = 0.0;
// How much of the storm is snow: a snow sky is a pale, flat grey, not a dark one.
uniform float snowy : hint_range(0.0, 1.0) = 0.0;

// How far the sky's colours are the air's own (atmosphere.gdshaderinc) rather than the painted
// ones above, 0 for those alone: sunlight scattered blue overhead, reddened low, the planet's shadow rising opposite a
// set sun. The night colours still come in over it, and dusk_color is the painted sky's alone.
uniform float atmosphere : hint_range(0.0, 1.0) = 1.0;
// Dust and droplets in the air: more pales the blue and whitens the sky round the sun.
uniform float atmosphere_haze : hint_range(0.0, 10.0) = 1.0;
uniform float atmosphere_exposure : hint_range(0.0, 100.0) = 20.0;
// OvercastSky sets these, once for the whole sky: where the sun really is, below the horizon too;
// the sunlight reaching the ground against the noon sun's, as the eye takes it; the air's light
// overhead and level.
uniform vec3 atmosphere_sun = vec3(0.0, 1.0, 0.0);
uniform vec3 atmosphere_light = vec3(1.0);
uniform vec3 atmosphere_cloud_light = vec3(1.0);   // as atmosphere_light, at the clouds' height
uniform vec3 atmosphere_mid_light = vec3(1.0);     // and at the middle layer's and the cirrus'
uniform vec3 atmosphere_high_light = vec3(1.0);
uniform vec3 atmosphere_zenith = vec3(0.0);
uniform vec3 atmosphere_horizon = vec3(0.0);
// The air's light over the sky for the sun now, as atmosphere_lut.gdshader draws it.
uniform sampler2D atmosphere_lut : filter_linear, repeat_disable, hint_default_black;

#include "res://addons/overcast/shaders/flash.gdshaderinc"
#include "res://addons/overcast/shaders/noise.gdshaderinc"
#include "res://addons/overcast/shaders/clouds.gdshaderinc"
#include "res://addons/overcast/shaders/color_space.gdshaderinc"

const vec3 OVERCAST_LUMA = vec3(0.299, 0.587, 0.114);

// Linear light in the space the painted colours are in on this renderer.
vec3 overcast_art(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return overcast_to_srgb(c);
#else
	return c;
#endif
}

// Bright light rolled off toward white instead of clipping there, so cloud by the sun keeps its
// shape. Below the knee a colour is untouched.
vec3 overcast_shoulder(vec3 c) {
	const float KNEE = 0.8;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	c = overcast_to_srgb(c);
#endif
	c = min(c, KNEE) + (1.0 - KNEE) * (1.0 - exp(-max(c - KNEE, 0.0) / (1.0 - KNEE)));
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	c = overcast_to_linear(c);
#endif
	return c;
}

// Volumetric clouds: cloud_volume_density in clouds.gdshaderinc, marched here.
// metres of slab a ray marches at most; past it is haze
#define MARCH_MAX (900.0 * CLOUD_M)
// metres per step, wanted
#define MARCH_STEP (12.0 * CLOUD_M)
const int MARCH_STEPS_MIN = 16;
const int MARCH_STEPS_MAX = 48;
// Short strides under the weather map's cloud, per long one.
const int FINE = 4;

float hg_phase(float c, float g) {
	return (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * c, 1.5);   // x4π: isotropic is 1
}

// Ray-march the slab along eye_dir, from `t0` metres out where it meets the shell at noise point
// `cp` (cloud_distance, cloud_layer + wind). rgb is the light the cloud sends us, alpha how much
// of the sky behind it the cloud hides; `body` comes back as the mean density it was hidden by.
vec4 cloud_march(vec3 cam, vec3 eye_dir, float t0, vec2 cp, vec3 sun, vec3 sun_col, vec3 base_col,
		vec3 top_col, vec2 frag, out float body) {
	float t1 = min(cloud_distance_to(cam, eye_dir, CLOUD_HEIGHT + CLOUD_THICK), t0 + MARCH_MAX);
	// Overhead the slab is short; toward the horizon a ray crosses a long way of it.
	int steps = clamp(int((t1 - t0) / MARCH_STEP), MARCH_STEPS_MIN, MARCH_STEPS_MAX);
	float dt = (t1 - t0) / float(steps);
	// The step pattern turns into a fine grain instead of bands.
	float jitter = overcast_jitter(frag);
	float c = dot(eye_dir, sun);
	// Forward-scattering lobe for the silver lining, plus an even share for light that has
	// bounced around inside the cloud: the sunlit side is bright from any angle.
	float phase = min(mix(hg_phase(c, 0.65), hg_phase(c, -0.25), 0.35), 6.0) * 0.5 + 0.7;
	float field = cloud_field(cp);
	vec3 wind = cloud_volume_wind();
	float fair = cloud_fair();
	vec2 cp_per_m = eye_dir.xz * (overcast_scale / CLOUD_HEIGHT);
	vec3 p0 = cam + eye_dir * t0;
	float low_sun = 1.0 - smoothstep(0.0, 0.3, sun.y);
	vec3 scattered = vec3(0.0);
	float trans = 1.0;
	float weight = 0.0;
	// Long strides where the weather map holds no cloud, short ones where it does, until a long
	// one's worth is clear again. One long step through a sunlit edge is all but opaque, so which
	// part of the edge it lands on would decide the pixel, a grain at every low sun. The map is
	// broad and smooth, so neighbouring pixels change stride together: changing on the cloud
	// itself left its thinnest wisps found by some pixels and not their neighbours, a sparkle.
	// Short strides are no finer than MARCH_STEP's share (overhead, dt is already short), and there
	// are enough steps to cross the whole slab in them.
	float fine = clamp(MARCH_STEP / float(FINE), dt / float(FINE), dt);
	float stride = dt;
	float t = dt * jitter;
	int clear_run = 0;
	for (int i = 0; i < steps + int(ceil((t1 - t0) / fine)); i++) {
		if (t > t1 - t0) {
			break;
		}
		vec3 p = p0 + eye_dir * t;
		float weather = cloud_weather(cp + cp_per_m * t, field);
		if (weather > 0.0 && stride == dt) {
			stride = fine;
			clear_run = 0;
			if (i > 0) {
				t -= dt - stride;
				continue;
			}
		}
		clear_run = weather > 0.0 ? 0 : clear_run + 1;
		if (clear_run >= FINE) {
			stride = dt;
		}
		float crease = 0.0;
		float d = weather > 0.0 ? cloud_volume_density(p, cam, wind, fair, weather, crease) : 0.0;
		if (d <= 0.0) {
			t += stride;
			continue;
		}
		// Light march toward the sun, steps growing outward.
		float od = 0.0;
		float ls = 6.0 * CLOUD_M;
		vec3 lp = p;
		for (int j = 0; j < LIGHT_STEPS; j++) {
			lp += sun * ls;
			od += cloud_volume_bulk(lp, cam, wind, fair, weather) * ls;
			ls *= 1.8;
		}
		od *= EXTINCTION;
		// Beer's law, plus a long, weak tail standing in for light scattered many times over. Only
		// the light scattered once keeps the sun's direction, so only it takes the phase: into the
		// sun, a thick cloud's body is lit by the even, many-times-scattered glow, and its thin
		// edges blaze.
		float light = exp(-od) * phase + mix(0.35, 0.6, low_sun) * exp(-od * mix(0.1, 0.06, low_sun));
		float powder = 1.0 - exp(-d * MARCH_STEP * EXTINCTION * 2.0);
		vec3 amb = mix(base_col, top_col, clamp(cloud_height_frac(p, cam), 0.0, 1.0));
		// The creases between billows sit in their shade.
		vec3 radiance = (sun_col * light * mix(0.5, 1.0, powder) + amb) * mix(1.04, 0.84, crease);
		float absorbed = 1.0 - exp(-d * EXTINCTION * stride);
		scattered += trans * radiance * absorbed;
		weight += trans * absorbed * d;
		trans *= 1.0 - absorbed;
		if (trans < 0.02) {
			break;
		}
		t += stride;
	}
	float alpha = 1.0 - trans;
	body = weight / max(alpha, 1e-4);
	return vec4(scattered / max(alpha, 1e-4), alpha);
}

// How thick a storm deck reads where the flat layer's density is `n`: mottled by the noise that
// shaped it, so a full deck still has bodies to it rather than one flat lid.
float storm_body_of(float n) {
	return clamp(0.55 + 0.7 * n, 0.4, 1.3);
}

// Stars and the Milky Way along eye_dir, for a sky `sky_lum` bright behind them. `amount` is how
// many are out.
vec3 overcast_stars(vec3 eye_dir, float amount, float sky_lum) {
	// A sky still lit drowns them, the faint ones first.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	float drowned = smoothstep(0.12, 0.45, sky_lum);
#else
	float drowned = smoothstep(0.013, 0.17, sky_lum);
#endif
	float up = eye_dir.y;
	if (up <= 0.0 || drowned >= 1.0) {
		return vec3(0.0);
	}
	vec3 dir = star_basis * eye_dir;

	// The Milky Way: a band round the sky where the stars crowd, over their unresolved glow,
	// mottled and split by dark dust.
	const vec3 POLE = vec3(0.48, 0.36, 0.8);
	float lat = dot(dir, POLE);
	vec3 bu = normalize(cross(POLE, vec3(0.0, 1.0, 0.0)));
	vec2 along = vec2(dot(dir, bu), dot(dir, cross(POLE, bu)));
	float mottle = overcast_vnoise(along * 7.0 + lat * 9.0) * 0.6 + overcast_vnoise(along * 19.0 - lat * 23.0) * 0.4;
	float dust = smoothstep(0.35, 0.7, overcast_vnoise(along * 5.0 + vec2(3.1, 9.2) + lat * 4.0));
	float band = exp(-lat * lat * 22.0) * (0.35 + 0.65 * mottle) * (1.0 - 0.7 * dust * exp(-lat * lat * 160.0));

	// The air dims what is low, and makes it flicker.
	float low = 1.0 - smoothstep(0.0, 0.35, up);
	float seen = smoothstep(0.0, 0.02, up) * mix(1.0, 0.35, low) * (1.0 - drowned);
	vec3 col = mix(night_horizon_color, star_color, 0.5) * band * 0.22 * min(amount * 1.5, 1.0) * seen;

	vec3 sp = dir * 320.0;
	vec3 cell = floor(sp);
	float h = overcast_hash13(cell);
	// `amount` is a density, but the useful range is tiny: a cell in a few dozen.
	float threshold = 1.0 - min(amount * 0.06 * (1.0 + 4.0 * band), 1.0);
	if (h < threshold) {
		return col;
	}
	// Few are bright and most are faint; the bright ones are the first out at dusk.
	float rank = (h - threshold) / max(1.0 - threshold, 1e-4);
	float bright = 0.12 + 0.88 * pow(rank, 3.5);
	float tint = overcast_hash13(cell + 41.3);
	vec3 star = star_color * mix(vec3(1.0, 0.82, 0.62), vec3(0.72, 0.84, 1.0), smoothstep(0.15, 0.7, tint));
	float d = length(fract(sp) - 0.5);
	float twinkle = 1.0 - mix(0.2, 0.6, low) * (0.5 + 0.5 * sin(TIME * mix(1.7, 5.0, tint) + h * 4217.0));
	float faint = 1.0 - smoothstep(bright * 0.6, bright * 0.6 + 0.3, drowned);
	float size = mix(0.3, 0.48, bright);
	return col + star * smoothstep(size, size * 0.4, d) * bright * 1.6 * twinkle * seen * faint;
}

// The grey a cloud out of the sun takes: lit by the sky, so the sky's colour rather than a grey.
vec3 overcast_skylit(vec3 ambient) {
	return mix(vec3(dot(ambient, OVERCAST_LUMA)), ambient, 0.6);
}

// A cloud colour as the air lights it at a layer's height (`air_light`, one of the atmosphere_*_light).
vec3 overcast_cloud_lit(vec3 cloud_col, vec3 sun_col, vec3 air_light) {
	vec3 lit = cloud_col * mix(vec3(1.0), sun_col, 0.5);
	return mix(lit, cloud_col * mix(overcast_art(air_light), mix(vec3(1.0), moon_color, 0.5), night_amount),
		atmosphere);
}

// The layers over the cloud layer, on their own shells: cirrus streaks highest, and an
// altocumulus sheet of small puffs in rows between. Colour, and how much they cover, over `col`.
vec4 overcast_higher_cloud(vec3 eye_dir, vec3 cam, vec3 sun, vec3 col, vec3 ambient, vec3 cloud_col,
		vec3 sun_col) {
	float up = eye_dir.y;
	vec3 out_col = col;
	float out_cover = 0.0;
	vec2 wind = cloud_wind();
	float clear = 1.0 - storm;
	if (cirrus_amount > 0.0) {
		float h = CLOUD_HEIGHT * cirrus_rise;
		float d = cloud_distance_to(cam, eye_dir, h);
		vec2 hp = cloud_layer_at(cam, eye_dir, d, h) * 0.6;
		float far = smoothstep(1.5 * h, cloud_horizon_at(cam, h), d);
		float c = cloud_tex(vec2(hp.x * 0.25, hp.y) + wind * 2.5 + vec2(3.7, 1.3));
		float streaks = smoothstep(0.55, 0.85, c) * 0.45 * (1.0 - far);
		// Cirrostratus: a milky veil, faintly fibrous, thickening toward the horizon.
		float milky = (0.32 + 0.12 * c) * mix(1.0, 1.6, smoothstep(0.4, 0.0, up));
		float ci = mix(streaks, milky, cirrus_sheet) * cirrus_amount * clear * smoothstep(0.0, 0.15, up);
		vec3 lit = overcast_cloud_lit(cloud_col, sun_col, atmosphere_high_light);
		out_col = mix(out_col, mix(ambient, lit, 0.7), ci);
		// The 22° halo, from ice crystals: a sharp reddish inner edge, white and diffuse outward.
		float halo_veil = milky * cirrus_amount * cirrus_sheet * clear;
		float cos_ang = dot(eye_dir, sun);
		if (halo_veil > 0.0 && cos_ang > 0.8) {
			float ang = acos(min(cos_ang, 1.0));
			float inner = (ang - 0.384) / 0.008;
			float outer = (ang - 0.384) / 0.05;
			float ring = exp(-inner * inner) + 0.5 * exp(-outer * outer) * step(0.384, ang);
			vec3 tint = mix(vec3(1.0, 0.72, 0.55), vec3(0.9, 0.95, 1.0), smoothstep(0.378, 0.41, ang));
			out_col += sun_col * tint * ring * halo_veil * 0.3 * light_strength * smoothstep(-0.02, 0.05, sun.y);
		}
	}
	if (mid_cloud_amount > 0.0) {
		float h = CLOUD_HEIGHT * mid_cloud_rise;
		float d = cloud_distance_to(cam, eye_dir, h);
		vec2 mp = cloud_layer_at(cam, eye_dir, d, h) + wind * 1.3;
		float far = smoothstep(1.5 * h, cloud_horizon_at(cam, h), d);
		// Where the sheet is: broad patches that join up as there is more of it.
		float patches = cloud_tex(mp * 0.3 + vec2(9.1, 4.4)) + (cloud_tex(mp * 0.8 + vec2(1.7, 6.3)) - 0.5) * 0.5;
		float edge = mix(0.78, 0.18, mid_cloud_amount);
		float sheet = smoothstep(edge - 0.06, edge + 0.14, patches);
		// The puffs: worley cells drawn out across the wind into rows, their outlines broken.
		vec2 t = cloud_tex2(vec2(mp.x * 3.0, mp.y * 5.5) + vec2(2.3, 7.7));
		float cell = t.g + (t.r - 0.5) * 0.3;
		float size = mix(0.3, 0.55, sheet * mid_cloud_amount);
		float puff = 1.0 - smoothstep(size - 0.1, size + 0.03, cell);
		// Far off, a cell is finer than a pixel: the sheet's average, banking up toward the horizon.
		puff = mix(puff, mix(0.5, 0.85, mid_cloud_amount), far);
		// Altostratus: the patches spread smooth and grey, seen through.
		float smooth_sheet = smoothstep(edge - 0.2, edge + 0.25, patches);
		float cover = mix(puff * sheet, smooth_sheet * 0.85, mid_cloud_sheet) * clear * smoothstep(0.0, 0.06, up);
		float toward = clamp(dot(eye_dir, sun) * 0.5 + 0.5, 0.0, 1.0);
		// Thin: lit through, a little grey at a puff's heart, bright at its rim toward the sun.
		float heart = 1.0 - smoothstep(0.0, size, cell);
		vec3 lit = overcast_cloud_lit(cloud_col, sun_col, atmosphere_mid_light);
		// The sky lights it too, so out of the sun it is the sky's grey, not black.
		vec3 skylit = overcast_skylit(ambient) * 0.9;
		vec3 c = max(mix(lit, mix(skylit, lit, 0.55), heart * mix(0.7, 0.3, toward)), skylit * mix(1.0, 0.8, heart));
		c += sun_col * hg_phase(dot(eye_dir, sun), 0.8) / 45.0 * (1.0 - heart) * light_strength;
		vec3 grey = mix(skylit, lit, 0.45) * (0.92 + 0.16 * patches);
		c = mix(c, grey, mid_cloud_sheet);
		vec3 through = exp(-far * vec3(0.5, 0.6, 0.8));
		c = c * through + out_col * (1.0 - through);
		out_col = mix(out_col, c, cover);
		// A thin veil leaves the sun's disc to be seen through it.
		out_cover = cover * mix(1.0, 0.55, mid_cloud_sheet);
	}
	return vec4(out_col, out_cover);
}

float overcast_smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// Thunderheads far off round the horizon (cloud_towering): towers of heaped lobes, the biggest
// spreading into a flat-topped anvil downwind, their tops lit by the air at their height. Colour
// over `col`, and how much they cover.
vec4 overcast_towers(vec3 eye_dir, vec3 sun, vec3 ambient, vec3 cloud_col, vec3 sun_col, vec3 col) {
	float e = asin(clamp(eye_dir.y, -1.0, 1.0));
	if (cloud_towering <= 0.0 || e > 0.45 || e < -0.05) {
		return vec4(col, 0.0);
	}
	float az = atan(eye_dir.x, -eye_dir.z);
	float sun_az = atan(sun.x, -sun.z);
	vec3 skylit = overcast_skylit(ambient) * 0.75;
	float anvil_amount = smoothstep(0.5, 1.0, cloud_towering);
	vec3 out_col = col;
	float out_cover = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float h = overcast_hash12(vec2(fi, 7.1));
		// More of them as it rises, and taller.
		if (h > cloud_towering) {
			continue;
		}
		float centre = overcast_hash12(vec2(fi, 2.3)) * TAU + length(overcast_cloud_drift) * 0.02;
		float top = mix(0.07, 0.2, overcast_hash12(vec2(fi, 5.9))) * mix(0.5, 1.0, cloud_towering);
		// In units of the cloud's height: x across, y up from the horizon.
		vec2 p = vec2(mod(az - centre + PI, TAU) - PI, e) / top;
		if (abs(p.x) > 2.8 || p.y > 1.3) {
			continue;
		}
		float sdf = 1e3;
		// Each lobe a ball, their surface normals blended by nearness: they shade the bulges.
		vec3 normal_sum = vec3(0.0);
		float nearest = 1e3;
		for (int j = 0; j < 6; j++) {
			float fj = float(j);
			float r = mix(0.55, 0.26, fj / 5.0) * mix(0.85, 1.2, overcast_hash12(vec2(fi, fj + 20.0)));
			vec2 c = vec2((overcast_hash12(vec2(fi, fj + 40.0)) - 0.5) * mix(0.9, 0.3, fj / 5.0), 0.1 + fj * 0.15);
			float dl = length(p - c) - r;
			nearest = min(nearest, dl);
			vec2 n = clamp((p - c) / r, vec2(-1.0), vec2(1.0));
			normal_sum += normalize(vec3(n, sqrt(max(1.0 - dot(n, n), 0.0)) + 0.05)) * exp(-max(dl, -0.3) * 18.0);
			sdf = overcast_smin(sdf, dl, 0.12);
		}
		vec3 normal = normalize(normal_sum + vec3(0.0, 0.0, 1e-4));
		if (anvil_amount > 0.0) {
			float downwind = overcast_hash12(vec2(fi, 9.4)) > 0.5 ? 1.0 : -1.0;
			float reach = mix(1.3, 2.0, h);
			// Out of the crown, thinning downwind; flat on top where the storm meets the stratosphere.
			vec2 q = p - vec2(downwind * reach * 0.45, 0.93);
			float slab = (length(q / vec2(reach * 0.65, 0.17 + 0.15 * (1.0 - abs(q.x) / reach))) - 1.0) * 0.17;
			float hood = (length((p - vec2(downwind * 0.2, 0.86)) / vec2(0.8, 0.26)) - 1.0) * 0.26;
			float anvil = max(overcast_smin(slab, hood, 0.12), p.y - 1.02);
			normal = normalize(mix(normal, vec3(0.0, 0.6, 0.8), smoothstep(0.05, -0.05, anvil - nearest) * anvil_amount));
			sdf = mix(sdf, overcast_smin(sdf, anvil, 0.1), anvil_amount);
		}
		float billow = overcast_vnoise(p * 9.0 + fi * 13.0) - 0.5;
		billow += (overcast_vnoise(p * 22.0 + fi * 7.0) - 0.5) * 0.5;
		sdf += billow * 0.05;
		// A flat base, as cumulus have, a little over the horizon this far off.
		float base = 0.07 + 0.01 * billow;
		float column = sdf;
		sdf = max(sdf, base - p.y);
		float inside = 1.0 - smoothstep(-0.012, 0.012, sdf);
		// Under a cumulonimbus, its rain: a grey curtain from the base to the ground.
		float curtain = anvil_amount * smoothstep(0.02, -0.12, column) * step(p.y, base)
			* (0.45 + 0.55 * cloud_tex(vec2(p.x * 5.0 - p.y * 2.0, 0.3) + fi));
		if (curtain > 0.0) {
			out_col = mix(out_col, skylit * 0.9, curtain * 0.55);
		}
		if (inside <= 0.0) {
			continue;
		}
		// Cauliflower: small bulges on the lobes, tilting the surface their way.
		vec2 fp = p * 1.6 + fi * 3.7;
		float f0 = cloud_tex(fp);
		vec2 grad = vec2(cloud_tex(fp + vec2(0.04, 0.0)), cloud_tex(fp + vec2(0.0, 0.04))) - f0;
		normal = normalize(normal - vec3(grad * 9.0, 0.0));
		// Lit full face on with the sun behind us, on one side with it to the side, dark against
		// it but for a silver edge; brighter toward the top, which stands high in the sun's light.
		float rel = sun_az - centre;
		float facing = 0.5 - 0.5 * cos(rel);
		float up_frac = clamp(p.y, 0.0, 1.0);
		// The sun in the cloud's own frame: x across, y up, z toward us.
		float sun_flat = sqrt(max(1.0 - sun.y * sun.y, 0.0));
		vec3 to_sun = vec3(sin(rel) * sun_flat, sun.y, -cos(rel) * sun_flat);
		float lambert = clamp(dot(normal, to_sun) * 0.75 + 0.25, 0.0, 1.0);
		float light = clamp(lambert + billow * 0.12, 0.0, 1.0) * mix(0.6, 1.0, up_frac);
		vec3 air = mix(atmosphere_cloud_light, atmosphere_high_light, up_frac);
		vec3 sunlit = overcast_cloud_lit(cloud_col, sun_col, air);
		vec3 c = mix(skylit, sunlit, light * light_strength);
		float rim = (1.0 - smoothstep(0.0, 0.04, -sdf)) * (1.0 - facing) * smoothstep(-0.3, 0.6, cos(rel));
		c += sunlit * rim * 0.6 * light_strength;
		// Far off: their feet lost in the haze, their tops clearer.
		c = mix(c, col, mix(0.5, 0.08, smoothstep(0.0, 0.5, up_frac)));
		out_col = mix(out_col, c, inside);
		out_cover = max(out_cover, inside);
	}
	return vec4(out_col, out_cover);
}

// The sky along eye_dir (unit, world space) seen from `cam` (world space), at pixel `frag`.
// storm_cover and storm_body come back for overcast_sky_flash: where storm cloud is, and how
// thick. `clouds` false skips the cloud layer, for a cheap pass such as a radiance cubemap.
vec3 overcast_sky(vec3 eye_dir, vec3 cam, vec2 frag, bool clouds, out float storm_cover,
		out float storm_body) {
	vec3 sun = length(light_dir) > 0.0 ? normalize(light_dir) : normalize(sun_dir);
	float up = eye_dir.y;
	vec2 flat_eye = normalize(eye_dir.xz + vec2(1e-5));
	vec2 flat_sun = normalize(sun.xz + vec2(1e-5));
	float sun_bearing = dot(flat_eye, flat_sun);
	float sun_side = max(sun_bearing, 0.0);
	// The day's colours at this time of day.
	float glow = dusk_amount * (0.45 + 0.55 * sun_side);
	vec3 zen = mix(zenith_color * mix(1.0, 0.6, dusk_amount), night_zenith_color, night_amount);
	vec3 hor = mix(mix(horizon_color, dusk_color, glow * 0.8), night_horizon_color, night_amount);
	vec3 gnd = ground_color * mix(1.0, 0.15, night_amount);
	vec3 sun_col = mix(mix(sun_color, dusk_color * 1.3, dusk_amount), moon_color, night_amount);
	// Cloud by night is as pale as the moon lights it.
	vec3 cloud_col = mix(cloud_color, mix(night_horizon_color, vec3(1.0), 0.35) * mix(0.5, 1.0, moonlight), night_amount);
	float stars = max(star_amount, night_stars * night_amount);
	vec3 above_air = vec3(0.0);
	if (atmosphere > 0.0) {
		// Night's colours over the air's light, which is all but gone by then.
		vec3 night_zen = night_zenith_color * night_amount;
		vec3 night_hor = night_horizon_color * night_amount;
		zen = mix(zen, overcast_art(atmosphere_zenith) + night_zen, atmosphere);
		hor = mix(hor, overcast_art(atmosphere_horizon) + night_hor, atmosphere);
		vec3 lit_sun = mix(sun_color * atmosphere_light, moon_color, night_amount);
		sun_col = mix(sun_col, lit_sun, atmosphere);
		vec2 flat_air_sun = normalize(atmosphere_sun.xz + vec2(1e-5));
		float bearing = acos(clamp(dot(flat_eye, flat_air_sun), -1.0, 1.0)) / PI;
		vec3 air = texture(atmosphere_lut, vec2(bearing, 1.0 - sqrt(max(up, 0.0)))).rgb;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		air = overcast_to_linear(air);
#endif
		above_air = air + mix(night_hor, night_zen, pow(max(up, 0.0), horizon_falloff));
	}

	// Gradient. Above and below the horizon are the same expression mirrored, so the seam at
	// y=0 is exactly the horizon colour from both sides and never shows.
	vec3 above = mix(hor, zen, pow(clamp(up, 0.0, 1.0), horizon_falloff));
	// Below, the air's light is taken level, so it meets the ground at the horizon's colour here.
	above = mix(above, above_air, atmosphere);
	vec3 below = mix(up < 0.0 ? mix(hor, above_air, atmosphere) : hor, gnd, pow(clamp(-up, 0.0, 1.0), horizon_falloff));
	vec3 col = mix(below, above, step(0.0, up));
	// What a storm cloud is measured against: the sky it covers, not the cloud colour, which on a
	// moonlit sky is pale and would light the deck up at night.
	float sky_lum = dot(col, OVERCAST_LUMA);
	// An overcast sky is the horizon's grey, the grey rain's haze fades into, and lighter overhead
	// where the cloud is looked through at its thinnest.
	float storm_lum = mix(sky_lum, dot(hor, OVERCAST_LUMA) * (1.0 + 0.45 * smoothstep(0.0, 0.6, up)),
		smoothstep(0.0, 0.1, up));
	col = mix(col, vec3(storm_lum) * mix(0.55, 1.0, snowy), storm);

	// The air alone, for what the moon's dark side hides the stars with.
	vec3 air_col = col;
	// Stars before clouds and sun, so both occlude them.
	if (stars > 0.0 && storm < 1.0) {
		col += overcast_stars(eye_dir, stars, sky_lum) * (1.0 - storm);
	}

	storm_cover = 0.0;
	storm_body = 0.0;
	float sun_hidden = 0.0;
	// The sky lights the shadowed side of a cloud, so it takes the sky's colour rather than a grey.
	vec3 ambient = mix(zen, hor, 0.5);
	if (clouds && storm < 1.0) {
		if (up > 0.0) {
			vec4 higher = overcast_higher_cloud(eye_dir, cam, sun, col, ambient, cloud_col, sun_col);
			col = higher.rgb;
			sun_hidden = higher.a;
		}
		// Their feet run a little under the horizon, where a level's own ground edge often is.
		vec4 towers = overcast_towers(eye_dir, sun, ambient, cloud_col, sun_col, col);
		col = towers.rgb;
		sun_hidden = max(sun_hidden, towers.a);
	}
	float amount = overcast_cover;
	if (clouds && amount > 0.0) {
		float dist = cloud_distance(cam, eye_dir);
		vec2 wind = cloud_wind();
		vec2 layer = cloud_layer(cam, eye_dir, dist);
		vec2 cp = layer + wind;
		float toward = clamp(dot(eye_dir, sun) * 0.5 + 0.5, 0.0, 1.0);
		vec3 shadow_col = overcast_skylit(ambient) * 0.9;
		// Sunrise and sunset light the clouds in their full colour, and do for a while after the
		// sun is gone from the ground.
		vec3 lit_col = overcast_cloud_lit(cloud_col, sun_col, atmosphere_cloud_light);
		float far = smoothstep(1.5 * CLOUD_HEIGHT, cloud_horizon(cam), dist);
		// A low sun's light reaches the cloud toward it first, still gold, and the cloud far the other
		// way last, through more air: pink and dimmer.
		float sunset = (1.0 - smoothstep(0.0, 0.3, atmosphere_sun.y)) * (1.0 - night_amount) * atmosphere;
		float along = sun_bearing * far;
		lit_col *= mix(vec3(1.0), along > 0.0 ? vec3(1.15, 1.05, 0.8) : vec3(0.85, 0.62, 0.74), abs(along) * sunset);

		// Each path gives the tail what it uses: the cloud's colour and cover, its body for a storm
		// deck's mottling, how lit it is, and how much silver lining it still needs.
		vec3 lit;
		float cover;
		float shade;
		float rim;
		if (overcast_volumetric > 0.5) {
			float body = 0.0;
			vec4 v = vec4(0.0);
			if (up > -0.02) {   // below the horizon it would be marched and thrown away
				v = cloud_march(cam, eye_dir, dist, cp, sun, lit_col * 0.8, shadow_col * 0.95,
					ambient * 0.8 + lit_col * 0.35, frag, body);
			}
			lit = v.rgb;
			cover = v.a * smoothstep(-0.02, 0.06, up);
			storm_body = clamp(0.72 + 0.42 * body, 0.4, 1.3);
			if (storm > 0.0 && v.a > 0.0) {
				// A closed deck is all but one density to the march: its bellies come from the
				// flat layer's pattern.
				storm_body = mix(storm_body, storm_body_of(cloud_density(cp)), 0.75 * storm);
			}
			shade = clamp(dot(lit, OVERCAST_LUMA) / max(dot(lit_col, OVERCAST_LUMA), 1e-3), 0.0, 1.0);
			rim = 0.0;   // the march's phase lights thin edges itself
		} else {
			float n = cloud_density(cp);
			float edge = cloud_edge(amount);
			// Far off, the noise blurs toward its mean, which sits under the edge: thresholded as
			// it is overhead, the distant clouds would all vanish. Widened with the distance, a
			// blurred patch covers about what its clouds would have. And toward the horizon a line
			// of sight crosses more of the layer, so they bank up there rather than thin out.
			float spread = overcast_softness + far * 0.35;
			cover = smoothstep(edge - spread * 0.6 - far * 0.15, edge + spread * 1.2, n);
			cover = mix(cover, 1.0 - (1.0 - cover) * (1.0 - cover), far * 0.6);
			cover *= smoothstep(-0.01, 0.05, up);
			// Light from the sun loses itself in the cloud it crosses on the way (Beer's law: two
			// steps sunward through the layer) and in the cloud above us, so thick bases go grey.
			vec2 sun_step = normalize(sun.xz + vec2(1e-4));
			float thick = max(n - edge, 0.0);
			vec2 s1 = cp + sun_step * 0.25;
			vec2 s2 = cp + sun_step * 0.6;
			float sunward = max(cloud_spread(s1, cloud_shape(s1)) - edge, 0.0)
				+ max(cloud_spread(s2, cloud_shape(s2)) - edge, 0.0);
			// A low sun shines in under the layer, so the cloud overhead is not in its way.
			shade = exp(-(sunward * 2.5 + thick * mix(2.2, 0.5, sunset)));
			// Powder: a thin edge has had little chance to scatter light toward us, so with the sun
			// behind us a cloud's rim reads darker than its body.
			shade *= mix(1.0 - exp(-thick * 12.0 - 0.15), 1.0, toward);
			shade *= mix(0.6, 1.0, toward);
			// A flat layer only has undersides; low in the sky, though, a cloud is seen from the
			// side. Its face toward the sun is lit however deep it is: bright with the sun behind
			// us, grey into it. Its top (the far edge, seen this low) catches more than its base.
			float side = (1.0 - smoothstep(0.08, 0.5, up)) * smoothstep(-0.1, 0.15, sun.y);
			float top = clamp((n - cloud_shape(cp + flat_eye * 0.2)) * 3.0, -1.0, 1.0);
			float face = clamp(mix(1.0, 0.45, toward) + top * 0.3, 0.0, 1.0);
			shade = mix(shade, max(shade, face), side);
			lit = mix(shadow_col, lit_col, shade);
			storm_body = storm_body_of(n);
			rim = exp(-thick * 10.0);
		}
		// Stratus: one even grey, a little darker where it is thicker.
		float stratus = cloud_stratus();
		lit = mix(lit, mix(shadow_col, lit_col, 0.6) * mix(0.7, 1.0, shade), stratus * 0.8);
		// Storm cloud: grey, darker than the sky it closes over.
		vec3 heavy = vec3(storm_lum) * 0.7 * mix(0.6, 1.1, toward * toward) * storm_body * mix(0.6, 1.0, shade);
		// Its thin spots are no brighter than the sky they would open onto.
		heavy = min(heavy, col * 1.1);
		heavy = mix(heavy, vec3(storm_lum) * mix(0.9, 1.1, storm_body - 0.4), snowy);
		lit = mix(lit, heavy, storm);
		// Silver lining: thin cloud near the sun scatters it forward (Henyey-Greenstein, g 0.8,
		// scaled to 1 looking straight at the sun).
		lit += sun_col * hg_phase(dot(eye_dir, sun), 0.8) / 45.0 * rim * 1.2 * (1.0 - storm) * light_strength;
		// The air in front of distant cloud takes the blue out of its light and puts the sky's own
		// in: lit faces go cream, shaded ones the sky's colour. By day: a failing light has little
		// blue to give, and dark cloud would glow with it.
		vec3 through = exp(-far * mix(vec3(0.6), vec3(0.3, 0.55, 1.1), 1.0 - max(dusk_amount, night_amount)));
		lit = lit * through + col * (1.0 - through);
		// Rain in the air hides a deck long before the horizon does.
		lit = mix(lit, col, storm * (1.0 - smoothstep(0.03, 0.3, up)));
		storm_cover = cover * storm;
		col = mix(col, lit, cover);
		sun_hidden = max(sun_hidden, cover);
	}

	// Rain falling far off: dark curtains hung under the deck round the horizon, leaning with the
	// wind and drifting with the cloud, lost in the haze before they reach the ground.
	if (storm > 0.0 && clouds && up > 0.0 && up < 0.3) {
		vec2 round = (flat_eye + vec2(-flat_eye.y, flat_eye.x) * up * 1.2) * 1.6 + cloud_wind() * 0.5;
		float shafts = smoothstep(0.45, 0.75, cloud_tex(round) * 0.65 + cloud_tex(round * 2.7 + vec2(4.1, 1.9)) * 0.35);
		float under = smoothstep(0.0, 0.1, up) * (1.0 - smoothstep(0.12, 0.3, up));
		col *= 1.0 - 0.3 * shafts * under * storm * (1.0 - 0.6 * snowy);
	}

	// Sun last. Thin cloud dims it and thick cloud hides the disc; the glow leaks through.
	float sd = dot(eye_dir, sun);
	// The ground hides a sun or moon below the horizon.
	float sun_through = (1.0 - 0.95 * storm) * smoothstep(-0.02, 0.01, up);
	float unclouded = 1.0 - smoothstep(0.15, 0.75, sun_hidden);
	// The moon: a ball lit from one side, mottled with darker seas. Its dark side is the sky's
	// colour with the stars put out: just seen by night, lost by day.
	if (dot(eye_dir, moon_dir) > cos(moon_size * 1.1)) {
		vec3 mx = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
		vec3 my = cross(mx, moon_dir);
		vec2 q = vec2(dot(eye_dir, mx), dot(eye_dir, my)) / sin(moon_size);
		float r = length(q);
		float face = (1.0 - smoothstep(0.92, 1.0, r)) * sun_through * unclouded;
		vec3 normal = q.x * mx + q.y * my - moon_dir * sqrt(max(1.0 - r * r, 0.0));
		float lit = smoothstep(-0.03, 0.15, dot(normal, moon_lit_from));
		float seas = overcast_vnoise(q * 2.2 + 7.0) * 0.6 + overcast_vnoise(q * 5.0 + 3.0) * 0.4;
		vec3 ball = moon_color * mix(0.3, 0.6, smoothstep(0.35, 0.65, seas));
		col = mix(col, air_col + ball * 0.04, face);
		col += ball * lit * face * mix(0.45, moon_energy, night_amount);
	}
	// The sun's disc; past half night light_dir is the moon, drawn above.
	float disc = smoothstep(cos(sun_size * 1.4), cos(sun_size), sd) * (1.0 - step(0.5, night_amount));
	col += sun_col * disc * sun_energy * light_strength * sun_through * unclouded;
	col += sun_col * pow(max(sd, 0.0), sun_glow_exp) * sun_glow_energy * light_strength * sun_through
		* (1.0 - 0.6 * sun_hidden);
	// The halo is the air between us and the cloud, so it sits over cloud and sky alike. A moon
	// lights little of it.
	float horizon_band = pow(1.0 - abs(up), 8.0) * pow(sun_side, 3.0);
	vec3 halo_color = mix(sun_col, vec3(1.0), 0.4);
	col += halo_color * sun_halo_energy * mix(1.0, 0.25, night_amount) * light_strength * sun_through
		* (pow(max(sd, 0.0), sun_halo_exp) + 0.35 * horizon_band)
		// The air's own light already brightens round the sun, and takes most of this one's place.
		* (1.0 - 0.6 * atmosphere * (1.0 - night_amount));
	return overcast_shoulder(col);
}

// Lightning over `col` (overcast_flash), and over a dark storm deck, which a multiply cannot lift,
// its shape added outright.
vec3 overcast_sky_flash(vec3 col, vec3 eye_dir, float storm_cover, float storm_body) {
	if (flash_color == vec3(0.0)) {
		return col;
	}
	float toward = max(dot(eye_dir, normalize(flash_dir)), 0.0);
	return overcast_flash(col, eye_dir) + flash_color * storm_cover * storm_body * (0.25 + 0.9 * pow(toward, 2.0));
}

// A step of dither, so the wide smooth gradients do not band in 8 bits.
vec3 overcast_dither(vec3 col, vec2 frag) {
	return col + (overcast_hash12(frag) - 0.5) / 255.0;
}
#endif
