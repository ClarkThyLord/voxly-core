## Abstract base class for all nodes that display voxel content.
##
## Defines the core properties (voxel set, voxel size, meshing mode, rendering
## flags) and the voxel-grid API shared by every concrete voxel node.
@tool
@icon("res://addons/voxly-core/assets/icons/voxel_node_3d.svg")
@abstract
class_name VoxelNode3D
extends Node3D

## Debug context tag used when logging through [VoxlyDebug].
var _debug_context: String = "VoxelNode3D"

## Emitted when the mesh generation mode changes.
signal mesh_mode_changed

## Emitted when the voxel size changes.
signal voxel_size_changed

## Emitted when the assigned [VoxelSet] changes.
signal voxel_set_changed

## Emitted after [method update] completes.
signal updated

## Supported meshing modes, listed from least to most optimized.
enum MeshMode {
	## Every face is emitted, with no neighbor culling.
	BRUTE = 0,
	## Only faces not hidden by an opaque neighbor are emitted.
	NAIVE = 1,
	## Adjacent coplanar faces are merged into quads (most optimized).
	GREEDY = 2,
}

## Inspector button that forces a full refresh of the node.
@export_tool_button("Update", "Reload")
var update_button = update

## Reference to the [VoxelSet] palette that provides the voxel definitions.
@export var voxel_set: VoxelSet:
	set = set_voxel_set,
	get = get_voxel_set

## When enabled, [method update] is called automatically whenever the assigned
## [VoxelSet] resource is modified. Disable for manual control.
@export var update_with_voxel_set: bool = true

@export_group("Rendering")

## Mesh generation algorithm ([enum MeshMode]).
@export var mesh_mode: MeshMode = MeshMode.GREEDY:
	set = set_mesh_mode,
	get = get_mesh_mode

## Size of an individual voxel in world units (meters).
## Clamped to a minimum of 0.1 on every axis to avoid degenerate meshes.
@export var voxel_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set = set_voxel_size,
	get = get_voxel_size

## Whether generated vertices carry vertex colors.
@export var include_vertex_colors: bool = true:
	set = set_include_vertex_colors,
	get = get_include_vertex_colors

## Whether generated vertices carry UV coordinates.
@export var include_textures: bool = true:
	set = set_include_textures,
	get = get_include_textures

@export_group("Collision")

## When enabled, the voxel node owns a [StaticBody3D] child whose trimesh
## [CollisionShape3D] is generated from the node's render mesh. [method update]
## refreshes the shape; disabling removes the generated body.
@export var attach_static_body := false:
	set = set_attach_static_body,
	get = get_attach_static_body

## True while a mesh rebuild is queued and waiting to run.
var _pending_rebuild: bool = false
## True once the node has completed its initial setup.
var _is_initialized := false
## Caches each voxel type's opacity so it is resolved only once per [VoxelSet].
var _opacity_cache: Dictionary[int, bool] = {}

## Initializes the node and builds its initial mesh.
func _ready() -> void:
	_is_initialized = true
	# Enable editor group editing by default so that selecting a child node
	# (e.g. the MeshInstance3D) in the editor selects this VoxelNode3D instead.
	set_meta("_edit_group_", true)

## Returns the world-space size of a single voxel.
func get_voxel_size() -> Vector3:
	return voxel_size

## Sets the world-space size of a single voxel and schedules a rebuild.
func set_voxel_size(new_voxel_size: Vector3) -> void:
	var clamped_size := new_voxel_size.max(Vector3(0.1, 0.1, 0.1))
	if clamped_size != voxel_size:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Voxel size changed: %s -> %s" % [voxel_size, clamped_size])
		voxel_size = clamped_size
		voxel_size_changed.emit()
		_queue_rebuild()

## Returns the current meshing mode.
func get_mesh_mode() -> MeshMode:
	return mesh_mode

