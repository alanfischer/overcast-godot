@tool
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


## Drifts lie on faces at least this level (their normal's y): off steeper ones the snow slides.
const LIES_ON := 0.7
## Vertices closer than this (m) are one, so faces that meet share their edge.
const WELD := 0.001
## What a cell a vertex lies with but has no share of counts for, by how near it is (_weld).
const NEAR := 1e-3
## How far (cells) a vertex looks for its own ground past a wall's or a ledge's cells, which read
## their top up to a cell out from their face.
const REACH := 1.5
## UV2.x of a vertex on a drift's side, at its top and at its foot (shaders/drift.gdshaderinc).
const SIDE_TOP := 1.0
const SIDE_FOOT := 2.0


## What drifts lie on (lay), for surface_arrays.
class Ground extends RefCounted:
	var dims := Vector2i.ZERO
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()  # the first of the four field cells about each vertex
	var uv2s := PackedVector2Array()  # x: 0 the drift's top, SIDE_TOP, SIDE_FOOT
	var weights := PackedFloat32Array()  # four a vertex: its share of each cell's snow
	var cells := PackedInt32Array()  # four a vertex: those cells, as indices into the field
	var tris := PackedInt32Array()


## What drifts lie on: the faces of `faces` (world-space triangles, three vertices each, wound as
## Godot draws them) that face up and that rain reaches on `rain_floor`, cut along the lines through
## its cells' middles so that each piece lies among four cells and takes a blend of their snow. A
## vertex leaves out any of the four whose ground is not its own (a wall's, the floor past a
## ledge), so a drift ends where its face does, and where nothing lies beside it there a side runs
## down from the snow's top to the face's edge. Once for a floor; safe off the main thread.
static func lay(rain_floor: OvercastRainFloor, faces: PackedVector3Array) -> Ground:
	var g := Ground.new()
	g.dims = rain_floor.image.get_size()
	var cell := rain_floor.size / Vector2(g.dims)
	var corner := Vector2(rain_floor.origin.x, rain_floor.origin.z)
	var heights := _floats(rain_floor.image, Image.FORMAT_RF)
	var covered := PackedFloat32Array()  # the ground under a roof, per cell; NO_SEED where none
	covered.resize(heights.size())
	covered.fill(NO_SEED)
	if rain_floor.under and rain_floor.under.get_size() == g.dims:
		var gaps := _floats(rain_floor.under, Image.FORMAT_RGF)
		for i in heights.size():
			if gaps[i * 2] > gaps[i * 2 + 1]:
				covered[i] = gaps[i * 2 + 1]
	var reach := REACH * maxf(cell.x, cell.y)
	var welded := {}
	for t in range(0, faces.size() - 2, 3):
		var a := faces[t]
		var b := faces[t + 1]
		var c := faces[t + 2]
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		if n.y < LIES_ON:
			continue
		# A cell is as high as its highest point, so on a slope it stands off a vertex's ground by
		# up to the slope across a cell and a half.
		var same := SAME_GROUND + sqrt(1.0 - n.y * n.y) / n.y * reach
		for piece in _cut(PackedVector3Array([a, b, c]), corner, cell, g.dims):
			if not _near_ground(piece, corner, cell, g.dims, heights, same):
				continue
			var ids := PackedInt32Array()
			var reached := false
			for p in piece:
				var id := _weld(g, welded, p, corner, cell, heights, covered, same)
				ids.append(id)
				reached = reached or g.weights[id * 4] + g.weights[id * 4 + 1] \
					+ g.weights[id * 4 + 2] + g.weights[id * 4 + 3] > 0.0
			if not reached:
				continue
			for k in range(1, ids.size() - 1):
				var p0 := g.verts[ids[0]]
				if (g.verts[ids[k]] - p0).cross(g.verts[ids[k + 1]] - p0).length_squared() > 1e-10:
					g.tris.append_array([ids[0], ids[k], ids[k + 1]])
	_add_sides(g)
	return g


## `poly` (convex, in the world) cut to the floor and split along the lines through the middles
## of its cells.
static func _cut(poly: PackedVector3Array, corner: Vector2, cell: Vector2, dims: Vector2i) -> Array[PackedVector3Array]:
	var pieces: Array[PackedVector3Array] = []
	for axis in [0, 2]:
		var lo := corner.x if axis == 0 else corner.y
		var span := cell.x * dims.x if axis == 0 else cell.y * dims.y
		poly = _split(poly, axis, lo)[1]
		poly = _split(poly, axis, lo + span)[0]
		if poly.size() < 3:
			return pieces
	var strips: Array[PackedVector3Array] = []
	_split_along(poly, 0, corner.x, cell.x, dims.x, strips)
	for strip in strips:
		_split_along(strip, 2, corner.y, cell.y, dims.y, pieces)
	return pieces


