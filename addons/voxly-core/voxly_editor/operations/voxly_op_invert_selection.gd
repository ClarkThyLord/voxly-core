@tool
extends VoxlyEditOperation
## Invert selection, selects all filled voxels not currently selected, and
## deselects those that are.

func _init() -> void:
	id = "invert_selection"
	category = "selection"
	display_name = "Invert Selection"

func is_available(editor) -> bool:
	return editor != null and editor.selection != null and editor.selection.count() > 0

func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	
	var filled: Array[Vector3i] = target.get_voxel_positions_used()
	if filled.is_empty():
		return
	
	var old_positions = editor.selection.to_array()
	var new_positions: Array[Vector3i] = []
	for pos in filled:
		if not editor.selection.has(pos):
			new_positions.append(pos)
	
	undo_redo.create_action("Voxly Invert Selection")
	undo_redo.add_do_method(editor.selection, "set_positions", new_positions)
	undo_redo.add_undo_method(editor.selection, "set_positions", old_positions)
	undo_redo.commit_action()
