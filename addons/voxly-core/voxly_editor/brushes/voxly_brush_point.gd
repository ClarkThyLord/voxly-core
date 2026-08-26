@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/point.svg")

func _init() -> void:
	name = "point"
	display_name = "Point"
	requires_drag = false
	icon = ICON

func get_options() -> Array[Dictionary]:
	return [
		{"label": "Continuous", "property": "continuous", "type": TYPE_BOOL, "default": false},
	]

func get_positions(editor, hit: Dictionary) -> Array[Vector3i]:
	if hit.is_empty():
		return []
	
	var pos := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	# Apply tool placement only when hitting an existing voxel via DDA.
	# Cage wall hits already resolve to the correct interior cell.
	return [offset_for_tool(editor, pos, normal, hit.get("dda_hit", false))]
