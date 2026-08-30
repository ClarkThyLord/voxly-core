## Core voxel editor logic. Manages brushes, tools, mirror state, hit data,
## and provides utility methods for position manipulation and raycasting.
##
## This class is UI-agnostic and does not reference the Godot UI or scene tree.
## All 3D overlay and UI concerns are handled by controllers.
@tool
class_name VoxlyEditor
extends RefCounted

## Debug context tag used when logging through [VoxlyDebug].
const _debug_context := "VoxlyEditor"

## Emitted when the active brush changes.
signal brush_changed(brush_name: String)
## Emitted when the active tool changes.
signal tool_changed(tool_name: String)
## Emitted when the mirror axes change.
signal mirror_changed(mirrors: Vector3i)
## Emitted when editing mode is enabled or disabled.
signal editing_toggled(enabled: bool)
## Emitted when the selected palette voxel changes.
signal palette_changed(voxel_id: int)
## Emitted when an edit action requires a palette voxel but none is selected.
signal palette_voxel_required

## Undo action name shared by every continuous stroke. A stroke is committed
## as a single merged action (see [method begin_stroke] / [method end_stroke]).
const ACTION_STROKE := "Voxly Edit Stroke"

## Registry holding brush and tool class references.
var registry: VoxlyRegistry

## Currently active brush instance.
var active_brush: VoxlyBrush:
	set = set_active_brush_instance

## Currently active tool instance.
var active_tool: VoxlyTool:
	set = set_active_tool_instance

## Current brush name.
var brush_name: String = ""

## Current tool name.
var tool_name: String = ""

## Mirror axes: X=1, Y=2, Z=4.
var mirrors: Vector3i = Vector3i.ZERO

## Whether editing is enabled.
var editing_enabled: bool = false

## Hit data from the last raycast. Contains "position" (Vector3i) and
## "normal" (Vector3i).
var last_hit: Dictionary = {}

## Hit data from the previous frame (for drag detection).
var previous_hit: Dictionary = {}

## Currently selected palette voxel ID (-1 = none).
var palette_id: int = -1

## Voxel set reference (can be null).
var voxel_set = null

## The voxel node proxy for the node currently being edited. Set by the
## controller on start_editing. Brushes, tools, operations, and the controller
## all reach the voxel node through this adapter, never the raw node.
var adapter: VoxlyNodeAdapter = null

## Per-position palette overrides set by the pattern brush when
## use_palette_id is false. Maps world position to palette ID. Checked by tools
## during work().
var pattern_voxel_overrides: Dictionary = {}

## Continuous stroke state. A stroke buffers every voxel change (and selection
## change) and commits ONE undo action on release. Tools funnel through
## [method record_voxel_change] / [method record_selection_change] so the
## buffering is invisible to them.
## Whether a continuous stroke is currently being painted.
var stroke_active: bool = false

## Voxel edits accumulated during the current stroke: position = [old_id, new_id].
## `old_id` is null for empty cells; `new_id` is null for removals.
var _stroke_voxel_delta: Dictionary = {}

## Selection toggles accumulated during the current stroke:
## [{position: Vector3i, was_selected: bool}, ...].
var _stroke_selection_delta: Array[Dictionary] = []

## Positions already touched during the current stroke, used to avoid
## re-applying the brush to the same voxel multiple times per stroke.
var _stroke_touched: Dictionary[Vector3i, bool] = {}

## Clipboard for Copy/Cut/Paste operations: [code]Dictionary[Vector3i, int][/code]
## mapping world voxel position to a palette ID. Populated by Copy/Cut,
## consumed by Paste.
var clipboard: Dictionary = {}

## Transient flag set by the controller while computing hover preview
## positions. Brushes that support a preview generate a cheaper, limited region
## while this is true, then the full region on apply.
var brush_preview_mode: bool = false

## Persistent selection of voxel positions, shared across brushes and to
## operations. Cleared when editing stops (see
## [method VoxelNode3DController.stop_editing]).
var selection: VoxlySelection = VoxlySelection.new()

## Shape of the voxel grid being edited (in voxel units).
## Used by [method mirror_position] to mirror around the center of the grid.
var voxel_shape: Vector3i = Vector3i(16, 16, 16)

## Initializes the editor with its default palette and tool state.
func _init() -> void:
	registry = VoxlyRegistry.new()