## Sets the meshing mode and schedules a rebuild.
func set_mesh_mode(new_mesh_mode: MeshMode) -> void:
	if new_mesh_mode != mesh_mode:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Mesh mode changed: %s -> %s" % [MeshMode.keys()[mesh_mode], MeshMode.keys()[new_mesh_mode]])
		mesh_mode = new_mesh_mode
		mesh_mode_changed.emit()
		_queue_rebuild()

## Returns the voxel set this node renders.
func get_voxel_set() -> VoxelSet:
	return voxel_set

## Sets the voxel set this node renders and schedules a rebuild.
func set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if voxel_set != new_voxel_set:
		# Disconnect from the old set's change signal first.
		if voxel_set and voxel_set.changed.is_connected(_on_voxel_set_content_changed):
			voxel_set.changed.disconnect(_on_voxel_set_content_changed)
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "VoxelSet changed")
		voxel_set = new_voxel_set
		# Opacity caching is tied to a specific set's voxel definitions.
		_opacity_cache.clear()
		
		# Connect to the new set so content edits refresh the node automatically.
		if voxel_set and not voxel_set.changed.is_connected(_on_voxel_set_content_changed):
			voxel_set.changed.connect(_on_voxel_set_content_changed)
		
		voxel_set_changed.emit()
		# Drop any rebuild queued while the node was not yet initialized, then
		# attempt one now that the set is available.
		if _pending_rebuild:
			_pending_rebuild = false
		_queue_rebuild()

## Returns whether vertex colors are included in rendering.
func get_include_vertex_colors() -> bool:
	return include_vertex_colors

## Sets whether vertex colors are included in rendering.
func set_include_vertex_colors(new_value: bool) -> void:
	if include_vertex_colors != new_value:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Vertex colors: %s" % new_value)
		include_vertex_colors = new_value
		_queue_rebuild()

## Returns whether textures are included in rendering.
func get_include_textures() -> bool:
	return include_textures

## Sets whether textures are included in rendering.
func set_include_textures(new_value: bool) -> void:
	if include_textures != new_value:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Textures: %s" % new_value)
		include_textures = new_value
		_queue_rebuild()

## Returns the total number of voxels stored by this node.
@abstract
func get_voxel_count() -> int

## Returns the grid positions of every voxel stored by this node.
@abstract
func get_voxel_positions_used() -> Array[Vector3i]

## Returns the voxel ID at the given position, or the [Voxel] definition when
## [param return_voxel_objects] is true. Returns null if the position is empty.
@abstract
func get_voxel(voxel_position: Vector3i, return_voxel_objects: bool = false) -> Variant

## Returns all voxels as a [code]Dictionary[Vector3i, int][/code], or as
## [code]Dictionary[Vector3i, Voxel][/code] when [param return_voxel_objects]
## is true.
@abstract
func get_voxels(return_voxel_objects: bool = false) -> Dictionary

## Sets the voxel ID at the given position.
@abstract
func set_voxel(voxel_position: Vector3i, voxel_id: int) -> void

## Removes the voxel at the given position.
@abstract
func remove_voxel(voxel_position: Vector3i) -> void

## Removes the voxels at the given positions.
@abstract
func remove_voxels(voxel_positions: Array[Vector3i]) -> void

## Removes all voxels from this node.
@abstract
func clear_voxels() -> void

## High-level refresh: rebuilds the mesh, notifies listeners, and optionally
## refreshes collision. Call this after editing voxels.
func update() -> void:
	rebuild_mesh()
	updated.emit()
	if attach_static_body:
		create_static_body()

## Rebuilds the mesh arrays only. Concrete nodes override this to generate
## geometry from their stored voxels.
func rebuild_mesh() -> void:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Rebuilding mesh")

## Converts a world position to local voxel grid coordinates.
func world_to_voxel_position(world_position: Vector3) -> Vector3i:
	return Vector3i((world_position / voxel_size).round())

