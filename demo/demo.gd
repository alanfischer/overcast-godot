extends Node3D
## A field, a few huts and the weather over them. Drag to look, WASD to walk, and the panel on the
## left drives the rain and snow.

const Weather = preload("res://addons/overcast/overcast_weather.gd")
const SkyScript = preload("res://addons/overcast/overcast_sky.gd")
const Clouds = preload("res://addons/overcast/overcast_clouds.gd")
const GroundShader = preload("res://demo/ground.gdshader")

const FIELD := 120.0
## Photographed surfaces (textures/CREDITS.md): the maps' name, and metres one spans.
const GROUND := ["forrest_ground_01", 2.0]
const POSTS := ["rough_wood", 0.6]
const ROOF := ["weathered_brown_planks", 1.8]

@onready var sun: DirectionalLight3D = $Sun
@onready var camera: Camera3D = $Camera3D
@onready var weather: Weather = $Weather
@onready var rain_slider: HSlider = %Rain
@onready var snow_slider: HSlider = %Snow
@onready var cycle_check: CheckBox = %Cycle

## The sky in the scene's WorldEnvironment, which the weather finds by itself.
var sky: SkyScript
var _surfaces := {}
var _yaw := 0.0
var _pitch := 0.15


func _ready() -> void:
	sky = $WorldEnvironment.environment.sky.sky_material
	sky.sun_dir = SkyScript.sun_dir_of(sun)

	var field := _add_box(Vector3(FIELD, 1, FIELD), Vector3(0, -0.5, 0), _surface(GROUND))
	field.set_shader_parameter("vary", true)
	for hut in [Vector3(0, 0, -12), Vector3(14, 0, -6), Vector3(-12, 0, -20)]:
		_add_hut(hut)

	# Physics has to have the boxes before the rain floor can be traced against them. A scene built
	# in the editor would bake it there instead (the weather's Bake Rain Floor).
	await get_tree().physics_frame
	await get_tree().physics_frame
	weather.bake_rain_floor()

	rain_slider.value_changed.connect(_set_falling.unbind(1))
	snow_slider.value_changed.connect(_set_falling.unbind(1))
	%Wind.value_changed.connect(func(v: float) -> void: weather.wind = Vector3(v, 0.0, v * 0.4))
	%Volumetric.toggled.connect(Clouds.set_volumetric)
	%Strike.pressed.connect(func() -> void: weather.strike(randi()))
	%Time.value_changed.connect(_set_time)
	cycle_check.toggled.connect(func(on: bool) -> void: weather.cycle = on)


## Returns the box's material.
func _add_box(size: Vector3, pos: Vector3, mat: ShaderMaterial) -> ShaderMaterial:
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
	return mat


## A material of GroundShader drawing `surface` (name, metres), one per surface, shared.
func _surface(surface: Array) -> ShaderMaterial:
	if _surfaces.has(surface[0]):
		return _surfaces[surface[0]]
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("color", Color.WHITE)
	mat.set_shader_parameter("textured", true)
	mat.set_shader_parameter("tile", surface[1])
	for map: Array in [["albedo", "diff"], ["normal", "nor_gl"], ["roughness", "rough"]]:
		mat.set_shader_parameter(map[0] + "_map",
			load("res://demo/textures/%s_%s_1k.jpg" % [surface[0], map[1]]))
	_surfaces[surface[0]] = mat
	return mat


## Four posts and a roof: open sides, so you can watch the rain stop at its edge.
func _add_hut(at: Vector3) -> void:
	for x in [-3.0, 3.0]:
		for z in [-2.5, 2.5]:
			_add_box(Vector3(0.3, 3.0, 0.3), at + Vector3(x, 1.5, z), _surface(POSTS))
	_add_box(Vector3(7.0, 0.3, 6.0), at + Vector3(0, 3.15, 0), _surface(ROOF))


## The sliders are how much rain and how much snow; the weather takes how much falls in all
## (`rain`) and the share of it that is snow (`snow`).
func _set_falling() -> void:
	cycle_check.button_pressed = false
	var total := rain_slider.value + snow_slider.value
	weather.rain = total
	if total > 0.0:
		weather.snow = snow_slider.value / total


func _set_time(hours: float) -> void:
	sky.time_of_day = hours  # the weather turns the sun, and lights its rain, to match


func _process(delta: float) -> void:
	# The eye stops down over a snowfield, as a game would by weather.snow_lying.
	$WorldEnvironment.environment.tonemap_exposure = lerpf(1.0, 0.75, weather.snow_lying)
	if weather.cycle:  # 20x, in the scene: a shower every half minute or so
		rain_slider.set_value_no_signal(weather.rainfall())
		snow_slider.set_value_no_signal(weather.snowfall())
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
