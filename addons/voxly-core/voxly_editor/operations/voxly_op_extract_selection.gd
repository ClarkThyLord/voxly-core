## Requires a selection to create a new sibling VoxelModel3D containing the
## current selection, then removes those voxels from the source model.
@tool
extends VoxlyEditOperation

## Registers the extract operation in the registry.
func _init() -> void:
	id = "extract_selection"
	category = "new_model"
	display_name = "Extract Selection to New Model"
	modifies_voxels = true

## Returns whether a selection exists to extract.
func is_available(editor: VoxlyEditor) -> bool:
	return editor != null and editor.selection != null and editor.selection.count() > 0

## Extracts the selection to a new model.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	var source := _get_target(editor)
	if source == null or editor.selection.count() == 0:
		return
	var positions = editor.selection.to_array()
	if positions.is_empty():
		return
	
	var min_corner := _min_corner(positions)
	var max_corner := _max_corner(positions)
	var new_shape := max_corner - min_corner + Vector3i.ONE
	
	# Build the new model's voxel map.
	var voxel_map: Dictionary[Vector3i, int] = {}
	for position in positions:
		var voxel_id = source.get_voxel(position)
		if voxel_id != null:
			voxel_map[position - min_corner] = voxel_id
	if voxel_map.is_empty():
		return
	
	# Create the sibling model.
	var new_model := VoxelModel3D.new()
	new_model.name = "%s_Extracted" % source.name
	new_model.voxel_set = source.voxel_set
	new_model.voxel_size = source.voxel_size
	new_model.shape = new_shape
	# Shift its origin so it rests at the source's world position.
	new_model.origin = source.origin + Vector3(min_corner) * source.voxel_size
	
	var parent := source.get_parent()
	if parent == null:
		return
	
	# Add the new node and populate it.
	undo_redo.create_action("Voxly Extract Selection")
	undo_redo.add_do_method(parent, "add_child", new_model)
	undo_redo.add_do_method(new_model, "set_owner", source.owner)
	
	for voxel_position in voxel_map:
		undo_redo.add_do_method(new_model, "set_voxel", voxel_position, voxel_map[voxel_position])
	undo_redo.add_do_method(new_model, "update")
	undo_redo.add_undo_method(parent, "remove_child", new_model)
	
	# Remove the extracted voxels from the source.
	_record_remove_all(undo_redo, source, positions)
	_record_rebuild(undo_redo, source)
	
	# Clear selection.
	_record_selection_clear(undo_redo, editor)
	undo_redo.commit_action()

## Returns the minimum corner of the positions.
func _min_corner(positions: Array[Vector3i]) -> Vector3i:
	var result := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for position in positions:
		for i in 3:
			result[i] = mini(result[i], position[i])
	return result

## Returns the maximum corner of the positions.
func _max_corner(positions: Array[Vector3i]) -> Vector3i:
	var result := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for position in positions:
		for i in 3:
			result[i] = maxi(result[i], position[i])
	return result
