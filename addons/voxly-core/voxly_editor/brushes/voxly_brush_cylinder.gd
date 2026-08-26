@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/cylinder.svg")
var _radius: int = 2
var _height: int = 1
var _axis_orientation: int = 0

func _init() -> void:
	name = "cylinder"
	display_name = "Cylinder"
	requires_drag = false
	icon = ICON

## The radius of the cylinder in voxel units.
var radius: int:
	get: return _radius
	set(v):
		_radius = maxi(v, 1)

## The height of the cylinder in voxel units.
var height: int:
	get: return _height
	set(v):
		_height = maxi(v, 1)

## Fixed axis orientation for the cylinder (0=auto from normal, 1=X, 2=Y, 3=Z).
var axis_orientation: int:
	get: return _axis_orientation
	set(v):
		_axis_orientation = clampi(v, 0, 3)

func get_options() -> Array[Dictionary]:
	return [
		{"label": "Continuous", "property": "continuous", "type": TYPE_BOOL, "default": false},
		{"label": "Radius", "property": "radius", "type": TYPE_INT, "default": 2, "min": 1, "max": 32, "step": 1},
		{"label": "Height", "property": "height", "type": TYPE_INT, "default": 1, "min": 1, "max": 32, "step": 1},
		{"label": "Axis", "property": "axis_orientation", "type": TYPE_INT, "default": 0, "min": 0, "max": 3, "step": 1,
		 "hint": "0=Auto, 1=X, 2=Y, 3=Z"}
	]

func _get_axis(normal: Vector3i, orientation: int) -> int:
	if orientation > 0:
		# Fixed orientation: 1=X, 2=Y, 3=Z
		return orientation - 1
	# Auto: use the dominant axis of the normal
	var abs_n := absi(normal.x) + absi(normal.y) + absi(normal.z)
	if abs_n == 0:
		return -1
	if normal.x != 0:
		return 0  # X axis
	elif normal.y != 0:
		return 1  # Y axis
	elif normal.z != 0:
		return 2  # Z axis
	return -1

func get_positions(editor, hit: Dictionary) -> Array[Vector3i]:
	if hit.is_empty():
		return []
	var center := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	# Apply tool placement only when hitting an existing voxel via DDA.
	center = offset_for_tool(editor, center, normal, hit.get("dda_hit", false))
	
	var axis := _get_axis(normal, _axis_orientation)
	if axis < 0:
		return []
	
	var r2 = _radius * _radius
	var positions: Array[Vector3i] = []
	
	match axis:
		0:  # X axis — cross-section in YZ
			for h in range(_height):
				for y in range(-_radius, _radius + 1):
					for z in range(-_radius, _radius + 1):
						if y * y + z * z <= r2:
							positions.append(center + Vector3i(h - (_height / 2), y, z))
		1:  # Y axis — cross-section in XZ
			for h in range(_height):
				for x in range(-_radius, _radius + 1):
					for z in range(-_radius, _radius + 1):
						if x * x + z * z <= r2:
							positions.append(center + Vector3i(x, h - (_height / 2), z))
		2:  # Z axis — cross-section in XY
			for h in range(_height):
				for x in range(-_radius, _radius + 1):
					for y in range(-_radius, _radius + 1):
						if x * x + y * y <= r2:
							positions.append(center + Vector3i(x, y, h - (_height / 2)))
	
	return positions
