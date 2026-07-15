@tool
@icon("res://addons/voxly-core/assets/icons/voxel_node_3d.svg")
@abstract
class_name VoxelNode3D
extends Node3D
## Abstract base class for all nodes that display voxel content.
## Defines core properties and methods shared across voxel content object.

var DEBUG_CONTEXT := "VoxelNode3D"

## Emitted when mesh generation mode changes
signal mesh_mode_changed

## Emitted when voxel size changes
signal voxel_size_changed

## Emitted when the VoxelSet changes
signal voxel_set_changed

## Emitted when voxel data changes
signal voxels_changed

## Supported meshing modes
enum MeshMode {
	BRUTE = 0,   # All faces, no culling
	NAIVE = 1,   # Culled faces (check neighbors)
	GREEDY = 2   # Greedy merged faces (most optimized)
}

@export_tool_button("Rebuild Mesh", "BoxMesh")
var rebuild_mesh_button = rebuild_mesh

## When enabled (default), the mesh automatically updates whenever
## the assigned VoxelSet resource is modified. Disable for manual control.
@export
var update_with_voxel_set: bool = true

## Mesh generation algorithm
@export
var mesh_mode: MeshMode = MeshMode.GREEDY:
	get = get_mesh_mode,
	set = set_mesh_mode

## Size of individual voxels in world units
@export
var voxel_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	get = get_voxel_size,
	set = set_voxel_size

## Reference to VoxelSet resource
@export
var voxel_set: VoxelSet:
	get = get_voxel_set,
	set = set_voxel_set

## Whether to include vertex colors
@export
var voxels_colored: bool = true:
	get = get_voxels_colored,
	set = set_voxels_colored

## Whether to include UV coordinates
@export
var voxels_textured: bool = true:
	get = get_voxels_textured,
	set = set_voxels_textured

var _pending_rebuild: bool = false

func get_voxel_size() -> Vector3:
	return voxel_size

func set_voxel_size(new_voxel_size: Vector3) -> void:
	var clamped_size := new_voxel_size.max(Vector3(0.1, 0.1, 0.1))
	if clamped_size != voxel_size:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Voxel size changed: %s -> %s" % [voxel_size, clamped_size])
		voxel_size = clamped_size
		voxel_size_changed.emit()
		_queue_rebuild()

func get_mesh_mode() -> MeshMode:
	return mesh_mode

func set_mesh_mode(new_mesh_mode: MeshMode) -> void:
	if new_mesh_mode != mesh_mode:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Mesh mode changed: %s -> %s" % [MeshMode.keys()[mesh_mode], MeshMode.keys()[new_mesh_mode]])
		mesh_mode = new_mesh_mode
		mesh_mode_changed.emit()
		_queue_rebuild()

func get_voxel_set() -> VoxelSet:
	return voxel_set

func set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if voxel_set != new_voxel_set:
		# Disconnect old signal
		if voxel_set and voxel_set.changed.is_connected(_on_voxel_set_content_changed):
			voxel_set.changed.disconnect(_on_voxel_set_content_changed)
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "VoxelSet changed")
		voxel_set = new_voxel_set
		
		# Connect new signal for auto-refresh when VoxelSet content changes
		if voxel_set and not voxel_set.changed.is_connected(_on_voxel_set_content_changed):
			voxel_set.changed.connect(_on_voxel_set_content_changed)
		
		voxel_set_changed.emit()
		if _pending_rebuild:
			_pending_rebuild = false
		_queue_rebuild()

## Called when the VoxelSet resource's `changed` signal fires
## (e.g., after voxel properties are edited via the VoxelSet editor).
## Triggers a mesh rebuild so the node reflects the updated data.
func _on_voxel_set_content_changed() -> void:
	if update_with_voxel_set:
		_queue_rebuild()

func get_voxels_colored() -> bool:
	return voxels_colored

func set_voxels_colored(new_value: bool) -> void:
	if voxels_colored != new_value:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Vertex colors: %s" % new_value)
		voxels_colored = new_value
		_queue_rebuild()

func get_voxels_textured() -> bool:
	return voxels_textured

func set_voxels_textured(new_value: bool) -> void:
	if voxels_textured != new_value:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Textures: %s" % new_value)
		voxels_textured = new_value
		_queue_rebuild()

## Returns the total number of voxels
@abstract
func get_voxel_count() -> int

## Returns all used voxel positions
@abstract
func get_voxel_positions_used() -> Array[Vector3i]

