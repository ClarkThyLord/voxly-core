## Cylinder brush: stamps a cylinder of voxels around the hovered cell, with a
## configurable axis orientation (auto from the hit normal, or fixed X/Y/Z).
@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/cylinder.svg")

## Cylinder radius in voxels.
var _radius: int = 2
## Cylinder height in voxels.
var _height: int = 1
## Cylinder axis (0 = X, 1 = Y, 2 = Z).
var _axis_orientation: int = 0

## Registers the cylinder brush in the registry.
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

## Returns the cylinder options.
func get_options() -> Array[Dictionary]:
	return [
		{"label": "Continuous", "property": "continuous", "type": TYPE_BOOL, "default": false},
		{"label": "Radius", "property": "radius", "type": TYPE_INT, "default": 2, "min": 1, "max": 32, "step": 1},
		{"label": "Height", "property": "height", "type": TYPE_INT, "default": 1, "min": 1, "max": 32, "step": 1},
		{"label": "Axis", "property": "axis_orientation", "type": TYPE_INT, "default": 0, "min": 0, "max": 3, "step": 1,
		 "hint": "0=Auto, 1=X, 2=Y, 3=Z"},
	]

## Resolves the cylinder axis from the configured orientation and the hit normal.
## Fixed orientations map 1=X, 2=Y, 3=Z. In auto mode the dominant axis of the
## normal wins. Returns -1 when the axis cannot be determined.
func _get_axis(normal: Vector3i, orientation: int) -> int:
	if orientation > 0:
		return orientation - 1
	# Auto: use the dominant axis of the normal.
	var normal_abs_sum := absi(normal.x) + absi(normal.y) + absi(normal.z)
	if normal_abs_sum == 0:
		return -1
	if normal.x != 0:
		return 0  # X axis
	elif normal.y != 0:
		return 1  # Y axis
	elif normal.z != 0:
		return 2  # Z axis
	return -1

## Returns the cylinder voxel positions.
func get_positions(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	if hit.is_empty():
		return []
	var center := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	# Apply tool placement only when hitting an existing voxel via DDA.
	center = offset_for_tool(editor, center, normal, hit.get("dda_hit", false))
	
	var axis := _get_axis(normal, _axis_orientation)
	if axis < 0:
		return []
	
	var radius_squared := _radius * _radius
	var positions: Array[Vector3i] = []
	
	match axis:
		0:  # X axis: cross-section in YZ.
			for height_offset in range(_height):
				for y in range(-_radius, _radius + 1):
					for z in range(-_radius, _radius + 1):
						if y * y + z * z <= radius_squared:
							positions.append(center + Vector3i(height_offset - (_height / 2), y, z))
		1:  # Y axis: cross-section in XZ.
			for height_offset in range(_height):
				for x in range(-_radius, _radius + 1):
					for z in range(-_radius, _radius + 1):
						if x * x + z * z <= radius_squared:
							positions.append(center + Vector3i(x, height_offset - (_height / 2), z))
		2:  # Z axis: cross-section in XY.
			for height_offset in range(_height):
				for x in range(-_radius, _radius + 1):
					for y in range(-_radius, _radius + 1):
						if x * x + y * y <= radius_squared:
							positions.append(center + Vector3i(x, y, height_offset - (_height / 2)))
	
	return positions
