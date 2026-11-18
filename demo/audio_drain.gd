extends Node
## Holds the quit until the mixer drops the sounds the scene stopped as it was freed. A stopped
## playback goes a few mix steps later, but Godot stops the mixer right after freeing the tree, so
## the wind playing at quit could leak. Autoloads are freed after the scene.

const DRAIN_MSEC := 100


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		OS.delay_msec(DRAIN_MSEC)
