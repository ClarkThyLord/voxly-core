## Pattern brush: lets the user capture a custom selection as a reusable
## pattern and stamp it anywhere. Supports storing exact per-voxel data
## (palette IDs) or stamping with the currently selected palette ID.
@tool
class_name VoxlyBrushPattern
extends VoxlyBrush

const ICON := preload("res://addons/voxly-core/assets/icons/pattern.svg")

## The stored pattern positions, relative to the pattern's origin.
var pattern_positions: Array[Vector3i] = []

## Voxel data for each relative position in the pattern.
## Maps relative position to palette ID captured at the time of storing.
## Used when [member use_palette_id] is false.
var pattern_voxel_data: Dictionary = {}

## Voxel positions the user has selected for the pattern.
var selection_set: Array[Vector3i] = []

## Whether we're currently in a drag operation.
var _is_dragging: bool = false

## Drag origin position.
var _drag_origin: Vector3i = Vector3i.ZERO

## Drag origin hit (used to compute the selection rectangle).
var _drag_origin_hit: Dictionary = {}

## Current drag rectangle positions for preview.
var _drag_preview_positions: Array[Vector3i] = []

## Whether to use the current palette ID when stamping (true) or the exact
## captured voxel data (false).
var use_palette_id: bool = true

## Registers the pattern brush in the registry.
func _init() -> void:
	name = "pattern"
	display_name = "Pattern"
	requires_drag = false
	icon = ICON

## Returns true when the pattern is being defined (no stored pattern yet).
func is_selecting() -> bool:
	return pattern_positions.is_empty()

## Toggles a voxel position in/out of the selection set.
func toggle_selection(position: Vector3i) -> void:
	if position in selection_set:
		selection_set.erase(position)
	else:
		selection_set.append(position)

## Notifies the editor that the brush state changed so the UI refreshes.
func _notify_change(editor: VoxlyEditor) -> void:
	if editor:
		editor.brush_changed.emit(editor.brush_name)

## Adds all positions in the rectangle from the drag origin to the hit into
## the selection set.
func commit_rect_selection(hit: Dictionary) -> void:
	if _drag_origin_hit.is_empty():
		return
	
	var from_position := _drag_origin_hit.get("position", Vector3i.ZERO)
	var to_position := hit.get("position", Vector3i.ZERO)
	
	var min_position := Vector3i(
		mini(from_position.x, to_position.x),
		mini(from_position.y, to_position.y),
		mini(from_position.z, to_position.z)
	)
	var max_position := Vector3i(
		maxi(from_position.x, to_position.x),
		maxi(from_position.y, to_position.y),
		maxi(from_position.z, to_position.z)
	)
	
	var rect_positions: Array[Vector3i] = []
	for x in range(min_position.x, max_position.x + 1):
		for y in range(min_position.y, max_position.y + 1):
			for z in range(min_position.z, max_position.z + 1):
				rect_positions.append(Vector3i(x, y, z))
	
	# Add all rectangle positions to the selection.
	for position in rect_positions:
		if position not in selection_set:
			selection_set.append(position)

## Returns the current selection set (for preview).
func get_selection_for_preview() -> Array[Vector3i]:
	return selection_set

## Returns the current drag preview positions.
func get_drag_preview_for_preview() -> Array[Vector3i]:
	return _drag_preview_positions

## Stores the current selection as the pattern, capturing both positions and
## voxel data (palette IDs) from the target node's voxel set.
func store_pattern(editor_state: VoxlyEditor) -> void:
	if selection_set.is_empty():
		return
	
	# Find the minimum position to use as the pattern origin.
	var min_position := Vector3i(0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF)
	for position in selection_set:
		min_position.x = mini(min_position.x, position.x)
		min_position.y = mini(min_position.y, position.y)
		min_position.z = mini(min_position.z, position.z)
	
	pattern_positions.clear()
	pattern_voxel_data.clear()
	
	for position in selection_set:
		var relative_position := position - min_position
		pattern_positions.append(relative_position)
		
		# Capture voxel data at this position.
		if editor_state and editor_state.voxel_set:
			var voxel_id := _get_voxel_at(editor_state, position)
			if voxel_id >= 0:
				pattern_voxel_data[relative_position] = voxel_id
	
	# Clear the selection now that it's stored.
	clear_selection()

