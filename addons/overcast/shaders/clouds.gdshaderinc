#ifndef OVERCAST_CLOUDS_GDSHADERINC
#define OVERCAST_CLOUDS_GDSHADERINC
// The cloud layer, in the world: a shell overcast_height over the scene's origin. The sky traces the
// view ray to it (sky.gdshaderinc) and anything lit includes this and traces toward the sun
// (cloud_sunlight), so the cloud in front of the sun is the one whose shadow you are standing in.
// Global uniforms, one sky at a time: OvercastClouds sets them, and the plugin declares them.

// Tiling noise (OvercastClouds.noise): perlin fbm in r, worley fbm in g (distance: 0 at a cell's
// centre). One tile spans CLOUD_TILE noise units.
global uniform sampler2D overcast_noise : filter_linear_mipmap, repeat_enable;
global uniform float overcast_height;    // metres over the origin
global uniform float overcast_scale;     // noise units per overcast_height
global uniform vec2 overcast_cloud_drift;      // noise units the wind has carried the pattern
global uniform float overcast_softness;
global uniform float overcast_cover;     // how much of the sky is cloud, storm included
global uniform float overcast_shadow;    // how much of the sky's share a cloud takes off; 0 for none
global uniform float overcast_veil;      // how much the higher cloud takes off it, evenly
global uniform float overcast_sheet;     // 0 heaped cumulus, 0.5 stratocumulus, 1 a stratus sheet
#ifndef OVERCAST_SUN_DIR  // snow.gdshaderinc reads it too
#define OVERCAST_SUN_DIR
global uniform vec3 overcast_sun_dir;    // unit, toward the sun
#endif
global uniform float overcast_volumetric; // 1 when the sky ray-marches its clouds
// Where the clouds really are (OvercastSky.set_cover_map): a map, white where cloudy, black where
// clear and mid grey where it has no say, of the real ground round the scene's origin, north up.
// frame: east's world direction (xz), the real metres the map spans, the sky's world_scale.
// place: the drift when it was laid, and its weight (0 off). _was_place: the one before, fading
// out. Both are in the one texture, the laid on the left and the one before on the right: a
// sampler apiece would put a world shader past Compatibility's sixteen.
global uniform sampler2D overcast_cover_map : filter_linear, repeat_disable;
global uniform vec4 overcast_cover_map_frame;
global uniform vec4 overcast_cover_map_place;
global uniform vec4 overcast_cover_map_was_place;
const float CLOUD_TILE = 12.0;
// Every length below is tuned at a height of 100 m and scales with it, so a higher layer looks
// the same, only bigger.
#define CLOUD_HEIGHT overcast_height
#define CLOUD_M (overcast_height / 100.0)
// The shell curves like a planet this many times its height across, so it meets the horizon at a
// finite distance instead of smearing out to infinity like a flat plane.
const float CLOUD_EARTH = 12.0;
const float CLOUD_BILLOW = 0.5;
// Clouds gather into fields with clear sky between: a slow, broad swing in density that drifts
// against the wind, so clouds grow and thin out rather than only sliding past. Fades out as a
// storm closes the sky over.
const float CLOUD_FIELDS = 0.32;
const float CLOUD_FIELD_SCALE = 0.13;

vec2 cloud_tex2(vec2 p) {
	return texture(overcast_noise, p / CLOUD_TILE).rg;
}

float cloud_tex(vec2 p) {
	return cloud_tex2(p).r;
}

// 1 for fair-weather cumulus, 0 once a storm has closed the sky into one flat deck.
float cloud_fair() {
	return (1.0 - smoothstep(0.7, 0.95, overcast_cover)) * (1.0 - 0.8 * overcast_sheet);
}

// How far toward stratus the layer has spread: 0 up to stratocumulus, 1 at a full sheet.
float cloud_stratus() {
	return max(overcast_sheet * 2.0 - 1.0, 0.0);
}

// The layer spread out (overcast_sheet) from density `n` at noise point cp: toward
// stratocumulus, rolls of cells packed side by side across the wind with thin gaps between;
// toward stratus, broad smooth patches that close into one even sheet.
float cloud_spread(vec2 cp, float n) {
	if (overcast_sheet <= 0.0) {
		return n;
	}
	vec2 t = cloud_tex2(vec2(cp.x * 0.5, cp.y * 0.9) + vec2(4.2, 1.1));
	float cells = 0.85 - t.g * 0.75 + (n - 0.5) * 0.3;
	float even = 0.62 + (cloud_tex(cp * 0.12 + vec2(1.3, 5.9)) - 0.5) * 0.7 + (n - 0.5) * 0.06;
	return mix(mix(n, cells, min(overcast_sheet * 2.0, 1.0)), even, cloud_stratus());
}

