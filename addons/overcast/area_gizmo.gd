@tool
extends EditorNode3DGizmoPlugin
## OvercastWeather's `area` in the viewport: its box, with a handle on each face to drag.

const Weather = preload("res://addons/overcast/overcast_weather.gd")

var undo_redo: EditorUndoRedoManager


func _init() -> void:
	create_material("lines", Color(0.55, 0.75, 1.0))
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "OvercastWeather area"


func _has_gizmo(node: Node3D) -> bool:
	return node is Weather


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var box: AABB = gizmo.get_node_3d().area
	var lines := PackedVector3Array()
	for e in _EDGES:
		lines.append(box.get_endpoint(e[0]))
		lines.append(box.get_endpoint(e[1]))
	gizmo.add_lines(lines, get_material("lines", gizmo))
	var handles := PackedVector3Array()
	for id in 6:
		handles.append(_face(box, id))
	gizmo.add_handles(handles, get_material("handles", gizmo), [])


## AABB.get_endpoint indices: bit 0 is +Z, bit 1 +Y, bit 2 +X.
const _EDGES := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7],
	[0, 4], [1, 5], [2, 6], [3, 7]]
const _NAMES := ["-X", "+X", "-Y", "+Y", "-Z", "+Z"]


## The centre of face `id`: axis id / 2, the far side when id is odd.
static func _face(box: AABB, id: int) -> Vector3:
	var p := box.get_center()
	p[id / 2] = box.end[id / 2] if id % 2 else box.position[id / 2]
	return p


func _get_handle_name(_gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	return _NAMES[id]


func _get_handle_value(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().area


func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D,
		screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d()
	var to_local := node.global_transform.affine_inverse()
	var from := to_local * camera.project_ray_origin(screen_pos)
	var dir := (to_local.basis * camera.project_ray_normal(screen_pos)).normalized()
	var box: AABB = node.area
	var axis := id / 2
	var along := Vector3.ZERO
	along[axis] = 1.0
	var face := _face(box, id)
	var v: float = Geometry3D.get_closest_points_between_segments(face - along * 1e5,
		face + along * 1e5, from, from + dir * 1e5)[0][axis]
	if id % 2:
		box.size[axis] = maxf(v - box.position[axis], 0.1)
	else:
		var end: float = box.end[axis]
		box.position[axis] = minf(v, end - 0.1)
		box.size[axis] = end - box.position[axis]
	node.area = box


func _commit_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool, restore: Variant,
		cancel: bool) -> void:
	var node := gizmo.get_node_3d()
	if cancel or undo_redo == null:
		if cancel:
			node.area = restore
		return
	undo_redo.create_action("Resize Weather Area")
	undo_redo.add_do_property(node, "area", node.area)
	undo_redo.add_undo_property(node, "area", restore)
	undo_redo.commit_action(false)
