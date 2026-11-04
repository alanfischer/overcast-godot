@tool
extends EditorPlugin
## Declares Overcast's global shader uniforms (OvercastGlobals.GLOBALS) in the project, which every
## Overcast shader needs to compile. Checked on every editor start, so an update that adds one
## declares it too.

const Globals = preload("res://addons/overcast/overcast_globals.gd")
const AreaGizmo = preload("res://addons/overcast/area_gizmo.gd")

var _gizmo: EditorNode3DGizmoPlugin


func _enter_tree() -> void:
	_declare()
	_gizmo = AreaGizmo.new()
	_gizmo.undo_redo = get_undo_redo()
	add_node_3d_gizmo_plugin(_gizmo)


func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(_gizmo)


func _enable_plugin() -> void:
	_declare()


func _disable_plugin() -> void:
	for key in Globals.GLOBALS:
		ProjectSettings.set_setting("shader_globals/" + key, null)
	ProjectSettings.save()


func _declare() -> void:
	var added := false
	for key in Globals.GLOBALS:
		var setting: String = "shader_globals/" + key
		if not ProjectSettings.has_setting(setting):
			ProjectSettings.set_setting(setting,
				{"type": Globals.GLOBALS[key][0], "value": Globals.GLOBALS[key][1]})
			added = true
	if added:
		ProjectSettings.save()
	Globals.declare()  # this session's RenderingServer too, which read the settings at startup
