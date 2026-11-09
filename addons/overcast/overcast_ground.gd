@tool
class_name OvercastGround
extends RefCounted
## What lies on the ground under an OvercastWeather (its `ground`): how wet it is, how far frozen
## over, how much snow, and cell by cell over the rain floor the snow's depth and the ice. Kept on
## every peer, headless included, for footing (wetness_at, ice_at, snow_depth_at).
##
## A networked game keeps one peer's ground and has the others take it up: turn `soaks` off on the
## others and send them `wetness`, `ice` and `snow_cover`; send the heat() calls that changed
## something for every peer to take; and hand a peer that joins late ice_cells() and snow_cells(),
## which it takes up with set_ice_cells() and set_snow_cells().

const _Field = preload("res://addons/overcast/overcast_snow_field.gd")
const _Ice = preload("res://addons/overcast/overcast_ice_field.gd")

## Degrees C off freezing at which the weather's freeze_time and thaw_time hold: further off it goes
## faster, nearer slower, though never as slow as _ICE_SLOWEST degrees off it would.
const _ICE_DEGREES := 5.0
const _ICE_SLOWEST := 0.5

## Whether the ground soaks and dries, freezes and thaws, and is snowed over and melts by itself.
## Off, `wetness`, `ice` and `snow_cover` stay as they are set: a client's, as its server sends
## them, so the two agree on footing.
var soaks := true
## How wet the ground is, 0 dry to 1 soaked (overcast_wetness), as rain soaks it and it dries.
var wetness: float:
	get:
		return _wetness
	set(value):
		_wetness = clampf(value, 0.0, 1.0)
## How far the wet ground has frozen over, 0 to 1 as `wetness` is (overcast_ice). Each rain floor
## cell has its own ice (ice_at), which follows this but for heat.
var ice: float:
	get:
		return _ice
	set(value):
		_ice = clampf(value, 0.0, 1.0)
## How far snow has covered the ground, 0 to 1 (overcast_snow_cover): for a game's exposure, or its
## footsteps. Each rain floor cell holds its own depth (snow_depth_at).
var snow_cover: float:
	get:
		return _snow_cover
	set(value):
		_snow_cover = clampf(value, 0.0, 1.0)
## How far puddles have filled, 0 to 1 (overcast_puddles): only a downpour fills them. Every peer
## fills its own.
var puddles: float:
	get:
		return _puddles

var _weather: OvercastWeather
var _wetness := 0.0
var _ice := 0.0
var _puddles := 0.0
var _snow_cover := 0.0
var _snow: _Field  # the snow lying on the rain floor, cell by cell, drawn or not
var _ice_field: _Ice  # the ice, drawn or not
var _snowless: Array[AABB] = []


func _init(weather: OvercastWeather) -> void:
	_weather = weather


## How wet the ground is at world point `p`, 0 to 1: `wetness` where rain reaches it (the weather's
## rains_on), else none.
func wetness_at(p: Vector3) -> float:
	return _wetness if _weather.rains_on(p) else 0.0


## How icy the ground is at world point `p`, 0 to 1, where rain reaches it: the cell's own ice, heat
## and all; `ice` off the rain floor.
func ice_at(p: Vector3) -> float:
	if not _weather.rains_on(p):
		return 0.0
	return _ice_field.value_at(p) if _ice_field else _ice


## Metres of snow lying at world point `p`, where snow reaches it: the cell's own, drifts and melts
## and all; the even layer as far as it has settled off the rain floor.
func snow_depth_at(p: Vector3) -> float:
	if not _weather.rains_on(p):
		return 0.0
	return _snow.depth_at(p) if _snow else _snow_cover * OvercastWeather.DRIFT_LAYER


## Heat on the ground within `radius` metres of `at`, on what lies near its height: in full in the
## middle, thinning out to the edge. Warm (`amount` > 0, fire) melts that share of the lying snow
## and thaws that share of the ice; snow fills in again while it keeps settling, and ice freezes
## over again while it is freezing. Cold (`amount` < 0) freezes that share of the wet ground, which
## holds while it is freezing and thaws once it is not; dry ground has nothing to freeze. One peer
## says where, and the others take the same heat. Whether any snow or ice changed.
func heat(at: Vector3, radius: float, amount := 1.0) -> bool:
	var melted := _snow != null and _snow.melt(at, radius, amount)
	var thawed := _ice_field != null and _ice_field.heat(at, radius, amount, _wetness)
	return melted or thawed


## Every rain floor cell's ice, for another peer to take up (set_ice_cells): what heat left there,
## which the weather alone would not say. Empty without a rain floor.
func ice_cells() -> PackedByteArray:
	return _ice_field.cells() if _ice_field else PackedByteArray()


func set_ice_cells(cells: PackedByteArray) -> void:
	if _ice_field:
		_ice_field.set_cells(cells)


## Every rain floor cell's snow, for another peer to take up (set_snow_cells): what melts and the
## drifts left there. Empty without a rain floor.
func snow_cells() -> PackedByteArray:
	return _snow.cells() if _snow else PackedByteArray()