// Perlin swelling into round billows: worley cells push the outline out into lobes, so a cloud's
// edge is cauliflower rather than smoke.
float cloud_shape(vec2 p) {
	vec2 t = cloud_tex2(p);
	return t.r + (0.5 - t.g) * CLOUD_BILLOW * mix(0.3, 1.0, cloud_fair());
}

// Metres from `origin` along unit `dir` to the shell `height` over the origin, on the curve the
// cloud shell's planet gives it.
float cloud_distance_to(vec3 origin, vec3 dir, float height) {
	float r = CLOUD_EARTH * CLOUD_HEIGHT;
	float h = max(height - origin.y, 1.0);
	float b = r * dir.y;
	return -b + sqrt(b * b + 2.0 * r * h + h * h);
}

// Metres from `origin` along unit `dir` to the cloud shell.
float cloud_distance(vec3 origin, vec3 dir) {
	return cloud_distance_to(origin, dir, CLOUD_HEIGHT);
}

// cloud_distance_to looking at the horizon.
float cloud_horizon_at(vec3 origin, float height) {
	return cloud_distance_to(origin, vec3(1.0, 0.0, 0.0), height);
}

float cloud_horizon(vec3 origin) {
	return cloud_horizon_at(origin, CLOUD_HEIGHT);
}

vec2 cloud_wind() {
	return overcast_cloud_drift;
}

// As cloud_layer, for a shell `height` over the origin, scaled as the layer is by its own.
vec2 cloud_layer_at(vec3 origin, vec3 dir, float dist, float height) {
	return (origin.xz + dir.xz * dist) * (overcast_scale / height);
}

// Noise coordinates of where the ray meets the shell, before the wind moves the pattern.
vec2 cloud_layer(vec3 origin, vec3 dir, float dist) {
	return cloud_layer_at(origin, dir, dist, CLOUD_HEIGHT);
}

// How far the density moves per unit of amount the cover map adds: cloud_edge's slope, so the
// low layer there looks as at the amount the map sees.
const float CLOUD_MAP_FIELD = 0.73;
const float EARTH_KM = 6371.0;

// Where on a cover map a shell `height` over the origin is met at world point w (xz, the wind's
// carrying since the map was laid taken off), and how far inside the map that is (0 off it) in
// .z. The shell curls down to the horizon a few heights out, where the real layer runs on for a
// hundred km or more: a point is looked up where the real cloud seen at its elevation and bearing
// would be.
vec3 cloud_map_uv(vec2 w, float height) {
	float rho = length(w);
	float r = CLOUD_EARTH * CLOUD_HEIGHT;
	float y = sqrt(max((r + height) * (r + height) - rho * rho, 0.0)) - r;
	// The sine of its elevation, and kilometres along the ground to the real layer seen there,
	// the stable form.
	float s = y * inversesqrt(y * y + max(rho * rho, 1e-6));
	float h = height / overcast_cover_map_frame.w * 0.001;
	float d = (2.0 * EARTH_KM * h + h * h)
		/ (sqrt(EARTH_KM * EARTH_KM * s * s + 2.0 * EARTH_KM * h + h * h) + EARTH_KM * s);
	vec2 real = rho > 1e-3 ? w / rho * d * 1000.0 : vec2(0.0);
	vec2 east = overcast_cover_map_frame.xy;
	vec2 north = vec2(east.y, -east.x);
	vec2 uv = 0.5 + vec2(dot(real, east), -dot(real, north)) / overcast_cover_map_frame.z;
	return vec3(uv, 1.0 - smoothstep(0.42, 0.5, max(abs(uv.x - 0.5), abs(uv.y - 0.5))));
}

// The cover maps' tops, real km, at green 1.
const float COVER_TOP_KM = 16.0;

