extends SceneTree
## Screenshots of the demo for the README: OUT=dir, and RAIN=0.8 SNOW=1 VOL=1 TIME=18.5 to vary it;
## CLEARED=1 clears the sky over the settled weather.
##   godot --path . -s res://tools/screenshot.gd

const Clouds = preload("res://addons/overcast/overcast_clouds.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_environment("OUT")
	var demo: Node3D = load("res://demo/demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	Clouds.set_volumetric(OS.get_environment("VOL") == "1")
	if OS.get_environment("TIME") != "":
		demo.get_node("%Time").value = float(OS.get_environment("TIME"))
	var rain := float(OS.get_environment("RAIN")) if OS.get_environment("RAIN") != "" else 0.0
	demo.get_node("%Rain").value = rain
	if OS.get_environment("SNOW") != "":
		demo.get_node("%Snow").value = float(OS.get_environment("SNOW"))
	for i in 20:
		await physics_frame
	var weather = demo.get_node("Weather")
	weather.settle()
	if OS.get_environment("CLEARED") == "1":  # the snow lying, and the sky cleared over it
		weather.rain = 0.0
		weather.storm = 0.0
		weather.snowy = 0.0
	demo.get_node("UI").visible = false
	var views := {"field": [Vector3(0, 1.7, 8), 0.12, 0.0], "up": [Vector3(0, 1.7, 8), 0.7, 0.6],
		"hut": [Vector3(-4, 1.7, -4), -0.05, 0.9], "ground": [Vector3(0, 1.7, 8), -0.45, 0.0]}
	for name in views:
		var v: Array = views[name]
		demo._yaw = v[2]
		demo._pitch = v[1]
		demo.camera.position = v[0]
		for i in 30:
			await process_frame
		if OS.get_environment("STRIKE") == "1":
			weather.strike(7)
			for i in 3:
				await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	quit()
