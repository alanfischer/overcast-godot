extends "res://tests/suite.gd"

const RainFloor = preload("res://addons/overcast/overcast_rain_floor.gd")
const Drift = preload("res://addons/overcast/overcast_snow_drift.gd")
const NO_GAP := -1e6

const W := 60
const H := 30


## Flat ground at 0, a cell a metre, with `walls` (Rect2i of cells -> height) standing solid on it
## and `roofs` (Rect2i -> height) over open air.
func _floor(walls := {}, roofs := {}) -> RainFloor:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RF)
	var air := Image.create_empty(W, H, false, Image.FORMAT_RGF)
	air.fill(Color(NO_GAP, NO_GAP, 0))
	for rect: Rect2i in walls:
		img.fill_rect(rect, Color(walls[rect], 0, 0))
	for rect: Rect2i in roofs:
		img.fill_rect(rect, Color(roofs[rect], 0, 0))
		air.fill_rect(rect, Color(roofs[rect] - 0.2, 0.0, 0))
	return RainFloor.create(img, Vector3.ZERO, Vector2(W, H), 10.0, air)


func _at(img: Image, i: int, j: int) -> float:
	return img.get_pixel(i, j).r


func test_a_calm_leaves_an_even_layer() -> void:
	var f := _floor({Rect2i(20, 10, 1, 10): 2.0})
	var d := Drift.bake(f, Vector3(1, 0, 0), 0.3)
	assert_eq(d.get_size(), Vector2i(W, H))
	assert_eq(d.get_format(), Image.FORMAT_RF)
	for p in [Vector2i(5, 5), Vector2i(21, 15), Vector2i(20, 15), Vector2i(50, 25)]:
		assert_almost_eq(_at(d, p.x, p.y), 0.3, 1e-5, "even at %s" % p)


func test_a_wall_drifts_deep_in_its_lee_and_runs_out_downwind() -> void:
	# A wall 2 m high across the wind, at x 20, z 10..19; the wind blows +x.
	var f := _floor({Rect2i(20, 10, 1, 10): 2.0})
	var d := Drift.bake(f, Vector3(10, 0, 0), 0.3)
	var behind := _at(d, 21, 15)
	assert_almost_eq(behind, minf(2.0 * Drift.LEE_FILL, Drift.DEEPEST) - Drift.LEE_SLOPE, 1e-4,
		"against its lee it fills most of the way up")
	assert_gt(behind, _at(d, 25, 15), "and is shallower further off")
	assert_gt(_at(d, 25, 15), _at(d, 30, 15), "and shallower still")
	assert_almost_eq(_at(d, 40, 15), 0.3 * (1.0 - Drift.SCOUR), 1e-5, "it has run out by 10 heights off")
	assert_almost_eq(_at(d, 5, 5), 0.3 * (1.0 - Drift.SCOUR), 1e-5, "the open is scoured")
	var bank := _at(d, 19, 15)
	assert_almost_eq(bank, 2.0 * Drift.WINDWARD_FILL - Drift.WINDWARD_SLOPE, 1e-4, "a smaller bank on its windward side")
	assert_lt(_at(d, 17, 15), bank, "falling off upwind")
	assert_almost_eq(_at(d, 20, 15), 0.3 * (1.0 - Drift.SCOUR), 1e-5, "its top is scoured too")
	assert_lt(_at(d, 25, 22), _at(d, 25, 15), "past its end the drift falls away sideways")


func test_a_cliff_drifts_no_deeper_than_a_wall() -> void:
	var f := _floor({Rect2i(20, 0, 1, 30): 20.0})
	var d := Drift.bake(f, Vector3(10, 0, 0), 0.3)
	assert_almost_eq(_at(d, 21, 15), Drift.DEEPEST - Drift.LEE_SLOPE, 1e-4, "a 20 m cliff's lee starts as deep as DEEPEST")
	assert_almost_eq(_at(d, 40, 15), 0.3 * (1.0 - Drift.SCOUR), 1e-5,
		"and runs out as soon as a drift that deep would, not across the map")
	assert_lt(_at(d, 19, 15), Drift.DEEPEST, "its windward bank is no deeper")


