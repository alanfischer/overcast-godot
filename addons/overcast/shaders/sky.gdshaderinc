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
// Toward what lights the sky now, sun or moon (OvercastSky sets it); sun_dir while unset.
uniform vec3 light_dir = vec3(0.0);
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
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
// A thin, streaky layer high over the main one, drifting faster.
uniform float cirrus_amount : hint_range(0.0, 1.0) = 0.5;

uniform float star_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 star_color : source_color = vec3(1.0, 1.0, 1.0);

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
uniform float night_stars : hint_range(0.0, 1.0) = 0.7;

// Rain: 0 is the sky as configured, 1 a full storm — the deck closes over, its clouds go dark and
// heavy, the sky behind them greys, and sun, moon and stars are lost. Everything is relative to
// the sky's own colours, so a storm at night stays a night sky.
uniform float storm : hint_range(0.0, 1.0) = 0.0;

#include "res://addons/overcast/shaders/flash.gdshaderinc"
#include "res://addons/overcast/shaders/noise.gdshaderinc"
#include "res://addons/overcast/shaders/clouds.gdshaderinc"

const vec3 OVERCAST_LUMA = vec3(0.299, 0.587, 0.114);

// Volumetric clouds: cloud_volume_density in clouds.gdshaderinc, marched here.
// metres of slab a ray marches at most; past it is haze
#define MARCH_MAX (900.0 * CLOUD_M)
// metres per step, wanted
#define MARCH_STEP (12.0 * CLOUD_M)
const int MARCH_STEPS_MIN = 16;
const int MARCH_STEPS_MAX = 48;

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
	// Interleaved gradient noise: the step pattern turns into a fine grain instead of bands.
	float jitter = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
	float c = dot(eye_dir, sun);
	// Forward-scattering lobe for the silver lining, plus an even share for light that has
	// bounced around inside the cloud: the sunlit side is bright from any angle.
	float phase = min(mix(hg_phase(c, 0.65), hg_phase(c, -0.25), 0.35), 6.0) * 0.5 + 0.7;
	float field = cloud_field(cp);
	vec3 wind = cloud_volume_wind();
	float fair = cloud_fair();
	vec3 step_p = eye_dir * dt;
	vec2 step_cp = eye_dir.xz * dt * (overcast_scale / CLOUD_HEIGHT);
	vec3 p0 = cam + eye_dir * t0 + step_p * jitter;
	vec2 cp0 = cp + step_cp * jitter;
	vec3 scattered = vec3(0.0);
	float trans = 1.0;
	float weight = 0.0;
	for (int i = 0; i < steps; i++) {
		vec3 p = p0 + step_p * float(i);
		float weather = cloud_weather(cp0 + step_cp * float(i), field);
		if (weather <= 0.0) {
			continue;
		}
		float d = cloud_volume_density(p, cam, wind, fair, weather, true);
		if (d <= 0.0) {
			continue;
		}
		// Light march toward the sun, steps growing outward.
		float od = 0.0;
		float ls = 6.0 * CLOUD_M;
		vec3 lp = p;
		for (int j = 0; j < LIGHT_STEPS; j++) {
			lp += sun * ls;
			od += cloud_volume_density(lp, cam, wind, fair, weather, false) * ls;
			ls *= 1.8;
		}
		od *= EXTINCTION;
		// Beer's law, plus a long, weak tail standing in for light scattered many times over.
		float light = exp(-od) + 0.35 * exp(-od * 0.1);
		float powder = 1.0 - exp(-d * dt * EXTINCTION * 2.0);
		vec3 amb = mix(base_col, top_col, clamp(cloud_height_frac(p, cam), 0.0, 1.0));
		vec3 radiance = sun_col * light * phase * mix(0.5, 1.0, powder) + amb;
		float absorbed = 1.0 - exp(-d * EXTINCTION * dt);
		scattered += trans * radiance * absorbed;
		weight += trans * absorbed * d;
		trans *= 1.0 - absorbed;
		if (trans < 0.02) {
			break;
		}
	}
	float alpha = 1.0 - trans;
	body = weight / max(alpha, 1e-4);
	return vec4(scattered / max(alpha, 1e-4), alpha);
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
	float sun_side = max(dot(flat_eye, flat_sun), 0.0);
	// The day's colours at this time of day.
	float glow = dusk_amount * (0.45 + 0.55 * sun_side);
	vec3 zen = mix(zenith_color * mix(1.0, 0.6, dusk_amount), night_zenith_color, night_amount);
	vec3 hor = mix(mix(horizon_color, dusk_color, glow * 0.8), night_horizon_color, night_amount);
	vec3 gnd = ground_color * mix(1.0, 0.15, night_amount);
	vec3 sun_col = mix(mix(sun_color, dusk_color * 1.3, dusk_amount), moon_color, night_amount);
	vec3 cloud_col = mix(cloud_color, mix(night_horizon_color, vec3(1.0), 0.35), night_amount);
	float stars = max(star_amount, night_stars * night_amount);

	// Gradient. Above and below the horizon are the same expression mirrored, so the seam at
	// y=0 is exactly the horizon colour from both sides and never shows.
	vec3 above = mix(hor, zen, pow(clamp(up, 0.0, 1.0), horizon_falloff));
	vec3 below = mix(hor, gnd, pow(clamp(-up, 0.0, 1.0), horizon_falloff));
	vec3 col = mix(below, above, step(0.0, up));
	// What a storm cloud is measured against: the sky it covers, not the cloud colour, which on a
	// moonlit sky is pale and would light the deck up at night.
	float sky_lum = dot(col, OVERCAST_LUMA);
	col = mix(col, vec3(sky_lum) * 0.55, storm);

	// Stars before clouds and sun, so both occlude them.
	if (stars > 0.0) {
		vec3 sp = eye_dir * 320.0;
		vec3 cell = floor(sp);
		float h = overcast_hash13(cell);
		// star_amount is a density, but the useful range is tiny — one cell in a few hundred.
		float lit = step(1.0 - stars * 0.035, h);
		float d = length(fract(sp) - 0.5);
		float twinkle = 0.65 + 0.35 * sin(TIME * 1.7 + h * 217.0);
		col += star_color * smoothstep(0.42, 0.0, d) * lit * twinkle * (1.0 - storm);
	}

	storm_cover = 0.0;
	storm_body = 0.0;
	float sun_hidden = 0.0;
	float amount = overcast_cover;
	if (clouds && amount > 0.0) {
		float dist = cloud_distance(cam, eye_dir);
		vec2 wind = cloud_wind();
		vec2 layer = cloud_layer(cam, eye_dir, dist);
		vec2 cp = layer + wind;
		float toward = clamp(dot(eye_dir, sun) * 0.5 + 0.5, 0.0, 1.0);
		// The sky lights the shadowed side, so it takes the sky's colour rather than a grey.
		vec3 ambient = mix(zen, hor, 0.5);
		vec3 shadow_col = mix(vec3(dot(ambient, OVERCAST_LUMA)), ambient, 0.6) * 0.9;
		vec3 lit_col = cloud_col * mix(vec3(1.0), sun_col, 0.5);
		float far = smoothstep(1.5 * CLOUD_HEIGHT, cloud_horizon(cam), dist);

		if (cirrus_amount > 0.0 && cloud_amount > 0.0) {
			vec2 hp = layer * 0.6;
			float c = cloud_tex(vec2(hp.x * 0.25, hp.y) + wind * 2.5 + vec2(3.7, 1.3));
			float ci = smoothstep(0.55, 0.85, c) * cirrus_amount * 0.45 * (1.0 - storm) * (1.0 - far);
			col = mix(col, mix(ambient, lit_col, 0.7), ci * smoothstep(0.0, 0.15, up));
		}

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
			shade = clamp(dot(lit, OVERCAST_LUMA) / max(dot(lit_col, OVERCAST_LUMA), 1e-3), 0.0, 1.0);
			rim = 0.0;   // the march's phase lights thin edges itself
		} else {
			float n = cloud_density(cp);
			float edge = cloud_edge(amount);
			cover = cloud_coverage(n, amount);
			cover *= smoothstep(-0.02, 0.12, up) * (1.0 - 0.5 * far);
			// Light from the sun loses itself in the cloud it crosses on the way (Beer's law: two
			// steps sunward through the layer) and in the cloud above us, so thick bases go grey.
			vec2 sun_step = normalize(sun.xz + vec2(1e-4));
			float thick = max(n - edge, 0.0);
			float sunward = max(cloud_shape(cp + sun_step * 0.25) - edge, 0.0)
				+ max(cloud_shape(cp + sun_step * 0.6) - edge, 0.0);
			shade = exp(-(sunward * 2.5 + thick * 2.2));
			// Powder: a thin edge has had little chance to scatter light toward us, so with the sun
			// behind us a cloud's rim reads darker than its body.
			shade *= mix(1.0 - exp(-thick * 12.0 - 0.15), 1.0, toward);
			lit = mix(shadow_col, lit_col, shade * mix(0.6, 1.0, toward));
			// Mottled by the same noise that shaped it, so a full storm deck still has bodies to it
			// rather than one flat lid.
			storm_body = clamp(0.55 + 0.7 * n, 0.4, 1.3);
			rim = exp(-thick * 10.0);
		}
		// Storm cloud: grey, darker than the sky it closes over.
		vec3 heavy = vec3(sky_lum) * mix(0.6, 1.1, toward * toward) * storm_body * mix(0.8, 1.0, shade);
		lit = mix(lit, heavy, storm);
		// Silver lining: thin cloud near the sun scatters it forward (Henyey-Greenstein, g 0.8,
		// scaled to 1 looking straight at the sun).
		lit += sun_col * hg_phase(dot(eye_dir, sun), 0.8) / 45.0 * rim * 1.2 * (1.0 - storm);
		// Distant cloud sinks into the horizon haze.
		lit = mix(lit, col, far * 0.5);
		storm_cover = cover * storm;
		col = mix(col, lit, cover);
		sun_hidden = cover;
	}

	// Sun last. Thin cloud dims it and thick cloud hides the disc; the glow leaks through.
	float sd = dot(eye_dir, sun);
	float disc = smoothstep(cos(sun_size * 1.4), cos(sun_size), sd);
	// The ground hides a sun or moon below the horizon.
	float sun_through = (1.0 - 0.95 * storm) * smoothstep(-0.02, 0.01, up);
	float disc_energy = mix(sun_energy, moon_energy, night_amount);
	col += sun_col * disc * disc_energy * sun_through * (1.0 - smoothstep(0.15, 0.75, sun_hidden));
	col += sun_col * pow(max(sd, 0.0), sun_glow_exp) * sun_glow_energy * sun_through * (1.0 - 0.6 * sun_hidden);
	// The halo is the air between us and the cloud, so it sits over cloud and sky alike. A moon
	// lights little of it.
	float horizon_band = pow(1.0 - abs(up), 8.0) * pow(sun_side, 3.0);
	vec3 halo_color = mix(sun_col, vec3(1.0), 0.4);
	col += halo_color * sun_halo_energy * mix(1.0, 0.25, night_amount) * sun_through
		* (pow(max(sd, 0.0), sun_halo_exp) + 0.35 * horizon_band);
	return col;
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
