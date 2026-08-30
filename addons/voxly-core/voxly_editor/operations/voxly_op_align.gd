## Aligns the targeted voxels' AABB edge to the model shape edge.
## Targets the selection when one exists, otherwise all filled voxels.
##
## The targeted voxels are translated along `axis` so that their min/center/max
## edge lines up with the corresponding shape edge:
##   min    = 0
##   center = (shape - 1) / 2
##   max    = shape - 1
##
## NOTE: Voxels whose destination falls outside the model shape are clipped.
@tool
extends VoxlyEditOperation

## Align axis: 0=X, 1=Y, 2=Z. Set by the menu before executing.
var axis: int = 0

## Align mode: 0=min, 1=center, 2=max. Set by the menu before executing.
var align_mode: int = 0

## When true, all three axes are aligned to center in one operation.
var align_all_axes: bool = false

## Registers the align operation in the registry.
func _init() -> void:
	id = "align_voxels"
	category = "align"
	display_name = "Align"
	uses_selection_fallback = true
	modifies_voxels = true

## Parameterized menu entries (rendered as an Align submenu).
func get_param_entries() -> Array[Dictionary]:
	return [
		{"label": "Center XYZ", "param": "xyz_center"},
		{"separator": true},
		{"label": "Min X", "param": "x_min"},
		{"label": "Center X", "param": "x_center"},
		{"label": "Max X", "param": "x_max"},
		{"separator": true},
		{"label": "Min Y", "param": "y_min"},
		{"label": "Center Y", "param": "y_center"},
		{"label": "Max Y", "param": "y_max"},
		{"separator": true},
		{"label": "Min Z", "param": "z_min"},
		{"label": "Center Z", "param": "z_center"},
		{"label": "Max Z", "param": "z_max"},
	]

## Returns whether a selection exists to align.
func is_available(editor: VoxlyEditor) -> bool:
	return _target_has_content(editor)

## Aligns the selected voxels.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	var shape := Vector3i.ZERO
	if target.has_method("get_shape"):
		shape = target.get_shape()
	
	# AABB of the targeted voxels.
	var min_corner := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var max_corner := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for position in positions:
		for i in 3:
			min_corner[i] = mini(min_corner[i], position[i])
			max_corner[i] = maxi(max_corner[i], position[i])
	
	# Compute the translation per axis. Center XYZ aligns all three axes in
	# one operation; single-axis aligns produce zero delta on the other axes.
	var delta := Vector3i.ZERO
	var axes = [0, 1, 2] if align_all_axes else [axis]
	for axis_index in axes:
		var shape_edge: int
		match align_mode:
			0: shape_edge = 0
			1: shape_edge = (shape[axis_index] - 1) / 2
			_: shape_edge = shape[axis_index] - 1
		var current_edge: int
		match align_mode:
			0: current_edge = min_corner[axis_index]
			1: current_edge = (min_corner[axis_index] + max_corner[axis_index]) / 2
			_: current_edge = max_corner[axis_index]
		delta[axis_index] = shape_edge - current_edge
	
	if delta == Vector3i.ZERO:
		return
	
	# Capture source IDs, then compute aligned destinations.
	var voxel_ids: Dictionary[Vector3i, int] = {}
	for position in positions:
		voxel_ids[position] = target.get_voxel(position)
	
	var dest_to_id: Dictionary[Vector3i, int] = {}
	var seen: Dictionary[Vector3i, bool] = {}
	for position in positions:
		var dest := position + delta
		if target.has_method("is_voxel_position_valid"):
			if not target.is_voxel_position_valid(dest):
				continue
		if seen.has(dest):
			continue
		seen[dest] = true
		var voxel_id = voxel_ids.get(position)
		if voxel_id != null:
			dest_to_id[dest] = voxel_id
	
	if dest_to_id.is_empty():
		return
	
	var action_name: String
	if align_all_axes:
		action_name = "Voxly Align Center XYZ"
	else:
		action_name = "Voxly Align %s %s" % [
			["X", "Y", "Z"][axis],
			["Min", "Center", "Max"][align_mode],
		]
	undo_redo.create_action(action_name)
	_record_remove_all(undo_redo, target, positions)
	_record_set_all(undo_redo, target, dest_to_id)
	_record_rebuild(undo_redo, target)
	_record_selection_transform(undo_redo, editor, dest_to_id.keys())
	undo_redo.commit_action()
