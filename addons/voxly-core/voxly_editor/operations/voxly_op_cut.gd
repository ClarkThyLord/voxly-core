## Copies the targeted voxels to the clipboard, then removes them from the
## model in a single undo step. Targets the selection when one exists,
## otherwise all filled voxels.
@tool
extends VoxlyEditOperation

const _debug_context := "VoxlyOpCut"

## Registers the cut operation in the registry.
func _init() -> void:
	id = "cut_voxels"
	category = "clipboard"
	display_name = "Cut"
	uses_selection_fallback = true
	modifies_voxels = true
	shortcut = make_shortcut(KEY_X, true, false, true)

## Returns whether a selection exists to cut.
func is_available(editor: VoxlyEditor) -> bool:
	return _target_has_content(editor)

## Cuts the selection to the clipboard.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	# Snapshot the targeted voxels into the clipboard.
	var data: Dictionary[Vector3i, int] = {}
	for position in positions:
		var voxel_id = target.get_voxel(position)
		if voxel_id != null:
			data[position] = voxel_id
	if data.is_empty():
		return
	editor.clipboard = data
	
	var positions_to_remove: Array[Vector3i] = []
	for position in data:
		positions_to_remove.append(position)
	
	# Snapshot the selection so cut can clear it and undo can restore it.
	var old_selection: Array[Vector3i] = []
	if editor.selection:
		old_selection = editor.selection.to_array()
	
	undo_redo.create_action("Voxly Cut")
	_record_remove_all(undo_redo, target, positions_to_remove)
	_record_rebuild(undo_redo, target)
	# Clear the selection on do and restore it on undo.
	undo_redo.add_do_method(editor.selection, "clear")
	undo_redo.add_undo_method(editor.selection, "set_positions", old_selection)
	undo_redo.commit_action()
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context,
		"Cut %d voxels to clipboard" % data.size())
