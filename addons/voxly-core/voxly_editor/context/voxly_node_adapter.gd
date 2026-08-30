## Single ownership point for every voxel-node touch in the editor pipeline.
##
## Brushes, tools, the controller, and operation helpers all reach voxel data
## through this adapter instead of holding the raw node. This:
## - Gives UndoRedo a stable RefCounted to register methods on (RefCounted
##   stays alive as long as the undo stack references it).
## - Provides a single [method is_valid] guard, so a freed node can never crash
##   a pending undo/redo operation.
@tool
class_name VoxlyNodeAdapter
extends RefCounted

## The wrapped voxel node (a [VoxelNode3D] or subclass).
var node = null

## Creates an adapter wrapping the given node.
func _init(node = null) -> void:
	self.node = node

## True while the underlying node is still alive.
func is_valid() -> bool:
	return is_instance_valid(node)

## Returns the raw wrapped node.
func get_node():
	return node

## Returns the palette ID at the position, or null when empty.
func voxel_at(position: Vector3i):
	if not is_valid() or not node.has_method("get_voxel"):
		return null
	return node.get_voxel(position)

## Writes (or removes, with null) a palette ID at the position.
func set_voxel(position: Vector3i, voxel_id) -> void:
	if not is_valid():
		return
	if voxel_id == null:
		if node.has_method("remove_voxel"):
			node.remove_voxel(position)
	else:
		node.set_voxel(position, voxel_id)

## Removes the voxel at the position (delegates to node.remove_voxel).
## Exposed so UndoRedo can bind a real method callable to the adapter
## (UndoRedo rejects callables to methods that don't exist on the target).
func remove_voxel(position: Vector3i) -> void:
	if is_valid() and node.has_method("remove_voxel"):
		node.remove_voxel(position)

## Bulk-applies a [code]Dictionary[Vector3i, id][/code] voxel map. Idempotent,
## so both do and undo can re-run the same call safely.
func apply_voxel_map(voxels: Dictionary) -> void:
	for position in voxels:
		set_voxel(position, voxels[position])

## High-level refresh: rebuilds the node's mesh, notifies listeners, and
## optionally refreshes collision (no-op when invalid/freed). Call after
## editing voxels through the adapter.
func update() -> void:
	if is_valid() and node.has_method("update"):
		node.update()

## All filled positions (for select-all style operations).
func get_voxel_positions_used() -> Array[Vector3i]:
	if not is_valid() or not node.has_method("get_voxel_positions_used"):
		return []
	return node.get_voxel_positions_used()

## Number of filled voxels.
func get_voxel_count() -> int:
	if not is_valid() or not node.has_method("get_voxel_count"):
		return 0
	return node.get_voxel_count()

## Connected face region (extrude brush).
func get_exposed_face_voxels(position: Vector3i, normal: Vector3i, match_id: bool) -> Array[Vector3i]:
	if not is_valid() or not node.has_method("get_exposed_face_voxels"):
		return []
	return node.get_exposed_face_voxels(position, normal, match_id)

## True when the position is inside the model's grid bounds.
func is_voxel_position_valid(position: Vector3i) -> bool:
	if not is_valid() or not node.has_method("is_voxel_position_valid"):
		return true
	return node.is_voxel_position_valid(position)

## DDA raycast against occupied voxels (for voxel-level hit resolution).
func voxel_raycast(from: Vector3, direction: Vector3, max_dist: float) -> Dictionary:
	if not is_valid() or not node.has_method("voxel_raycast"):
		return {}
	return node.voxel_raycast(from, direction, max_dist)

## Node-local version of a global position.
func to_local(global_pos: Vector3) -> Vector3:
	if not is_valid():
		return global_pos
	return node.to_local(global_pos)

## Grid shape in voxel units.
func get_shape() -> Vector3i:
	if is_valid() and "shape" in node:
		return node.shape
	return Vector3i(16, 16, 16)

## Grid voxel size.
func get_voxel_size() -> Vector3:
	if is_valid() and "voxel_size" in node:
		return node.voxel_size
	return Vector3.ONE
