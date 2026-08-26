@tool
extends VoxlyEditOperation
## Selects every filled voxel.

func _init() -> void:
	id = "select_all"
	category = "selection"
	display_name = "Select All Voxels"

func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	editor.select_all_positions(undo_redo)
