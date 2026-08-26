@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/sphere.svg")

var _radius: int = 2

func _init() -> void:
	name = "sphere"
	display_name = "Sphere"
	requires_drag = false
	icon = ICON

## The radius of the sphere in voxel units.
var radius: int:
	set(v):
		_radius = maxi(v, 1)

func get_options() -> Array[Dictionary]:
	return [
		{"label": "Continuous", "property": "continuous", "type": TYPE_BOOL, "default": false},
		{"label": "Radius", "property": "radius", "type": TYPE_INT, "default": 2, "min": 1, "max": 32, "step": 1}
	]

func get_positions(editor, hit: Dictionary) -> Array[Vector3i]:
	if hit.is_empty():
		return []
	
	var center := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	# Apply tool placement only when hitting an existing voxel via DDA.
	center = offset_for_tool(editor, center, normal, hit.get("dda_hit", false))
	
	var positions: Array[Vector3i] = []
	var r2 := _radius * _radius
	for x in range(-_radius, _radius + 1):
		for y in range(-_radius, _radius + 1):
			for z in range(-_radius, _radius + 1):
				if x * x + y * y + z * z <= r2:
					positions.append(center + Vector3i(x, y, z))
	
	return positions
