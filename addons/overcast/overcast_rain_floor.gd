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
	var corners := PackedFloat32Array()
	corners.resize((w + 1) * (h + 1))
	for j in h + 1:
		for i in w + 1:
			corners[j * (w + 1) + i] = drop.call(box.position.x + i * cell, box.position.z + j * cell)
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	for j in h:
		for i in w:
			var y: float = drop.call(box.position.x + (i + 0.5) * cell, box.position.z + (j + 0.5) * cell)
			for c in [j * (w + 1) + i, j * (w + 1) + i + 1, (j + 1) * (w + 1) + i, (j + 1) * (w + 1) + i + 1]:
				y = maxf(y, corners[c])
			heights[j * w + i] = y
	return create(Image.create_from_data(w, h, false, Image.FORMAT_RF, heights.to_byte_array()),
		box.position, Vector2(w * cell, h * cell), ceiling)


## A rain floor from heights of your own: `image` FORMAT_RF, row 0 at min Z.
static func create(heights: Image, at: Vector3, span: Vector2, ceiling := 1e6) -> OvercastRainFloor:
	var f := OvercastRainFloor.new()
	f.image = heights
	f.origin = at
	f.size = span
	f.top = ceiling
	return f
