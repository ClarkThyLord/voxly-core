## Extrude brush: selects a face of connected voxels and extrudes it outward
## along the face normal on drag. The extrude depth is determined by the
## distance the cursor is dragged from the face.
##
## Direction is driven by the active tool's EditIntent (ADD extrudes outward,
## REMOVE extrudes inward).
@tool
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/extrude.svg")

## Positions of the face being extruded.
var _face_positions: Array[Vector3i] = []
## Normal of the face being extruded.
var _face_normal: Vector3i = Vector3i.ZERO
## True while a drag is in progress.
var _dragging: bool = false
## Cached positions computed during the drag.
var _cached_drag_positions: Array[Vector3i] = []
## Whether extrusion only fills matching voxel IDs.
var _match_id: bool = false

## Registers the extrude brush in the registry.
func _init() -> void:
	name = "extrude"
	display_name = "Extrude"
	requires_drag = true
	hit_resolution = HitResolution.VOXEL
	icon = ICON

## Extrude defines its shape by dragging, so continuous painting doesn't apply.
func supports_continuous() -> bool:
	return false

## If true, only flood-fill through voxels with the same ID as the hit position.
var match_id: bool:
	get: return _match_id
	set(v):
		_match_id = v

## Returns the extrude options.
func get_options() -> Array[Dictionary]:
	return [
		{"label": "Match ID", "property": "match_id", "type": TYPE_BOOL, "default": false},
	]

## Returns the extruded positions.
func get_positions(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	# While dragging, return the cached positions.
	if _dragging:
		return _cached_drag_positions.duplicate()
	if hit.is_empty():
		return []
	
	var position := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	
	# Extrude only works on existing voxels (DDA hit).
	if not hit.get("dda_hit", false):
		return []
	
	var adapter = editor.adapter
	if not adapter or adapter.voxel_at(position) == null:
		return []
	
	# Compute the face selection from the hit position.
	var face = adapter.get_exposed_face_voxels(position, normal, _match_id)
	if face.is_empty():
		return []
	
	# Tool placement offset: ADD offsets the preview outside the voxel to show
	# where new voxels will go; IN_PLACE tools show the face itself since we're
	# acting on the existing voxels.
	var tool_offset := Vector3i.ZERO
	if editor.active_tool and editor.active_tool.placement == VoxlyTool.Placement.ON_SURFACE:
		tool_offset = offset_for_tool(editor, position, normal, true) - position
	
	# Offset the face positions and remove duplicates.
	var is_add = editor.active_tool != null and editor.active_tool.placement == VoxlyTool.Placement.ON_SURFACE
	var seen: Dictionary[Vector3i, bool] = {}
	var result: Array[Vector3i] = []
	for face_position in face:
		var offset_position = face_position + tool_offset
		if seen.has(offset_position):
			continue
		if is_add and adapter.voxel_at(offset_position) != null:
			continue
		seen[offset_position] = true
		result.append(offset_position)
	return result

## Captures the face and normal at the drag start.
func on_drag_start(editor: VoxlyEditor, hit: Dictionary) -> void:
	_dragging = true
	_cached_drag_positions.clear()
	
	var position := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	
	var adapter = editor.adapter
	if not adapter:
		return
	
	# Compute the face selection and store it (raw, un-offset).
	_face_positions = adapter.get_exposed_face_voxels(position, normal, _match_id)
	_face_normal = normal
	
	# Bake tool placement offset into the stored face positions so that the
	# face itself is positioned correctly for the active tool.
	var tool_offset := Vector3i.ZERO
	if editor.active_tool and editor.active_tool.placement == VoxlyTool.Placement.ON_SURFACE:
		tool_offset = offset_for_tool(editor, position, normal, true) - position
	
	if tool_offset != Vector3i.ZERO:
		for i in range(_face_positions.size()):
			_face_positions[i] += tool_offset
	
	# Preview shows the (offset) face only at drag start.
	# Deduplicate to avoid rendering multiple boxes on the same position.
	var seen: Dictionary[Vector3i, bool] = {}
	var unique: Array[Vector3i] = []
	for face_position in _face_positions:
		if not seen.has(face_position):
			seen[face_position] = true
			unique.append(face_position)
	_cached_drag_positions = unique

## Computes the extrusion column along the face normal.
func on_drag_move(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	if not _dragging:
		return []
	elif _face_positions.is_empty():
		return []
	
	var current_position := hit.get("position", Vector3i.ZERO)
	
	# Determine the extrusion direction from the active tool's EditIntent:
	#   ADD    - extrude outward from the face (+normal).
	#   REMOVE - extrude inward into the block (-normal).
	var extrude_direction := -1 if (editor.active_tool and editor.active_tool.edit_intent == VoxlyTool.EditIntent.REMOVE) else 1
	
	# Compute the depth based on the drag distance from the origin, measured
	# along the normal axis. The depth is direction-sensitive so each tool has
	# a natural drag direction.
	var face_dot = Vector3(current_position).dot(_face_normal)
	var origin_dot = Vector3(_face_positions[0]).dot(_face_normal)
	var is_remove = editor.active_tool and editor.active_tool.edit_intent == VoxlyTool.EditIntent.REMOVE
	var depth := maxi(origin_dot - face_dot if is_remove else face_dot - origin_dot, 0)
	
	# Clamp to a reasonable range.
	depth = clampi(depth, 0, 100)
	
	# Generate positions, including the base face.
	var positions: Array[Vector3i] = []
	for depth_step in range(depth + 1):
		for face_position in _face_positions:
			positions.append(face_position + _face_normal * extrude_direction * depth_step)
	
	# Remove duplicates to avoid double rendering or placing on the same position.
	var seen: Dictionary[Vector3i, bool] = {}
	var unique: Array[Vector3i] = []
	for position in positions:
		if not seen.has(position):
			seen[position] = true
			unique.append(position)
	_cached_drag_positions = unique
	return unique

## Clears the drag state.
func on_drag_end() -> void:
	_dragging = false
	_face_positions.clear()
	_cached_drag_positions.clear()
