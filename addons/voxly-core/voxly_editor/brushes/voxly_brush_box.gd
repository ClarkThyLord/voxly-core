@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/box.svg")

var _drag_origin: Vector3i = Vector3i.ZERO
var _dragging: bool = false
var _cached_drag_positions: Array[Vector3i] = []

func _init() -> void:
	name = "box"
	display_name = "Box"
	requires_drag = true
	icon = ICON

## Box defines its shape by dragging, so continuous painting doesn't apply.
func supports_continuous() -> bool:
	return false

# Returns the voxel position at the given hit, with tool placement offset applied.
# Only offsets on DDA hits (existing voxels), not cage wall hits.
func _compute_offset_pos(editor, hit: Dictionary) -> Vector3i:
	var pos := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	return offset_for_tool(editor, pos, normal, hit.get("dda_hit", false))

func get_positions(editor, hit: Dictionary) -> Array[Vector3i]:
	# While actively dragging, return the cached preview positions.
	# When not dragging, compute single position from hit.
	if _dragging:
		return _cached_drag_positions.duplicate()
	if hit.is_empty():
		return []
	var pos := _compute_offset_pos(editor, hit)
	return [pos]

func on_drag_start(editor, hit: Dictionary) -> void:
	_dragging = true
	_cached_drag_positions.clear()
	# Compute the offset origin (with tool placement) for the first voxel.
	_drag_origin = _compute_offset_pos(editor, hit)
	# Cache the single origin position so click-without-drag still works
	_cached_drag_positions = [_drag_origin]

var _drag_current: Vector3i = Vector3i.ZERO

func on_drag_move(editor, hit: Dictionary) -> Array[Vector3i]:
	if not _dragging:
		return []
	# Compute the offset end position using the current hit's normal.
	var current := _compute_offset_pos(editor, hit)
	_drag_current = current
	
	# Calculate box from (offset) origin to (offset) current
	var min_pos := Vector3i(
		mini(_drag_origin.x, current.x),
		mini(_drag_origin.y, current.y),
		mini(_drag_origin.z, current.z)
	)
	var max_pos := Vector3i(
		maxi(_drag_origin.x, current.x),
		maxi(_drag_origin.y, current.y),
		maxi(_drag_origin.z, current.z)
	)
	
	var positions: Array[Vector3i] = []
	for x in range(min_pos.x, max_pos.x + 1):
		for y in range(min_pos.y, max_pos.y + 1):
			for z in range(min_pos.z, max_pos.z + 1):
				positions.append(Vector3i(x, y, z))
	
	_cached_drag_positions = positions
	return positions

func get_drag_info() -> String:
	if not _dragging:
		return ""
	var min_pos := Vector3i(
		mini(_drag_origin.x, _drag_current.x),
		mini(_drag_origin.y, _drag_current.y),
		mini(_drag_origin.z, _drag_current.z)
	)
	var max_pos := Vector3i(
		maxi(_drag_origin.x, _drag_current.x),
		maxi(_drag_origin.y, _drag_current.y),
		maxi(_drag_origin.z, _drag_current.z)
	)
	var dx := max_pos.x - min_pos.x + 1
	var dy := max_pos.y - min_pos.y + 1
	var dz := max_pos.z - min_pos.z + 1
	return "Box: %dx%dx%d" % [dx, dy, dz]

func on_drag_end() -> void:
	_dragging = false
	_cached_drag_positions.clear()
