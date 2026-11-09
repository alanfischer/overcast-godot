@tool
class_name OvercastRainFloor
extends Resource
## Where rain stops, per column: the height it falls to before something catches it. Baked once,
## in the editor (OvercastWeather's Bake Rain Floor) or at runtime (bake), then the drops, haze
## and wet ground all read it, so rain stays out from under a roof.

## One height per cell, metres, FORMAT_RF, row 0 at min Z.
@export var image: Image
## The min-X/min-Z corner, at the bottom of the baked box.
@export var origin := Vector3.ZERO
## Metres the image spans on X and Z.
@export var size := Vector2.ONE
## No rain above this height.
@export var top := 1e6
## The open air under what catches rain, per cell (at its middle), FORMAT_RGF: r the underside of
## the roof, g the ground under it; equal where there is none (a wall, solid ground). Wind blows
## rain in through it, under eaves and open shelters. Without it all under the floor is solid.
@export var under: Image

## Where a cell has no air under cover.
const _NO_GAP := -1e6
## Air under a roof thinner than this does not count, and the underside is looked for at most
## _GAP_SEARCH metres under the top.
const _MIN_GAP := 0.3
const _GAP_SEARCH := 4.0


## Bake by raycasting down through `box` in the world's physics, one column every `cell` metres.
## Each cell takes the highest of its centre and four corners: a wall's top along a cell's edge
## keeps rain off the floor beside it, at the cost of a dry strip under a cell's width outdoors.
## Colliders must exist in the physics space already (at runtime, call after a physics frame).
static func bake(world: World3D, box: AABB, cell := 0.5, mask := 0xFFFFFFFF) -> OvercastRainFloor:
	var space := world.direct_space_state
	var w := maxi(int(ceil(box.size.x / cell)), 1)
	var h := maxi(int(ceil(box.size.z / cell)), 1)
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = mask
	query.hit_back_faces = false
	var ceiling := box.end.y
	var bottom := box.position.y
	var drop := func(x: float, z: float) -> float:
		query.from = Vector3(x, ceiling, z)
		query.to = Vector3(x, bottom, z)
		var hit := space.intersect_ray(query)
		return hit["position"].y if hit else bottom
	var up := PhysicsRayQueryParameters3D.new()
	up.collision_mask = mask
	up.hit_back_faces = true
	up.hit_from_inside = true
	# Each corner's height and the air under it, shared by the cells around it.
	var corners := PackedFloat32Array()
	corners.resize((w + 1) * (h + 1))
	var corner_gaps := PackedVector2Array()
	corner_gaps.resize((w + 1) * (h + 1))
	for j in h + 1:
		for i in w + 1:
			var x := box.position.x + i * cell
			var z := box.position.z + j * cell
			var y: float = drop.call(x, z)
			corners[j * (w + 1) + i] = y
			corner_gaps[j * (w + 1) + i] = _gap(space, up, query, x, z, y, bottom)
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	var gaps := PackedFloat32Array()
	gaps.resize(w * h * 2)
	for j in h:
		for i in w:
			var x := box.position.x + (i + 0.5) * cell
			var z := box.position.z + (j + 0.5) * cell
			var middle: float = drop.call(x, z)
			var tops := [middle]
			var airs := [_gap(space, up, query, x, z, middle, bottom)]
			for k in 4:
				var c: int = (j + k / 2) * (w + 1) + i + k % 2
				tops.append(corners[c])
				airs.append(corner_gaps[c])
			var y: float = tops.max()
			heights[j * w + i] = y
			var gap := _cell_gap(y, tops, airs)
			gaps[(j * w + i) * 2] = gap.x
			gaps[(j * w + i) * 2 + 1] = gap.y
	return create(Image.create_from_data(w, h, false, Image.FORMAT_RF, heights.to_byte_array()),
		box.position, Vector2(w * cell, h * cell), ceiling,
		Image.create_from_data(w, h, false, Image.FORMAT_RGF, gaps.to_byte_array()))


## The air under a cell's top `y`, from its middle and corners (`tops`, and the air under each,
## `airs`; the middle first). Solid where its middle is, or two of its corners: a wall thinner than
## a cell, between the middles, touches two corners of every cell along it, so it is not lost, and
## a post thinner than one is not spread over four. Else the air every open sample agrees on: one
## whose top is the cell's has the air under it; one lower down, out from under the roof, has open
## air from its top up.
static func _cell_gap(y: float, tops: Array, airs: Array) -> Vector2:
	var none := Vector2(_NO_GAP, _NO_GAP)
	var solid := 0
	var hi := INF
	var lo := -INF
	for k in tops.size():
		if tops[k] >= y - 0.01:
			if airs[k].x <= airs[k].y:
				if k == 0:
					return none
				solid += 1
				continue
			hi = minf(hi, airs[k].x)
			lo = maxf(lo, airs[k].y)
		else:
			lo = maxf(lo, tops[k])
	if solid >= 2 or hi == INF:
		return none
	return Vector2(hi, lo) if hi - lo >= _MIN_GAP else none


## The open air under `top` at x, z: the underside of what rain stops on there, found by looking up
## from ever further under it (so a table under the roof is not taken for it), then the ground
## under that. A wall, or the inside of a closed mesh, is none.
static func _gap(space: PhysicsDirectSpaceState3D, up: PhysicsRayQueryParameters3D,
		down: PhysicsRayQueryParameters3D, x: float, z: float, top: float, bottom: float) -> Vector2:
	var none := Vector2(_NO_GAP, _NO_GAP)
	var under := NAN
	var depth := 0.5
	while depth <= _GAP_SEARCH:
		up.from = Vector3(x, top - depth, z)
		up.to = Vector3(x, top - 0.01, z)
		var hit := space.intersect_ray(up)
		# Started inside something (a lintel under the roof): its underside is further down.
		if hit and hit["normal"] != Vector3.ZERO:
			under = hit["position"].y
			break
		depth *= 2.0
	if is_nan(under):
		return none
	down.hit_back_faces = true
	down.hit_from_inside = true
	down.from = Vector3(x, under - 0.01, z)
	down.to = Vector3(x, bottom, z)
	var ground := space.intersect_ray(down)
	down.hit_back_faces = false
	down.hit_from_inside = false
	# Starting inside a shape (a wall under the roof: its normal comes back zero), or going down
	# onto a face that looks down (leaving a closed mesh from inside): solid.
	if ground and (ground["normal"] == Vector3.ZERO or ground["normal"].y < -0.1):
		return none
	var floor_y: float = ground["position"].y if ground else bottom
	return Vector2(under, floor_y) if under - floor_y >= _MIN_GAP else none


## A rain floor from heights of your own: `image` FORMAT_RF, row 0 at min Z, and the air under
## cover if you have it (see `under`).
static func create(heights: Image, at: Vector3, span: Vector2, ceiling := 1e6,
		air: Image = null) -> OvercastRainFloor:
	var f := OvercastRainFloor.new()
	f.image = heights
	f.origin = at
	f.size = span
	f.top = ceiling
	f.under = air
	return f
