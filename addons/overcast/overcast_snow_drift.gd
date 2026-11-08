@tool
class_name OvercastSnowDrift
extends RefCounted
## How deep snow lies once it has all settled, per rain floor cell, over the height rain stops at
## there: an even layer in a calm; in a wind, scoured thin in the open and drifted deep in the lee
## of what stands in its way, deepest against it and running out downwind, with a smaller bank on
## its windward side. Baked from a rain floor and the steady wind (bake), again when the wind turns.
##
## What shelters is what stands solid from the ground up: the wind blows under a roof on posts, so
## it drifts nothing, and the ground under a roof gets none.

## Snow starts to drift past CALM (m/s), and drifts all it will past DRIFTING.
const CALM := 2.0
const DRIFTING := 8.0
## The share of the even layer the open keeps in a drifting wind.
const SCOUR := 0.5
## In an obstacle's lee the drift starts at LEE_FILL of its height and falls LEE_SLOPE a metre
## downwind; on its windward side it banks to WINDWARD_FILL, falling WINDWARD_SLOPE a metre upwind.
## Both fall SIDE_SLOPE a metre sideways, past the obstacle's ends.
const LEE_FILL := 0.85
const LEE_SLOPE := 1.0 / 7.0
const WINDWARD_FILL := 0.5
const WINDWARD_SLOPE := 0.4
## The deepest a drift starts against what it lies by (m), however tall, unless bake is given
## another: a cliff's lee drifts as a wall's does, not a heap of most of its height.
const DEEPEST := 1.5
const SIDE_SLOPE := 0.7
## Snow less than this over the even layer is the even layer (stored as 32-bit floats, it is a hair
## over it).
const HEAPED := 0.01
## Ground this much higher or lower than a cell beside it is another surface: a wall, a roof.
const SAME_GROUND := 0.1
## A cell no drift starts from, in _sweep.
const NO_SEED := -1e6

## Metres of snow on each cell of `rain_floor` once it has all settled, FORMAT_RF, laid out as the
## floor's image is. `depth` is the even layer a calm leaves; `wind` the steady wind (y ignored).
static func bake(rain_floor: OvercastRainFloor, wind: Vector3, depth := 0.3, deepest := DEEPEST) -> Image:
	var dims := rain_floor.image.get_size()
	var n := dims.x * dims.y
	var solid := _floats(rain_floor.image, Image.FORMAT_RF)
	var roofed := PackedByteArray()
	roofed.resize(n)
	if rain_floor.under and rain_floor.under.get_size() == dims:
		var gaps := _floats(rain_floor.under, Image.FORMAT_RGF)
		for i in n:
			if gaps[i * 2] > gaps[i * 2 + 1]:
				solid[i] = gaps[i * 2 + 1]
				roofed[i] = 1
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(depth)
	var flat := Vector2(wind.x, wind.z)
	var k := smoothstep(CALM, DRIFTING, flat.length())
	if k > 0.0:
		var cell := rain_floor.size / Vector2(dims)
		var lee := _sweep(solid, dims, cell, flat.normalized(), LEE_FILL, LEE_SLOPE, deepest)
		var bank := _sweep(solid, dims, cell, -flat.normalized(), WINDWARD_FILL, WINDWARD_SLOPE, deepest)
		var bare := depth * (1.0 - SCOUR)
		for i in n:
			var drift := 0.0 if roofed[i] else minf(maxf(lee[i], bank[i]) - solid[i], deepest)
			out[i] = lerpf(depth, maxf(bare, drift), k)
	return Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RF, out.to_byte_array())


static func _floats(img: Image, format: Image.Format) -> PackedFloat32Array:
	if img.get_format() != format:
		img = img.duplicate()
		img.convert(format)
	return img.get_data().to_float32_array()