// What one cover map, laid at `place` in `half` of the texture (0 left, 1 right), sees of a layer
// `height` up at noise point q, as (cloud seen there times say, say). A top at the layer's height
// is that layer's cloud; one well above it hides it, so the map has no say over what lies under.
vec2 cloud_map_one(float half, vec4 place, vec2 q, float height) {
	if (place.z <= 0.0) {
		return vec2(0.0);
	}
	vec3 at = cloud_map_uv((q - place.xy) * (CLOUD_HEIGHT / overcast_scale), height);
	vec2 uv = clamp(at.xy, 0.0, 1.0);
	vec4 m = textureLod(overcast_cover_map, vec2((uv.x + half) * 0.5, uv.y), 0.0);
	float rise = log(max(m.g * COVER_TOP_KM, 0.05) / max(height / overcast_cover_map_frame.w * 0.001, 0.05));
	float say = m.a * at.z * place.z * (1.0 - m.r * smoothstep(0.4, 0.8, rise));
	return vec2(m.r * (1.0 - smoothstep(0.4, 0.8, abs(rise))), 1.0) * say;
}

// How much of a layer `height` up stands at noise point q (as cp: the cloud layer's, the wind
// in), `amount` of it over the whole sky: the cover maps' where they see it, the laid one and the
// one before as it fades.
float cloud_map_amount(vec2 q, float height, float amount) {
	vec2 seen = cloud_map_one(0.0, overcast_cover_map_place, q, height)
		+ cloud_map_one(1.0, overcast_cover_map_was_place, q, height);
	return mix(amount, seen.x / max(seen.y, 1e-4), min(seen.y, 1.0));
}

// A higher layer's kind (`sheet`, its own) where a cover map has made `amount` of what the sky
// gave as `own`: what the map adds is a sheet, as a cold shield 2 km pixels can see mostly is.
float cloud_map_sheet(float amount, float own, float sheet) {
	return mix(sheet, 1.0, clamp((amount - own) / max(amount, 1e-3), 0.0, 1.0));
}

// Whether a cover map is laid: a layer it sees may be one the sky has none of.
bool cloud_map_laid() {
	return overcast_cover_map_place.z + overcast_cover_map_was_place.z > 0.0;
}

// The broad swing that gathers clouds into fields (CLOUD_FIELDS), at noise point cp: the cover
// map's where it has one.
float cloud_field(vec2 cp) {
	float swing = (cloud_tex(cp * CLOUD_FIELD_SCALE + vec2(2.1, 8.7) - cloud_wind() * 0.6) - 0.5)
		* CLOUD_FIELDS * cloud_fair();
	if (!cloud_map_laid()) {
		return swing;
	}
	// Where the map leaves none at all, none: at amount 0 the swing can still reach the edge.
	float amount = cloud_map_amount(cp, CLOUD_HEIGHT, overcast_cover);
	return swing + (amount - overcast_cover) * CLOUD_MAP_FIELD - (1.0 - smoothstep(0.0, 0.05, amount));
}

// Cloud density at `cp`, which comes back moved to where the shape was sampled (billows are the
// pattern pushed around by a coarser copy of itself; fine detail eats into the edges).
float cloud_density(inout vec2 cp) {
	vec2 wind = cloud_wind();
	vec2 warp = vec2(cloud_tex(cp * 0.5 + vec2(0.31, 0.17) - wind * 0.4),
		cloud_tex(cp * 0.5 + vec2(5.71, 2.53) + wind * 0.3)) - 0.5;
	cp += warp * 0.35;
	return cloud_spread(cp, cloud_shape(cp) + (0.5 - cloud_tex2(cp * 3.1 + vec2(7.3, 2.9)).g)
		* mix(0.08, 0.2, cloud_fair()) + cloud_field(cp));
}

// The density a cloud starts at. `amount` drives coverage, not opacity: at 0 the threshold sits
// above anything the noise returns, so no cloud at all.
float cloud_edge(float amount) {
	return mix(0.95, 0.22, amount);
}

// How much of the sky a cloud of density `n` covers, 0 to 1.
float cloud_coverage(float n, float amount) {
	float edge = cloud_edge(amount);
	return smoothstep(edge - overcast_softness * 0.6, edge + overcast_softness * 1.2, n);
}

// The volumetric clouds' weather map: how much cloud stands over noise point cp, 0 to 1. Smooth
// and broad, as the 3D noise carves the clouds themselves out of it.
float cloud_weather(vec2 cp, float field) {
	float n = cloud_spread(cp, cloud_tex(cp * 0.45) + field);
	float edge = mix(0.75, 0.25, overcast_cover);
	return smoothstep(edge - 0.15, edge + 0.25, n);
}

