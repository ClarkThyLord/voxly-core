## Rotates the targeted voxels 90° around the Y axis, relative to the targeted
## region's minimum corner. Targets the selection when one exists, otherwise
## all filled voxels.
@tool
extends VoxlyEditOperation

## True = clockwise, false = counter-clockwise.
var clockwise: bool = true

## Registers the rotate operation in the registry.
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

## Returns whether a selection exists to rotate.
func is_available(editor: VoxlyEditor) -> bool:
	return _target_has_content(editor)

## Rotates the selection around an axis.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	# Region origin: the min corner of the targeted voxels.
	var min_corner := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for position in positions:
		min_corner.x = mini(min_corner.x, position.x)
		min_corner.y = mini(min_corner.y, position.y)
		min_corner.z = mini(min_corner.z, position.z)
	
	# Capture source IDs and compute rotated destinations.
	var dest_to_id: Dictionary[Vector3i, int] = {}
	for position in positions:
		var relative_position := position - min_corner
		var rotated_position := _rotate_y(relative_position, clockwise)
		var dest := min_corner + rotated_position
		if target.has_method("is_voxel_position_valid"):
			if not target.is_voxel_position_valid(dest):
				continue
		var voxel_id = target.get_voxel(position)
		if voxel_id != null:
			dest_to_id[dest] = voxel_id
	
	# Replace every targeted voxel: clear old positions, write rotated ones.
	undo_redo.create_action("Voxly Rotate %s 90°" % ("Right" if clockwise else "Left"))
	_record_remove_all(undo_redo, target, positions)
	_record_set_all(undo_redo, target, dest_to_id)
	_record_rebuild(undo_redo, target)
	_record_selection_transform(undo_redo, editor, dest_to_id.keys())
	undo_redo.commit_action()

## Rotates a position 90° around the Y axis at integer coordinates.
func _rotate_y(relative_position: Vector3i, clockwise: bool) -> Vector3i:
	if clockwise:
		return Vector3i(-relative_position.z, relative_position.y, relative_position.x)
	return Vector3i(relative_position.z, relative_position.y, -relative_position.x)
