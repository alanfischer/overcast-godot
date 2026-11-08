@tool
extends RefCounted
## Lying snow, per rain floor cell: metres of it over where rain stops there. It heaps up toward
## `target` (OvercastSnowDrift.bake: an even layer in a calm, drifted in a wind) while snow
## settles, wears away while it melts, comes round to a new target as the wind turns, and is dug out
## where something hot melts it (melt). A few rows are stepped a frame, all of them every PASS
## seconds, and none once every cell has come to rest.

## Seconds for the steps to come round every row.
const PASS := 0.25
## Seconds between uploads while the field changes.
const UPLOAD_EVERY := 0.05
## Of a melt's radius, the share in the middle melted bare; it thins to nothing at the edge.
const MELT_CORE := 0.35
## How far past a snowless box's top and bottom a cell's floor still counts as inside it.
const KEEP_OFF_REACH := 0.1

var dims := Vector2i.ZERO
var origin := Vector3.ZERO
var cell := Vector2.ONE
## The even layer a calm leaves. A cell shallower than its target fills as fast as this would.
var layer := 0.3
var depth := PackedFloat32Array()
var target := PackedFloat32Array()
## What the shaders read: `depth`, FORMAT_RF, laid out as the floor's image is. None undrawn.
var image: Image
var texture: ImageTexture

var _heights := PackedFloat32Array()
var _bare := PackedInt32Array()  # cells no snow lies on (keep_off)
var _is_bare := PackedByteArray()
var _speed := PackedFloat32Array()  # metres a unit of rate moves each cell: fixed while it heads somewhere
var _row := 0
var _row_time := PackedFloat64Array()
var _clock := 0.0
var _still_rows := 0  # rows in a row that a step left as they were
var _settling := false
var _moving := false
var _dirty := false
var _upload_in := 0.0


func _init(rain_floor: OvercastRainFloor, even: float, drawn: bool) -> void:
	var img := rain_floor.image
	if img.get_format() != Image.FORMAT_RF:
		img = img.duplicate()
		img.convert(Image.FORMAT_RF)
	dims = img.get_size()
	origin = rain_floor.origin
	cell = rain_floor.size / Vector2(dims)
	layer = even
	_heights = img.get_data().to_float32_array()
	depth.resize(dims.x * dims.y)
	target.resize(dims.x * dims.y)
	target.fill(even)
	_is_bare.resize(dims.x * dims.y)
	_speed.resize(dims.x * dims.y)
	_speed.fill(even)
	_row_time.resize(dims.y)
	if drawn:
		image = Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RF, depth.to_byte_array())
		texture = ImageTexture.create_from_image(image)


## Whether every cell has come to its goal, so a step does nothing until something changes.
func resting() -> bool:
	return _still_rows >= dims.y


## A step's worth of time: while `settling`, each cell heaps up toward its target, else wears
## away, `rate` of the most it held or heads for (at least the even layer) a second. At a rate of
## none it holds as it lies.
func step(delta: float, settling: bool, rate: float) -> void:
	_clock += delta
	if settling != _settling or (rate > 0.0) != _moving:
		_settling = settling
		_moving = rate > 0.0
		_wake()
	if not _moving:
		_still_rows = dims.y
	if not resting():
		for k in mini(ceili(dims.y * delta / PASS), dims.y):
			_step_row(_row, rate)
			_row = (_row + 1) % dims.y
	_upload_in -= delta
	if _dirty and _upload_in <= 0.0:
		upload()


func _step_row(r: int, rate: float) -> void:
	var k := rate * (_clock - _row_time[r])
	_row_time[r] = _clock
	var moved := false
	for i in range(r * dims.x, (r + 1) * dims.x):
		var goal := target[i] if _settling else 0.0
		var d := depth[i]
		if d == goal:
			continue
		depth[i] = move_toward(d, goal, _speed[i] * k)
		moved = true
	if moved:
		_dirty = true
		_still_rows = 0
	else:
		_still_rows += 1


