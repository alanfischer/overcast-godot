extends "res://tests/suite.gd"

const RainFloor = preload("res://addons/overcast/overcast_rain_floor.gd")


func _box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	body.position = pos
	_root().add_child(body)
	return _keep(body)


func test_rain_stops_on_the_roof_and_the_ground() -> void:
	_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))  # ground, top at 0
	_box(Vector3(6, 0.2, 6), Vector3(0, 3.0, 0))   # roof, top at 3.1
	await (Engine.get_main_loop() as SceneTree).physics_frame
	await (Engine.get_main_loop() as SceneTree).physics_frame
	var box := AABB(Vector3(-10, -2, -10), Vector3(20, 12, 20))
	var f := RainFloor.bake(_root().get_world_3d(), box, 1.0)
	var img: Image = f.image
	assert_eq(img.get_size(), Vector2i(20, 20), "a cell a metre")
	assert_eq(f.origin, box.position, "from the box's min corner")
	assert_almost_eq(f.top, 10.0, 1e-6, "and no rain over its top")
	assert_almost_eq(img.get_pixel(10, 10).r, 3.1, 0.01, "under the roof rain stops on it")
	assert_almost_eq(img.get_pixel(2, 2).r, 0.0, 0.01, "in the open it reaches the ground")
	# The roof spans x -3..3, i.e. cells 7..12; cell 6 touches its edge with a corner.
	assert_almost_eq(img.get_pixel(6, 10).r, 3.1, 0.01, "a cell the roof's edge crosses counts as covered")
	assert_almost_eq(img.get_pixel(5, 10).r, 0.0, 0.01, "the next one out is open")


func test_a_baked_floor_saves_and_loads() -> void:
	var img := Image.create_empty(3, 2, false, Image.FORMAT_RF)
	img.set_pixel(2, 1, Color(4.5, 0, 0))
	var f := RainFloor.create(img, Vector3(-1, 0, -1), Vector2(3, 2), 9.0)
	var path := "user://overcast_test_floor.res"
	assert_eq(ResourceSaver.save(f, path), OK, "it saves")
	var loaded: RainFloor = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_almost_eq(loaded.image.get_pixel(2, 1).r, 4.5, 1e-6, "its heights")
	assert_eq(loaded.origin, Vector3(-1, 0, -1), "its corner")
	assert_eq(loaded.size, Vector2(3, 2), "its span")
	assert_almost_eq(loaded.top, 9.0, 1e-6, "and its top")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_air_under_cover_is_baked_and_walls_are_solid() -> void:
	_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))   # ground, top at 0
	_box(Vector3(6, 0.2, 6), Vector3(0, 3.0, 0))    # roof on nothing, 2.9..3.1
	_box(Vector3(1, 0.5, 1), Vector3(-1.5, 0.75, -1.5))  # a crate under it, 0.5..1.0
	_box(Vector3(1, 4, 1), Vector3(6.5, 2, 0.5))      # a wall, 0..4
	_box(Vector3(1, 2.9, 1), Vector3(2.5, 1.45, 2.5))  # a post holding the roof up, 0..2.9
	_box(Vector3(1, 1.0, 1), Vector3(0.5, 2.4, -2.5))  # a beam under the roof, 1.9..2.9
	await (Engine.get_main_loop() as SceneTree).physics_frame
	await (Engine.get_main_loop() as SceneTree).physics_frame
	var f := RainFloor.bake(_root().get_world_3d(), AABB(Vector3(-10, -2, -10), Vector3(20, 12, 20)), 1.0)
	assert_eq(f.under.get_size(), f.image.get_size(), "a gap per cell")
	assert_eq(f.under.get_format(), Image.FORMAT_RGF)
	var gap := f.under.get_pixel(9, 11)
	assert_almost_eq(gap.r, 2.9, 0.01, "under the roof the air reaches its underside")
	assert_almost_eq(gap.g, 0.0, 0.01, "from the ground")
	gap = f.under.get_pixel(8, 8)
	assert_almost_eq(gap.r, 2.9, 0.01, "over the crate it is the roof's underside, not the crate's")
	assert_almost_eq(gap.g, 1.0, 0.01, "down to the crate's top")
	gap = f.under.get_pixel(16, 10)
	assert_true(gap.r < 0.5, "a wall has no air in it below its top (%s)" % gap)
	gap = f.under.get_pixel(10, 7)
	assert_almost_eq(gap.r, 1.9, 0.01, "under a beam the air reaches the beam's underside")
	assert_almost_eq(gap.g, 0.0, 0.01, "from the ground")
	gap = f.under.get_pixel(12, 12)
	assert_true(gap.r < 0.5, "nor does a post under the roof (%s)" % gap)
