@tool
extends VoxlyEditOperation
## Rotates the targeted voxels 90° around the axis, relative to the targeted 
## region's minimum corner. Targets the selection when one exists, otherwise 
## all filled voxels.

## True = clockwise, false = counter-clockwise
var clockwise: bool = true

func _init() -> void:
	id = "rotate_voxels"
	category = "transform"
	display_name = "Rotate"
	uses_selection_fallback = true
	modifies_voxels = true

## Parameterized menu entries (rendered as a Rotate submenu).
func get_param_entries() -> Array[Dictionary]:
	return [
		{"label": "Right 90°", "param": "right"},
		{"label": "Left 90°", "param": "left"},
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
	
	# Region origin, min corner of the targeted voxels.
	var min_corner := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for pos in positions:
		min_corner.x = mini(min_corner.x, pos.x)
		min_corner.y = mini(min_corner.y, pos.y)
		min_corner.z = mini(min_corner.z, pos.z)
	
	# Capture source ids and compute rotated destinations.
	var dest_to_id: Dictionary = {}
	for pos in positions:
		var rel := pos - min_corner
		var rot := _rotate_y(rel, clockwise)
		var dest := min_corner + rot
		if target.has_method("is_voxel_position_valid"):
			if not target.is_voxel_position_valid(dest):
				continue
		var voxel_id = target.get_voxel(pos)
		if voxel_id != null:
			dest_to_id[dest] = voxel_id
	
	# Replace every targeted voxel: clear old positions, write rotated ones.
	undo_redo.create_action("Voxly Rotate %s 90°" % ("Right" if clockwise else "Left"))
	_record_remove_all(undo_redo, target, positions)
	_record_set_all(undo_redo, target, dest_to_id)
	_record_rebuild(undo_redo, target)
	_record_selection_transform(undo_redo, editor, dest_to_id.keys())
	undo_redo.commit_action()

## Rotation around axis at integer coordinates.
func _rotate_y(rel: Vector3i, cw: bool) -> Vector3i:
	if cw:
		return Vector3i(-rel.z, rel.y, rel.x)
	return Vector3i(rel.z, rel.y, -rel.x)
