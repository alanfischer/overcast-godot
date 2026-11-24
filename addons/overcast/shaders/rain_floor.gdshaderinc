#ifndef OVERCAST_RAIN_FLOOR_GDSHADERINC
#define OVERCAST_RAIN_FLOOR_GDSHADERINC
// Where rain stops: per column, the height rain falls to before something catches it (a roof, the
// ground), in a texture whose min-X/min-Z corner sits at overcast_rain_floor_origin. Globals that
// OvercastWeather sets (overcast_globals.gd).
global uniform bool overcast_has_rain_floor;  // without one, rain falls everywhere
global uniform bool overcast_rain_beyond_floor;  // whether it falls off the floor's edges
global uniform sampler2D overcast_rain_floor : filter_nearest;
global uniform vec3 overcast_rain_floor_origin;
global uniform vec2 overcast_rain_floor_size;
global uniform float overcast_rain_top;  // no rain above this
// Metres the wind carries rain sideways per metre it falls (OvercastWeather, from its steady wind).
global uniform vec2 overcast_rain_slant;
// What lies on the ground comes round to a new wind gradually: it is wet (or snowed on) as for the
// slant in xy, turning to that in zw by overcast_ground_shift, 0 to 1.
global uniform vec4 overcast_ground_slant;
global uniform float overcast_ground_shift;

// The open air under what catches rain, per column: r the underside of the roof, g the ground under
// it; none where they are equal (OvercastRainFloor.under). Unset, there is none anywhere, and all
// that is under the floor is solid. b the share of the cell the floor's height covers, a the height
// rain falls to on the rest.
global uniform sampler2D overcast_rain_under : filter_nearest;

// Wind-driven rain comes down a slanted line. It reaches a point if, walking up that line toward
// the wind, it meets nothing solid: under a roof it may blow, in past its edge, but not down
// through it. Walked in RAIN_SLANT_TAPS steps up to RAIN_SLANT_UP metres up, and never more than
// RAIN_SLANT_REACH sideways; where the steps fall wanders over the ground, so the edge of a wind
// shadow is ragged, as a drift's is, not stepped. Under cover, it thins to 1/e for every
// RAIN_SHELTER_DEPTH metres it had to blow in from the edge, and further in than the walk reaches
// none comes at all.
// Through an open shelter and out the other side it loses nothing: only the roof stops it.
// The steps are closer than a rain floor cell (at its default 0.5 m), so a wall one cell thick is
// not stepped over.
const int RAIN_SLANT_TAPS = 7;
const float RAIN_SLANT_UP = 5.0;
const float RAIN_SLANT_REACH = 3.0;
const float RAIN_SHELTER_DEPTH = 3.0;
// A surface's walk (rain_slant_surface) lets rain fade in over the top RAIN_EDGE metres of what it
// would stop on, so the edge of a wind shadow is a smooth line and not a staircase of cells.
const float RAIN_EDGE = 0.15;
#include "res://addons/overcast/shaders/noise.gdshaderinc"

// Where world point p falls on the rain floor.
vec2 rain_floor_uv(vec3 p) {
	return (p.xz - overcast_rain_floor_origin.xz) / overcast_rain_floor_size;
}

bool rain_floor_covers(vec2 uv) {
	return uv.x >= 0.0 && uv.y >= 0.0 && uv.x < 1.0 && uv.y < 1.0;
}

// Whether nothing is straight above world point p to catch rain: everywhere with no floor, and off
// it only with overcast_rain_beyond_floor. Wind aside: for the haze's march, which takes many.
bool rain_open_above(vec3 p) {
	if (!overcast_has_rain_floor) {
		return true;
	}
	vec2 uv = rain_floor_uv(p);
	if (!rain_floor_covers(uv)) {
		return overcast_rain_beyond_floor;
	}
	return p.y > textureLod(overcast_rain_floor, uv, 0.0).r;
}

// The cell of a field `res` cells across whose middle is the corner of the four around uv, and in
// `f` where uv is between their middles; rain_cell steps to each of the four, rain_bilerp blends
// their values.
ivec2 rain_quad(vec2 uv, ivec2 res, out vec2 f) {
	vec2 texel = uv * vec2(res) - 0.5;
	f = fract(texel);
	return ivec2(floor(texel));
}

ivec2 rain_cell(ivec2 cell, int i, ivec2 res) {
	return clamp(cell + ivec2(i % 2, i / 2), ivec2(0), res - 1);
}

float rain_bilerp(vec4 v, vec2 f) {
	return mix(mix(v.x, v.y, f.x), mix(v.z, v.w, f.x), f.y);
}

