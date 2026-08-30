## Removes any voxel with zero solid neighbors along the 6 main directions.
@tool
extends VoxlyEditOperation

## Registers the remove-floating operation in the registry.
func _init() -> void:
	id = "remove_floating"
	category = "model"
	display_name = "Remove Floating Voxels"
	modifies_voxels = true

## Returns whether floating voxels can be removed.
func is_available(editor: VoxlyEditor) -> bool:
	return _target_has_content(editor)

## Removes floating voxels.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	
	var occupied: Dictionary[Vector3i, bool] = {}
	for position in target.get_voxel_positions_used():
		occupied[position] = true
	
	var to_remove: Array[Vector3i] = []
	for position in occupied:
		var has_neighbor := false
		for direction in _neighbors():
			if occupied.has(position + direction):
				has_neighbor = true
				break
		if not has_neighbor:
			to_remove.append(position)
	
	if to_remove.is_empty():
		return
	
	undo_redo.create_action("Voxly Remove Floating Voxels")
	_record_remove_all(undo_redo, target, to_remove)
	_record_rebuild(undo_redo, target)
	
	# Clear any selection overlapping the removed floating voxels.
	_record_selection_clear(undo_redo, editor)
	undo_redo.commit_action()