## The snow surface a wind along `dir` drifts over `solid` (heights, row by row): each cell that
## stands over the lowest ground beside it sheds `fill` of its height over that ground (`deepest`
## at most), falling `slope` a metre along `dir` and SIDE_SLOPE a metre across it, and each keeps the
## highest of what reaches it. A cell with nothing lower beside it sheds nothing: the top of a
## building is not a drift, or it would spread over the ground past it as one. Nor does a drift
## carry on over a drop: blown on, it stands `deepest` at most over the ground under it, and falls
## away from there, so a cliff's lee drifts as a wall's does. Worked on a grid turned
## to the wind, where each fall is taken exactly a row or a column at a time, then read back.
static func _sweep(solid: PackedFloat32Array, dims: Vector2i, cell: Vector2, dir: Vector2,
		fill: float, slope: float, deepest := DEEPEST) -> PackedFloat32Array:
	var w := dims.x
	var h := dims.y
	var seeds := PackedFloat32Array()
	seeds.resize(w * h)
	for j in h:
		for i in w:
			var g := solid[j * w + i]
			var foot := g
			for nj in range(maxi(j - 1, 0), mini(j + 2, h)):
				for ni in range(maxi(i - 1, 0), mini(i + 2, w)):
					foot = minf(foot, solid[nj * w + ni])
			seeds[j * w + i] = foot + minf((g - foot) * fill, deepest) if g - foot > SAME_GROUND else NO_SEED
	# The turned grid: u along dir and v across it, from the floor's middle, in square cells `c`;
	# cell (a, b) is turned[b * nu + a], its middle at u0 + (a + 0.5) c, v0 + (b + 0.5) c.
	var c := minf(cell.x, cell.y)
	var across := Vector2(-dir.y, dir.x)
	var mid := Vector2(w, h) * cell * 0.5
	var nu := maxi(ceili((absf(mid.x * dir.x) + absf(mid.y * dir.y)) * 2.0 / c - 1e-4), 2)
	var nv := maxi(ceili((absf(mid.x * across.x) + absf(mid.y * across.y)) * 2.0 / c - 1e-4), 2)
	var u0 := -nu * c * 0.5
	var v0 := -nv * c * 0.5
	var turned := PackedFloat32Array()
	turned.resize(nu * nv)
	var ground := PackedFloat32Array()  # the ground under each turned cell, its highest
	ground.resize(nu * nv)
	# Each turned cell takes the floor cell under its middle (off the floor, the nearest), then each
	# floor cell raises the turned cell its middle is in, so a wall a cell thin has no gaps.
	for b in nv:
		for a in nu:
			var p := mid + dir * (u0 + (a + 0.5) * c) + across * (v0 + (b + 0.5) * c)
			var i := clampi(floori(p.x / cell.x), 0, w - 1)
			var j := clampi(floori(p.y / cell.y), 0, h - 1)
			turned[b * nu + a] = seeds[j * w + i]
			ground[b * nu + a] = solid[j * w + i]
	for j in h:
		for i in w:
			var q := Vector2((i + 0.5) * cell.x, (j + 0.5) * cell.y) - mid
			var a := clampi(floori((q.dot(dir) - u0) / c), 0, nu - 1)
			var b := clampi(floori((q.dot(across) - v0) / c), 0, nv - 1)
			turned[b * nu + a] = maxf(turned[b * nu + a], seeds[j * w + i])
			ground[b * nu + a] = maxf(ground[b * nu + a], solid[j * w + i])
	var side := SIDE_SLOPE * c
	for a in nu:
		for b in range(1, nv):
			var t := b * nu + a
			turned[t] = maxf(turned[t], minf(turned[t - nu] - side, ground[t] + deepest))
		for b in range(nv - 2, -1, -1):
			var t := b * nu + a
			turned[t] = maxf(turned[t], minf(turned[t + nu] - side, ground[t] + deepest))
	var fall := slope * c
	for b in nv:
		for a in range(b * nu + 1, (b + 1) * nu):
			turned[a] = maxf(turned[a], minf(turned[a - 1] - fall, ground[a] + deepest))
	var surface := PackedFloat32Array()
	surface.resize(w * h)
	for j in h:
		for i in w:
			var q := Vector2((i + 0.5) * cell.x, (j + 0.5) * cell.y) - mid
			var fu := (q.dot(dir) - u0) / c - 0.5
			var fv := (q.dot(across) - v0) / c - 0.5
			var a := clampi(floori(fu), 0, nu - 2)
			var b := clampi(floori(fv), 0, nv - 2)
			var tu := clampf(fu - a, 0.0, 1.0)
			var tv := clampf(fv - b, 0.0, 1.0)
			var k := b * nu + a
			# Blended between the four round it, leaving out any no drift reached.
			var sum := 0.0
			var weight := 0.0
			for corner in [[k, (1.0 - tu) * (1.0 - tv)], [k + 1, tu * (1.0 - tv)],
					[k + nu, (1.0 - tu) * tv], [k + nu + 1, tu * tv]]:
				var t := turned[corner[0]]
				if t > NO_SEED * 0.5:
					sum += t * corner[1]
					weight += corner[1]
			surface[j * w + i] = sum / weight if weight > 1e-6 else NO_SEED
	return surface


