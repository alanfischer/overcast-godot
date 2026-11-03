class_name OvercastRainFloor
extends Object
## Where rain stops, per column: the height it falls to before something catches it. Baked once,
## then the drops, haze and wet ground all read it, so rain stays out from under a roof.
##
## A rain floor is a Dictionary: "image" (FORMAT_RF, one height per cell, metres), "origin" (the
## min-X/min-Z corner), "size" (Vector2, metres the image spans on X and Z) and "top" (no rain
## above it). Hand it to OvercastWeather.set_rain_floor.


## Bake by raycasting down through `box` in the world's physics, one column every `cell` metres.
## Each cell takes the highest of its centre and four corners: a wall's top along a cell's edge
## keeps rain off the floor beside it, at the cost of a dry strip under a cell's width outdoors.
## Colliders must exist in the physics space already (call after a physics frame).
static func bake(world: World3D, box: AABB, cell := 0.5, mask := 0xFFFFFFFF) -> Dictionary:
	var space := world.direct_space_state
	var w := maxi(int(ceil(box.size.x / cell)), 1)
	var h := maxi(int(ceil(box.size.z / cell)), 1)
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = mask
	query.hit_back_faces = false
	var top := box.end.y
	var bottom := box.position.y
	var drop := func(x: float, z: float) -> float:
		query.from = Vector3(x, top, z)
		query.to = Vector3(x, bottom, z)
		var hit := space.intersect_ray(query)
		return hit["position"].y if hit else bottom
	var corners := PackedFloat32Array()
	corners.resize((w + 1) * (h + 1))
	for j in h + 1:
		for i in w + 1:
			corners[j * (w + 1) + i] = drop.call(box.position.x + i * cell, box.position.z + j * cell)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RF)
	for j in h:
		for i in w:
			var y: float = drop.call(box.position.x + (i + 0.5) * cell, box.position.z + (j + 0.5) * cell)
			for c in [j * (w + 1) + i, j * (w + 1) + i + 1, (j + 1) * (w + 1) + i, (j + 1) * (w + 1) + i + 1]:
				y = maxf(y, corners[c])
			img.set_pixel(i, j, Color(y, 0.0, 0.0))
	return {"image": img, "origin": box.position, "size": Vector2(w * cell, h * cell), "top": top}