## Returns the voxel ID or voxel object at specified position
@abstract
func get_voxel(voxel_position: Vector3i, as_voxel: bool = false)

## Gets all voxels as Dictionary[Vector3i, int]
@abstract
func get_voxels(as_voxel: bool = false)

## Sets a voxel at specified position
@abstract
func set_voxel(voxel_position: Vector3i, voxel_id: int) -> void

## Removes a voxel at specified position
@abstract
func remove_voxel(voxel_position: Vector3i) -> void

## Removes voxels at specified positions
@abstract
func remove_voxels(voxel_positions: Array[Vector3i]) -> void

## Clears all voxels
@abstract
func clear_voxels() -> void

## Rebuilds the mesh using the current mesher
func rebuild_mesh() -> void:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Rebuilding mesh")
	voxels_changed.emit()

## Queues a rebuild (called when properties change in editor)
func _queue_rebuild() -> void:
	if Engine.is_editor_hint():
		if not is_instance_valid(voxel_set):
			_pending_rebuild = true
			return
		rebuild_mesh()

## Converts a world position to local voxel grid coordinates
func world_to_voxel_position(world_position: Vector3) -> Vector3i:
	return Vector3i((world_position / voxel_size).round())

## Converts voxel grid coordinates to world position
func voxel_to_world_position(voxel_position: Vector3i) -> Vector3:
	return Vector3(voxel_position) * voxel_size

## Raycasts through the voxel grid using DDA algorithm
func voxel_raycast(origin: Vector3, direction: Vector3, length: float) -> Dictionary:
	var result = {}
	var voxel_pos = world_to_voxel_position(origin)
	var step = Vector3i(
		sign(direction.x),
		sign(direction.y),
		sign(direction.z)
	)
	
	# Calculate t_max and t_delta
	var t_max := Vector3(
		(voxel_pos.x + max(0, step.x) - origin.x / voxel_size.x) / direction.x if direction.x != 0 else INF,
		(voxel_pos.y + max(0, step.y) - origin.y / voxel_size.y) / direction.y if direction.y != 0 else INF,
		(voxel_pos.z + max(0, step.z) - origin.z / voxel_size.z) / direction.z if direction.z != 0 else INF
	)
	
	var t_delta := Vector3(
		abs(1.0 / (direction.x * voxel_size.x)) if direction.x != 0 else INF,
		abs(1.0 / (direction.y * voxel_size.y)) if direction.y != 0 else INF,
		abs(1.0 / (direction.z * voxel_size.z)) if direction.z != 0 else INF
	)
	
	var traveled := 0.0
	while traveled < length:
		var voxel = get_voxel(voxel_pos)
		if voxel != null:
			result.hit = true
			result.hit_position = voxel_pos
			
			# Determine normal from the closest plane
			if t_max.x < t_max.y and t_max.x < t_max.z:
				result.hit_normal = Vector3i(-step.x, 0, 0)
			elif t_max.y < t_max.z:
				result.hit_normal = Vector3i(0, -step.y, 0)
			else:
				result.hit_normal = Vector3i(0, 0, -step.z)
			return result
		
		# Step to next voxel
		if t_max.x < t_max.y and t_max.x < t_max.z:
			voxel_pos.x += step.x
			traveled = t_max.x
			t_max.x += t_delta.x
		elif t_max.y < t_max.z:
			voxel_pos.y += step.y
			traveled = t_max.y
			t_max.y += t_delta.y
		else:
			voxel_pos.z += step.z
			traveled = t_max.z
			t_max.z += t_delta.z
	
	return result

## Returns positions of voxels that have a neighbor in the given direction
func get_covered_voxels(voxel_positions: Array[Vector3i], face_covered: Vector3i) -> Array[Vector3i]:
	var covered: Array[Vector3i] = []
	for voxel_position in voxel_positions:
		if typeof(get_voxel(voxel_position)) == TYPE_INT:
			if typeof(get_voxel(voxel_position + face_covered)) == TYPE_INT:
				covered.append(voxel_position)
	return covered

## Returns positions of voxels that do NOT have a neighbor in the given direction
func get_uncovered_voxels(voxel_positions: Array[Vector3i], face_uncovered: Vector3i) -> Array[Vector3i]:
	var uncovered: Array[Vector3i] = []
	for voxel_position in voxel_positions:
		if typeof(get_voxel(voxel_position)) == TYPE_INT:
			if typeof(get_voxel(voxel_position + face_uncovered)) != TYPE_INT:
				uncovered.append(voxel_position)
	return uncovered
