## Flips the targeted voxels in place across the targeted region's center axis.
## Targets the selection when one exists, otherwise all filled voxels.
@tool
extends VoxlyEditOperation

## Flip axis: 0=X, 1=Y, 2=Z. Set by the menu before executing.
var axis: int = 0

## Registers the flip operation in the registry.
func _init() -> void:
	id = "flip_voxels"
	category = "transform"
	display_name = "Flip"
	uses_selection_fallback = true
	modifies_voxels = true

## Parameterized menu entries (rendered as a Flip submenu).
func get_param_entries() -> Array[Dictionary]:
	return [
		{"label": "X", "param": "x"},
		{"label": "Y", "param": "y"},
		{"label": "Z", "param": "z"},
	]

## Returns whether a selection exists to flip.
func is_available(editor: VoxlyEditor) -> bool:
	return _target_has_content(editor)

## Flips the selection along an axis.
func execute(editor: VoxlyEditor, undo_redo: EditorUndoRedoManager) -> void:
	var target := _get_target(editor)
	if target == null:
		return
	var positions := _resolve_positions(editor)
	if positions.is_empty():
		return
	
	# Region bounds along the flip axis for in-place mirroring.
	var min_corner := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var max_corner := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for position in positions:
		for i in 3:
			min_corner[i] = mini(min_corner[i], position[i])
			max_corner[i] = maxi(max_corner[i], position[i])
	
	# Capture source IDs, then compute flipped destinations.
	var voxel_ids: Dictionary[Vector3i, int] = {}
	for position in positions:
		voxel_ids[position] = target.get_voxel(position)
	
	var dest_to_id: Dictionary[Vector3i, int] = {}
	var seen: Dictionary[Vector3i, bool] = {}
	for position in positions:
		var flipped := position
		flipped[axis] = max_corner[axis] - (position[axis] - min_corner[axis])
		if not seen.has(flipped) and flipped != position:
			seen[flipped] = true
			var voxel_id = voxel_ids.get(position)
			if voxel_id != null:
				dest_to_id[flipped] = voxel_id
	
	if dest_to_id.is_empty():
		return
	
	undo_redo.create_action("Voxly Flip %s" % ["X", "Y", "Z"][axis])
	_record_remove_all(undo_redo, target, positions)
	_record_set_all(undo_redo, target, dest_to_id)
	_record_rebuild(undo_redo, target)
	_record_selection_transform(undo_redo, editor, dest_to_id.keys())
	undo_redo.commit_action()
