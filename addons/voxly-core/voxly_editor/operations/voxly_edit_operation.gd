@tool
@abstract
class_name VoxlyEditOperation
extends RefCounted
## Base class for model edit operations, which are registered in VoxlyRegistry, 
## and the dock builds its menus from them data-driven.

## Unique identifier, e.g. "erase_voxels".
var id: String = ""

## Menu group this operation belongs to.
## Categories drive menu grouping:
## "edit", "selection", "clipboard", "transform", "model", "new_model"
var category: String = ""

## Used to build the menu label, e.g. "Erase", "Mirror", "Copy".
var display_name: String = ""

## When true, the operation targets the selection if one exists, otherwise
## all filled voxels.
var uses_selection_fallback: bool = false

## True if this operation modifies voxel data.
## Used to decide whether a mesh rebuild is needed.
var modifies_voxels: bool = false

## When true, the operation's `get_options()`
## are collected through the ContextWindow prompt before executing.
var prompts_for_options: bool = false

## Optional keyboard shortcut rendered right-aligned in the menu (e.g.
## Ctrl+Shift+C for Copy). PopupMenu fires the item when the shortcut is
## pressed even while the menu is closed.
var shortcut: Shortcut = null

## Returns the option schema used to render operation prompts in the editor's
## ContextWindow (same contract as VoxlyBrush/VoxlyTool `get_options()`).
## Override + return rows to prompt the user for parameters before executing.
func get_options() -> Array[Dictionary]:
	return []

## Returns parameterized submenu entries for this operation. When non-empty,
## the operation renders as a submenu with one item per entry. Each entry is:
##   { "label": String, "param": String }
## where `param` is fed to _apply_param-like handling on execution.
func get_param_entries() -> Array[Dictionary]:
	return []

## Returns fixed count-submenu entries for operations that present a 1..N
## count list; where each entry is {"label": String, "count": int}.
## Empty by default (no count submenu).
func get_count_entries() -> Array[Dictionary]:
	return []

## Builds a keyboard Shortcut from a keycode + modifiers, for use as
## `shortcut` (e.g. copy: KEY_C, ctrl=true, shift=true).
func make_shortcut(keycode: int, ctrl := false, alt := false, shift := false) -> Shortcut:
	var shortcut := Shortcut.new()
	var event := InputEventKey.new()
	event.keycode = keycode
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.shift_pressed = shift
	shortcut.events = [event]
	return shortcut

## Returns the menu label given whether a selection currently exists.
func get_display_label(has_selection: bool) -> String:
	if uses_selection_fallback:
		return "%s %s" % [display_name, "Selection" if has_selection else "All Voxels"]
	return display_name

## Returns true if this operation can run right now (disables menu items).
func is_available(editor) -> bool:
	return true

## Executes the operation with undo/redo support.
func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	pass

## Returns the target voxel node during editing. Sourced through the editor's
## adapter so the operation layer never holds a stale/corrupt node reference.
func _get_target(editor) -> Node:
	if editor == null:
		return null
	if editor.adapter:
		return editor.adapter.get_node()
	return null

## Resolves the positions this operation applies to: the selection when one
## exists (only if uses_selection_fallback), otherwise all filled voxels.
func _resolve_positions(editor) -> Array[Vector3i]:
	var positions: Array[Vector3i] = []
	if uses_selection_fallback and editor.selection and editor.selection.count() > 0:
		return editor.selection.to_array()
	var target := _get_target(editor)
	if target and target.has_method("get_voxel_positions_used"):
		positions = target.get_voxel_positions_used()
	return positions

## True if the target has any filled voxels.
func _target_has_content(editor) -> bool:
	var target := _get_target(editor)
	return target != null and target.has_method("get_voxel_count") and target.get_voxel_count() > 0

## Records removal of every occupied position, restoring the original ID on undo.
func _record_remove_all(undo_redo: EditorUndoRedoManager, target, positions: Array[Vector3i]) -> void:
	for pos in positions:
		var old_id = target.get_voxel(pos)
		if old_id != null:
			undo_redo.add_do_method(target, "remove_voxel", pos)
			undo_redo.add_undo_method(target, "set_voxel", pos, old_id)

## Records setting voxels from a Dictionary[Vector3i, int], restoring each
## destination's previous voxel on undo.
func _record_set_all(undo_redo: EditorUndoRedoManager, target, voxels: Dictionary) -> void:
	for pos in voxels:
		var old_id = target.get_voxel(pos)
		undo_redo.add_do_method(target, "set_voxel", pos, voxels[pos])
		if old_id != null:
			undo_redo.add_undo_method(target, "set_voxel", pos, old_id)
		else:
			undo_redo.add_undo_method(target, "remove_voxel", pos)

## Records a high-level refresh (mesh rebuild + optional collision) on both
## do and undo.
func _record_rebuild(undo_redo: EditorUndoRedoManager, target) -> void:
	undo_redo.add_do_method(target, "update")
	undo_redo.add_undo_method(target, "update")

## Registers undoable selection changes that follow moved voxels.
## No-op when there is no active selection (the operation targeted all voxels).
## `dest_positions` is the post-transform selection (the moved voxels).
func _record_selection_transform(undo_redo: EditorUndoRedoManager, editor, dest_positions: Array) -> void:
	if editor == null or editor.selection == null or editor.selection.count() == 0:
		return
	var source_positions = editor.selection.to_array()
	# Convert to a typed array so UndoRedo re-invocation matches the
	# Array[Vector3i] signature of VoxlySelection.set_positions().
	var typed_dest: Array[Vector3i] = []
	for pos in dest_positions:
		typed_dest.append(pos)
	undo_redo.add_do_method(editor.selection, "set_positions", typed_dest)
	undo_redo.add_undo_method(editor.selection, "set_positions", source_positions)

## Registers an undoable selection clear (restoring it on undo).
## No-op when there is no active selection.
func _record_selection_clear(undo_redo: EditorUndoRedoManager, editor) -> void:
	if editor == null or editor.selection == null or editor.selection.count() == 0:
		return
	var old_selection = editor.selection.to_array()
	undo_redo.add_do_method(editor.selection, "clear")
	undo_redo.add_undo_method(editor.selection, "set_positions", old_selection)

## Standard 6-direction neighbors.
func _neighbors() -> Array[Vector3i]:
	return [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
