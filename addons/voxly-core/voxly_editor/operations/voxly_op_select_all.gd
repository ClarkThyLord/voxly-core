## Selects every filled voxel.
@tool
extends VoxlyEditOperation

## Registers the select-all operation in the registry.
func _init() -> void:
	id = "select_all"
	category = "selection"
	display_name = "Select All Voxels"

## Selects all voxels.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	editor.select_all_positions(undo_redo)
