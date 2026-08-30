## Line brush: defines a voxel line (optionally thickened) by dragging from one
## corner to another, rendered with the 3D Bresenham algorithm.
@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/line.svg")

## Voxel position where the drag started.
var _drag_origin: Vector3i = Vector3i.ZERO
## True while a drag is in progress.
var _dragging: bool = false
## Cached positions computed during the drag.
var _cached_drag_positions: Array[Vector3i] = []
## Line thickness in voxels.
var _width: int = 1
## Current drag end position.
var _drag_end: Vector3i = Vector3i.ZERO

## Registers the line brush in the registry.
func _init() -> void:
	name = "line"
	display_name = "Line"
	requires_drag = true
	icon = ICON

## Returns whether this brush supports continuous painting.
func supports_continuous() -> bool:
	return false

## Width/thickness of the line in voxel units.
var width: int:
	set(v):
		_width = maxi(v, 1)

## Returns the line width option.
func get_options() -> Array[Dictionary]:
	return [
		{"label": "Width", "property": "width", "type": TYPE_INT, "default": 1, "min": 1, "max": 16, "step": 1},
	]

## Returns the voxel position at the given hit, with tool placement offset
## applied.
func _compute_offset_position(editor: VoxlyEditor, hit: Dictionary) -> Vector3i:
	var position := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	return offset_for_tool(editor, position, normal, hit.get("dda_hit", false))

## Returns the line voxel positions.
func get_positions(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	# While actively dragging, return the cached preview positions.
	if _dragging:
		return _cached_drag_positions.duplicate()
	elif hit.is_empty():
		return []
	var position := _compute_offset_position(editor, hit)
	return [position]

## Records the line origin.
func on_drag_start(editor: VoxlyEditor, hit: Dictionary) -> void:
	_dragging = true
	_cached_drag_positions.clear()
	# Compute the offset origin (with tool placement) for the first voxel.
	_drag_origin = _compute_offset_position(editor, hit)
	# Cache the single origin position so click-without-drag still works.
	_cached_drag_positions = [_drag_origin]

## Computes the line to the current hit.
func on_drag_move(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	if not _dragging:
		return []
	
	# Compute the offset end position using the current hit's normal.
	var end_position := _compute_offset_position(editor, hit)
	_drag_end = end_position
	# Draw the Bresenham line between the (already-offset) origin and the end.
	var spine := _bresenham_3d(_drag_origin, end_position)
	
	# Apply width: expand each spine voxel to a box of the given size.
	if _width > 1:
		var half := _width / 2
		var expanded: Array[Vector3i] = []
		for spine_position in spine:
			for x in range(-half, _width - half):
				for y in range(-half, _width - half):
					for z in range(-half, _width - half):
						expanded.append(spine_position + Vector3i(x, y, z))
		# Deduplicate.
		var seen: Dictionary[Vector3i, bool] = {}
		var unique: Array[Vector3i] = []
		for position in expanded:
			if not seen.has(position):
				seen[position] = true
				unique.append(position)
		_cached_drag_positions = unique
		return unique
	
	_cached_drag_positions = spine
	return spine

## Returns a length summary for the drag status.
func get_drag_info() -> String:
	if not _dragging:
		return ""
	
	var size_x := absi(_drag_end.x - _drag_origin.x) + 1
	var size_y := absi(_drag_end.y - _drag_origin.y) + 1
	var size_z := absi(_drag_end.z - _drag_origin.z) + 1
	return "Line: %dx%dx%d" % [size_x, size_y, size_z]

## Clears the drag state.
func on_drag_end() -> void:
	_dragging = false

## Bresenham 3D line algorithm, returns all voxel positions along a line.
func _bresenham_3d(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	var positions: Array[Vector3i] = []
	var current := from
	
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var dz := absi(to.z - from.z)
	
	var sx := 1 if to.x > from.x else -1
	var sy := 1 if to.y > from.y else -1
	var sz := 1 if to.z > from.z else -1
	
	if dx >= dy and dx >= dz:
		var py := 2 * dy - dx
		var pz := 2 * dz - dx
		for i in range(dx + 1):
			positions.append(current)
			if py >= 0:
				current.y += sy
				py -= 2 * dx
			if pz >= 0:
				current.z += sz
				pz -= 2 * dx
			py += 2 * dy
			pz += 2 * dz
			current.x += sx
	elif dy >= dx and dy >= dz:
		var px := 2 * dx - dy
		var pz := 2 * dz - dy
		for i in range(dy + 1):
			positions.append(current)
			if px >= 0:
				current.x += sx
				px -= 2 * dy
			if pz >= 0:
				current.z += sz
				pz -= 2 * dy
			px += 2 * dx
			pz += 2 * dz
			current.y += sy
	else:
		var px := 2 * dx - dz
		var py := 2 * dy - dz
		for i in range(dz + 1):
			positions.append(current)
			if px >= 0:
				current.x += sx
				px -= 2 * dz
			if py >= 0:
				current.y += sy
				py -= 2 * dz
			px += 2 * dx
			py += 2 * dy
			current.z += sz
	
	return positions
