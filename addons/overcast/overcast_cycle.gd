class_name OvercastCycle
extends RefCounted
## Weather that comes and goes on its own: showers of a few minutes that swell, wander and die
## away, with dry spells between. rain_at(t) is the rain `t` seconds in, for OvercastWeather.rain;
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

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
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
	while t >= _end:
		_plan(_end)
	if t <= _start:
		return 0.0
	var envelope := smoothstep(0.0, RAMP, t - _start) * smoothstep(0.0, RAMP, _end - t)
	var wander := 1.0 - WANDER * (0.5 + 0.5 * _noise.get_noise_1d(t))
	return maxf(_peak * envelope * wander, 0.01)
