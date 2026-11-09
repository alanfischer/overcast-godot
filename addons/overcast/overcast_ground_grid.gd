@tool
extends RefCounted
## A value per rain floor cell, laid over where rain stops there: what the snow and ice fields
## share. A subclass steps a row at a time (_step_row); a few rows go a frame, all of them every
## PASS seconds, and none once every cell has come to rest. Drawn, `values` go to the shaders as
## `texture` (FORMAT_RF, laid out as the floor's image is).

const PASS := 0.25
## Seconds between uploads while the values change.
const UPLOAD_EVERY := 0.05
## Of a brush's radius (falloff), the share in the middle it takes in full; it thins to nothing at
## the edge.
const CORE := 0.35
## How far past a kept-off box's top and bottom a cell's floor still counts as inside it.
const KEEP_OFF_REACH := 0.1

var dims := Vector2i.ZERO
var origin := Vector3.ZERO
var cell := Vector2.ONE
var values := PackedFloat32Array()
var image: Image  # none undrawn
var texture: ImageTexture

var _heights := PackedFloat32Array()
var _bare := PackedInt32Array()  # cells kept off (keep_off)
var _is_bare := PackedByteArray()
var _row := 0
var _row_time := PackedFloat64Array()
var _clock := 0.0
var _still_rows := 0  # rows in a row that a step left as they were
var _dirty := false
var _upload_in := 0.0


func _init(rain_floor: OvercastRainFloor, drawn: bool) -> void:
	var img := rain_floor.image
	if img.get_format() != Image.FORMAT_RF:
		img = img.duplicate()
		img.convert(Image.FORMAT_RF)
	dims = img.get_size()
	origin = rain_floor.origin
	cell = rain_floor.size / Vector2(dims)
	_heights = img.get_data().to_float32_array()
	values.resize(dims.x * dims.y)
	_is_bare.resize(dims.x * dims.y)
	_row_time.resize(dims.y)
	if drawn:
		image = Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RF, values.to_byte_array())
		texture = ImageTexture.create_from_image(image)


## Whether every cell has come to its goal, so a step does nothing until something changes.
func resting() -> bool:
	return _still_rows >= dims.y


## Steps the rows due in `delta` (already on the clock), and uploads what they moved.
func _step_rows(delta: float) -> void:
	if not resting():
		for k in mini(ceili(dims.y * delta / PASS), dims.y):
			var r := _row
			var elapsed := _clock - _row_time[r]
			_row_time[r] = _clock
			if _step_row(r, elapsed):
				_dirty = true
				_still_rows = 0
			else:
				_still_rows += 1
			_row = (_row + 1) % dims.y
	_upload_in -= delta
	if _dirty and _upload_in <= 0.0:
		upload()


## Moves row `r` on by `elapsed` seconds; whether any cell in it moved.
func _step_row(_r: int, _elapsed: float) -> bool:
	return false


## Something changed what the cells head for: they step again, from now.
func _wake() -> void:
	if resting():
		_row_time.fill(_clock)
	_still_rows = 0


## The values changed outside a step: uploaded next step.
func _changed() -> void:
	_dirty = true
	_upload_in = 0.0


## Keeps every cell whose floor lies inside one of `boxes` (AABBs) at none: the bed of a pool or a
## moat, which the rain floor takes for the ground, or lava.
func keep_off(boxes: Array) -> void:
	for box: AABB in boxes:
		var lo := Vector2i(((Vector2(box.position.x, box.position.z) - Vector2(origin.x, origin.z)) / cell).floor())
		var hi := Vector2i(((Vector2(box.end.x, box.end.z) - Vector2(origin.x, origin.z)) / cell).ceil())
		for j in range(clampi(lo.y, 0, dims.y), clampi(hi.y, 0, dims.y)):
			for i in range(clampi(lo.x, 0, dims.x), clampi(hi.x, 0, dims.x)):
				var c := j * dims.x + i
				var middle := _middle(i, j)
				var floor_y := _heights[c]
				if _is_bare[c] or middle.x < box.position.x or middle.x > box.end.x \
						or middle.y < box.position.z or middle.y > box.end.z \
						or floor_y < box.position.y - KEEP_OFF_REACH or floor_y > box.end.y + KEEP_OFF_REACH:
					continue
				_is_bare[c] = 1
				_bare.append(c)
				values[c] = 0.0
				_kept_off(c)
	_changed()


## Cell `c` was just kept off.
func _kept_off(_c: int) -> void:
	pass


## The cells keep_off keeps at none.
func bare_cells() -> PackedInt32Array:
	return _bare


## The cells a brush of `radius` round `at` can reach, as a rect of the grid.
func _reach(at: Vector3, radius: float) -> Rect2i:
	var lo := Vector2i(((Vector2(at.x, at.z) - Vector2(origin.x, origin.z) - Vector2.ONE * radius) / cell).floor())
	var hi := Vector2i(((Vector2(at.x, at.z) - Vector2(origin.x, origin.z) + Vector2.ONE * radius) / cell).ceil())
	lo = lo.clamp(Vector2i.ZERO, dims)
	return Rect2i(lo, hi.clamp(Vector2i.ZERO, dims) - lo)


## How much of a brush of `radius` round `at` cell (i, j) takes: 1 in its middle, thinning to 0
## at its edge, and none on a kept-off cell or a floor further than `radius` from at's height.
func _falloff(i: int, j: int, at: Vector3, radius: float) -> float:
	var c := j * dims.x + i
	if _is_bare[c] or absf(_heights[c] - at.y) > radius:
		return 0.0
	var r := _middle(i, j).distance_to(Vector2(at.x, at.z)) / radius
	return 1.0 - smoothstep(CORE, 1.0, r) if r < 1.0 else 0.0


func _middle(i: int, j: int) -> Vector2:
	return Vector2(origin.x + (i + 0.5) * cell.x, origin.z + (j + 0.5) * cell.y)


## The value on the cell under world point `p`; none off the floor.
func value_at(p: Vector3) -> float:
	var i := floori((p.x - origin.x) / cell.x)
	var j := floori((p.z - origin.z) / cell.y)
	if i < 0 or j < 0 or i >= dims.x or j >= dims.y:
		return 0.0
	return values[j * dims.x + i]


func upload() -> void:
	_dirty = false
	_upload_in = UPLOAD_EVERY
	if image == null:
		return
	image.set_data(dims.x, dims.y, false, Image.FORMAT_RF, values.to_byte_array())
	texture.update(image)
