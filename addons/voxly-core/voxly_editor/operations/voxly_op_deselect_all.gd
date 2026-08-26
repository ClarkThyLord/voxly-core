@tool
extends VoxlyEditOperation
## Clears the current selection.

func _init() -> void:
	id = "deselect_all"
	category = "selection"
	display_name = "Deselect All Voxels"

func is_available(editor) -> bool:
	return editor != null and editor.selection != null and editor.selection.count() > 0

func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	editor.deselect_all(undo_redo)
