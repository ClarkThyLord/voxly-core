@tool
extends VoxlyEditOperation
## Translate the targeted voxels by an integer grid offset.
## Targets the selection when one exists, otherwise all filled voxels.

## Offset applied along each axis, in voxel units.
var offset_x: int = 0
var offset_y: int = 0
var offset_z: int = 0

func _init() -> void:
	id = "translate_voxels"
	category = "transform"
	display_name = "Translate"
	uses_selection_fallback = true
	modifies_voxels = true
	prompts_for_options = true

func is_available(editor) -> bool:
	return _target_has_content(editor)

## Returns the option schema used by the editor's ContextWindow to prompt the
## user for the X/Y/Z offsets.
func get_options() -> Array[Dictionary]:
	return [
		{
			"label": "Offset X",
			"property": "offset_x",
			"type": TYPE_INT,
			"min": -1000,
			"max": 1000,
			"step": 1,
			"default": 0,
		},
		{
			"label": "Offset Y",
			"property": "offset_y",
			"type": TYPE_INT,
			"min": -1000,
			"max": 1000,
			"step": 1,
			"default": 0,
		},
		{
			"label": "Offset Z",
			"property": "offset_z",
			"type": TYPE_INT,
			"min": -1000,
			"max": 1000,
			"step": 1,
			"default": 0,
		},
	]

func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	var delta := Vector3i(offset_x, offset_y, offset_z)
	if delta == Vector3i.ZERO:
		return
	
	# Capture source ids, then compute translated destinations.
	var voxel_ids: Dictionary = {}
	for pos in positions:
		voxel_ids[pos] = target.get_voxel(pos)
	
	var dest_to_id: Dictionary = {}
	var seen: Dictionary[Vector3i, bool] = {}
	for pos in positions:
		var dest := pos + delta
		if target.has_method("is_voxel_position_valid"):
			if not target.is_voxel_position_valid(dest):
				continue
		if seen.has(dest):
			continue
		seen[dest] = true
		var voxel_id = voxel_ids.get(pos)
		if voxel_id != null:
			dest_to_id[dest] = voxel_id
	
	if dest_to_id.is_empty():
		return
	
	undo_redo.create_action("Voxly Translate (%d, %d, %d)" % [delta.x, delta.y, delta.z])
	_record_remove_all(undo_redo, target, positions)
	_record_set_all(undo_redo, target, dest_to_id)
	_record_rebuild(undo_redo, target)
	_record_selection_transform(undo_redo, editor, dest_to_id.keys())
	undo_redo.commit_action()
