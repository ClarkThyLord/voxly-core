@tool
class_name VoxlyBrushPattern
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/pattern.svg")

## The stored pattern positions.
var pattern_positions: Array[Vector3i] = []

## Voxel data for each relative position in the pattern.
## Maps relative_position to palette_id captured at the time of storing.
## Used when `use_exact_voxel_data` is true.
var pattern_voxel_data: Dictionary = {}

## Voxel positions the user has selected for the pattern.
var selection_set: Array[Vector3i] = []

## Whether we're currently in a drag operation.
var _is_dragging: bool = false

## Drag origin position.
var _drag_origin: Vector3i = Vector3i.ZERO

## Drag origin hit (for computing rect).
var _drag_origin_hit: Dictionary = {}

## Current drag rect positions for preview.
var _drag_preview_positions: Array[Vector3i] = []

## Whether to use the palette ID when stamping (true) or exact captured voxel data (false).
var use_palette_id: bool = true


func _init() -> void:
	name = "pattern"
	display_name = "Pattern"
	requires_drag = false
	icon = ICON

## Returns true when the pattern is being defined (no stored pattern yet).
func is_selecting() -> bool:
	return pattern_positions.is_empty()


## Toggles a voxel position in/out of the selection set.
func toggle_selection(pos: Vector3i) -> void:
	if pos in selection_set:
		selection_set.erase(pos)
	else:
		selection_set.append(pos)


func _notify_change(editor) -> void:
	if editor:
		editor.brush_changed.emit(editor.brush_name)


## Adds all positions in the rect from drag_origin to hit to the selection.
func commit_rect_selection(hit: Dictionary) -> void:
	if _drag_origin_hit.is_empty():
		return
	
	var from_pos := _drag_origin_hit.get("position", Vector3i.ZERO)
	var to_pos := hit.get("position", Vector3i.ZERO)
	
	var min_pos := Vector3i(
		mini(from_pos.x, to_pos.x),
		mini(from_pos.y, to_pos.y),
		mini(from_pos.z, to_pos.z)
	)
	var max_pos := Vector3i(
		maxi(from_pos.x, to_pos.x),
		maxi(from_pos.y, to_pos.y),
		maxi(from_pos.z, to_pos.z)
	)
	
	var rect_positions: Array[Vector3i] = []
	for x in range(min_pos.x, max_pos.x + 1):
		for y in range(min_pos.y, max_pos.y + 1):
			for z in range(min_pos.z, max_pos.z + 1):
				rect_positions.append(Vector3i(x, y, z))
	
	# Add all rect positions to selection
	for pos in rect_positions:
		if pos not in selection_set:
			selection_set.append(pos)


## Returns the current selection set (for preview).
func get_selection_for_preview() -> Array[Vector3i]:
	return selection_set


## Returns the current drag preview positions.
func get_drag_preview_for_preview() -> Array[Vector3i]:
	return _drag_preview_positions

## Stores the current selection as the pattern, capturing both positions and
## voxel data (palette IDs) from the target node's voxel set.
func store_pattern(editor_state) -> void:
	if selection_set.is_empty():
		return
	
	# Find the minimum position to use as origin
	var min_pos := Vector3i(0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF)
	for pos in selection_set:
		min_pos.x = mini(min_pos.x, pos.x)
		min_pos.y = mini(min_pos.y, pos.y)
		min_pos.z = mini(min_pos.z, pos.z)
	
	pattern_positions.clear()
	pattern_voxel_data.clear()
	
	for pos in selection_set:
		var rel_pos := pos - min_pos
		pattern_positions.append(rel_pos)
		
		# Capture voxel data at this position
		if editor_state and editor_state.voxel_set:
			var voxel_id := _get_voxel_at(editor_state, pos)
			if voxel_id >= 0:
				pattern_voxel_data[rel_pos] = voxel_id
	
	# Clear selection now that it's stored
	clear_selection()


## Clears both the stored pattern and any active selection.
func clear_pattern() -> void:
	pattern_positions.clear()
	pattern_voxel_data.clear()
	clear_selection()


## Clears only the active selection (leaves pattern intact).
func clear_selection() -> void:
	selection_set.clear()
	_is_dragging = false
	_drag_preview_positions.clear()
	_drag_origin_hit = {}

func on_drag_start(editor, hit: Dictionary) -> void:
	if not is_selecting():
		return
	_is_dragging = true
	_drag_origin_hit = hit


