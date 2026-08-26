@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/cube.svg")

var _size_x: int = 2
var _size_y: int = 2
var _size_z: int = 2

func _init() -> void:
	name = "cube"
	display_name = "Cube"
	requires_drag = false
	icon = ICON

## Size in voxels along the X axis (half-extent).
var size_x: int:
	get: return _size_x
	set(v):
		_size_x = maxi(v, 0)

## Size in voxels along the Y axis (half-extent).
var size_y: int:
	get: return _size_y
	set(v):
		_size_y = maxi(v, 0)

## Size in voxels along the Z axis (half-extent).
var size_z: int:
	get: return _size_z
	set(v):
		_size_z = maxi(v, 0)

func get_options() -> Array[Dictionary]:
	return [
		{"label": "Continuous", "property": "continuous", "type": TYPE_BOOL, "default": false},
		{"label": "Size X", "property": "size_x", "type": TYPE_INT, "default": 2, "min": 0, "max": 32, "step": 1},
		{"label": "Size Y", "property": "size_y", "type": TYPE_INT, "default": 2, "min": 0, "max": 32, "step": 1},
		{"label": "Size Z", "property": "size_z", "type": TYPE_INT, "default": 2, "min": 0, "max": 32, "step": 1}
	]

func get_positions(editor, hit: Dictionary) -> Array[Vector3i]:
	if hit.is_empty():
		return []
	var center := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	# Apply tool placement only when hitting an existing voxel via DDA.
	center = offset_for_tool(editor, center, normal, hit.get("dda_hit", false))
	
	var positions: Array[Vector3i] = []
	for x in range(-_size_x, _size_x + 1):
		for y in range(-_size_y, _size_y + 1):
			for z in range(-_size_z, _size_z + 1):
				positions.append(center + Vector3i(x, y, z))
	return positions