## Whether any cell near `piece` (all within one blend's four) has ground within `same` of it.
static func _near_ground(piece: PackedVector3Array, corner: Vector2, cell: Vector2, dims: Vector2i,
		heights: PackedFloat32Array, same: float) -> bool:
	var mid := Vector3.ZERO
	var lo := INF
	var hi := -INF
	for p in piece:
		mid += p
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	mid /= piece.size()
	var i := floori((mid.x - corner.x) / cell.x - 0.5)
	var j := floori((mid.z - corner.y) / cell.y - 0.5)
	for nj in range(maxi(j - 1, 0), mini(j + 3, dims.y)):
		for ni in range(maxi(i - 1, 0), mini(i + 3, dims.x)):
			var y := heights[nj * dims.x + ni]
			if y >= lo - same and y <= hi + same:
				return true
	return false


## `poly` split on `axis` at from + (i + 0.5) * step for each i under n it crosses, into `out`.
static func _split_along(poly: PackedVector3Array, axis: int, from: float, step: float, n: int,
		out: Array[PackedVector3Array]) -> void:
	var lo := INF
	var hi := -INF
	for p in poly:
		lo = minf(lo, p[axis])
		hi = maxf(hi, p[axis])
	var rest := poly
	for i in range(maxi(ceili((lo - from) / step - 0.5), 0), mini(floori((hi - from) / step - 0.5), n - 1) + 1):
		var halves := _split(rest, axis, from + (i + 0.5) * step)
		if halves[0].size() >= 3:
			out.append(halves[0])
		rest = halves[1]
		if rest.size() < 3:
			return
	out.append(rest)


## `poly` either side of `at` on `axis`: [below, above].
static func _split(poly: PackedVector3Array, axis: int, at: float) -> Array[PackedVector3Array]:
	var below := PackedVector3Array()
	var above := PackedVector3Array()
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		var dp := p[axis] - at
		var dq := q[axis] - at
		if dp <= 0.0:
			below.append(p)
		if dp >= 0.0:
			above.append(p)
		if (dp < 0.0 and dq > 0.0) or (dp > 0.0 and dq < 0.0):
			var x := p.lerp(q, dp / (dp - dq))
			x[axis] = at
			below.append(x)
			above.append(x)
	return [below, above]


## The vertex at `p`, made the first time: it takes the snow of the four cells about it that it lies
## with (ground within `same` of its own), each by how near it is.
static func _weld(g: Ground, welded: Dictionary, p: Vector3, corner: Vector2, cell: Vector2,
		heights: PackedFloat32Array, covered: PackedFloat32Array, same: float) -> int:
	var key := Vector3i(roundi(p.x / WELD), roundi(p.y / WELD), roundi(p.z / WELD))
	var id: int = welded.get(key, -1)
	if id >= 0:
		return id
	id = g.verts.size()
	welded[key] = id
	g.verts.append(p)
	g.normals.append(Vector3.UP)
	g.uv2s.append(Vector2.ZERO)
	var w := g.dims.x
	var fx := (p.x - corner.x) / cell.x - 0.5
	var fz := (p.z - corner.y) / cell.y - 0.5
	# The four it lies among (either side, on a line through their middles); past a wall's or a
	# ledge's cell, which reads its top a cell or so out from its face, the nearest with its ground.
	var best := _cells_about(fx, fz, [floori(fx - 1e-4), floori(fx + 1e-4)],
		[floori(fz - 1e-4), floori(fz + 1e-4)], g.dims, heights, p.y, same)
	var own := clampi(floori(fz + 0.5), 0, g.dims.y - 1) * w + clampi(floori(fx + 0.5), 0, w - 1)
	if absf(covered[own] - p.y) <= same:
		best = [0.0, 0, 0, [0.0, 0.0, 0.0, 0.0]]  # under a roof
	elif best[0] <= 0.0:
		best = _cells_about(fx, fz, range(floori(fx) - 1, floori(fx) + 2),
			range(floori(fz) - 1, floori(fz) + 2), g.dims, heights, p.y, same)
	var sum: float = best[3][0] + best[3][1] + best[3][2] + best[3][3]
	var i0: int = best[1]
	var j0: int = best[2]
	g.uvs.append(Vector2(i0, j0))
	for k in 4:
		g.weights.append(best[3][k] / sum if sum > 0.0 else 0.0)
		g.cells.append(mini(j0 + k / 2, g.dims.y - 1) * w + mini(i0 + k % 2, g.dims.x - 1))
	return id


## Of the four cells from each (i, j) of `xs` x `zs`, those with ground within `same` of `y`, the
## best: [score, i, j, shares]. Each takes its share of a blend at (fx, fz), in cells, and a hair
## more by how near it is, so one with no share still counts.
static func _cells_about(fx: float, fz: float, xs: Array, zs: Array, dims: Vector2i,
		heights: PackedFloat32Array, y: float, same: float) -> Array:
	var best := [0.0, 0, 0, [0.0, 0.0, 0.0, 0.0]]
	for fi: int in xs:
		for fj: int in zs:
			var i := clampi(fi, 0, maxi(dims.x - 2, 0))
			var j := clampi(fj, 0, maxi(dims.y - 2, 0))
			var tx := clampf(fx - i, 0.0, 1.0)
			var tz := clampf(fz - j, 0.0, 1.0)
			var i1 := mini(i + 1, dims.x - 1)
			var j1 := mini(j + 1, dims.y - 1)
			var around := [j * dims.x + i, j * dims.x + i1, j1 * dims.x + i, j1 * dims.x + i1]
			var share := [(1.0 - tx) * (1.0 - tz), tx * (1.0 - tz), (1.0 - tx) * tz, tx * tz]
			var score := 0.0
			var nearest := 0.0
			var ws := [0.0, 0.0, 0.0, 0.0]
			for k in 4:
				var off := Vector2(fx - (i + k % 2), fz - (j + k / 2)).length()
				if absf(heights[around[k]] - y) > same or off > REACH:
					continue
				var near := 1.0 / (1.0 + off)
				ws[k] = share[k] + NEAR * near
				score += share[k]
				nearest = maxf(nearest, near)
			score += NEAR * nearest
			if score > best[0]:
				best = [score, i, j, ws]
	return best


