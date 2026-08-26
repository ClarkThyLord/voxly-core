@tool
class_name VoxlyPatternSelectInteraction
extends VoxlyInteraction
## Pattern-capture interaction: used when the active brush is a VoxlyBrushPattern
## still in selection mode. Single clicks toggle a voxel in
## or out of the selection set; drags commit a rectangular region.

## The pattern brush being configured.
var _pattern_brush = null


func _ready_to_interact() -> bool:
	if not (_pattern_brush is VoxlyBrushPattern):
		return false
	return _pattern_brush.is_selecting()


func begin(_event: InputEventMouse, hit: Dictionary) -> void:
	_pattern_brush = editor.active_brush
	if _ready_to_interact():
		_pattern_brush.on_drag_start(editor, hit)


func update(_event: InputEventMouse, hit: Dictionary) -> void:
	if not _ready_to_interact():
		return
	var positions = _pattern_brush.on_drag_move(editor, hit)
	if not positions.is_empty():
		refresh_preview(hit)


func finish(_event: InputEventMouse, hit: Dictionary) -> void:
	if not _ready_to_interact():
		return
	
	if _pattern_brush._drag_preview_positions.is_empty():
		# Single click — toggle this voxel in/out of selection.
		var pos := hit.get("position", Vector3i.ZERO)
		_pattern_brush.toggle_selection(pos)
	else:
		# Was a drag — commit rect selection.
		_pattern_brush.commit_rect_selection(hit)
	
	_pattern_brush.on_drag_end()
	_pattern_brush._notify_change(editor)
	refresh_preview(hit)


func refresh_preview(hit: Dictionary) -> void:
	# During hover (no press yet) `_pattern_brush` is null, fall back to the
	# active brush so the capture preview still shows before any interaction.
	var brush = _pattern_brush if _pattern_brush != null else editor.active_brush
	if not preview or not (brush is VoxlyBrushPattern):
		return
	
	# build the selection overlay + drag preview + hovered voxel, ported from
	# the controller's _update_pattern_preview().
	var selection = brush.get_selection_for_preview()
	var drag_preview = brush.get_drag_preview_for_preview()
	var hit_pos := hit.get("position", Vector3i.ZERO) if not hit.is_empty() else null

	var colored: Array[Dictionary] = []
	var seen: Dictionary[Vector3i, bool] = {}
	
	# Selection voxels (blue).
	for pos in selection:
		if not seen.has(pos):
			seen[pos] = true
			colored.append({"position": pos, "color": preview.selection_color})
	
	# Drag preview voxels (semi-transparent white).
	for pos in drag_preview:
		if not seen.has(pos):
			seen[pos] = true
			colored.append({"position": pos, "color": preview.drag_preview_color})
	
	# Hovered voxel (unless already covered).
	if hit_pos != null and not seen.has(hit_pos):
		colored.append({"position": hit_pos, "color": preview.drag_preview_color})
		seen[hit_pos] = true

	if colored.is_empty():
		clear_preview()
	else:
		preview.update_preview_colored(colored)


func cancel() -> void:
	if _pattern_brush:
		_pattern_brush.on_drag_end()
	_pattern_brush = null
	clear_preview()
