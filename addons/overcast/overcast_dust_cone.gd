@tool
class_name OvercastDustCone
extends Node3D
## A gust of dust blown out of a point along a cone: the weather's grit streaks and wisps
## (OvercastWeather's dust), carried by one jet of air of its own rather than the wind, so it blows
## under a roof as well. It points down -Z, widening from `start_radius` at the node to `end_radius`
## `length` out.
##
## Set `blowing` and the dust runs out from the mouth; clear it and the last of it runs off the end,
## then `blown_out` is emitted. `reach` cuts it short where something stands in the way. It draws
## unshaded, in `light` (the scene's light where it blows, which only the game knows).

signal blown_out

const _MOTE_COLOR := Color(0.6, 0.53, 0.43)
## The motes ride out at 3/4 to 6/4 the mean speed: wrapping their flow at 4 keeps each one's
## place unbroken at the wrap.
const _FLOW_WRAP := 4.0
## The last of it leaves at this share of the mouth speed once the air stops.
const _TAIL_SPEED := 0.5

@export var blowing := false:
	set(value):
		if value == blowing:
			return
		blowing = value
		if blowing:
			_front = 0.0
			_tail = 0.0
		_set_visible()
@export_range(0.5, 100.0, 0.1, "or_greater") var length := 8.0
@export_range(0.0, 10.0, 0.05, "or_greater") var start_radius := 0.5
@export_range(0.0, 50.0, 0.05, "or_greater") var end_radius := 4.0
## How fast (m/s) the air leaves the mouth: the dust slows to a third of it by the end.
@export_range(0.0, 100.0, 0.5, "or_greater") var speed := 30.0
## Radians each mote turns about the axis on its way down: a whirl (a dust devil, the debris round
## a tornado's foot) rather than a jet.
@export_range(-50.0, 50.0, 0.1) var twist := 0.0
## How far down it (m) the dust shows: where something stands in the way.
@export var reach := INF
@export_range(0, 20000, 10) var motes := 1500
## The share of the motes that are wisps, soft puffs of fine dust, rather than grit.
@export_range(0.0, 1.0, 0.01) var wisps := 0.1
@export var color := _MOTE_COLOR
## The light on the dust where it blows; with `color` it gives what the dust shows.
@export var light := Color.WHITE
## How far the dust hazes over distance, as the weather's rain_haze does its own.
@export var haze_density := 0.0

var _mesh: MultiMeshInstance3D
var _material: ShaderMaterial
var _flowed := 0.0
var _front := 0.0
var _tail := INF
var _linear_output := true


func _ready() -> void:
	_linear_output = OvercastSky._renderer_is_linear()
	_material = ShaderMaterial.new()
	_material.shader = preload("res://addons/overcast/shaders/dust_cone.gdshader")
	_material.render_priority = Material.RENDER_PRIORITY_MAX
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.surface_set_material(0, _material)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	_mesh = MultiMeshInstance3D.new()
	_mesh.name = "Dust"
	_mesh.multimesh = multimesh
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh, false, Node.INTERNAL_MODE_FRONT)
	if blowing:
		_front = length
		_tail = 0.0
	_set_visible()
	_push()


## Whether any of it is up: blowing, or the last of it still running off the end.
func visible_dust() -> bool:
	return blowing or _tail < length


func _process(delta: float) -> void:
	if not visible_dust():
		return
	if speed > 0.0:
		_flowed = fposmod(_flowed + speed / (1.5 * length) * delta, _FLOW_WRAP)
	if blowing:
		_front = minf(_front + speed * delta, length)
	else:
		_tail += speed * _TAIL_SPEED * delta
		if _tail >= length:
			_set_visible()
			blown_out.emit()
			return
	_push()


func _push() -> void:
	if _material == null:
		return
	var count := maxi(motes, 0)
	if _mesh.multimesh.instance_count != count:
		_mesh.multimesh.instance_count = count
	var c := color * light
	if not _linear_output:
		c = c.linear_to_srgb()
	_material.set_shader_parameter("color", Vector3(c.r, c.g, c.b))
	_material.set_shader_parameter("cone_xform", Projection(global_transform))
	_material.set_shader_parameter("cone_length", length)
	_material.set_shader_parameter("start_radius", start_radius)
	_material.set_shader_parameter("end_radius", end_radius)
	_material.set_shader_parameter("speed", speed)
	_material.set_shader_parameter("twist", twist)
	_material.set_shader_parameter("wisps", wisps)
	_material.set_shader_parameter("flowed", _flowed)
	_material.set_shader_parameter("front", _front)
	_material.set_shader_parameter("tail", _tail if not blowing else 0.0)
	_material.set_shader_parameter("reach", minf(reach, 1e5))
	_material.set_shader_parameter("haze_density", haze_density)
	# The shader puts every mote itself, anywhere down the cone.
	var r := maxf(start_radius, end_radius) + 2.0
	_mesh.custom_aabb = AABB(Vector3(-r, -r, -length - 2.0), Vector3(2.0 * r, 2.0 * r, length + 4.0))


func _set_visible() -> void:
	if _mesh:
		_mesh.visible = visible_dust()
