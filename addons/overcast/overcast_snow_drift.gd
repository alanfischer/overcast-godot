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
const SIDE_SLOPE := 0.7
## debug_mesh's snow is red this deep, with a contour every DEBUG_CONTOUR metres of depth.
const DEBUG_RED := 1.5
const DEBUG_CONTOUR := 0.25
const DEBUG_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float red;
uniform float contour;
varying float depth;
void vertex() {
	depth = UV.x;
}
void fragment() {
	float t = clamp(depth / red, 0.0, 1.0);
	vec3 c = mix(vec3(0.55, 0.65, 0.9), vec3(0.95, 0.85, 0.2), smoothstep(0.0, 0.5, t));
	c = mix(c, vec3(0.9, 0.15, 0.1), smoothstep(0.5, 1.0, t));
	float d = depth / contour;
	float line = 1.0 - smoothstep(0.0, 1.5 * fwidth(d), abs(d - round(d)));
	ALBEDO = mix(c, vec3(0.05), line * step(0.5, d));
	ROUGHNESS = 1.0;
}
"""


## Metres of snow on each cell of `rain_floor` once it has all settled, FORMAT_RF, laid out as the
## floor's image is. `depth` is the even layer a calm leaves; `wind` the steady wind (y ignored).
static func bake(rain_floor: OvercastRainFloor, wind: Vector3, depth := 0.3) -> Image:
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
		var lee := _sweep(solid, dims, cell, flat.normalized(), LEE_FILL, LEE_SLOPE)
		var bank := _sweep(solid, dims, cell, -flat.normalized(), WINDWARD_FILL, WINDWARD_SLOPE)
		var bare := depth * (1.0 - SCOUR)
		for i in n:
			var drift := 0.0 if roofed[i] else maxf(lee[i], bank[i]) - solid[i]
			out[i] = lerpf(depth, maxf(bare, drift), k)
	return Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RF, out.to_byte_array())


static func _floats(img: Image, format: Image.Format) -> PackedFloat32Array:
	if img.get_format() != format:
		img = img.duplicate()
		img.convert(format)
	return img.get_data().to_float32_array()


## The snow surface a wind along `dir` drifts over `solid` (heights, row by row): each cell sheds
## `fill` of its height over the lowest ground beside it, falling `slope` a metre along `dir` and
## SIDE_SLOPE a metre across it, and keeps the highest of what reaches it. Worked on a grid turned
## to the wind, where each fall is taken exactly a row or a column at a time, then read back.
static func _sweep(solid: PackedFloat32Array, dims: Vector2i, cell: Vector2, dir: Vector2,
		fill: float, slope: float) -> PackedFloat32Array:
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
			seeds[j * w + i] = foot + (g - foot) * fill
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
	# Each turned cell takes the floor cell under its middle (off the floor, the nearest), then each
	# floor cell raises the turned cell its middle is in, so a wall a cell thin has no gaps.
	for b in nv:
		for a in nu:
			var p := mid + dir * (u0 + (a + 0.5) * c) + across * (v0 + (b + 0.5) * c)
			var i := clampi(floori(p.x / cell.x), 0, w - 1)
			var j := clampi(floori(p.y / cell.y), 0, h - 1)
			turned[b * nu + a] = seeds[j * w + i]
	for j in h:
		for i in w:
			var q := Vector2((i + 0.5) * cell.x, (j + 0.5) * cell.y) - mid
			var a := clampi(floori((q.dot(dir) - u0) / c), 0, nu - 1)
			var b := clampi(floori((q.dot(across) - v0) / c), 0, nv - 1)
			turned[b * nu + a] = maxf(turned[b * nu + a], seeds[j * w + i])
	var side := SIDE_SLOPE * c
	for a in nu:
		for b in range(1, nv):
			turned[b * nu + a] = maxf(turned[b * nu + a], turned[(b - 1) * nu + a] - side)
		for b in range(nv - 2, -1, -1):
			turned[b * nu + a] = maxf(turned[b * nu + a], turned[(b + 1) * nu + a] - side)
	var fall := slope * c
	for b in nv:
		for a in range(b * nu + 1, (b + 1) * nu):
			turned[a] = maxf(turned[a], turned[a - 1] - fall)
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
			var k := b * nu + a
			surface[j * w + i] = lerpf(lerpf(turned[k], turned[k + 1], tu),
				lerpf(turned[k + nu], turned[k + nu + 1], tu), clampf(fv - b, 0.0, 1.0))
	return surface


## A mesh of the snow `drift` (bake) lays on `rain_floor`, in world space, coloured by how deep it
## is: blue shallow, yellow, then red at DEBUG_RED metres and deeper, with contours. To see a bake.
static func debug_mesh(rain_floor: OvercastRainFloor, drift: Image) -> ArrayMesh:
	var dims := rain_floor.image.get_size()
	var w := dims.x
	var h := dims.y
	var cell := rain_floor.size / Vector2(dims)
	var depths := _floats(drift, Image.FORMAT_RF)
	var tops := _floats(rain_floor.image, Image.FORMAT_RF)
	for c in w * h:
		tops[c] += depths[c]
	# Neighbours further apart than this are on different surfaces (a roof's edge over the ground).
	var jump := 1.5 * maxf(cell.x, cell.y)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j in h:
		for i in w:
			var c := j * w + i
			var y := tops[c]
			verts.append(Vector3(rain_floor.origin.x + (i + 0.5) * cell.x, y, rain_floor.origin.z + (j + 0.5) * cell.y))
			var dx := (_near(tops, c + 1, y, jump) if i + 1 < w else y) - (_near(tops, c - 1, y, jump) if i > 0 else y)
			var dz := (_near(tops, c + w, y, jump) if j + 1 < h else y) - (_near(tops, c - w, y, jump) if j > 0 else y)
			normals.append(Vector3(-dx / (2.0 * cell.x), 1.0, -dz / (2.0 * cell.y)).normalized())
			uvs.append(Vector2(depths[c], 0.0))
	var indices := PackedInt32Array()
	for j in h - 1:
		for i in w - 1:
			var a := j * w + i
			for tri in [[a, a + 1, a + w], [a + 1, a + w + 1, a + w]]:
				var lo := minf(tops[tri[0]], minf(tops[tri[1]], tops[tri[2]]))
				var hi := maxf(tops[tri[0]], maxf(tops[tri[1]], tops[tri[2]]))
				var deep := maxf(depths[tri[0]], maxf(depths[tri[1]], depths[tri[2]]))
				if hi - lo <= jump and deep > 0.01:
					indices.append_array(tri)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if indices.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = DEBUG_SHADER
	mat.set_shader_parameter("red", DEBUG_RED)
	mat.set_shader_parameter("contour", DEBUG_CONTOUR)
	mesh.surface_set_material(0, mat)
	return mesh


static func _near(tops: PackedFloat32Array, c: int, y: float, jump: float) -> float:
	return tops[c] if absf(tops[c] - y) <= jump else y
