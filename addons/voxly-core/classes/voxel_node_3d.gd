@tool
@icon("res://addons/voxly-core/assets/icons/voxel_node_3d.svg")
@abstract
class_name VoxelNode3D
extends Node3D
## Abstract base class for all nodes that display voxel content.
## Defines core properties and methods shared across voxel content object.

var DEBUG_CONTEXT := "VoxelNode3D"

## Emitted when mesh generation mode changes.
signal mesh_mode_changed

## Emitted when voxel size changes.
signal voxel_size_changed

## Emitted when the VoxelSet changes.
signal voxel_set_changed

## Emitted after update() is called.
signal updated

## Supported meshing modes.
enum MeshMode {
	BRUTE = 0, # All faces, no culling.
	NAIVE = 1, # Culled faces (check neighbors).
	GREEDY = 2 # Greedy merged faces (most optimized).
}

@export_tool_button("Update", "Reload")
var _update_button = update

## When enabled, whenever the assigned VoxelSet resource is changed update() is 
## called. Disable for manual control.
@export
var update_with_voxel_set: bool = true

## Mesh generation algorithm.
@export
var mesh_mode: MeshMode = MeshMode.GREEDY:
	get = get_mesh_mode,
	set = set_mesh_mode

## Size of individual voxels in world units.
@export
var voxel_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	get = get_voxel_size,
	set = set_voxel_size

## Reference to VoxelSet resource.
@export
var voxel_set: VoxelSet:
	get = get_voxel_set,
	set = set_voxel_set

## Whether to include vertex colors.
@export
var voxels_colored: bool = true:
	get = get_voxels_colored,
	set = set_voxels_colored

## Whether to include UV coordinates.
@export
var voxels_textured: bool = true:
	get = get_voxels_textured,
	set = set_voxels_textured

var _pending_rebuild: bool = false
var _is_initialized := false
var _opacity_cache: Dictionary[int, bool] = {}

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
		_opacity_cache.clear()
		
		# Connect new signal for auto-refresh when VoxelSet content changes.
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
	_opacity_cache.clear()
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

## High-level refresh: rebuilds the mesh, notifies listeners, and
## optionally refreshes collision. Call this after editing voxels.
func update() -> void:
	rebuild_mesh()
	updated.emit()
	if attach_static_body:
		create_static_body()

## Rebuilds mesh arrays only.
func rebuild_mesh() -> void:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Rebuilding mesh")

## Queues a rebuild.
func _queue_rebuild() -> void:
	if not _is_initialized:
		_pending_rebuild = true
		return
	if Engine.is_editor_hint():
		if not is_instance_valid(voxel_set):
			_pending_rebuild = true
			return
		update()

func _ready() -> void:
	_is_initialized = true
	# Enable editor group editing by default so that selecting a child node
	# (e.g. the MeshInstance3D) in the editor selects this VoxelNode3D instead.
	set_meta("_edit_group_", true)

## Converts a world position to local voxel grid coordinates
func world_to_voxel_position(world_position: Vector3) -> Vector3i:
	return Vector3i((world_position / voxel_size).round())

## Converts voxel grid coordinates to world position
func voxel_to_world_position(voxel_position: Vector3i) -> Vector3:
	return Vector3(voxel_position) * voxel_size


## Raycasts through the voxel grid in WORLD coordinates (meters).
## Converts to the node's local space internally, then walks the grid with
## DDA. Handles node transforms.
##
## Returns a empty dictionary on miss or dictionary with following on hit:
##   hit          (bool)     : whether a voxel was hit
##   hit_position (Vector3i) : grid cell coordinates of the hit
##   hit_normal   (Vector3i) : grid-space face normal of the entry point
func voxel_raycast(ray_origin: Vector3, direction: Vector3, length: float) -> Dictionary:
	var local_origin := to_local(ray_origin)
	var local_dir := to_local(ray_origin + direction) - local_origin
	return _dda(local_origin, local_dir, length)