func set_snow_cells(cells: PackedByteArray) -> void:
	if _snow:
		_snow.set_cells(cells)


## Keeps lying snow and ice off the ground inside `box`: a pool, a moat, lava. The rain floor stops
## at what is solid, so under a liquid it is the bed, and snow would lie there and drift up through
## the surface. Kept for every floor the weather takes.
func add_snowless(box: AABB) -> void:
	_snowless.append(box)
	if _snow:
		_snow.keep_off([box])
	if _ice_field:
		_ice_field.keep_off([box])


## Lets snow and ice back onto the ground inside `box`, as add_snowless was given it: a pool
## drained, lava cooled.
func remove_snowless(box: AABB) -> void:
	if not _snowless.has(box):
		return
	_snowless.erase(box)
	if _snow:
		_snow.keep_only(_snowless)
		_weather._forget_drifts()  # baked again, onto the ground let back
	if _ice_field:
		_ice_field.keep_only(_snowless)


func has_snowless(box: AABB) -> bool:
	return _snowless.has(box)


## The fields for a new rain floor, or none without one.
func _take_floor(rain_floor: OvercastRainFloor, has_floor: bool, drawn: bool) -> void:
	_snow = _Field.new(rain_floor, OvercastWeather.DRIFT_LAYER, drawn) if has_floor else null
	_ice_field = _Ice.new(rain_floor, drawn) if has_floor else null
	if _snow:
		_snow.keep_off(_snowless)
	if _ice_field:
		_ice_field.keep_off(_snowless)


## Straight to what the weather now is heading for: soaked or dry, frozen or not, snowed over or
## bare.
func _soak() -> void:
	var freezing := _freezing()
	if soaks:
		if _weather.rainfall > 0.0 or not _wet_holds():
			_wetness = 1.0 if _weather.rainfall > 0.0 else 0.0
		_ice = _wetness if freezing else 0.0
		if _settling():
			_snow_cover = 1.0
		elif not freezing:
			_snow_cover = 0.0
	_puddles = OvercastWeather._heaviness(_weather.rainfall)
	if _snow:
		_snow.fill(_snow_cover)
	if _ice_field:
		_ice_field.fill(_ice)


## A step's worth of the weather on the ground: `lying`, whether anything is falling or lies to
## change, soaks and dries it and lays and melts the snow; the fields follow either way.
func _step(delta: float, lying: bool) -> void:
	if lying:
		_weather_ground(delta)
	if _snow:
		_snow.step(delta, _snow_settles(), _snow_rate())
	if _ice_field:
		_ice_field.step(delta, _freezing(), _ice, _ice_rate())


func _weather_ground(delta: float) -> void:
	var w := _weather
	if soaks:
		_snow_cover = move_toward(_snow_cover, 1.0 if _snow_settles() else 0.0, _snow_rate() * delta)
	var freezing := _freezing()
	# Melting snow keeps the ground under it wet.
	var melting := _snow_cover > 0.0 and not freezing
	var wet_target := 1.0 if (w.rainfall > 0.0 or melting) and w.wet_ground else 0.0
	var puddle_target := OvercastWeather._heaviness(w.rainfall) if w.wet_ground else 0.0
	if soaks:
		var dry_rate := 0.0 if _wet_holds() else 1.0 / w.dry_time
		_wetness = move_toward(_wetness, wet_target,
			(lerpf(0.35, 1.0, puddle_target) / w.soak_time if wet_target > _wetness else dry_rate) * delta)
		_ice = move_toward(_ice, _wetness if freezing else 0.0, _ice_rate() * delta)
	_puddles = move_toward(_puddles, puddle_target,
		(1.0 / w.puddle_time if puddle_target > _puddles else 1.0 / w.puddle_dry_time) * delta)


## Whether wet ground keeps its wet rather than drying: it is ice, turning to it, or not yet thawed.
func _wet_holds() -> bool:
	return _freezing() or _ice > 0.0


func _freezing() -> bool:
	return _weather.temperature <= OvercastWeather.FREEZING


## Snow lies while it falls on freezing ground.
func _settling() -> bool:
	return _freezing() and _weather.snowfall > 0.0


func _snow_settles() -> bool:
	return _settling() and _weather.lying_snow


## How fast snow lies or melts, of all of it a second: none while it holds, freezing with none
## falling.
func _snow_rate() -> float:
	var w := _weather
	if _snow_settles():
		return lerpf(0.35, 1.0, OvercastWeather._heaviness(w.snowfall)) / w.snow_time
	if _freezing() and w.lying_snow:
		return 0.0
	return (1.0 + 3.0 * OvercastWeather._heaviness(w.rainfall)) / w.melt_time


## How fast wet ground freezes over or its ice thaws, of a full glaze a second.
func _ice_rate() -> float:
	var w := _weather
	var off := maxf(absf(w.temperature - OvercastWeather.FREEZING), _ICE_SLOWEST) / _ICE_DEGREES
	if _freezing():
		return off / w.freeze_time
	return off * (1.0 + 3.0 * OvercastWeather._heaviness(w.rainfall)) / w.thaw_time
