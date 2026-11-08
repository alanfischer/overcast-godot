@tool
extends RefCounted
## Ice on the ground, per rain floor cell: 0 none to 1 the wet there all frozen. While it is
## freezing each cell freezes up to `glaze` (how far the wet ground has frozen over) and keeps any
## more that cold put there (heat); above freezing it all thaws. Heat thaws it where it lands, and
## while it is still freezing, it freezes over again. A few rows are stepped a frame, all of them
## every PASS seconds, and none once every cell has come to rest.

const PASS := 0.25
const UPLOAD_EVERY := 0.05
## Of a heat's radius, the share in the middle it takes in full; it thins to nothing at the edge.
const HEAT_CORE := 0.35
## How far past a box's top and bottom a cell's floor still counts as inside it (keep_off).
const KEEP_OFF_REACH := 0.1

var dims := Vector2i.ZERO
var origin := Vector3.ZERO
var cell := Vector2.ONE
var ice := PackedFloat32Array()
## What the shaders read: `ice`, FORMAT_RF, laid out as the floor's image is. None undrawn.
var image: Image
var texture: ImageTexture

var _heights := PackedFloat32Array()
var _is_bare := PackedByteArray()
var _row := 0
var _row_time := PackedFloat64Array()
var _clock := 0.0
var _still_rows := 0
var _freezing := false
var _glaze := 0.0
var _rate := 0.0
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
	ice.resize(dims.x * dims.y)
	_is_bare.resize(dims.x * dims.y)
	_row_time.resize(dims.y)
	_still_rows = dims.y
	if drawn:
		image = Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RF, ice.to_byte_array())
		texture = ImageTexture.create_from_image(image)


func resting() -> bool:
	return _still_rows >= dims.y


## A step's worth of time: freezing, each cell freezes up to `glaze`, else thaws, `rate` of a full
## glaze a second.
func step(delta: float, freezing: bool, glaze: float, rate: float) -> void:
	_clock += delta
	if freezing != _freezing or glaze != _glaze or rate != _rate:
		_freezing = freezing
		_glaze = glaze
		_rate = rate
		_wake()
	if not resting():
		for k in mini(ceili(dims.y * delta / PASS), dims.y):
			_step_row(_row)
			_row = (_row + 1) % dims.y
	_upload_in -= delta
	if _dirty and _upload_in <= 0.0:
		upload()


func _step_row(r: int) -> void:
	var k := _rate * (_clock - _row_time[r])
	_row_time[r] = _clock
	var moved := false
	for i in range(r * dims.x, (r + 1) * dims.x):
		var v := ice[i]
		var goal := 0.0
		if _freezing:
			goal = 0.0 if _is_bare[i] else maxf(v, _glaze)
		if v == goal:
			continue
		ice[i] = move_toward(v, goal, k)
		moved = true
	if moved:
		_dirty = true
		_still_rows = 0
	else:
		_still_rows += 1


func _wake() -> void:
	if resting():
		_row_time.fill(_clock)
	_still_rows = 0


## Keeps ice off every cell whose floor lies inside one of `boxes` (AABBs): the bed of a pool or a
## moat, which the rain floor takes for the ground.
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
				if middle.x < box.position.x or middle.x > box.end.x \
						or middle.y < box.position.z or middle.y > box.end.z \
						or floor_y < box.position.y - KEEP_OFF_REACH or floor_y > box.end.y + KEEP_OFF_REACH:
					continue
				_is_bare[c] = 1
				ice[c] = 0.0
	_dirty = true
	_upload_in = 0.0


## Every cell straight to `glaze`, for a scene that starts frozen over.
func fill(glaze: float) -> void:
	for i in ice.size():
		ice[i] = 0.0 if _is_bare[i] else glaze
	_wake()
	_dirty = true
	_upload_in = 0.0


## Heat within `radius` of `at`, on the surfaces near its height, in full in the middle and
## thinning out to the edge. Warm (`amount` > 0) thaws that share of a glaze; cold freezes that
## share of `water`, the wet there, and no more of it than there is.
func heat(at: Vector3, radius: float, amount: float, water: float) -> void:
	if radius <= 0.0 or amount == 0.0:
		return
	var lo := Vector2i(((Vector2(at.x, at.z) - Vector2(origin.x, origin.z) - Vector2.ONE * radius) / cell).floor())
	var hi := Vector2i(((Vector2(at.x, at.z) - Vector2(origin.x, origin.z) + Vector2.ONE * radius) / cell).ceil())
	lo = lo.clamp(Vector2i.ZERO, dims)
	hi = hi.clamp(Vector2i.ZERO, dims)
	var any := false
	for j in range(lo.y, hi.y):
		for i in range(lo.x, hi.x):
			var c := j * dims.x + i
			if _is_bare[c] or absf(_heights[c] - at.y) > radius:
				continue
			var middle := Vector2(origin.x + (i + 0.5) * cell.x, origin.z + (j + 0.5) * cell.y)
			var r := middle.distance_to(Vector2(at.x, at.z)) / radius
			if r >= 1.0:
				continue
			var k := (1.0 - smoothstep(HEAT_CORE, 1.0, r)) * absf(amount)
			var was := ice[c]
			if amount > 0.0:
				ice[c] = maxf(was - k, 0.0)
			else:
				ice[c] = maxf(was, minf(was + k * water, water))
			any = any or ice[c] != was
	if any:
		_wake()
		_dirty = true
		_upload_in = 0.0


## How much of the wet on the cell under world point `p` has frozen; none off the floor.
func ice_at(p: Vector3) -> float:
	var i := floori((p.x - origin.x) / cell.x)
	var j := floori((p.z - origin.z) / cell.y)
	if i < 0 or j < 0 or i >= dims.x or j >= dims.y:
		return 0.0
	return ice[j * dims.x + i]


## Every cell's ice in 1/255 steps, for another peer to take up (set_cells).
func cells() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(ice.size())
	for i in ice.size():
		out[i] = roundi(ice[i] * 255.0)
	return out


## Takes up another peer's cells, as cells() gave them. Ignored if laid out for a different floor.
func set_cells(from: PackedByteArray) -> void:
	if from.size() != ice.size():
		return
	for i in ice.size():
		ice[i] = 0.0 if _is_bare[i] else from[i] / 255.0
	_wake()
	_dirty = true
	_upload_in = 0.0


func upload() -> void:
	_dirty = false
	_upload_in = UPLOAD_EVERY
	if image == null:
		return
	image.set_data(dims.x, dims.y, false, Image.FORMAT_RF, ice.to_byte_array())
	texture.update(image)