## Low-level DDA raycast in node-local meters.
## `local_origin` is a continuous position in meters relative to the node's
## origin (before any VoxelModel3D origin offset), `local_dir` is the ray
## direction, and `length` is the max distance in meters.
## Learn more: https://www.youtube.com/watch?v=ztkh1r1ioZo
func _dda(local_origin: Vector3, local_dir: Vector3, length_m: float) -> Dictionary:
	var result = {}
	# Use floor-based position for the DDA stepping, but compute the
	# first voxel position using round() ensuring t_max values are non-negative.
	var voxel_pos := Vector3i(
		floori(local_origin.x / voxel_size.x),
		floori(local_origin.y / voxel_size.y),
		floori(local_origin.z / voxel_size.z)
	)
	var step := Vector3i(
		sign(local_dir.x),
		sign(local_dir.y),
		sign(local_dir.z)
	)
	
	# Distance (t) along the ray to cross one voxel on each axis.
	# Using world-space t: position = origin + direction * t,
	# and voxel boundaries sit at (i * voxel_size).
	var t_delta := Vector3(
		abs(voxel_size.x / local_dir.x) if local_dir.x != 0 else INF,
		abs(voxel_size.y / local_dir.y) if local_dir.y != 0 else INF,
		abs(voxel_size.z / local_dir.z) if local_dir.z != 0 else INF
	)
	
	# Distance (t) to the first voxel boundary on each axis in the step direction.
	var t_max := Vector3(
		((voxel_pos.x + max(0, step.x)) * voxel_size.x - local_origin.x) / local_dir.x if local_dir.x != 0 else INF,
		((voxel_pos.y + max(0, step.y)) * voxel_size.y - local_origin.y) / local_dir.y if local_dir.y != 0 else INF,
		((voxel_pos.z + max(0, step.z)) * voxel_size.z - local_origin.z) / local_dir.z if local_dir.z != 0 else INF
	)
	
	var traveled := 0.0
	# The axis stepped to ENTER the current cell. Used to derive the entry
	# face normal on hit. Zero when the ray starts inside the first cell.
	var last_step := Vector3i.ZERO
	while traveled < length_m:
		var voxel = get_voxel(voxel_pos)
		if voxel != null:
			result.hit = true
			result.hit_position = voxel_pos
			# The entry face is opposite the last axis crossed. Deriving the
			# normal from the CURRENT t_max values (as before) identifies the
			# NEXT boundary instead, giving wrong normals near corners/edges.
			result.hit_normal = -last_step
			return result
		
		# Step to next voxel
		if t_max.x < t_max.y and t_max.x < t_max.z:
			voxel_pos.x += step.x
			traveled = t_max.x
			t_max.x += t_delta.x
			last_step = Vector3i(step.x, 0, 0)
		elif t_max.y < t_max.z:
			voxel_pos.y += step.y
			traveled = t_max.y
			t_max.y += t_delta.y
			last_step = Vector3i(0, step.y, 0)
		else:
			voxel_pos.z += step.z
			traveled = t_max.z
			t_max.z += t_delta.z
			last_step = Vector3i(0, 0, step.z)
	
	return result

## When enabled, the voxel node owns a StaticBody3D child whose trimesh
## CollisionShape3D is generated from the node's render mesh. update()
## refreshes the shape; disabling removes the generated body.
@export var attach_static_body := false:
	set = set_attach_static_body,
	get = get_attach_static_body

func get_attach_static_body() -> bool:
	return attach_static_body

func set_attach_static_body(value: bool) -> void:
	if attach_static_body == value:
		return
	attach_static_body = value
	if _is_voxly_editing():
		# deferred to when we stop editing
		return
	if value:
		if _is_initialized:
			create_static_body()
	else:
		remove_static_body()

## Creates (or refreshes) the node's StaticBody3D trimesh collision from the
## current render mesh. Reuses an existing generated body and swaps its shape
## in place for performance.
##
## Returns the collision body, or null after removing stale collision when
## there is no render mesh.
func create_static_body() -> StaticBody3D:
	var mesh_instance := _get_mesh_instance()
	var body := _get_generated_static_body()
	
	# While editing, never create or touch geometry just disable any existing
	# shape so the collider can't interfere with the edit session.
	if _is_voxly_editing():
		if body:
			var shape_node := _get_or_create_collision_shape_node(body)
			shape_node.set_deferred("disabled", true)
		return body
	
	if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
		# Keep an existing generated body alive when attach_static_body enabled.
		# The body is only removed when the flag is explicitly turned off.
		if attach_static_body and body:
			return body
		remove_static_body()
		return null
	
	if body == null:
		body = StaticBody3D.new()
		body.set_meta("_voxly_static_body_generated", true)
		body.name = "VoxlyStaticBody"
		add_child(body)
	
	# Mark the body as owned by the node's scene owner so the editor saves
	# it with the scene and shows it in the Scene dock.
	if owner:
		body.owner = owner
	
	# The body mirrors the render mesh's transform so the shape lines up with
	# the voxels.
	body.transform = mesh_instance.transform
	
	var shape := mesh_instance.mesh.create_trimesh_shape()
	
	# Trimesh collisions are single-sided in Jolt by default; enabling
	# backface collision keeps the player from clipping through when the
	# character starts inside/on the boundary of the terrain surface.
	shape.backface_collision = true
	var shape_node := _get_or_create_collision_shape_node(body)
	shape_node.position = Vector3.ZERO
	shape_node.shape = shape
	shape_node.set_deferred("disabled", not attach_static_body)
	return body

## Removes the generated StaticBody3D the voxel node owns.
func remove_static_body() -> void:
	for child in get_children():
		if child is StaticBody3D and child.has_meta("_voxly_static_body_generated"):
			child.queue_free()

