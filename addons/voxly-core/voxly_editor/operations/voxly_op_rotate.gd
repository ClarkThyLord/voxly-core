## Rotates the targeted voxels 90° around the configured axis, relative to the
## minimum corner of the targeted region. Targets the selection when one exists,
## otherwise all filled voxels.
##
## Rotations pivot on that corner and use the region size so the rotated voxels
## stay inside the model bounds.
@tool
extends VoxlyEditOperation

## Rotation axis: 0 = X, 1 = Y, 2 = Z. Set by the menu before executing.
var axis: int = 1

## True = clockwise seen from the positive axis, false = counter-clockwise.
## Set by the menu before executing.
var clockwise: bool = true

## Registers the rotate operation in the registry.
func _init() -> void:
	id = "rotate_voxels"
	category = "transform"
	display_name = "Rotate"
	uses_selection_fallback = true
	modifies_voxels = true

## Parameterized menu entries (rendered as a Rotate submenu), one pair per axis.
func get_param_entries() -> Array[Dictionary]:
	return [
		{"label": "X Right 90°", "param": "x_right"},
		{"label": "X Left 90°", "param": "x_left"},
		{"separator": true},
		{"label": "Y Right 90°", "param": "y_right"},
		{"label": "Y Left 90°", "param": "y_left"},
		{"separator": true},
		{"label": "Z Right 90°", "param": "z_right"},
		{"label": "Z Left 90°", "param": "z_left"},
	]

## Returns whether a selection exists to rotate.
func is_available(editor: VoxlyEditor) -> bool:
	return _target_has_content(editor)

## Rotates the targeted voxels around [member axis].
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	# Region bounds: rotations pivot on the minimum corner of the region and use
	# the region size to map every voxel back into the positive octant.
	var min_corner := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var max_corner := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for position in positions:
		for i in 3:
			min_corner[i] = mini(min_corner[i], position[i])
			max_corner[i] = maxi(max_corner[i], position[i])
	var extent := max_corner - min_corner + Vector3i.ONE
	
	# Capture source IDs and compute rotated destinations.
	var dest_to_id: Dictionary[Vector3i, int] = {}
	for position in positions:
		var relative_position := position - min_corner
		var dest := min_corner + _rotate(relative_position, extent)
		if target.has_method("is_voxel_position_valid"):
			if not target.is_voxel_position_valid(dest):
				continue
		var voxel_id = target.get_voxel(position)
		if voxel_id != null:
			dest_to_id[dest] = voxel_id
	
	# Replace every targeted voxel: clear old positions, write rotated ones.
	var axis_name: String = ["X", "Y", "Z"][axis]
	var direction: String = "Right" if clockwise else "Left"
	undo_redo.create_action("Voxly Rotate %s %s 90°" % [axis_name, direction])
	_record_remove_all(undo_redo, target, positions)
	_record_set_all(undo_redo, target, dest_to_id)
	_record_rebuild(undo_redo, target)
	_record_selection_transform(undo_redo, editor, dest_to_id.keys())
	undo_redo.commit_action()

## Rotates a relative position 90° around [member axis] at integer coordinates.
##
## [param extent] is the region size along each axis, used to normalise the
## rotated coordinates back into the positive octant because a rotation swaps
## the extents of the axis pair it rotates in.
func _rotate(relative_position: Vector3i, extent: Vector3i) -> Vector3i:
	var x := relative_position.x
	var y := relative_position.y
	var z := relative_position.z
	match axis:
		0:
			# X axis: rotates the YZ plane.
			if clockwise:
				return Vector3i(x, z, extent.y - 1 - y)
			return Vector3i(x, extent.z - 1 - z, y)
		2:
			# Z axis: rotates the XY plane.
			if clockwise:
				return Vector3i(y, extent.x - 1 - x, z)
			return Vector3i(extent.y - 1 - y, x, z)
		_:
			# Y axis: rotates the XZ plane (the default).
			if clockwise:
				return Vector3i(extent.z - 1 - z, y, x)
			return Vector3i(z, y, extent.x - 1 - x)