## Something changed what the cells head for: they step again, from now, each as fast as it takes
## to cover the most it holds or heads for in 1 / rate seconds.
func _wake(speeds := true) -> void:
	if resting():
		_row_time.fill(_clock)
	_still_rows = 0
	if speeds:
		for i in depth.size():
			_speed[i] = maxf(maxf(target[i], depth[i]), layer)


## A new target (OvercastSnowDrift.bake), laid out as the floor's image is: the snow comes round to
## it as fast as it settles.
func set_target(heights: PackedFloat32Array) -> void:
	target = heights
	for c in _bare:
		target[c] = 0.0
	_wake()


## Keeps snow off every cell whose floor lies inside one of `boxes` (AABBs): a pool or a moat,
## whose bed the rain floor takes for the ground, or lava.
func keep_off(boxes: Array) -> void:
	for box: AABB in boxes:
		var lo := Vector2i(((Vector2(box.position.x, box.position.z) - Vector2(origin.x, origin.z)) / cell).floor())
		var hi := Vector2i(((Vector2(box.end.x, box.end.z) - Vector2(origin.x, origin.z)) / cell).ceil())
		lo = lo.clamp(Vector2i.ZERO, dims)
		hi = hi.clamp(Vector2i.ZERO, dims)
		for j in range(lo.y, hi.y):
			for i in range(lo.x, hi.x):
				var c := j * dims.x + i
				var middle := Vector2(origin.x + (i + 0.5) * cell.x, origin.z + (j + 0.5) * cell.y)
				var floor_y := _heights[c]
				if _is_bare[c] or middle.x < box.position.x or middle.x > box.end.x \
						or middle.y < box.position.z or middle.y > box.end.z \
						or floor_y < box.position.y - KEEP_OFF_REACH or floor_y > box.end.y + KEEP_OFF_REACH:
					continue
				_is_bare[c] = 1
				_bare.append(c)
				target[c] = 0.0
				depth[c] = 0.0
	_wake(false)
	_dirty = true
	_upload_in = 0.0


## The cells keep_off keeps bare.
func bare_cells() -> PackedInt32Array:
	return _bare


## Straight to `fraction` of the target everywhere, for a scene that starts mid-snowfall.
func fill(fraction: float) -> void:
	for i in depth.size():
		depth[i] = target[i] * fraction
	_wake()
	_dirty = true
	_upload_in = 0.0


## Melts the snow within `radius` of `at` on the surfaces near its height, bare in the middle and
## thinning out to the edge. It fills in again while snow settles.
func melt(at: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	var lo := Vector2i(((Vector2(at.x, at.z) - Vector2(origin.x, origin.z) - Vector2.ONE * radius) / cell).floor())
	var hi := Vector2i(((Vector2(at.x, at.z) - Vector2(origin.x, origin.z) + Vector2.ONE * radius) / cell).ceil())
	lo = lo.clamp(Vector2i.ZERO, dims)
	hi = hi.clamp(Vector2i.ZERO, dims)
	var any := false
	for j in range(lo.y, hi.y):
		for i in range(lo.x, hi.x):
			var c := j * dims.x + i
			if depth[c] <= 0.0 or absf(_heights[c] - at.y) > radius:
				continue
			var middle := Vector2(origin.x + (i + 0.5) * cell.x, origin.z + (j + 0.5) * cell.y)
			var r := middle.distance_to(Vector2(at.x, at.z)) / radius
			if r >= 1.0:
				continue
			depth[c] *= smoothstep(MELT_CORE, 1.0, r)
			_speed[c] = maxf(target[c], layer)
			any = true
	if any:
		_wake(false)
		_dirty = true
		_upload_in = 0.0


## Metres of snow on the cell under world point `p`; none off the floor.
func depth_at(p: Vector3) -> float:
	var i := floori((p.x - origin.x) / cell.x)
	var j := floori((p.z - origin.z) / cell.y)
	if i < 0 or j < 0 or i >= dims.x or j >= dims.y:
		return 0.0
	return depth[j * dims.x + i]


func upload() -> void:
	_dirty = false
	_upload_in = UPLOAD_EVERY
	if image == null:
		return
	image.set_data(dims.x, dims.y, false, Image.FORMAT_RF, depth.to_byte_array())
	texture.update(image)
