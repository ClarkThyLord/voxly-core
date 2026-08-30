## Model for the persistent selection of voxel positions in the voxel editor.
##
## Owned by [VoxlyEditor] (one instance per editor). Brushes, tools, and the
## Edit menu operate on this state. Every mutation emits [signal changed] so
## the selection overlay and UI stay in sync, including undo / redo.
@tool
class_name VoxlySelection
extends RefCounted

## Emitted whenever the selection contents change.
signal changed

## The ordered list of selected voxel positions.
var _positions: Array[Vector3i] = []

## Adds a position. No-op if already present.
func add(position: Vector3i) -> void:
	if position in _positions:
		return
	
	_positions.append(position)
	changed.emit()

## Removes a position. No-op if absent.
func remove(position: Vector3i) -> void:
	if not _positions.has(position):
		return
	
	_positions.erase(position)
	changed.emit()

## Sets the selection to exactly the given positions, deduplicated.
func set_positions(positions: Array[Vector3i]) -> void:
	var seen: Dictionary[Vector3i, bool] = {}
	var new_positions: Array[Vector3i] = []
	for position in positions:
		if not seen.has(position):
			seen[position] = true
			new_positions.append(position)
	
	var state_changed := new_positions.size() != _positions.size()
	if not state_changed:
		for position in new_positions:
			if not _positions.has(position):
				state_changed = true
				break
	
	if not state_changed:
		return
	
	_positions = new_positions
	changed.emit()

## Applies a batch of selection toggles, usually from a stroke's single undo
## action. [param entries] is an [code]Array[Dictionary][/code] with `position`
## (Vector3i) and `selected` (bool) keys.
func apply_stroke_delta(entries: Array[Dictionary]) -> void:
	for entry in entries:
		var position: Vector3i = entry["position"]
		if entry["selected"]:
			add(position)
		else:
			remove(position)

## Clears the selection, emits if non-empty.
func clear() -> void:
	if _positions.is_empty():
		return
	
	_positions.clear()
	changed.emit()

## Returns true if the position is currently selected.
func has(position: Vector3i) -> bool:
	return position in _positions

## Returns the number of selected positions.
func count() -> int:
	return _positions.size()

## Returns a copy of the selected positions.
func to_array() -> Array[Vector3i]:
	return _positions.duplicate()

## Populates the selection with every filled voxel position from the target
## node, if it exposes get_voxel_positions_used(). Replaces the current
## selection.
func select_all_from(target) -> void:
	if target == null:
		return
	elif not target.has_method("get_voxel_positions_used"):
		return
	
	var positions = target.get_voxel_positions_used()
	if positions is Array:
		set_positions(positions)
	else:
		clear()
