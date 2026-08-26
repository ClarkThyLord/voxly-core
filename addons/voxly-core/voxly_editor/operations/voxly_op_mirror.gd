@tool
extends VoxlyEditOperation
## Mirros the targeted voxels across the model center, adding the
## mirrored copies. Targets the selection when one exists, otherwise all
## filled voxels.

## Mirror axis: 0=X, 1=Y, 2=Z. Set by the menu before executing.
var axis: int = 0

func _init() -> void:
	id = "mirror_voxels"
	category = "transform"
	display_name = "Mirror"
	uses_selection_fallback = true
	modifies_voxels = true

## Parameterized menu entries (rendered as a Mirror submenu).
func get_param_entries() -> Array[Dictionary]:
	return [
		{"label": "X", "param": "x"},
		{"label": "Y", "param": "y"},
		{"label": "Z", "param": "z"},
	]

func is_available(editor) -> bool:
	return _target_has_content(editor)

func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	var shape := Vector3i.ZERO
	if target.has_method("get_shape"):
		shape = target.get_shape()
	var half := Vector3i(shape.x - 1, shape.y - 1, shape.z - 1)
	
	# Collect voxels to add: the mirrored copies of each targeted voxel.
	var additional: Dictionary = {}
	var seen: Dictionary[Vector3i, bool] = {}
	for pos in positions:
		seen[pos] = true
	var voxel_ids: Dictionary = {}
	for pos in positions:
		voxel_ids[pos] = target.get_voxel(pos)
	
	for pos in positions:
		var mirrored := pos
		if axis == 0:
			mirrored.x = half.x - mirrored.x
		elif axis == 1:
			mirrored.y = half.y - mirrored.y
		else:
			mirrored.z = half.z - mirrored.z
		if seen.has(mirrored):
			continue
		if voxel_ids.has(pos) and voxel_ids[pos] != null:
			additional[mirrored] = voxel_ids[pos]
			seen[mirrored] = true
	
	if additional.is_empty():
		return
	
	# Mirror selection now includes both the original
	# targeted voxels and the newly mirrored copies.
	var new_selection: Array[Vector3i] = positions.duplicate()
	for pos in additional:
		new_selection.append(pos)
	
	undo_redo.create_action("Voxly Mirror %s" % ["X", "Y", "Z"][axis])
	_record_set_all(undo_redo, target, additional)
	_record_rebuild(undo_redo, target)
	_record_selection_transform(undo_redo, editor, new_selection)
	undo_redo.commit_action()