## Sets the active brush by registered name.
func set_active_brush(brush_name: String) -> void:
	if not registry.has_brush(brush_name):
		push_error("VoxlyEditor: Brush '%s' not registered" % brush_name)
		return
	
	var brush := registry.create_brush(brush_name)
	if brush:
		set_active_brush_instance(brush)
		self.brush_name = brush_name

## Sets the active brush by instance.
func set_active_brush_instance(brush: VoxlyBrush) -> void:
	active_brush = brush
	brush_name = brush.name if brush.name != "base" else brush.display_name.to_lower()
	brush_changed.emit(brush_name)

## Gets the positions from the current brush based on the hit.
func get_brush_positions(hit: Dictionary = last_hit) -> Array[Vector3i]:
	if not active_brush or hit.is_empty():
		return []
	return active_brush.get_positions(self, hit)

## Gets brush positions with mirrors applied.
## When multiple axes are enabled, generates all reflections (e.g. X+Y+Z
## produces 8 total positions).
func get_mirrored_brush_positions(hit: Dictionary = last_hit) -> Array[Vector3i]:
	var positions := get_brush_positions(hit)
	if mirrors == Vector3i.ZERO:
		return positions
	
	var axes: Array[int] = []
	for i in 3:
		if mirrors[i] == 1:
			axes.append(i)
	
	var result: Array[Vector3i] = []
	for position in positions:
		for reflection_mask in range(1 << axes.size()):
			var mirrored := position
			for axis_bit in axes.size():
				if (reflection_mask >> axis_bit) & 1:
					var axis_vector := get_axis_vector(axes[axis_bit])
					mirrored = mirror_position(mirrored, axis_vector)
			result.append(mirrored)
	
	# Deduplicate to avoid double-counting positions on mirror planes.
	return deduplicate_positions(result)

## Sets the active tool by registered name.
func set_active_tool(tool_name: String) -> void:
	if not registry.has_tool(tool_name):
		push_error("VoxlyEditor: Tool '%s' not registered" % tool_name)
		return
	
	var tool := registry.create_tool(tool_name)
	if tool:
		set_active_tool_instance(tool)
		self.tool_name = tool_name

## Sets the active tool by instance.
func set_active_tool_instance(tool: VoxlyTool) -> void:
	active_tool = tool
	tool_name = tool.name if tool.name != "base" else tool.display_name.to_lower()
	tool_changed.emit(tool_name)

## Applies the active tool to the given positions. Tools access the voxel node
## through `editor.adapter` (set by the controller during editing).
func apply_tool(target_adapter: VoxlyNodeAdapter, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void:
	if not active_tool:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context, "apply_tool: no active tool")
		return
	elif positions.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context, "apply_tool: empty positions")
		return
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context,
		"Applying tool '%s' with %d positions" % [active_tool.name, positions.size()])
	active_tool.work(self, positions, undo_redo)
	active_tool.on_work_complete(self)

## Begins a continuous brush stroke. All voxel/selection changes recorded
## until [method end_stroke] are batched into one undo action.
func begin_stroke() -> void:
	stroke_active = true
	_stroke_voxel_delta.clear()
	_stroke_selection_delta.clear()
	_stroke_touched.clear()

## Ends the current stroke, committing every accumulated change as a SINGLE
## undo action. `commit_action(false)` registers the action without
## re-executing do, as the live state already matches the "do" end state.
func end_stroke(stroke_adapter: VoxlyNodeAdapter, undo_redo: EditorUndoRedoManager) -> void:
	if not stroke_active:
		return
	
	stroke_active = false
	_end_stroke_internal(stroke_adapter, undo_redo, false)

## Cancels the current stroke, reverting all live voxel writes and selection
## toggles without committing an undo action. Used when editing stops or the
## active tool/brush changes mid-stroke.
func cancel_stroke(stroke_adapter: VoxlyNodeAdapter = null) -> void:
	if not stroke_active:
		return
	
	stroke_active = false
	# Revert live voxel writes back to their pre-stroke values.
	for position in _stroke_voxel_delta:
		if stroke_adapter and stroke_adapter.is_valid():
			stroke_adapter.set_voxel(position, _stroke_voxel_delta[position][0])
	
	# Revert live selection toggles.
	for entry in _stroke_selection_delta:
		if entry["was_selected"]:
			selection.add(entry["position"])
		else:
			selection.remove(entry["position"])
	
	_stroke_voxel_delta.clear()
	_stroke_selection_delta.clear()
	_stroke_touched.clear()
	if stroke_adapter and stroke_adapter.is_valid():
		stroke_adapter.update()

