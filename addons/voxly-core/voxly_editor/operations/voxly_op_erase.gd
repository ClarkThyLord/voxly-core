## Removes the targeted voxels. Targets the selection when one exists,
## otherwise all filled voxels.
@tool
extends VoxlyEditOperation

## Registers the erase operation in the registry.
func _init() -> void:
	id = "erase_voxels"
	category = "edit"
	display_name = "Erase"
	uses_selection_fallback = true
	modifies_voxels = true

## Returns whether voxels can be erased.
func is_available(editor: VoxlyEditor) -> bool:
	return _target_has_content(editor)

## Erases the selected voxels.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	undo_redo.create_action("Voxly Erase")
	_record_remove_all(undo_redo, target, positions)
	_record_rebuild(undo_redo, target)
	_record_selection_clear(undo_redo, editor)
	undo_redo.commit_action()
