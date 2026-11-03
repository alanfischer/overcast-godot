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
	var img: Image = f["image"]
	assert_eq(img.get_size(), Vector2i(20, 20), "a cell a metre")
	assert_eq(f["origin"], box.position, "from the box's min corner")
	assert_almost_eq(f["top"], 10.0, 1e-6, "and no rain over its top")
	assert_almost_eq(img.get_pixel(10, 10).r, 3.1, 0.01, "under the roof rain stops on it")
	assert_almost_eq(img.get_pixel(2, 2).r, 0.0, 0.01, "in the open it reaches the ground")
	# The roof spans x -3..3, i.e. cells 7..12; cell 6 touches its edge with a corner.
	assert_almost_eq(img.get_pixel(6, 10).r, 3.1, 0.01, "a cell the roof's edge crosses counts as covered")
	assert_almost_eq(img.get_pixel(5, 10).r, 0.0, 0.01, "the next one out is open")