## Converts local voxel grid coordinates to a world position.
func voxel_to_world_position(voxel_position: Vector3i) -> Vector3:
	return Vector3(voxel_position) * voxel_size

## Raycasts through the voxel grid in WORLD coordinates (meters).
##
## The ray is converted to the node's local space internally, then walked with
## the DDA algorithm, so node transforms are handled automatically.
##
## Returns an empty dictionary on a miss, or a dictionary with the following
## on a hit:
## - [code]hit[/code] (bool): whether a voxel was hit
## - [code]hit_position[/code] (Vector3i): grid cell coordinates of the hit
## - [code]hit_normal[/code] (Vector3i): grid-space face normal of the entry point
func voxel_raycast(ray_origin: Vector3, direction: Vector3, length: float) -> Dictionary:
	var local_origin := to_local(ray_origin)
	var local_dir := to_local(ray_origin + direction) - local_origin
	return _dda(local_origin, local_dir, length)

## Low-level DDA (Digital Differential Analyzer) raycast in node-local meters.
##
## [param local_origin] is a continuous position in meters relative to the
## node's origin (before any origin offset applied by subclasses), [param
## local_dir] is the ray direction, and [param length_m] is the maximum
## distance in meters.
## Learn more: https://www.youtube.com/watch?v=ztkh1r1ioZo
func _dda(local_origin: Vector3, local_dir: Vector3, length_m: float) -> Dictionary:
	var result: Dictionary = {}
	# Use floor-based positions for the DDA stepping, but compute the first
	# voxel position using round() so the t_max values are non-negative.
	var voxel_position := Vector3i(
		floori(local_origin.x / voxel_size.x),
		floori(local_origin.y / voxel_size.y),
		floori(local_origin.z / voxel_size.z)
	)
	var step := Vector3i(
		sign(local_dir.x),
		sign(local_dir.y),
		sign(local_dir.z)
	)
	
	# Distance (t) along the ray needed to cross one voxel on each axis.
	# Using world-space t: position = origin + direction * t, and voxel
	# boundaries sit at (i * voxel_size).
	var t_delta := Vector3(
		abs(voxel_size.x / local_dir.x) if local_dir.x != 0 else INF,
		abs(voxel_size.y / local_dir.y) if local_dir.y != 0 else INF,
		abs(voxel_size.z / local_dir.z) if local_dir.z != 0 else INF
	)
	
	# Distance (t) to the first voxel boundary on each axis in the step direction.
	var t_max := Vector3(
		((voxel_position.x + max(0, step.x)) * voxel_size.x - local_origin.x) / local_dir.x if local_dir.x != 0 else INF,
		((voxel_position.y + max(0, step.y)) * voxel_size.y - local_origin.y) / local_dir.y if local_dir.y != 0 else INF,
		((voxel_position.z + max(0, step.z)) * voxel_size.z - local_origin.z) / local_dir.z if local_dir.z != 0 else INF
	)
	
	var traveled := 0.0
	# The axis stepped to ENTER the current cell, used to derive the entry face
	# normal on hit. Zero when the ray starts inside the first cell.
	var last_step := Vector3i.ZERO
	while traveled < length_m:
		var voxel = get_voxel(voxel_position)
		if voxel != null:
			result.hit = true
			result.hit_position = voxel_position
			# The entry face is opposite the last axis crossed. Deriving the
			# normal from the CURRENT t_max values (as before) identifies the
			# NEXT boundary instead, giving wrong normals near corners/edges.
			result.hit_normal = -last_step
			return result
		
		# Step to the next voxel along the axis with the smallest t.
		if t_max.x < t_max.y and t_max.x < t_max.z:
			voxel_position.x += step.x
			traveled = t_max.x
			t_max.x += t_delta.x
			last_step = Vector3i(step.x, 0, 0)
		elif t_max.y < t_max.z:
			voxel_position.y += step.y
			traveled = t_max.y
			t_max.y += t_delta.y
			last_step = Vector3i(0, step.y, 0)
		else:
			voxel_position.z += step.z
			traveled = t_max.z
			t_max.z += t_delta.z
			last_step = Vector3i(0, 0, step.z)
	
	return result

