@tool
extends EditorPlugin

## Plugin information.
const NAME = "Voxly-Core"
const VERSION = "1.0.0"

func _enter_tree() -> void:
	print("%s %s is active!" % [NAME, VERSION])

func _exit_tree() -> void:
	print("%s %s is inactive!" % [NAME, VERSION])