// A field laid out as the rain floor is (its own texture, or the snow's or the ice's) at uv,
// blended between the four cells around it.
float rain_floor_blend(sampler2D field, vec2 uv) {
	ivec2 res = textureSize(field, 0);
	vec2 f;
	ivec2 cell = rain_quad(uv, res, f);
	vec4 h;
	for (int i = 0; i < 4; i++) {
		h[i] = texelFetch(field, rain_cell(cell, i, res), 0).r;
	}
	return rain_bilerp(h, f);
}

// Where q is for rain slanting through it: in the open (over whatever catches rain there), in the
// air under cover, or in something solid. `roofed`: whether q's column has air under cover at all.
const int RAIN_OPEN = 0;
const int RAIN_SHELTERED = 1;
const int RAIN_SOLID = 2;
int rain_place(vec3 q, out bool roofed) {
	roofed = false;
	vec2 uv = rain_floor_uv(q);
	if (!rain_floor_covers(uv)) {
		return RAIN_OPEN;  // the slant only adds what is there to catch it
	}
	vec2 gap = textureLod(overcast_rain_under, uv, 0.0).rg;
	roofed = gap.x > gap.y;
	if (q.y > textureLod(overcast_rain_floor, uv, 0.0).r) {
		return RAIN_OPEN;
	}
	return q.y > gap.y && q.y < gap.x ? RAIN_SHELTERED : RAIN_SOLID;
}

// Whether the slanted line from `a` (in the air under cover) to `b` (in the open) came out past the
// roof's edge rather than up through the roof: looked at between them, where it would be in the
// roof if it went through it.
bool rain_slant_exits(vec3 a, vec3 b) {
	for (int i = 1; i <= 2; i++) {
		bool roofed;
		int at = rain_place(mix(a, b, float(i) / 3.0), roofed);
		if (at == RAIN_SOLID || (at == RAIN_OPEN && roofed)) {
			return false;
		}
	}
	return true;
}

// A rain floor cell's size in metres, x and z.
vec2 rain_floor_cell() {
	return overcast_rain_floor_size / vec2(max(textureSize(overcast_rain_floor, 0), ivec2(1)));
}

// Cubic B-spline weights for the four cells around a point `t` (0 to 1) past the second.
vec4 rain_bspline(float t) {
	float s = 1.0 - t;
	return vec4(s * s * s, 4.0 - 3.0 * t * t * (2.0 - t), 4.0 - 3.0 * s * s * (2.0 - s), t * t * t)
		/ 6.0;
}

// 1 where nothing straight above world point p (on the floor) catches rain, 0 under cover, all of
// it `ramp` per metre over where rain stops. Each cell reaches as far as the share of it under its
// height, and the rest down to the height under that (overcast_rain_under's b and a); the sixteen
// cells around p are blended by a cubic B-spline and the result sharpened, so the edge of what
// covers p runs straight along a roof at any angle to the cells, not as a staircase.
float rain_open_spline(vec3 p, float ramp) {
	ivec2 res = textureSize(overcast_rain_floor, 0);
	vec2 f;
	ivec2 cell = rain_quad(rain_floor_uv(p), res, f) - 1;
	vec4 wx = rain_bspline(f.x);
	vec4 wy = rain_bspline(f.y);
	float open = 0.0;
	for (int j = 0; j < 4; j++) {
		vec4 reach;
		for (int i = 0; i < 4; i++) {
			ivec2 c = clamp(cell + ivec2(i, j), ivec2(0), res - 1);
			vec2 share = texelFetch(overcast_rain_under, c, 0).ba;
			float high = clamp((p.y - texelFetch(overcast_rain_floor, c, 0).r) * ramp + 1.0, 0.0, 1.0);
			reach[i] = mix(clamp((p.y - share.y) * ramp + 1.0, 0.0, 1.0), high, share.x);
		}
		open += wy[j] * dot(wx, reach);
	}
	return smoothstep(0.25, 0.75, open);
}