func test_the_drift_follows_the_wind() -> void:
	var f := _floor({Rect2i(30, 10, 1, 10): 2.0})
	var east := Drift.bake(f, Vector3(10, 0, 0))
	var west := Drift.bake(f, Vector3(-10, 0, 0))
	assert_gt(_at(east, 31, 15), 1.0, "east of it in an east wind")
	assert_almost_eq(_at(west, 29, 15), _at(east, 31, 15), 1e-4, "west of it, as deep, in a west wind")
	assert_almost_eq(_at(west, 31, 15), _at(east, 29, 15), 1e-4, "and the bank swaps sides")


func test_a_light_wind_drifts_less() -> void:
	var f := _floor({Rect2i(20, 10, 1, 10): 2.0})
	var breeze := _at(Drift.bake(f, Vector3(Drift.CALM, 0, 0)), 21, 15)
	var mid := _at(Drift.bake(f, Vector3((Drift.CALM + Drift.DRIFTING) * 0.5, 0, 0)), 21, 15)
	var gale := _at(Drift.bake(f, Vector3(Drift.DRIFTING * 2.0, 0, 0)), 21, 15)
	assert_almost_eq(breeze, 0.3, 1e-5, "none at CALM")
	assert_gt(mid, breeze)
	assert_gt(gale, mid)


func test_the_wind_blows_under_a_roof_on_posts() -> void:
	# A roof 3 m up over open air, x 20..25: it drifts nothing, and none lies under it.
	var f := _floor({}, {Rect2i(20, 10, 6, 10): 3.0})
	var d := Drift.bake(f, Vector3(10, 0, 0), 0.3)
	var bare := 0.3 * (1.0 - Drift.SCOUR)
	assert_almost_eq(_at(d, 27, 15), bare, 1e-5, "nothing in its lee")
	assert_almost_eq(_at(d, 22, 15), bare, 1e-5, "its top is scoured like the open")


func test_a_slanted_wind_drifts_both_sides_alike() -> void:
	# A pillar two cells square in a wind at 45 degrees: the drift is as deep either side of the
	# line downwind. (One cell square is turned to the wind lopsidedly, by up to a tenth.)
	var f := _floor({Rect2i(20, 15, 2, 2): 2.0})
	var d := Drift.bake(f, Vector3(10, 0, 10))
	assert_gt(_at(d, 23, 18), 0.5, "downwind of it")
	assert_almost_eq(_at(d, 24, 18), _at(d, 23, 19), 0.05, "as deep either side")


func test_a_wind_off_the_grid_drifts_as_far() -> void:
	# The same wall in a wind 22 degrees off its square: the drift runs as far downwind of it.
	var f := _floor({Rect2i(20, 5, 1, 20): 2.0})
	var dir := Vector3(cos(0.38), 0, sin(0.38))
	var square := Drift.bake(f, Vector3(10, 0, 0))
	var slanted := Drift.bake(f, dir * 10.0)
	var off := Vector2(21, 15) + Vector2(dir.x, dir.z) * 6.0
	assert_almost_eq(_at(slanted, roundi(off.x), roundi(off.y)), _at(square, 27, 15), 0.15,
		"6 m downwind, as deep as straight behind it in a square wind")


func test_a_game_can_drift_shallower() -> void:
	var f := _floor({Rect2i(20, 0, 1, 30): 20.0})
	var d := Drift.bake(f, Vector3(10, 0, 0), 0.3, 0.6)
	assert_almost_eq(_at(d, 21, 15), 0.6 - Drift.LEE_SLOPE, 1e-4, "a lee starts no deeper than it is told")


