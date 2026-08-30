## Box brush: defines a cuboid region by dragging from one corner to another.
@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/box.svg")

## Voxel position where the drag started.
var _drag_origin: Vector3i = Vector3i.ZERO
## True while a drag is in progress.
var _dragging: bool = false
## Cached positions computed during the drag.
var _cached_drag_positions: Array[Vector3i] = []
## Current drag corner position.
var _drag_current: Vector3i = Vector3i.ZERO

## Registers the box brush in the registry.
func _init() -> void:
	name = "box"
	display_name = "Box"
	requires_drag = true
	icon = ICON

## Box defines its shape by dragging, so continuous painting doesn't apply.
func supports_continuous() -> bool:
	return false

## Returns the voxel position at the given hit, with tool placement offset
## applied. Only offsets on DDA hits (existing voxels), not cage wall hits.
func _compute_offset_position(editor: VoxlyEditor, hit: Dictionary) -> Vector3i:
	var position := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	return offset_for_tool(editor, position, normal, hit.get("dda_hit", false))

## Returns the box voxel positions, or the drag positions while dragging.
func get_positions(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	# While actively dragging, return the cached preview positions. When not
	# dragging, compute a single position from the hit.
	if _dragging:
		return _cached_drag_positions.duplicate()
	if hit.is_empty():
		return []
	var position := _compute_offset_position(editor, hit)
	return [position]

## Records the drag origin.
func on_drag_start(editor: VoxlyEditor, hit: Dictionary) -> void:
	_dragging = true
	_cached_drag_positions.clear()
	# Compute the offset origin (with tool placement) for the first voxel.
	_drag_origin = _compute_offset_position(editor, hit)
	# Cache the single origin position so click-without-drag still works.
	_cached_drag_positions = [_drag_origin]

## Computes the box between the origin and the current hit.
func on_drag_move(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	if not _dragging:
		return []
	# Compute the offset end position using the current hit's normal.
	var current_position := _compute_offset_position(editor, hit)
	_drag_current = current_position
	
	# Calculate the box from the (offset) origin to the (offset) current position.
	var min_position := Vector3i(
		mini(_drag_origin.x, current_position.x),
		mini(_drag_origin.y, current_position.y),
		mini(_drag_origin.z, current_position.z)
	)
	var max_position := Vector3i(
		maxi(_drag_origin.x, current_position.x),
		maxi(_drag_origin.y, current_position.y),
		maxi(_drag_origin.z, current_position.z)
	)
	
	var positions: Array[Vector3i] = []
	for x in range(min_position.x, max_position.x + 1):
		for y in range(min_position.y, max_position.y + 1):
			for z in range(min_position.z, max_position.z + 1):
				positions.append(Vector3i(x, y, z))
	
	_cached_drag_positions = positions
	return positions

## Returns a size summary for the drag status.
func get_drag_info() -> String:
	if not _dragging:
		return ""
	
	var min_position := Vector3i(
		mini(_drag_origin.x, _drag_current.x),
		mini(_drag_origin.y, _drag_current.y),
		mini(_drag_origin.z, _drag_current.z)
	)
	var max_position := Vector3i(
		maxi(_drag_origin.x, _drag_current.x),
		maxi(_drag_origin.y, _drag_current.y),
		maxi(_drag_origin.z, _drag_current.z)
	)
	var size_x := max_position.x - min_position.x + 1
	var size_y := max_position.y - min_position.y + 1
	var size_z := max_position.z - min_position.z + 1
	return "Box: %dx%dx%d" % [size_x, size_y, size_z]

## Clears the drag state.
func on_drag_end() -> void:
	_dragging = false
	_cached_drag_positions.clear()
