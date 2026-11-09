@tool
extends "res://addons/overcast/overcast_ground_grid.gd"
## Ice on the ground, per rain floor cell, 0 to 1 as the weather's wetness is. While it is freezing
## each cell freezes up to `glaze` (how far the wet ground has frozen over) and keeps any more that
## cold put there (heat); above freezing it all thaws. Heat thaws it where it lands, and while it is
## still freezing, it freezes over again.

var _freezing := false
var _glaze := 0.0
var _rate := 0.0


func _init(rain_floor: OvercastRainFloor, drawn: bool) -> void:
	super(rain_floor, drawn)
	_still_rows = dims.y  # nothing frozen, nothing to do


## A step's worth of time: freezing, each cell freezes up to `glaze`, else thaws, `rate` of a full
## glaze a second.
func step(delta: float, freezing: bool, glaze: float, rate: float) -> void:
	_clock += delta
	_rate = rate
	if freezing != _freezing or (freezing and glaze != _glaze):
		_wake()
	_freezing = freezing
	_glaze = glaze
	_step_rows(delta)


func _step_row(r: int, elapsed: float) -> bool:
	var k := _rate * elapsed
	var moved := false
	for i in range(r * dims.x, (r + 1) * dims.x):
		var v := values[i]
		var goal := maxf(v, _glaze) if _freezing and not _is_bare[i] else 0.0
		if v == goal:
			continue
		values[i] = move_toward(v, goal, k)
		moved = true
	return moved


## Every cell straight to `glaze`, for a scene that starts frozen over.
func fill(glaze: float) -> void:
	for i in values.size():
		values[i] = 0.0 if _is_bare[i] else glaze
	_wake()
	_changed()


## Heat within `radius` of `at`, on the surfaces near its height, in full in the middle and
## thinning out to the edge. Warm (`amount` > 0) thaws that share of a glaze; cold freezes that
## share of `water`, the wet there, and no more of it than there is. Whether any ice changed.
func heat(at: Vector3, radius: float, amount: float, water: float) -> bool:
	if radius <= 0.0 or amount == 0.0:
		return false
	var reach := _reach(at, radius)
	var any := false
	for j in range(reach.position.y, reach.end.y):
		for i in range(reach.position.x, reach.end.x):
			var k := _falloff(i, j, at, radius) * absf(amount)
			if k <= 0.0:
				continue
			var c := j * dims.x + i
			var was := values[c]
			if amount > 0.0:
				values[c] = maxf(was - k, 0.0)
			else:
				values[c] = maxf(was, minf(was + k * water, water))
			any = any or values[c] != was
	if any:
		_wake()
		_changed()
	return any


## Every cell's ice in 1/255 steps, for another peer to take up (set_cells).
func cells() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(values.size())
	for i in values.size():
		out[i] = roundi(values[i] * 255.0)
	return out


## Takes up another peer's cells, as cells() gave them. Ignored if laid out for a different floor.
func set_cells(from: PackedByteArray) -> void:
	if from.size() != values.size():
		return
	for i in values.size():
		values[i] = 0.0 if _is_bare[i] else from[i] / 255.0
	_wake()
	_changed()
