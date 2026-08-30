## Select by palette ID: selects every voxel matching the current palette voxel.
@tool
extends VoxlyEditOperation

## Registers the select-by-palette operation in the registry.
func _init() -> void:
	id = "select_by_palette"
	category = "selection"
	display_name = "Select by Palette ID"

## Returns whether a palette voxel is active.
func is_available(editor: VoxlyEditor) -> bool:
	return editor != null and editor.palette_id >= 0 and _target_has_content(editor)

## Selects all voxels matching the palette ID.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	if editor.palette_id < 0:
		return
	var target := _get_target(editor)
	if target == null:
		return
	
	var old_positions = editor.selection.to_array()
	var matched: Array[Vector3i] = []
	for position in target.get_voxel_positions_used():
		if target.get_voxel(position) == editor.palette_id:
			matched.append(position)
	
	undo_redo.create_action("Voxly Select by Palette ID")
	undo_redo.add_do_method(editor.selection, "set_positions", matched)
	undo_redo.add_undo_method(editor.selection, "set_positions", old_positions)
	undo_redo.commit_action()
