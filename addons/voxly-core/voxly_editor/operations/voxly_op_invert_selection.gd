## Invert selection: selects all filled voxels not currently selected, and
## deselects those that are.
@tool
extends VoxlyEditOperation

## Registers the invert operation in the registry.
func _init() -> void:
	id = "invert_selection"
	category = "selection"
	display_name = "Invert Selection"

## Returns whether the selection can be inverted.
func is_available(editor: VoxlyEditor) -> bool:
	return editor != null and editor.selection != null and editor.selection.count() > 0

## Inverts the selection.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	
	var filled: Array[Vector3i] = target.get_voxel_positions_used()
	if filled.is_empty():
		return
	
	var old_positions = editor.selection.to_array()
	var new_positions: Array[Vector3i] = []
	for position in filled:
		if not editor.selection.has(position):
			new_positions.append(position)
	
	undo_redo.create_action("Voxly Invert Selection")
	undo_redo.add_do_method(editor.selection, "set_positions", new_positions)
	undo_redo.add_undo_method(editor.selection, "set_positions", old_positions)
	undo_redo.commit_action()
