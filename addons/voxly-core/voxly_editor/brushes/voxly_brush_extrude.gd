@tool
extends VoxlyBrush
## Extrude brush, selects a face of connected voxels and extrudes it outward
## along the face normal on drag. The extrude depth is determined by the
## distance the cursor is dragged from the face.
##
## Direction is driven by the active tool's EditIntent.

const ICON := preload("res://addons/voxly-core/assets/icons/extrude.svg")

var _face_positions: Array[Vector3i] = []
var _face_normal: Vector3i = Vector3i.ZERO
var _dragging: bool = false
var _cached_drag_positions: Array[Vector3i] = []
var _match_id: bool = false

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

func get_options() -> Array[Dictionary]:
	return [
		{"label": "Match ID", "property": "match_id", "type": TYPE_BOOL, "default": false}
	]

func get_positions(editor, hit: Dictionary) -> Array[Vector3i]:
	# While dragging, return cached positions
	if _dragging:
		return _cached_drag_positions.duplicate()
	if hit.is_empty():
		return []
	
	var pos := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	
	# For extrude, we only work on existing voxels (DDA hit)
	if not hit.get("dda_hit", false):
		return []
	
	var adapter = editor.adapter
	if not adapter or adapter.voxel_at(pos) == null:
		return []
	
	# Compute the face selection from the hit position
	var face = adapter.get_exposed_face_voxels(pos, normal, _match_id)
	if face.is_empty():
		return []
	
	# Tool placement offset: ADD offsets the preview outside the voxel to show
	# where new voxels will go; IN_PLACE tools show the face itself since we're
	# acting on the existing voxels.
	var tool_offset := Vector3i.ZERO
	if editor.active_tool and editor.active_tool.placement == VoxlyTool.Placement.ON_SURFACE:
		tool_offset = offset_for_tool(editor, pos, normal, true) - pos
	
	# Offset the face positions and remove duplicates.
	var is_add = editor.active_tool != null and editor.active_tool.placement == VoxlyTool.Placement.ON_SURFACE
	var seen: Dictionary[Vector3i, bool] = {}
	var result: Array[Vector3i] = []
	for f in face:
		var offset_pos = f + tool_offset
		if seen.has(offset_pos):
			continue
		if is_add and adapter.voxel_at(offset_pos) != null:
			continue
		seen[offset_pos] = true
		result.append(offset_pos)
	return result

func on_drag_start(editor, hit: Dictionary) -> void:
	_dragging = true
	_cached_drag_positions.clear()
	
	var pos := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	
	var adapter = editor.adapter
	if not adapter:
		return
	
	# Compute the face selection and store it (raw, un-offset)
	_face_positions = adapter.get_exposed_face_voxels(pos, normal, _match_id)
	_face_normal = normal
	
	# Bake tool placement offset into the stored face positions so that
	# the face itself is positioned correctly for the active tool.
	var tool_offset := Vector3i.ZERO
	if editor.active_tool and editor.active_tool.placement == VoxlyTool.Placement.ON_SURFACE:
		tool_offset = offset_for_tool(editor, pos, normal, true) - pos
	
	if tool_offset != Vector3i.ZERO:
		for i in range(_face_positions.size()):
			_face_positions[i] += tool_offset
	
	# Preview shows the (offset) face only at drag start.
	# Deduplicate to avoid rendering multiple boxes on the same position.
	var seen: Dictionary[Vector3i, bool] = {}
	var unique: Array[Vector3i] = []
	for f in _face_positions:
		if not seen.has(f):
			seen[f] = true
			unique.append(f)
	_cached_drag_positions = unique

func on_drag_move(editor, hit: Dictionary) -> Array[Vector3i]:
	if not _dragging:
		return []
	elif _face_positions.is_empty():
		return []
	
	var current_pos := hit.get("position", Vector3i.ZERO)
	
	# Determine extrusion direction from the active tool's EditIntent:
	#   ADD    - extrude outward from the face (+normal)
	#   REMOVE - extrude inward into the block (-normal)
	var extrude_direction := -1 if (editor.active_tool and editor.active_tool.edit_intent == VoxlyTool.EditIntent.REMOVE) else 1
	
	# Compute depth based on the drag distance from the origin, measured
	# along the normal axis. The depth is direction-sensitive so each
	# tool has a natural drag direction:
	var face_dot = Vector3(current_pos).dot(_face_normal)
	var origin_dot = Vector3(_face_positions[0]).dot(_face_normal)
	var is_remove = editor.active_tool and editor.active_tool.edit_intent == VoxlyTool.EditIntent.REMOVE
	var depth := maxi(origin_dot - face_dot if is_remove else face_dot - origin_dot, 0)
	
	# Clamp to reasonable range
	depth = clampi(depth, 0, 100)
	
	# Generate positions, include the base face.
	var positions: Array[Vector3i] = []
	for e in range(depth + 1):
		for f in _face_positions:
			positions.append(f + _face_normal * extrude_direction * e)
	
	# Remove duplicates to avoid double rendering or placing on the same position.
	var seen: Dictionary[Vector3i, bool] = {}
	var unique: Array[Vector3i] = []
	for p in positions:
		if not seen.has(p):
			seen[p] = true
			unique.append(p)
	_cached_drag_positions = unique
	return unique

func on_drag_end() -> void:
	_dragging = false
	_face_positions.clear()
	_cached_drag_positions.clear()
