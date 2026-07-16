@tool
extends Node3D

@export
var camera_speed := 1.0

@onready
var camera_pivot : Node3D = %CameraPivot

func _process(delta : float) -> void:
	if Engine.is_editor_hint():
		return
	
	if camera_pivot:
		camera_pivot.rotate_y(1 * delta)