## Internal commit used by both [method end_stroke] and the stroke's final
## rebuild-merge. When `for_merge` is true the caller owns the action
## lifecycle.
func _end_stroke_internal(stroke_adapter: VoxlyNodeAdapter, undo_redo: EditorUndoRedoManager, for_merge: bool) -> void:
	if _stroke_voxel_delta.is_empty() and _stroke_selection_delta.is_empty():
		_stroke_voxel_delta.clear()
		_stroke_selection_delta.clear()
		_stroke_touched.clear()
		return
	
	undo_redo.create_action(ACTION_STROKE)
	if not _stroke_voxel_delta.is_empty():
		var do_map: Dictionary = {}
		var undo_map: Dictionary = {}
		for position in _stroke_voxel_delta:
			do_map[position] = _stroke_voxel_delta[position][1]
			undo_map[position] = _stroke_voxel_delta[position][0]
		undo_redo.add_do_method(stroke_adapter, "apply_voxel_map", do_map)
		undo_redo.add_undo_method(stroke_adapter, "apply_voxel_map", undo_map)
		undo_redo.add_do_method(stroke_adapter, "update")
		undo_redo.add_undo_method(stroke_adapter, "update")
	
	if not _stroke_selection_delta.is_empty():
		var do_sel: Array[Dictionary] = []
		var undo_sel: Array[Dictionary] = []
		for entry in _stroke_selection_delta:
			var position: Vector3i = entry["position"]
			do_sel.append({"position": position, "selected": not entry["was_selected"]})
			undo_sel.append({"position": position, "selected": entry["was_selected"]})
		undo_redo.add_do_method(selection, "apply_stroke_delta", do_sel)
		undo_redo.add_undo_method(selection, "apply_stroke_delta", undo_sel)
	
	undo_redo.commit_action(false if not for_merge else true)
	_stroke_voxel_delta.clear()
	_stroke_selection_delta.clear()
	_stroke_touched.clear()

## Returns true if the given position was already stamped during this stroke.
func stroke_has_touched(position: Vector3i) -> bool:
	return _stroke_touched.has(position)

## Marks positions as stamped during the current stroke.
func stroke_mark_touched(positions: Array[Vector3i]) -> void:
	for position in positions:
		_stroke_touched[position] = true

## Records a single voxel change. During a stroke the change is applied live
## and buffered; otherwise it is registered on the current undo action.
func record_voxel_change(
		target_adapter: VoxlyNodeAdapter,
		position: Vector3i,
		new_id,
		old_id,
		undo_redo: EditorUndoRedoManager) -> void:
	if stroke_active:
		if old_id != new_id:
			target_adapter.set_voxel(position, new_id)
			_stroke_voxel_delta[position] = [old_id, new_id]
	else:
		undo_redo.add_do_method(target_adapter, "set_voxel", position, new_id)
		if old_id != null:
			undo_redo.add_undo_method(target_adapter, "set_voxel", position, old_id)
		else:
			undo_redo.add_undo_method(target_adapter, "remove_voxel", position)

## Records a mesh rebuild on both do and undo. During a stroke the mesh is
## rebuilt live by the stroke interaction instead.
func record_rebuild(undo_redo: EditorUndoRedoManager, stroke_adapter: VoxlyNodeAdapter) -> void:
	undo_redo.add_do_method(stroke_adapter, "update")
	undo_redo.add_undo_method(stroke_adapter, "update")

## Records a selection toggle. During a stroke the selection is updated live
## and buffered; otherwise the caller is responsible for the undo action.
func record_selection_change(position: Vector3i, was_selected: bool) -> void:
	if not stroke_active:
		return
	
	if was_selected:
		selection.remove(position)
	else:
		selection.add(position)
	
	_stroke_selection_delta.append({"position": position, "was_selected": was_selected})

## Applies an undoable erase of every selected voxel on the target node.
## Removes each selected voxel (recording old IDs) and rebuilds the mesh.
## The selection is kept afterward so the user can re-apply or undo.
func erase_selection(undo_redo: EditorUndoRedoManager) -> void:
	if adapter == null or undo_redo == null:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context, "erase_selection: missing adapter or undo_redo")
		return
	elif selection.count() == 0:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context, "erase_selection: empty selection")
		return
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context,
		"Erasing %d selected voxels" % selection.count())
	
	undo_redo.create_action("Voxly Erase Selected")
	for position in selection.to_array():
		var old_id = adapter.voxel_at(position)
		if old_id != null:
			undo_redo.add_do_method(adapter, "remove_voxel", position)
			undo_redo.add_undo_method(adapter, "set_voxel", position, old_id)
	record_rebuild(undo_redo, adapter)
	undo_redo.commit_action()