## True while the voxly editor is actively editing this node.
func _is_voxly_editing() -> bool:
	return get_meta("_voxly_core_editing_", false)

## Returns the generated StaticBody3D owned by this node, or null.
func _get_generated_static_body() -> StaticBody3D:
	for child in get_children():
		if child is StaticBody3D and child.has_meta("_voxly_static_body_generated"):
			return child
	return null

## Locates the render MeshInstance3D used for this voxel node.
## Falls back to the first MeshInstance3D child if the node doesn't
## manage one itself.
func _get_mesh_instance() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D and not child is MultiMeshInstance3D:
			return child
	var mesh_children := find_children("*", "MeshInstance3D", false, false)
	if not mesh_children.is_empty():
		return mesh_children[0]
	return null

## Finds an existing CollisionShape3D or creates one.
func _get_or_create_collision_shape_node(body: StaticBody3D) -> CollisionShape3D:
	for child in body.get_children():
		if child is CollisionShape3D:
			return child
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	body.add_child(shape_node)
	# Owned so it saves with the scene alongside the generated body.
	if owner:
		shape_node.owner = owner
	return shape_node


## Returns positions of voxels that have an OPAQUE neighbor in the given direction.
## Translucent/refractive neighbors do NOT count as covering,
## so faces between solid and glass voxels remain visible.
func get_covered_voxels(voxel_positions: Array[Vector3i], face_covered: Vector3i) -> Array[Vector3i]:
	var covered: Array[Vector3i] = []
	for voxel_position in voxel_positions:
		if typeof(get_voxel(voxel_position)) == TYPE_INT:
			var neighbor_id = get_voxel(voxel_position + face_covered)
			if typeof(neighbor_id) == TYPE_INT and _is_voxel_id_opaque(neighbor_id):
				covered.append(voxel_position)
	return covered

## Returns positions of voxels that do NOT have an OPAQUE neighbor in the given
## direction. A face is considered "uncovered" when there is no neighbor OR the
## neighbor is translucent/refractive.
func get_uncovered_voxels(voxel_positions: Array[Vector3i], face_uncovered: Vector3i) -> Array[Vector3i]:
	var uncovered: Array[Vector3i] = []
	for voxel_position in voxel_positions:
		if typeof(get_voxel(voxel_position)) == TYPE_INT:
			var neighbor_id = get_voxel(voxel_position + face_uncovered)
			if typeof(neighbor_id) != TYPE_INT or not _is_voxel_id_opaque(neighbor_id):
				uncovered.append(voxel_position)
	return uncovered

## Returns whether the voxel with the given ID is fully opaque, using a cache
## so each unique voxel type is resolved only once per VoxelSet. The cache is
## cleared whenever the assigned VoxelSet changes.
func _is_voxel_id_opaque(voxel_id: int) -> bool:
	if _opacity_cache.has(voxel_id):
		return _opacity_cache[voxel_id]
	var opaque: bool = is_instance_valid(voxel_set) and voxel_set.is_voxel_opaque(voxel_id)
	_opacity_cache[voxel_id] = opaque
	return opaque

## Flood-fills through all connected voxels starting from `from_position`
## that have an exposed face in the given `face_normal` direction.
##
## Parameters:
## - from_position: The starting voxel position to flood-fill from.
## - face_normal: The direction to check for exposed faces.
## - match_id: If true, only flood-fill through voxels with the same
##   voxel ID as the starting position.
##
## Returns: Array[Vector3i] of connected voxels with exposed faces.
func get_exposed_face_voxels(from_position: Vector3i, face_normal: Vector3i, match_id: bool = false) -> Array[Vector3i]:
	var selected: Array[Vector3i] = []
	var visited: Dictionary[Vector3i, bool] = {}
	var stack: Array[Vector3i] = [from_position]
	
	# Get the 4 perpendicular directions from Voxel constants
	var perp_dirs: Array = Voxel.ADJACENT_FACES.get(face_normal, [])
	
	# Determine the target voxel ID if matching by ID
	var target_id = null
	if match_id:
		target_id = get_voxel(from_position)
		if target_id == null:
			return []
	
	while not stack.is_empty():
		var current = stack.pop_back()
		if visited.has(current):
			continue
		visited[current] = true
		
		var voxel = get_voxel(current)
		if voxel != null:
			# If match_id is set, skip voxels with a different ID
			if match_id and voxel != target_id:
				continue
			
			# Only include if the face in the given normal direction is exposed
			var neighbor_id = get_voxel(current + face_normal)
			if typeof(neighbor_id) != TYPE_INT or not _is_voxel_id_opaque(neighbor_id):
				selected.append(current)
				for dir in perp_dirs:
					var neighbor = current + dir
					if not visited.has(neighbor):
						stack.append(neighbor)
	
	return selected
