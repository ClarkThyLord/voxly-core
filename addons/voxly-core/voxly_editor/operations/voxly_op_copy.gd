## Copies the targeted voxels (positions + palette IDs) to the editor
## clipboard. Targets the selection when one exists, otherwise all filled
## voxels.
@tool
extends VoxlyEditOperation

const _debug_context := "VoxlyOpCopy"

## Registers the copy operation in the registry.
func _init() -> void:
	id = "copy_voxels"
	category = "clipboard"
	display_name = "Copy"
	uses_selection_fallback = true
	shortcut = make_shortcut(KEY_C, true, false, true)

## Returns whether a selection exists to copy.
func is_available(editor: VoxlyEditor) -> bool:
	return _target_has_content(editor)

## Copies the selection to the clipboard.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	var data: Dictionary[Vector3i, int] = {}
	for position in positions:
		var voxel_id = target.get_voxel(position)
		if voxel_id != null:
			data[position] = voxel_id
	if data.is_empty():
		return
	
	editor.clipboard = data
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context,
		"Copied %d voxels to clipboard" % data.size())