## Creates an undoable action that selects all filled voxels on the target node.
func select_all_positions(undo_redo: EditorUndoRedoManager) -> void:
	if adapter == null or undo_redo == null:
		return
	
	var filled := adapter.get_voxel_positions_used()
	if filled.is_empty():
		return
	
	# Capture current selection for undo.
	var old_positions := selection.to_array()
	
	undo_redo.create_action("Voxly Select All")
	undo_redo.add_do_method(selection, "set_positions", filled)
	undo_redo.add_undo_method(selection, "set_positions", old_positions)
	undo_redo.commit_action()

## Creates an undoable action that deselects everything.
func deselect_all(undo_redo: EditorUndoRedoManager) -> void:
	if undo_redo == null or selection.count() == 0:
		return
	
	var old_positions := selection.to_array()
	undo_redo.create_action("Voxly Deselect All")
	undo_redo.add_do_method(selection, "clear")
	undo_redo.add_undo_method(selection, "set_positions", old_positions)
	undo_redo.commit_action()

## Sets mirror state.
func set_mirrors(new_mirrors: Vector3i) -> void:
	mirrors = new_mirrors
	mirror_changed.emit(mirrors)

## Toggles a single mirror axis.
func toggle_mirror(axis: int) -> void:
	if axis < 0 or axis > 2:
		return
	
	var new_mirrors := mirrors
	new_mirrors[axis] = 1 if new_mirrors[axis] == 0 else 0
	set_mirrors(new_mirrors)

## Returns the axis vector for a given index (0=X, 1=Y, 2=Z).
func get_axis_vector(axis_index: int) -> Vector3i:
	match axis_index:
		0: return Vector3i(1, 0, 0)
		1: return Vector3i(0, 1, 0)
		2: return Vector3i(0, 0, 1)
	return Vector3i.ZERO

## Mirrors a position across the center of the model's shape.
func mirror_position(position: Vector3i, axis: Vector3i) -> Vector3i:
	var result := position
	var half := Vector3i(voxel_shape.x - 1, voxel_shape.y - 1, voxel_shape.z - 1)
	
	if axis.x == 1:
		result.x = half.x - result.x
	if axis.y == 1:
		result.y = half.y - result.y
	if axis.z == 1:
		result.z = half.z - result.z
	
	return result

## Enables or disables editing mode.
func set_editing(enabled: bool) -> void:
	if editing_enabled == enabled:
		return
	
	editing_enabled = enabled
	editing_toggled.emit(enabled)

## Updates the current pointer hit data.
func set_hit(hit: Dictionary) -> void:
	previous_hit = last_hit
	last_hit = hit

## Returns the color to use for preview based on the current tool and palette.
func get_preview_color() -> Color:
	if active_tool:
		return active_tool.get_preview_color(self)
	elif active_brush:
		return active_brush.get_preview_color(self)
	return Color.WHITE

## Returns what the ghost preview should render: the tool's declared
## PreviewSource (flat colored box vs the accurate palette voxel).
## Falls back to FLAT_COLOR when no tool is active.
func get_preview_source() -> VoxlyTool.PreviewSource:
	if active_tool:
		return active_tool.preview_source
	return VoxlyTool.PreviewSource.FLAT_COLOR

## Clips preview positions to the node's valid shape bounds.
func filter_preview_positions(positions: Array[Vector3i]) -> Array[Vector3i]:
	if positions.is_empty():
		return positions
	
	if not adapter or not adapter.is_valid():
		return positions
	
	var result: Array[Vector3i] = []
	for position in positions:
		if adapter.is_voxel_position_valid(position):
			result.append(position)
	
	return result

## Returns the current selection position (with tool placement applied).
func get_selection_position() -> Vector3i:
	if last_hit.is_empty():
		return Vector3i.MAX
	
	var position: Vector3i = last_hit.get("position", Vector3i.ZERO)
	var normal: Vector3i = last_hit.get("normal", Vector3i.ZERO)
	if active_tool:
		position = active_tool.offset_position(position, normal)
	return position

## Removes duplicate positions from an array.
func deduplicate_positions(positions: Array[Vector3i]) -> Array[Vector3i]:
	var seen: Dictionary[Vector3i, bool] = {}
	var result: Array[Vector3i] = []
	for position in positions:
		if not seen.has(position):
			seen[position] = true
			result.append(position)
	return result