// How much of the rain slanting in on the wind reaches p in the air, 0 to 1, by the walk described
// above. Surfaces have rain_slant_surface.
float rain_slant_reach(vec3 p, vec2 slant) {
	bool roofed;
	int was = rain_place(p, roofed);
	if (was == RAIN_SOLID) {
		return 0.0;
	}
	float len = length(slant);
	float up = min(RAIN_SLANT_UP, RAIN_SLANT_REACH / max(len, 1e-4));
	float wander = 0.15 + 0.7 * overcast_vnoise(p.xz * 1.3);
	float under = 0.0;  // metres sideways it blew in under cover to reach p
	bool inside = was == RAIN_SHELTERED;  // p is under cover, and the walk has not come out yet
	vec3 last = p;
	float last_s = 0.0;
	for (int i = 0; i < RAIN_SLANT_TAPS; i++) {
		float s = up * (float(i) + wander) / float(RAIN_SLANT_TAPS);
		vec3 q = p + vec3(-slant.x * s, s, -slant.y * s);
		int now = rain_place(q, roofed);
		if (now == RAIN_SOLID) {
			return 0.0;
		}
		if (was == RAIN_SHELTERED && now == RAIN_OPEN && (roofed || !rain_slant_exits(last, q))) {
			return 0.0;  // down through the roof
		}
		if (inside) {
			under += (s - last_s) * len;
			inside = now == RAIN_SHELTERED;
		}
		was = now;
		last = q;
		last_s = s;
	}
	if (inside) {
		return 0.0;  // under cover as far as the wind carries it: none comes this far in
	}
	return exp(-under / RAIN_SHELTER_DEPTH);
}

// Around world point q, blended between its four cells, the height of the solid under it: the
// ground under a roof, not the roof (`ground`); of those four that are roofs, with air under them,
// the highest one's top (x) and underside (y), or -1e30 with none (`roof`); and how much q is in
// the air under a roof, on the share of each cell roofed (`roofed`). Over all four, there is
// nothing: ground and roof -1e30, roofed 0.
void rain_cells(vec3 q, out float ground, out vec2 roof, out float roofed) {
	ivec2 res = textureSize(overcast_rain_floor, 0);
	vec2 f;
	ivec2 cell = rain_quad(rain_floor_uv(q), res, f);
	vec4 tops;
	for (int i = 0; i < 4; i++) {
		tops[i] = texelFetch(overcast_rain_floor, rain_cell(cell, i, res), 0).r;
	}
	roof = vec2(-1e30);
	ground = -1e30;
	roofed = 0.0;
	if (q.y >= max(max(tops.x, tops.y), max(tops.z, tops.w))) {
		return;
	}
	vec4 h;
	vec4 in_air;
	for (int i = 0; i < 4; i++) {
		vec4 under = texelFetch(overcast_rain_under, rain_cell(cell, i, res), 0);
		in_air[i] = q.y > under.g && q.y < under.r ? under.b : 0.0;
		if (under.r > under.g) {
			h[i] = under.g;
			if (tops[i] > roof.x) {
				roof = vec2(tops[i], under.r);
			}
		} else {
			h[i] = mix(under.a, tops[i], under.b);
		}
	}
	ground = rain_bilerp(h, f);
	roofed = rain_bilerp(in_air, f);
}

// On a surface, slanting rain is stopped by the ground and walls as the walk above has it, by the
// solid's height blended between cells, letting it in over the top RAIN_EDGE metres of what it
// would stop on (rain_cells: the ground under a roof, so a roof's height does not spill onto the
// open ground beside it). The roof p is under, or the first the walk finds, it clears if the line
// is not over it where it comes level with the roof's slab, asked as rain_open_spline asks it of
// the ground in still air: so the edge of what the wind blows in under a roof, and of its lee,
// runs straight along the roof's at any angle to the cells. A roof is found where any of the four
// cells around a step is one RAIN_SLANT_RISE or more above it: a cell early, so the test, not the
// cells, decides.
const float RAIN_EDGE_TEST = 0.05;
const float RAIN_SLANT_RISE = 0.3;

// How much of the rain along `dir` from p clears what has its top and underside in `cover`: not
// over it where the line comes level with the middle of it (of a roof's slab, or just under the
// top of what has no air under it).
float rain_slant_clears(vec3 p, vec3 dir, vec2 cover) {
	float level = cover.y < cover.x ? (cover.x + cover.y) * 0.5 : cover.x - RAIN_EDGE_TEST;
	vec3 e = p + dir * max(level - p.y, 0.0);
	if (!rain_floor_covers(rain_floor_uv(e))) {
		return 1.0;
	}
	return rain_open_spline(vec3(e.x, level, e.z), 2.0 / RAIN_EDGE_TEST);
}