func test_a_broad_block_drifts_no_deeper_than_a_wall() -> void:
	# A building 10 m deep and 20 m tall: its top is not a drift to spread over the ground past it.
	var f := _floor({Rect2i(10, 5, 10, 20): 20.0})
	var d := Drift.bake(f, Vector3(10, 0, 0), 0.3)
	assert_almost_eq(_at(d, 20, 15), Drift.DEEPEST - Drift.LEE_SLOPE, 1e-4, "its lee starts as deep as a wall's")
	for x in range(21, 40):
		assert_lt(_at(d, x, 15), Drift.DEEPEST, "and is no deeper %d m downwind" % (x - 19))
	assert_almost_eq(_at(d, 15, 15), 0.3 * (1.0 - Drift.SCOUR), 1e-5, "its top is scoured, not buried")


func test_a_drift_does_not_carry_on_over_a_drop() -> void:
	# A step 0.5 m up at x 10..29, falling 8 m at x 30 to ground at -7.5.
	var img := Image.create_empty(W, H, false, Image.FORMAT_RF)
	img.fill_rect(Rect2i(10, 0, 20, H), Color(0.5, 0, 0))
	img.fill_rect(Rect2i(30, 0, W - 30, H), Color(-7.5, 0, 0))
	var f := RainFloor.create(img, Vector3.ZERO, Vector2(W, H), 10.0)
	var d := Drift.bake(f, Vector3(10, 0, 0), 0.3)
	for x in range(30, W):
		assert_lt(_at(d, x, 15), Drift.DEEPEST + 1e-4, "no deeper than a wall's past the drop, %d m on" % (x - 29))
	assert_almost_eq(_at(d, 45, 15), 0.3 * (1.0 - Drift.SCOUR), 1e-5, "and run out by 15 m")


## A box's faces, wound as Godot draws them.
func _box(size: Vector3, middle: Vector3) -> PackedVector3Array:
	var mesh := BoxMesh.new()
	mesh.size = size
	return Transform3D(Basis(), middle) * mesh.get_faces()


## The snow a vertex of `g` takes from `heap` over `layer`.
func _thick(g: Drift.Ground, v: int, heap: PackedFloat32Array, layer := 0.3) -> float:
	var t := 0.0
	for k in 4:
		t += g.weights[v * 4 + k] * maxf(heap[g.cells[v * 4 + k]] - layer, 0.0)
	return t


func _heap(f: RainFloor, cells: Dictionary, layer := 0.3) -> PackedFloat32Array:
	var heap := PackedFloat32Array()
	heap.resize(W * H)
	heap.fill(layer)
	for rect: Rect2i in cells:
		for j in range(rect.position.y, rect.end.y):
			for i in range(rect.position.x, rect.end.x):
				heap[j * W + i] = cells[rect]
	return heap


## Ground at 0 to a ledge at x 20.4, off a cell's line, and 2 m down past it: the cells across the
## ledge read the ground above, as rain stops on its highest point.
func _ledge() -> Array:
	var f := _floor({Rect2i(21, 0, W - 21, H): -2.0})
	var faces := _box(Vector3(20.4, 1, H), Vector3(10.2, -0.5, H * 0.5))
	faces.append_array(_box(Vector3(W - 20.4, 1, H), Vector3(20.4 + (W - 20.4) * 0.5, -2.5, H * 0.5)))
	return [f, Drift.lay(f, faces)]


func test_a_drift_ends_where_its_ledge_does() -> void:
	var laid := _ledge()
	var g: Drift.Ground = laid[1]
	var heap := _heap(laid[0], {Rect2i(15, 0, 6, H): 0.8})
	var furthest := -INF
	for v in g.verts.size():
		if g.uv2s[v].x == 0.0 and g.verts[v].y > -1.0 and _thick(g, v, heap) > 0.0:
			furthest = maxf(furthest, g.verts[v].x)
	assert_almost_eq(furthest, 20.4, 1e-4, "the drift on the ledge reaches its edge and no further")
	var side := false
	for v in g.verts.size():
		if g.uv2s[v].x == Drift.SIDE_TOP and absf(g.verts[v].x - 20.4) < 1e-4 and g.verts[v].y > -1.0:
			side = side or (g.normals[v].x > 0.99 and _thick(g, v, heap) > 0.4)
	assert_true(side, "where a side stands flush with the ledge's face, facing off it")


