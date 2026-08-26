@tool
class_name VoxlySelection
extends RefCounted
## Model for the persistent selection of voxel positions in the voxel editor.
##
## Owned by VoxlyEditor (one instance per editor). Brushes, tools, and the
## Edit menu operate on this state. Every mutation emits `changed` so the
## selection overlay and UI stay in sync, including undo / redo.

## Emitted whenever the selection contents change.
signal changed

var _positions: Array[Vector3i] = []


## Adds a position. No-op if already present.
func add(pos: Vector3i) -> void:
	if pos in _positions:
		return
	
	_positions.append(pos)
	changed.emit()


## Removes a position. No-op if absent.
func remove(pos: Vector3i) -> void:
	if not _positions.has(pos):
		return
	
	_positions.erase(pos)
	changed.emit()


## Sets the selection to exactly the given positions, deduplicated.
func set_positions(positions: Array[Vector3i]) -> void:
	var seen: Dictionary[Vector3i, bool] = {}
	var new_positions: Array[Vector3i] = []
	for pos in positions:
		if not seen.has(pos):
			seen[pos] = true
			new_positions.append(pos)
	
	var state_changed := new_positions.size() != _positions.size()
	if not state_changed:
		for pos in new_positions:
			if not _positions.has(pos):
				state_changed = true
				break
	
	if not state_changed:
		return
	
	_positions = new_positions
	changed.emit()


## Applies a batch of selection toggles, usually from a stroke's single undo
## action. `entries` is an Array[Dictionary] with `pos` (Vector3i) and
## `selected` (bool) keys.
func apply_stroke_delta(entries: Array[Dictionary]) -> void:
	for entry in entries:
		var pos: Vector3i = entry["pos"]
		if entry["selected"]:
			add(pos)
		else:
			remove(pos)

## Clears the selection, emits if non-empty.
func clear() -> void:
	if _positions.is_empty():
		return
	
	_positions.clear()
	changed.emit()


## Returns true if the position is currently selected.
func has(pos: Vector3i) -> bool:
	return pos in _positions


## Returns the number of selected positions.
func count() -> int:
	return _positions.size()


## Returns a copy of the selected positions.
func to_array() -> Array[Vector3i]:
	return _positions.duplicate()


## Populates the selection with every filled voxel position
## from the target node, if it exposes get_voxel_positions_used().
## Replaces the current selection.
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