func on_drag_move(editor, hit: Dictionary) -> Array[Vector3i]:
	if not is_selecting() or _drag_origin_hit.is_empty() or hit.is_empty():
		return []
	
	var from_pos := _drag_origin_hit.get("position", Vector3i.ZERO)
	var to_pos := hit.get("position", Vector3i.ZERO)
	
	var min_pos := Vector3i(
		mini(from_pos.x, to_pos.x),
		mini(from_pos.y, to_pos.y),
		mini(from_pos.z, to_pos.z)
	)
	var max_pos := Vector3i(
		maxi(from_pos.x, to_pos.x),
		maxi(from_pos.y, to_pos.y),
		maxi(from_pos.z, to_pos.z)
	)
	
	_drag_preview_positions.clear()
	for x in range(min_pos.x, max_pos.x + 1):
		for y in range(min_pos.y, max_pos.y + 1):
			for z in range(min_pos.z, max_pos.z + 1):
				_drag_preview_positions.append(Vector3i(x, y, z))
	
	return _drag_preview_positions


func on_drag_end() -> void:
	if not is_selecting():
		return
	_is_dragging = false
	
	# If there were no drag preview positions, this was a single click (handled by controller)
	# If there were drag positions, commit them
	if not _drag_preview_positions.is_empty():
		for pos in _drag_preview_positions:
			if pos not in selection_set:
				selection_set.append(pos)
		_drag_preview_positions.clear()
	
	_drag_origin_hit = {}

func get_positions(editor, hit: Dictionary) -> Array[Vector3i]:
	# In selection mode, this is not used
	if is_selecting():
		return []
	
	if hit.is_empty() or pattern_positions.is_empty():
		return []
	
	var hit_pos := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	hit_pos = offset_for_tool(editor, hit_pos, normal, hit.get("dda_hit", false))
	
	var positions: Array[Vector3i] = []
	for rel_pos in pattern_positions:
		positions.append(hit_pos + rel_pos)
	
	# When using exact voxel data, populate per-position palette overrides
	# on the editor so tools can apply the correct palette ID per position.
	if not use_palette_id and not pattern_voxel_data.is_empty():
		editor.pattern_voxel_overrides.clear()
		for i in positions.size():
			var world_pos := positions[i]
			var rel_pos := pattern_positions[i]
			if pattern_voxel_data.has(rel_pos):
				editor.pattern_voxel_overrides[world_pos] = pattern_voxel_data[rel_pos]
	else:
		editor.pattern_voxel_overrides.clear()
	
	return positions

func get_options() -> Array[Dictionary]:
	return [
		{"label": "Continuous", "property": "continuous", "type": TYPE_BOOL, "default": false},
		{
			"label": "Use Palette ID",
			"property": "use_palette_id",
			"type": TYPE_NIL,
			"hint": "action",
			"action": "_on_toggle_use_palette",
		},
		{
			"label": _get_pattern_label(),
			"button_text": _get_set_button_text(),
			"property": "",
			"type": TYPE_NIL,
			"hint": "button",
			"action": "_on_set_pattern",
		},
	]


## Label shown beside the pattern action button.
func _get_pattern_label() -> String:
	if is_selecting():
		return "Pattern (%d selected)" % selection_set.size()
	return "Pattern (%d)" % pattern_positions.size()


## Button text: "Set" while capturing a new pattern, "Reset" to clear it.
func _get_set_button_text() -> String:
	return "Set" if is_selecting() else "Reset"


## Toggles whether to use palette ID or exact voxel data.
func _on_toggle_use_palette(editor) -> void:
	use_palette_id = not use_palette_id


## Called when the "Set Pattern" / "Clear Pattern" button is pressed.
func _on_set_pattern(editor) -> void:
	if is_selecting():
		# Store current selection as pattern
		store_pattern(editor)
	else:
		# Clear the stored pattern (stays in selection mode for new pattern)
		clear_pattern()

## Queries the editor's target node for the voxel palette ID at a position.
func _get_voxel_at(editor, pos: Vector3i) -> int:
	if not editor or not editor.voxel_set:
		return -1
	
	# The VoxelSet resource stores palette_id -> Voxel mappings.
	# We need to find which palette_id maps to a voxel at this position.
	var adapter = editor.adapter
	if not adapter:
		return -1
	return adapter.voxel_at(pos)
