class_name OvercastCycle
extends RefCounted
## Weather that comes and goes on its own: showers of a few minutes that swell, wander and die
## away, with dry spells between, and a wind that rises, falls and turns, blowing harder in them.
## rain_at(t) and wind_at(t) are the weather `t` seconds in, for OvercastWeather.rain and .wind
## (breeze_at(t) for the wind without the showers);
## the same seed gives the same weather, so peers that share one agree without talking.

## Dry spell between showers, and how long one lasts (s).
const DRY := Vector2(240.0, 600.0)
const SHOWER := Vector2(90.0, 240.0)
## Peak rain a shower can reach, weighted toward the light end: a downpour is the rare one.
const PEAK := Vector2(0.1, 1.0)
## Seconds a shower takes to build and to die away.
const RAMP := 30.0
## How far the rain wanders below its peak mid-shower.
const WANDER := 0.4
## Wind between showers (m/s), from near still to a breeze, and how much a shower adds at its
## peak by how hard it rains.
const BREEZE := Vector2(0.5, 5.0)
const SHOWER_WIND := 6.0
## How far the wind turns either way from where it prevails (rad), and the seconds its speed and
## its direction take to wander.
const TURN := PI * 0.5
const WIND_WANDER := 90.0
const TURN_WANDER := 600.0

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _wind_noise := FastNoiseLite.new()
var _prevailing := 0.0
var _start := 0.0
var _end := 0.0
var _peak := 0.0


## 0 picks a seed at random.
func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_noise.seed = _rng.randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0 / 40.0
	# Off the rain's seed rather than another draw, so a seed keeps the showers it had.
	_wind_noise.seed = _noise.seed + 1
	_wind_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wind_noise.frequency = 1.0
	_prevailing = posmod(hash(_noise.seed), 3600) / 3600.0 * TAU
	restart()


## Back to the start, with the first shower sooner than the rest, so turning the cycle on shows.
func restart() -> void:
	_plan(0.0)


func _plan(after: float) -> void:
	var dry := _rng.randf_range(DRY.x, DRY.y) * (0.25 if after == 0.0 else 1.0)
	_start = after + dry
	_end = _start + _rng.randf_range(SHOWER.x, SHOWER.y)
	_peak = lerpf(PEAK.x, PEAK.y, pow(_rng.randf(), 2.0))


## Rain at `t` seconds since restart(): 0 between showers. Times must not go backwards.
func rain_at(t: float) -> float:
	_reach(t)
	if t <= _start:
		return 0.0
	var wander := 1.0 - WANDER * (0.5 + 0.5 * _noise.get_noise_1d(t))
	return maxf(_peak * _envelope(t) * wander, 0.01)


## Wind across the ground at `t` seconds since restart() (m/s), blowing harder in a shower. Times
## must not go backwards.
func wind_at(t: float) -> Vector3:
	_reach(t)
	return _blowing(t, _breeze(t) + SHOWER_WIND * _peak * _envelope(t))


## The breeze alone at `t`: wind_at without what a shower adds, for a wind that comes and goes on
## its own while the rain is set some other way. Times must not go backwards.
func breeze_at(t: float) -> Vector3:
	_reach(t)
	return _blowing(t, _breeze(t))


func _breeze(t: float) -> float:
	return lerpf(BREEZE.x, BREEZE.y, smoothstep(-0.6, 0.6, _wind_noise.get_noise_1d(t / WIND_WANDER)))


## `speed` along the way the wind blows at `t`.
func _blowing(t: float, speed: float) -> Vector3:
	var angle := _prevailing + TURN * _wind_noise.get_noise_2d(t / TURN_WANDER, 100.0)
	return Vector3(sin(angle), 0.0, cos(angle)) * speed


func _reach(t: float) -> void:
	while t >= _end:
		_plan(_end)


func _envelope(t: float) -> float:
	if t <= _start:
		return 0.0
	return smoothstep(0.0, RAMP, t - _start) * smoothstep(0.0, RAMP, _end - t)