func test_the_floor_under_a_ledge_takes_none_of_the_snow_on_it() -> void:
	var laid := _ledge()
	var g: Drift.Ground = laid[1]
	var heap := _heap(laid[0], {Rect2i(15, 0, 6, H): 0.8})
	for v in g.verts.size():
		if g.verts[v].y < -1.0:
			assert_almost_eq(_thick(g, v, heap), 0.0, 1e-6, "none at %s, 2 m below" % g.verts[v])


func test_a_drift_meets_the_wall_it_lies_against() -> void:
	# A wall over x 10.3..11.3; the cells across its faces read its top.
	var f := _floor({Rect2i(10, 0, 2, H): 2.0})
	var faces := _box(Vector3(W, 1, H), Vector3(W * 0.5, -0.5, H * 0.5))
	faces.append_array(_box(Vector3(1, 2, H), Vector3(10.8, 1.0, H * 0.5)))
	var g := Drift.lay(f, faces)
	var heap := _heap(f, {Rect2i(12, 0, 1, H): 1.2})
	var at_face := -1.0
	for v in g.verts.size():
		if g.uv2s[v].x == 0.0 and absf(g.verts[v].y) < 1e-4 and g.verts[v].x > 11.0 and g.verts[v].x < 11.8:
			at_face = maxf(at_face, _thick(g, v, heap))
	assert_almost_eq(at_face, 0.9, 1e-3, "the floor up to the wall's face takes the lee's snow, all of it")


func test_no_drift_lies_on_the_floor_under_a_roof() -> void:
	var f := _floor({}, {Rect2i(30, 5, 10, 10): 3.0})
	var g := Drift.lay(f, _box(Vector3(W, 1, H), Vector3(W * 0.5, -0.5, H * 0.5)))
	for t in range(0, g.tris.size(), 3):
		var mid := (g.verts[g.tris[t]] + g.verts[g.tris[t + 1]] + g.verts[g.tris[t + 2]]) / 3.0
		assert_false(mid.x > 31.0 and mid.x < 39.0 and mid.z > 6.0 and mid.z < 14.0,
			"no face under the roof (%s)" % mid)


func test_no_drift_lies_on_a_steep_face() -> void:
	var f := _floor()
	var ramp := Transform3D(Basis(Vector3.BACK, deg_to_rad(60.0)), Vector3(30, 0, 15)) \
		* _box(Vector3(4, 0.1, 4), Vector3.ZERO)
	assert_true(Drift.lay(f, ramp).tris.is_empty(), "the snow slides off it")


func test_the_drift_faces_up() -> void:
	var laid := _ledge()
	var g: Drift.Ground = laid[1]
	var up := 0
	for t in range(0, g.tris.size(), 3):
		var a := g.verts[g.tris[t]]
		if g.uv2s[g.tris[t]].x == 0.0:
			var n := (g.verts[g.tris[t + 2]] - a).cross(g.verts[g.tris[t + 1]] - a)
			assert_gt(n.y, 0.0, "wound to face up, as Godot draws a front face")
			up += 1
	assert_gt(up, 0, "it has faces")


func test_the_drift_mesh_draws_only_where_snow_heaps() -> void:
	var laid := _ledge()
	var g: Drift.Ground = laid[1]
	var baked := Drift.surface_arrays(g, _heap(laid[0], {Rect2i(15, 0, 6, H): 0.8}), 0.3)
	var arrays: Array = baked[0]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_false(indices.is_empty(), "faces where it heaps")
	for i in indices:
		assert_true(g.verts[i].x > 13.9 and g.verts[i].x < 21.6, "and none far from it (%s)" % g.verts[i])
	assert_almost_eq(baked[1], 0.5, 1e-6, "as deep as it heaps over the layer")
	var mesh := Drift.surface_mesh(baked, null)
	assert_eq(mesh.surface_get_format(0) & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT),
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT, "each vertex's shares as four floats")
	assert_true(Drift.surface_arrays(g, _heap(laid[0], {}), 0.3)[0][Mesh.ARRAY_INDEX].is_empty(),
		"and nothing over the even layer")