// Volumetric clouds (OvercastClouds.set_volumetric): a slab CLOUD_THICK deep over the
// shell, carved from 3D noise — perlin-worley in r, finer worley in g (OvercastClouds.volume).
global uniform sampler3D overcast_volume : filter_linear, repeat_enable;
#define CLOUD_THICK (60.0 * CLOUD_M)
// metres one tile of overcast_volume spans
#define VOLUME_TILE (360.0 * CLOUD_M)
#define DETAIL_TILE (70.0 * CLOUD_M)
const int LIGHT_STEPS = 4;
// per metre at full density
#define EXTINCTION (0.3 / CLOUD_M)

// How far up the slab p is, 0 at its base and 1 at its top, seen from `viewer`: on the curve
// cloud_distance_to puts the shells on, a planet under the viewer. Measured flat, a distant cloud
// would sink out of the slab.
float cloud_height_frac(vec3 p, vec3 viewer) {
	float r = CLOUD_EARTH * CLOUD_HEIGHT;
	return (length(p - viewer + vec3(0.0, r, 0.0)) - r + viewer.y - CLOUD_HEIGHT) / CLOUD_THICK;
}

// cloud_wind in metres, for the volume.
vec3 cloud_volume_wind() {
	vec2 w = cloud_wind() * (CLOUD_HEIGHT / overcast_scale);
	return vec3(w.x, 0.0, w.y);
}

// The cloud's bulk at world point p, 0 to 1, before detail erodes its edges: what the light on its
// way in is dimmed by. `weather` is cloud_weather where p's column meets the shell; `wind` and
// `fair` are cloud_volume_wind() and cloud_fair(), taken once by the caller.
float cloud_volume_bulk(vec3 p, vec3 viewer, vec3 wind, float fair, float weather) {
	float hf = cloud_height_frac(p, viewer);
	// Flat bases, domed tops that rise with the weather: big clouds tower, thin ones stay low.
	// A storm flattens them into one deck.
	float top = mix(mix(0.3, 1.0, weather), 0.8, 1.0 - fair);
	float rise = clamp(hf / top, 0.0, 1.0);
	float cov = weather * smoothstep(0.0, 0.08, hf) * (1.0 - rise * rise * mix(1.0, 0.3, 1.0 - fair));
	if (cov <= 0.0) {
		return 0.0;
	}
	float s = texture(overcast_volume, (p + wind) / VOLUME_TILE).r;
	return clamp((s - (1.0 - cov)) / max(cov, 1e-3), 0.0, 1.0) * cov;
}

// Cloud density at world point p as the eye meets it, 0 to 1: cloud_volume_bulk with its edges
// eroded, and what is left twice as dense. `crease` comes back as how deep between billows p is,
// 0 to 1.
float cloud_volume_density(vec3 p, vec3 viewer, vec3 wind, float fair, float weather, out float crease) {
	crease = 0.0;
	float d = cloud_volume_bulk(p, viewer, wind, fair, weather);
	if (d <= 0.0) {
		return 0.0;
	}
	float e = texture(overcast_volume, (p + wind * 1.3) / DETAIL_TILE).g;
	// Wispy at the base, billowed higher up.
	e = mix(1.0 - e, e, clamp(cloud_height_frac(p, viewer) * 4.0, 0.0, 1.0));
	crease = smoothstep(0.45, 0.9, e);
	return clamp(2.0 * (d - e * 0.5) / (1.0 - e * 0.5), 0.0, 1.0);
}

// The multiplier on the sky's share of the light at world point p: 1 in sun, less under cloud.
float cloud_sunlight(vec3 p) {
	float veiled = 1.0 - overcast_veil;
	if (overcast_shadow <= 0.0) {
		return veiled;
	}
	if (overcast_volumetric > 0.5) {
		// One sample a third of the way up the slab, through the sun's slant of it.
		float dq = cloud_distance_to(p, overcast_sun_dir, CLOUD_HEIGHT + CLOUD_THICK * 0.35);
		vec2 qp = cloud_layer(p, overcast_sun_dir, dq) + cloud_wind();
		float d = cloud_volume_bulk(p + overcast_sun_dir * dq, p, cloud_volume_wind(), cloud_fair(),
			cloud_weather(qp, cloud_field(qp)));
		float depth = d * CLOUD_THICK * 0.5 / max(overcast_sun_dir.y, 0.2) * EXTINCTION;
		return veiled * (1.0 - overcast_shadow * (1.0 - exp(-depth)));
	}
	vec2 cp = cloud_layer(p, overcast_sun_dir, cloud_distance(p, overcast_sun_dir)) + cloud_wind();
	return veiled * (1.0 - overcast_shadow * cloud_coverage(cloud_density(cp), overcast_cover));
}
#endif
