@tool
extends VoxlyEditOperation
## Copy the targeted voxels to the clipboard, then removes them from
## the model in a single undo step. Targets the selection when one exists,
## otherwise all filled voxels.

func _init() -> void:
	id = "cut_voxels"
	category = "clipboard"
	display_name = "Cut"
	uses_selection_fallback = true
	modifies_voxels = true
	shortcut = make_shortcut(KEY_X, true, false, true)

func is_available(editor) -> bool:
	return _target_has_content(editor)

func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	# Snapshot the targeted voxels into the clipboard.
	var data: Dictionary = {}
	for pos in positions:
		var voxel_id = target.get_voxel(pos)
		if voxel_id != null:
			data[pos] = voxel_id
	if data.is_empty():
		return
	editor.clipboard = data
	
	var positions_to_remove: Array[Vector3i] = []
	for pos in data:
		positions_to_remove.append(pos)
	
	# Snapshot the selection so cut can clear it and undo can restore it.
	var old_selection: Array[Vector3i] = []
	if editor.selection:
		old_selection = editor.selection.to_array()
	
	undo_redo.create_action("Voxly Cut")
	_record_remove_all(undo_redo, target, positions_to_remove)
	_record_rebuild(undo_redo, target)
	# Clear the selection on do and restore it and restore it on undo.
	undo_redo.add_do_method(editor.selection, "clear")
	undo_redo.add_undo_method(editor.selection, "set_positions", old_selection)
	undo_redo.commit_action()
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "OpCut",
		"Cut %d voxels to clipboard" % data.size())