## Returns whether an optional generated [StaticBody3D] is attached.
func get_attach_static_body() -> bool:
	return attach_static_body

## Sets whether an optional generated [StaticBody3D] is attached.
func set_attach_static_body(enabled: bool) -> void:
	if attach_static_body == enabled:
		return
	attach_static_body = enabled
	if _is_voxly_editing():
		# Deferred until editing stops so the collider doesn't fight the editor.
		return
	if enabled:
		if _is_initialized:
			create_static_body()
	else:
		remove_static_body()

## Creates (or refreshes) the node's [StaticBody3D] trimesh collision from the
## current render mesh. Reuses an existing generated body and swaps its shape
## in place for performance.
##
## Returns the collision body, or null after removing stale collision when
## there is no render mesh.
func create_static_body() -> StaticBody3D:
	var mesh_instance := _get_mesh_instance()
	var body := _get_generated_static_body()
	
	# While editing, never create or touch geometry; just disable any existing
	# shape so the collider can't interfere with the edit session.
	if _is_voxly_editing():
		if body:
			var shape_node := _get_or_create_collision_shape_node(body)
			shape_node.set_deferred("disabled", true)
		return body
	
	if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
		# Keep an existing generated body alive when attach_static_body is on.
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
	
	# Mark the body as owned by the node's scene owner so the editor saves it
	# with the scene and shows it in the Scene dock.
	if owner:
		body.owner = owner
	
	# The body mirrors the render mesh's transform so the shape lines up with
	# the voxels.
	body.transform = mesh_instance.transform
	
	var shape := mesh_instance.mesh.create_trimesh_shape()
	
	# Trimesh collisions are single-sided in Jolt by default; enabling backface
	# collision keeps the player from clipping through when the character
	# starts inside/on the boundary of the terrain surface.
	shape.backface_collision = true
	var shape_node := _get_or_create_collision_shape_node(body)
	shape_node.position = Vector3.ZERO
	shape_node.shape = shape
	shape_node.set_deferred("disabled", not attach_static_body)
	return body

## Removes the generated [StaticBody3D] that this voxel node owns.
func remove_static_body() -> void:
	for child in get_children():
		if child is StaticBody3D and child.has_meta("_voxly_static_body_generated"):
			child.queue_free()

## Returns positions of voxels that have an OPAQUE neighbor in the given
## direction. Translucent/refractive neighbors do not count as covering, so
## faces between solid and glass voxels remain visible.
func get_covered_voxels(voxel_positions: Array[Vector3i], face_direction: Vector3i) -> Array[Vector3i]:
	var covered: Array[Vector3i] = []
	for voxel_position in voxel_positions:
		if typeof(get_voxel(voxel_position)) == TYPE_INT:
			var neighbor_id = get_voxel(voxel_position + face_direction)
			if typeof(neighbor_id) == TYPE_INT and _is_voxel_id_opaque(neighbor_id):
				covered.append(voxel_position)
	return covered

## Returns positions of voxels that do not have an OPAQUE neighbor in the given
## direction. A face is considered "uncovered" when there is no neighbor, or
## the neighbor is translucent/refractive.
func get_uncovered_voxels(voxel_positions: Array[Vector3i], face_direction: Vector3i) -> Array[Vector3i]:
	var uncovered: Array[Vector3i] = []
	for voxel_position in voxel_positions:
		if typeof(get_voxel(voxel_position)) == TYPE_INT:
			var neighbor_id = get_voxel(voxel_position + face_direction)
			if typeof(neighbor_id) != TYPE_INT or not _is_voxel_id_opaque(neighbor_id):
				uncovered.append(voxel_position)
	return uncovered