## `depth` (metres per cell, laid out as the floor's image is) rounded off over each cell's own
## ground: twice, each cell the mean of its neighbours on the same ground, never across a wall or a
## roof's edge. What the field heads for, so a drift's surface is smooth.
static func rounded(rain_floor: OvercastRainFloor, depth: PackedFloat32Array) -> PackedFloat32Array:
	var dims := rain_floor.image.get_size()
	var w := dims.x
	var h := dims.y
	var ground := _floats(rain_floor.image, Image.FORMAT_RF)
	var out := depth
	for _round in 2:
		var smooth := out.duplicate()
		for j in h:
			for i in w:
				var c := j * w + i
				var sum := 0.0
				var count := 0
				for nj in range(maxi(j - 1, 0), mini(j + 2, h)):
					for ni in range(maxi(i - 1, 0), mini(i + 2, w)):
						var o := nj * w + ni
						if absf(ground[o] - ground[c]) < SAME_GROUND:
							sum += out[o]
							count += 1
				smooth[c] = sum / count
		out = smooth
	return out


## Mesh arrays (Mesh.ARRAY_*) for drifted snow on `rain_floor`: faces wherever `heap` (metres per
## cell, as OvercastSnowField holds it) heaps past the even layer `layer`, which the ground's own
## snow draws. Vertices lie on the ground, in world space, each with the field cell whose snow
## raises it in UV, in texels, for shaders/drift.gdshader. One on a wall's cell takes the deepest
## heap beside it, so the heap runs up to the wall's face; the wall hides the rest. Safe off the
## main thread; surface_mesh makes the mesh.
static func surface_arrays(rain_floor: OvercastRainFloor, heap: PackedFloat32Array, layer: float) -> Array:
	var dims := rain_floor.image.get_size()
	var w := dims.x
	var h := dims.y
	var cell := rain_floor.size / Vector2(dims)
	var ground := _floats(rain_floor.image, Image.FORMAT_RF)
	var raised := PackedFloat32Array()
	raised.resize(w * h)
	for c in w * h:
		raised[c] = 0.0 if heap[c] < layer + HEAPED else heap[c] - layer
	var base := ground.duplicate()
	var source := PackedInt32Array()
	source.resize(w * h)
	for c in w * h:
		source[c] = c
	var heaped := raised.duplicate()
	for j in h:
		for i in w:
			var c := j * w + i
			if heaped[c] > 0.0:
				continue
			var best := -INF
			for nj in range(maxi(j - 1, 0), mini(j + 2, h)):
				for ni in range(maxi(i - 1, 0), mini(i + 2, w)):
					var o := nj * w + ni
					if heaped[o] > 0.0 and ground[o] < ground[c] - SAME_GROUND and ground[o] + heaped[o] > best:
						best = ground[o] + heaped[o]
						base[c] = ground[o]
						raised[c] = heaped[o]
						source[c] = o
	var jump := 1.5 * maxf(cell.x, cell.y)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(w * h)
	normals.resize(w * h)
	uvs.resize(w * h)
	for j in h:
		for i in w:
			var c := j * w + i
			verts[c] = Vector3(rain_floor.origin.x + (i + 0.5) * cell.x, base[c], rain_floor.origin.z + (j + 0.5) * cell.y)
			normals[c] = Vector3.UP
			uvs[c] = Vector2(source[c] % w, source[c] / w)
	var indices := PackedInt32Array()
	for j in h - 1:
		for i in w - 1:
			var a := j * w + i
			for tri in [[a, a + 1, a + w], [a + 1, a + w + 1, a + w]]:
				if raised[tri[0]] <= 0.0 and raised[tri[1]] <= 0.0 and raised[tri[2]] <= 0.0:
					continue
				var lo := minf(base[tri[0]], minf(base[tri[1]], base[tri[2]]))
				var hi := maxf(base[tri[0]], maxf(base[tri[1]], base[tri[2]]))
				if hi - lo <= jump:
					indices.append_array(tri)
	var deepest := 0.0
	for c in w * h:
		deepest = maxf(deepest, raised[c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return [arrays, deepest]


## The mesh of surface_arrays, drawn with `material` (shaders/drift.gdshader); none if it has no
## faces. Its bounds reach as high as the snow can heap, `deepest` over the layer.
static func surface_mesh(baked: Array, material: Material) -> ArrayMesh:
	var arrays: Array = baked[0]
	if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var bounds := mesh.get_aabb()
	bounds.size.y += baked[1]
	mesh.custom_aabb = bounds
	return mesh
