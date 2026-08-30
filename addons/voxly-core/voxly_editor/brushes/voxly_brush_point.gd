## Point brush: stamps a single voxel at the hovered cell.
@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/point.svg")

## Registers the point brush in the registry.
func _init() -> void:
	name = "point"
	display_name = "Point"
	requires_drag = false
	icon = ICON

## Returns no options for the point brush.
func get_options() -> Array[Dictionary]:
	return [
		{"label": "Continuous", "property": "continuous", "type": TYPE_BOOL, "default": false},
	]

## Returns a single voxel at the hit position.
func get_positions(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	if hit.is_empty():
		return []
	
	var position := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	# Apply tool placement only when hitting an existing voxel via DDA.
	# Cage wall hits already resolve to the correct interior cell.
	return [offset_for_tool(editor, position, normal, hit.get("dda_hit", false))]
