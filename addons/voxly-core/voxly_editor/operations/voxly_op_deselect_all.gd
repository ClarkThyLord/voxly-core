## Clears the current selection.
@tool
extends VoxlyEditOperation

## Registers the deselect-all operation in the registry.
func _init() -> void:
	id = "deselect_all"
	category = "selection"
	display_name = "Deselect All Voxels"

## Returns whether any voxels are selected.
func is_available(editor: VoxlyEditor) -> bool:
	return editor != null and editor.selection != null and editor.selection.count() > 0

## Clears the selection.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	editor.deselect_all(undo_redo)
