@tool
extends VoxlyEditOperation
## Resize to content by shrinks the model's shape to the tight AABB of its
## filled voxels.

func _init() -> void:
	id = "resize_to_content"
	category = "model"
	display_name = "Resize to Content"
	modifies_voxels = true

func is_available(editor) -> bool:
	return _target_has_content(editor)

func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null or not target.has_method("get_shape"):
		return
	
	var positions: Array[Vector3i] = target.get_voxel_positions_used()
	if positions.is_empty():
		return
	
	var min_corner := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var max_corner := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for pos in positions:
		for i in 3:
			min_corner[i] = mini(min_corner[i], pos[i])
			max_corner[i] = maxi(max_corner[i], pos[i])
	
	var new_shape := max_corner - min_corner + Vector3i.ONE
	var old_shape = target.get_shape()
	
	# Resizing the grid to start at 0,0,0 shifts the content in world space 
	# unless we compensate via the origin offset. However, for VoxelModel3D 
	# the world position is grid_pos * voxel_size + origin * voxel_size, so 
	# adding min_corner to origin preserves the content's world placement.
	var old_origin := Vector3.ZERO
	if target.has_method("get_origin"):
		old_origin = target.get_origin()
	var new_origin := old_origin + Vector3(min_corner)
	
	if new_shape == old_shape:
		return
	
	# Remap voxels so the content's min corner becomes 0,0,0.
	undo_redo.create_action("Voxly Resize to Content")
	var remapped: Dictionary = {}
	for pos in positions:
		var voxel_id = target.get_voxel(pos)
		if voxel_id != null:
			remapped[pos - min_corner] = voxel_id
	
	undo_redo.add_do_method(target, "set_shape", new_shape)
	undo_redo.add_undo_method(target, "set_shape", old_shape)
	undo_redo.add_do_property(target, "origin", new_origin)
	undo_redo.add_undo_property(target, "origin", old_origin)
	
	# Clear old positions after the shape change.
	_record_remove_all(undo_redo, target, positions)
	_record_set_all(undo_redo, target, remapped)
	_record_rebuild(undo_redo, target)
	
	# Update selection.
	var mapped_selection: Array[Vector3i] = []
	if editor.selection and editor.selection.count() > 0:
		for sel_pos in editor.selection.to_array():
			if positions.has(sel_pos):
				mapped_selection.append(sel_pos - min_corner)
	_record_selection_transform(undo_redo, editor, mapped_selection)
	undo_redo.commit_action()