## Flood-fills through all connected voxels starting from [param from_position]
## that have an exposed face in the given [param face_normal] direction.
##
## [param match_id]: If true, only flood-fills through voxels with the same
##   voxel ID as the starting position.
##
## Returns an [code]Array[Vector3i][/code] of connected voxels with exposed faces.
func get_exposed_face_voxels(from_position: Vector3i, face_normal: Vector3i, match_id: bool = false) -> Array[Vector3i]:
	var selected: Array[Vector3i] = []
	var visited: Dictionary[Vector3i, bool] = {}
	var stack: Array[Vector3i] = [from_position]
	
	# Get the 4 directions perpendicular to the face from the Voxel constants.
	var perpendicular_directions: Array = Voxel.ADJACENT_FACES.get(face_normal, [])
	
	# Determine the target voxel ID when matching by ID.
	var target_id: Variant = null
	if match_id:
		target_id = get_voxel(from_position)
		if target_id == null:
			return []
	
	while not stack.is_empty():
		var current: Vector3i = stack.pop_back()
		if visited.has(current):
			continue
		visited[current] = true
		
		var voxel = get_voxel(current)
		if voxel != null:
			# When matching by ID, skip voxels with a different ID.
			if match_id and voxel != target_id:
				continue
			
			# Only include the voxel if the face in the given normal direction
			# is exposed (no opaque neighbor).
			var neighbor_id = get_voxel(current + face_normal)
			if typeof(neighbor_id) != TYPE_INT or not _is_voxel_id_opaque(neighbor_id):
				selected.append(current)
				for direction in perpendicular_directions:
					var neighbor: Vector3i = current + direction
					if not visited.has(neighbor):
						stack.append(neighbor)
	
	return selected

## Returns whether the voxel with the given ID is fully opaque, using a cache
## so each unique voxel type is resolved only once per [VoxelSet]. The cache is
## cleared whenever the assigned [VoxelSet] changes.
func _is_voxel_id_opaque(voxel_id: int) -> bool:
	if _opacity_cache.has(voxel_id):
		return _opacity_cache[voxel_id]
	var opaque: bool = is_instance_valid(voxel_set) and voxel_set.is_voxel_opaque(voxel_id)
	_opacity_cache[voxel_id] = opaque
	return opaque

## Queues a mesh rebuild. Before the node is initialized (or while no voxel set
## is assigned in the editor) the rebuild is deferred until a later update.
func _queue_rebuild() -> void:
	if not _is_initialized:
		_pending_rebuild = true
		return
	if Engine.is_editor_hint():
		if not is_instance_valid(voxel_set):
			_pending_rebuild = true
			return
		update()

## Called when the assigned [VoxelSet] resource's [signal Resource.changed]
## signal fires (e.g. after voxel properties are edited via the VoxelSet
## editor). Triggers a mesh rebuild so the node reflects the updated data.
func _on_voxel_set_content_changed() -> void:
	_opacity_cache.clear()
	if update_with_voxel_set:
		_queue_rebuild()

## Returns true while the Voxly editor is actively editing this node.
func _is_voxly_editing() -> bool:
	return get_meta("_voxly_core_editing_", false)

## Returns the generated [StaticBody3D] owned by this node, or null.
func _get_generated_static_body() -> StaticBody3D:
	for child in get_children():
		if child is StaticBody3D and child.has_meta("_voxly_static_body_generated"):
			return child
	return null

## Locates the render [MeshInstance3D] used for this voxel node. Falls back to
## the first [MeshInstance3D] child if the node doesn't manage one itself.
func _get_mesh_instance() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D and not child is MultiMeshInstance3D:
			return child
	var mesh_children := find_children("*", "MeshInstance3D", false, false)
	if not mesh_children.is_empty():
		return mesh_children[0]
	return null

## Finds an existing [CollisionShape3D] on the body or creates one.
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