## Clears both the stored pattern and any active selection.
func clear_pattern() -> void:
	pattern_positions.clear()
	pattern_voxel_data.clear()
	clear_selection()

## Clears only the active selection (leaves the pattern intact).
func clear_selection() -> void:
	selection_set.clear()
	_is_dragging = false
	_drag_preview_positions.clear()
	_drag_origin_hit = {}

## Starts or extends the pattern selection.
func on_drag_start(editor: VoxlyEditor, hit: Dictionary) -> void:
	if not is_selecting():
		return
	_is_dragging = true
	_drag_origin_hit = hit

## Updates the pattern selection.
func on_drag_move(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	if not is_selecting() or _drag_origin_hit.is_empty() or hit.is_empty():
		return []
	
	var from_position := _drag_origin_hit.get("position", Vector3i.ZERO)
	var to_position := hit.get("position", Vector3i.ZERO)
	
	var min_position := Vector3i(
		mini(from_position.x, to_position.x),
		mini(from_position.y, to_position.y),
		mini(from_position.z, to_position.z)
	)
	var max_position := Vector3i(
		maxi(from_position.x, to_position.x),
		maxi(from_position.y, to_position.y),
		maxi(from_position.z, to_position.z)
	)
	
	_drag_preview_positions.clear()
	for x in range(min_position.x, max_position.x + 1):
		for y in range(min_position.y, max_position.y + 1):
			for z in range(min_position.z, max_position.z + 1):
				_drag_preview_positions.append(Vector3i(x, y, z))
	
	return _drag_preview_positions

## Finalizes the pattern selection.
func on_drag_end() -> void:
	if not is_selecting():
		return
	_is_dragging = false
	
	# A click without drag is handled by the controller; a drag commits the
	# rectangle to the selection.
	if not _drag_preview_positions.is_empty():
		for position in _drag_preview_positions:
			if position not in selection_set:
				selection_set.append(position)
		_drag_preview_positions.clear()
	
	_drag_origin_hit = {}

## Returns the pattern positions.
func get_positions(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	# In selection mode this is not used.
	if is_selecting():
		return []
	
	if hit.is_empty() or pattern_positions.is_empty():
		return []
	
	var hit_position := hit.get("position", Vector3i.ZERO)
	var normal := hit.get("normal", Vector3i.ZERO)
	hit_position = offset_for_tool(editor, hit_position, normal, hit.get("dda_hit", false))
	
	var positions: Array[Vector3i] = []
	for relative_position in pattern_positions:
		positions.append(hit_position + relative_position)
	
	# When using exact voxel data, populate per-position palette overrides on
	# the editor so tools can apply the correct palette ID per position.
	if not use_palette_id and not pattern_voxel_data.is_empty():
		editor.pattern_voxel_overrides.clear()
		for i in positions.size():
			var world_position := positions[i]
			var relative_position := pattern_positions[i]
			if pattern_voxel_data.has(relative_position):
				editor.pattern_voxel_overrides[world_position] = pattern_voxel_data[relative_position]
	else:
		editor.pattern_voxel_overrides.clear()
	
	return positions

## Returns the pattern brush options.
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

## Toggles whether to use the palette ID or exact voxel data.
func _on_toggle_use_palette(editor: VoxlyEditor) -> void:
	use_palette_id = not use_palette_id

## Called when the "Set Pattern" / "Clear Pattern" button is pressed.
func _on_set_pattern(editor: VoxlyEditor) -> void:
	if is_selecting():
		# Store the current selection as the pattern.
		store_pattern(editor)
	else:
		# Clear the stored pattern (stays in selection mode for a new pattern).
		clear_pattern()

## Queries the editor's target node for the voxel palette ID at a position.
func _get_voxel_at(editor: VoxlyEditor, position: Vector3i) -> int:
	if not editor or not editor.voxel_set:
		return -1
	
	var adapter = editor.adapter
	if not adapter:
		return -1
	return adapter.voxel_at(position)
