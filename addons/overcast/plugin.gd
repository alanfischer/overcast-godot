@tool
extends EditorPlugin
## Declares the cloud layer's global shader uniforms (OvercastClouds.GLOBALS) in the project, which
## every shader including clouds.gdshaderinc needs to compile.


const Clouds = preload("res://addons/overcast/overcast_clouds.gd")


func _enable_plugin() -> void:
	for key in Clouds.GLOBALS:
		var setting: String = "shader_globals/" + key
		if not ProjectSettings.has_setting(setting):
			ProjectSettings.set_setting(setting,
				{"type": Clouds.GLOBALS[key][0], "value": Clouds.GLOBALS[key][1]})
	ProjectSettings.save()


func _disable_plugin() -> void:
	for key in Clouds.GLOBALS:
		ProjectSettings.set_setting("shader_globals/" + key, null)
	ProjectSettings.save()
