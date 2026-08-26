@tool
extends VoxlyEditOperation
## Copies the targeted voxels (positions + palette ids) to the editor
## clipboard. Targets the selection when one exists, otherwise all filled voxels.

func _init() -> void:
	id = "copy_voxels"
	category = "clipboard"
	display_name = "Copy"
	uses_selection_fallback = true
	shortcut = make_shortcut(KEY_C, true, false, true)

func is_available(editor) -> bool:
	return _target_has_content(editor)

func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	var data: Dictionary = {}
	for pos in positions:
		var voxel_id = target.get_voxel(pos)
		if voxel_id != null:
			data[pos] = voxel_id
	if data.is_empty():
		return
	
	editor.clipboard = data
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "OpCopy",
		"Copied %d voxels to clipboard" % data.size())