// How much of the rain slanting in on the wind reaches p on a surface (on the floor), 0 to 1, as
// above. Past a roof it thins by how far it comes under cover.
float rain_slant_surface(vec3 p, vec2 slant) {
	float len = length(slant);
	float up = min(RAIN_SLANT_UP, RAIN_SLANT_REACH / max(len, 1e-4));
	vec3 dir = vec3(-slant.x, 1.0, -slant.y);
	float reach = 1.0;
	vec2 cover = vec2(-1e30);
	float covered = 0.0;  // the share of the walk in the air under a roof
	float wander = 0.15 + 0.7 * overcast_vnoise(p.xz * 1.3);
	for (int i = 0; i < RAIN_SLANT_TAPS; i++) {
		vec3 q = p + dir * (up * (float(i) + wander) / float(RAIN_SLANT_TAPS));
		if (!rain_floor_covers(rain_floor_uv(q))) {
			continue;
		}
		float ground;
		vec2 roof;
		float roofed;
		rain_cells(q, ground, roof, roofed);
		reach = min(reach, clamp((q.y - ground) / RAIN_EDGE + 1.0, 0.0, 1.0));
		if (reach <= 0.0) {
			return 0.0;
		}
		covered += roofed;
		if (cover.x < -1e29 && q.y < roof.x - RAIN_SLANT_RISE) {
			cover = roof;
		}
	}
	// The roof p is under, if it is, is the one to clear.
	vec2 uv = rain_floor_uv(p);
	float top = textureLod(overcast_rain_floor, uv, 0.0).r;
	vec2 gap = textureLod(overcast_rain_under, uv, 0.0).rg;
	if (p.y <= top && p.y > gap.y && p.y < gap.x) {
		cover = vec2(top, gap.x);
	}
	if (cover.x < -1e29) {
		return reach;
	}
	// A roof whose underside is higher over p than the walk goes up, the walk lets by: it ends
	// under it, or out from under it, and the thinning says which.
	float far = smoothstep(0.85 * up, up, cover.y - p.y);
	if (far < 1.0) {
		reach *= mix(rain_slant_clears(p, dir, cover), 1.0, far);
	}
	// Thinning by how far the wind blew it in under cover (alike from under a roof and beside it).
	float under = up * len * covered / float(RAIN_SLANT_TAPS);
	return reach * exp(-under / RAIN_SHELTER_DEPTH)
		* smoothstep(RAIN_SLANT_REACH, 0.85 * RAIN_SLANT_REACH, under);
}

// How much of the rain reaches world point p in the air, 0 to 1: everywhere with no floor, off it
// only with overcast_rain_beyond_floor, else straight down or, in wind, along its slant.
float rain_reaches_air(vec3 p) {
	if (!overcast_has_rain_floor) {
		return 1.0;
	}
	vec2 uv = rain_floor_uv(p);
	if (!rain_floor_covers(uv)) {
		return overcast_rain_beyond_floor ? 1.0 : 0.0;
	}
	if (overcast_rain_slant == vec2(0.0)) {
		return p.y > textureLod(overcast_rain_floor, uv, 0.0).r ? 1.0 : 0.0;
	}
	return rain_slant_reach(p, overcast_rain_slant);
}

// Whether rain falling past world point p, slanted by the wind, has not yet been caught.
bool rain_falls_at(vec3 p) {
	return rain_reaches_air(p) > 0.0;
}

// 1 where rain reaching world point p on a surface along `slant` would, 0 under cover: in still
// air all of it at the height rain stops and none a quarter metre below (rain_open_spline).
float rain_reaches_along(vec3 p, vec2 slant) {
	if (!rain_floor_covers(rain_floor_uv(p))) {
		return overcast_rain_beyond_floor ? 1.0 : 0.0;
	}
	return slant == vec2(0.0) ? rain_open_spline(p, 4.0) : rain_slant_surface(p, slant);
}

// How far to raise a point on a slope with this normal before asking whether rain reaches it. A
// cell holds the highest ground anywhere in it, so the rest of a sloped cell lies under its own
// height and would read as solid, cell by cell. `span`: how far, per axis, the point asked about
// has been moved off the surface sideways, which a slope also drops.
float rain_slope_lift(vec3 normal, vec2 span) {
	if (!overcast_has_rain_floor || normal.y <= 0.0) {
		return 0.0;
	}
	return dot(abs(normal.xz), rain_floor_cell() + span) / normal.y;
}

// 1 where rain has reached world point p on a surface, 0 under cover; in wind, along its slant, so
// it blows in under eaves and open shelters and leaves a dry lee, which follow a turning wind over
// time (overcast_ground_shift). Everywhere, with no floor.
float rain_reaches(vec3 p) {
	if (!overcast_has_rain_floor) {
		return 1.0;
	}
	float now = rain_reaches_along(p, overcast_ground_slant.zw);
	if (overcast_ground_shift >= 1.0) {
		return now;
	}
	return mix(rain_reaches_along(p, overcast_ground_slant.xy), now, overcast_ground_shift);
}
#endif
