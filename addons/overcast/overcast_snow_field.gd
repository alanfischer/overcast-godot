@tool
extends "res://addons/overcast/overcast_ground_grid.gd"
## Lying snow, per rain floor cell: metres of it over where rain stops there. It heaps up toward
## `target` (OvercastSnowDrift.bake: an even layer in a calm, drifted in a wind) while snow
## settles, wears away while it melts, comes round to a new target as the wind turns, and is dug out
## where something hot melts it (melt).

## The even layer a calm leaves. A cell shallower than its target fills as fast as this would.
var layer := 0.3
## Metres of snow per cell: `values`.
var depth: PackedFloat32Array:
	get:
		return values
var target := PackedFloat32Array()

var _speed := PackedFloat32Array()  # metres a unit of rate moves each cell: fixed while it heads somewhere
var _settling := false
var _moving := false
var _rate := 0.0


func _init(rain_floor: OvercastRainFloor, even: float, drawn: bool) -> void:
	super(rain_floor, drawn)
	layer = even
	target.resize(values.size())
	target.fill(even)
	_speed.resize(values.size())
	_speed.fill(even)


## A step's worth of time: while `settling`, each cell heaps up toward its target, else wears
## away, `rate` of the most it held or heads for (at least the even layer) a second. At a rate of
## none it holds as it lies.
func step(delta: float, settling: bool, rate: float) -> void:
	_clock += delta
	_rate = rate
	if settling != _settling or (rate > 0.0) != _moving:
		_settling = settling
		_moving = rate > 0.0
		_wake_all()
	if not _moving:
		_still_rows = dims.y
	_step_rows(delta)


func _step_row(r: int, elapsed: float) -> bool:
	var k := _rate * elapsed
	var moved := false
	for i in range(r * dims.x, (r + 1) * dims.x):
		var goal := target[i] if _settling else 0.0
		var d := values[i]
		if d == goal:
			continue
		values[i] = move_toward(d, goal, _speed[i] * k)
		moved = true
	return moved


## Wakes every cell, each to go as fast as it takes to cover the most it holds or heads for in
## 1 / rate seconds.
func _wake_all() -> void:
	_wake()
	for i in values.size():
		_speed[i] = maxf(maxf(target[i], values[i]), layer)


## A new target (OvercastSnowDrift.bake), laid out as the floor's image is: the snow comes round to
## it as fast as it settles.
func set_target(heights: PackedFloat32Array) -> void:
	target = heights
	for c in _bare:
		target[c] = 0.0
	_wake_all()


func keep_off(boxes: Array) -> void:
	super(boxes)
	_wake()


func _kept_off(c: int) -> void:
	target[c] = 0.0


## Straight to `fraction` of the target everywhere, for a scene that starts mid-snowfall.
func fill(fraction: float) -> void:
	for i in values.size():
		values[i] = target[i] * fraction
	_wake_all()
	_changed()


## Melts `amount` (1 all) of the snow within `radius` of `at` on the surfaces near its height, in
## full in the middle and thinning out to the edge. It fills in again while snow settles.
func melt(at: Vector3, radius: float, amount := 1.0) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if radius <= 0.0 or amount <= 0.0:
		return
	var reach := _reach(at, radius)
	var any := false
	for j in range(reach.position.y, reach.end.y):
		for i in range(reach.position.x, reach.end.x):
			var c := j * dims.x + i
			var k := _falloff(i, j, at, radius) * amount
			if k <= 0.0 or values[c] <= 0.0:
				continue
			values[c] *= 1.0 - k
			_speed[c] = maxf(target[c], layer)
			any = true
	if any:
		_wake()
		_changed()


## Metres of snow on the cell under world point `p`; none off the floor.
func depth_at(p: Vector3) -> float:
	return value_at(p)
