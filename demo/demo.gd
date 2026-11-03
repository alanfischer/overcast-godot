extends Node3D
## A field, a few huts and the weather over them. Drag to look, WASD to walk, and the panel on the
## left drives the rain.

const Weather = preload("res://addons/overcast/overcast_weather.gd")
const SkyScript = preload("res://addons/overcast/overcast_sky.gd")
const Clouds = preload("res://addons/overcast/overcast_clouds.gd")
const Cycle = preload("res://addons/overcast/overcast_cycle.gd")
const RainFloor = preload("res://addons/overcast/overcast_rain_floor.gd")
const GroundShader = preload("res://demo/ground.gdshader")

const FIELD := 120.0

@onready var sun: DirectionalLight3D = $Sun
@onready var camera: Camera3D = $Camera3D
@onready var weather: Weather = $Weather
@onready var rain_slider: HSlider = %Rain
@onready var cycle_check: CheckBox = %Cycle

var sky: SkyScript
var cycle := Cycle.new()
var _cycle_t := 0.0
var _yaw := 0.0
var _pitch := 0.15


func _ready() -> void:
	sky = SkyScript.new({"sun_dir": SkyScript.sun_dir_of(sun), "cloud_amount": 0.45})
	$WorldEnvironment.environment = sky.make_environment()
	weather.sky = sky
	weather.area = AABB(Vector3(-FIELD / 2, 0, -FIELD / 2), Vector3(FIELD, 4, FIELD))

	_add_box(Vector3(FIELD, 1, FIELD), Vector3(0, -0.5, 0), Color(0.36, 0.45, 0.26))
	for hut in [Vector3(0, 0, -12), Vector3(14, 0, -6), Vector3(-12, 0, -20)]:
		_add_hut(hut)

	# Physics has to have the boxes before the rain floor can be traced against them.
	await get_tree().physics_frame
	await get_tree().physics_frame
	weather.set_rain_floor(RainFloor.bake(get_world_3d(),
		AABB(Vector3(-FIELD / 2, -1, -FIELD / 2), Vector3(FIELD, 20, FIELD)), 0.5))
	weather.add_wet_materials(self)

	rain_slider.value_changed.connect(func(v: float) -> void:
		cycle_check.button_pressed = false
		weather.rain = v)
	%Volumetric.toggled.connect(Clouds.set_volumetric)
	%Strike.pressed.connect(func() -> void: weather.strike(randi()))
	%Night.value_changed.connect(_set_night)
	cycle_check.toggled.connect(func(on: bool) -> void:
		_cycle_t = 0.0
		cycle.restart())


func _add_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("color", color)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	body.add_child(mi)
	body.position = pos
	add_child(body)


## Four posts and a roof: open sides, so you can watch the rain stop at its edge.
func _add_hut(at: Vector3) -> void:
	var wood := Color(0.45, 0.33, 0.22)
	for x in [-3.0, 3.0]:
		for z in [-2.5, 2.5]:
			_add_box(Vector3(0.3, 3.0, 0.3), at + Vector3(x, 1.5, z), wood)
	_add_box(Vector3(7.0, 0.3, 6.0), at + Vector3(0, 3.15, 0), Color(0.55, 0.3, 0.25))


func _set_night(n: float) -> void:
	var light := Color(1, 1, 1).lerp(Color(0.12, 0.14, 0.24), n)
	weather.night = n
	weather.sky_light = light
	sun.light_color = light
	sky.material.set_shader_parameter("star_amount", n * 0.8)
	sky.material.set_shader_parameter("zenith_color", Color(0.25, 0.42, 0.70).lerp(Color(0.02, 0.03, 0.07), n))
	sky.material.set_shader_parameter("horizon_color", Color(0.62, 0.70, 0.82).lerp(Color(0.06, 0.07, 0.12), n))
	sky.params["horizon_color"] = Color(0.62, 0.70, 0.82).lerp(Color(0.06, 0.07, 0.12), n)


func _process(delta: float) -> void:
	if cycle_check.button_pressed:
		_cycle_t += delta * 20.0  # a shower every half minute or so, to watch it come and go
		weather.rain = cycle.rain_at(_cycle_t)
		rain_slider.set_value_no_signal(weather.rain)
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	for key in [[KEY_A, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN]]:
		if Input.is_physical_key_pressed(key[0]):
			move += key[1]
	var basis := Basis(Vector3.UP, _yaw)
	camera.position += basis * Vector3(move.x, 0, move.y) * 6.0 * delta
	camera.rotation = Vector3(_pitch, _yaw, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= event.relative.x * 0.004
		_pitch = clampf(_pitch - event.relative.y * 0.004, -1.4, 1.4)