## A side down each edge only one face has, from the snow's top to the face's edge, facing out:
## where a drift ends at a ledge it stands flush with the ledge's face. Against a wall the wall
## hides it, and where faces meet without sharing their edge it lies under the snow.
static func _add_sides(g: Ground) -> void:
	var edges := {}  # Vector2i(lower, higher) -> Vector3i(from, to, the face's third), x -1 once two have it
	for t in range(0, g.tris.size(), 3):
		for e in 3:
			var p := g.tris[t + e]
			var q := g.tris[t + (e + 1) % 3]
			var key := Vector2i(mini(p, q), maxi(p, q))
			edges[key] = Vector3i(-1, -1, -1) if edges.has(key) else Vector3i(p, q, g.tris[t + (e + 2) % 3])
	for key: Vector2i in edges:
		var e: Vector3i = edges[key]
		if e.x < 0:
			continue
		var a := g.verts[e.x]
		var along := g.verts[e.y] - a
		var out := Vector3(along.z, 0.0, -along.x)
		if out.length_squared() < 1e-10:
			continue
		out = out.normalized()
		if out.dot(g.verts[e.z] - a) > 0.0:
			out = -out
		var at := g.verts.size()
		for id in [e.x, e.y]:
			for side in [SIDE_TOP, SIDE_FOOT]:
				g.verts.append(g.verts[id])
				g.normals.append(out)
				g.uvs.append(g.uvs[id])
				g.uv2s.append(Vector2(side, 0.0))
				for k in 4:
					g.weights.append(g.weights[id * 4 + k])
					g.cells.append(g.cells[id * 4 + k])
		_face(g, [at, at + 2, at + 3], out)
		_face(g, [at, at + 3, at + 1], out)


## A side's triangle `ids`, wound to face `facing` (its tops stood up, as the shader raises them).
static func _face(g: Ground, ids: Array, facing: Vector3) -> void:
	var p: Array[Vector3] = []
	for id: int in ids:
		p.append(g.verts[id] + (Vector3.UP if g.uv2s[id].x == SIDE_TOP else Vector3.ZERO))
	if (p[2] - p[0]).cross(p[1] - p[0]).dot(facing) < 0.0:
		ids = [ids[0], ids[2], ids[1]]
	g.tris.append_array(ids)


## Mesh arrays (Mesh.ARRAY_*) for drifted snow on `ground` (lay): the faces wherever `heap`
## (metres per cell, as OvercastSnowField holds it) heaps past the even layer `layer`, which the
## ground's own snow draws. Vertices lie on the ground, for shaders/drift.gdshader to raise by the
## field's snow. Safe off the main thread; surface_mesh makes the mesh.
static func surface_arrays(ground: Ground, heap: PackedFloat32Array, layer: float) -> Array:
	var raised := PackedByteArray()
	raised.resize(ground.verts.size())
	var deepest := 0.0
	for v in ground.verts.size():
		for k in 4:
			if ground.weights[v * 4 + k] > 0.0:
				var over := heap[ground.cells[v * 4 + k]] - layer
				if over >= HEAPED:
					raised[v] = 1
					deepest = maxf(deepest, over)
	var indices := PackedInt32Array()
	var tris := ground.tris
	for t in range(0, tris.size(), 3):
		if raised[tris[t]] or raised[tris[t + 1]] or raised[tris[t + 2]]:
			indices.append_array([tris[t], tris[t + 1], tris[t + 2]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ground.verts
	arrays[Mesh.ARRAY_NORMAL] = ground.normals
	arrays[Mesh.ARRAY_TEX_UV] = ground.uvs
	arrays[Mesh.ARRAY_TEX_UV2] = ground.uv2s
	arrays[Mesh.ARRAY_CUSTOM0] = ground.weights
	arrays[Mesh.ARRAY_INDEX] = indices
	return [arrays, deepest]


## The mesh of surface_arrays, drawn with `material` (shaders/drift.gdshader); none if it has no
## faces. Its bounds reach as high as the snow can heap, `deepest` over the layer.
static func surface_mesh(baked: Array, material: Material) -> ArrayMesh:
	var arrays: Array = baked[0]
	if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, material)
	var bounds := mesh.get_aabb()
	bounds.size.y += baked[1]
	mesh.custom_aabb = bounds
	return mesh
