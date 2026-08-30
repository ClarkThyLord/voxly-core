## Voxel model for small voxel content such as items, weapons, and clothing.
##
## Stores all voxels in memory as a position mapped to a voxel ID, rendering them
## through a child [MeshInstance3D].
@tool
@icon("res://addons/voxly-core/assets/icons/voxel_model_3d.svg")
class_name VoxelModel3D
extends VoxelNode3D

## Emitted when the origin offset changes.
signal origin_changed

## Emitted when the model's delimiting shape changes.
signal shape_changed

## Origin offset of the model in voxel units.
@export var origin: Vector3 = Vector3.ZERO:
	set = set_origin,
	get = get_origin

## Delimiting shape of the model in voxel units. Voxels outside this box are
## rejected when set and pruned when the shape shrinks.
@export var shape: Vector3i = Vector3i(16, 16, 16):
	set = set_shape,
	get = get_shape

## The [MeshInstance3D] that displays the generated mesh.
var _mesh_instance: MeshInstance3D = null

## Internal voxel storage: grid position mapped to voxel ID.
var _voxels: Dictionary[Vector3i, int] = {}

## Configures the node debug context tag for VoxlyDebug logging.
func _init() -> void:
	_debug_context = "VoxelModel3D"

## Calls the parent setup and positions the mesh instance from the origin offset.
func _ready() -> void:
	super._ready()
	var mesh_instance := _get_mesh_instance()
	mesh_instance.position = origin * voxel_size

## Exposes the voxel data as a serializable property so scenes save it.
## The property is storage-only (not shown in the inspector) and is handled
## manually through [method _get] / [method _set].
func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	properties.append({
		"name": "_voxel_data",
		"type": TYPE_PACKED_BYTE_ARRAY,
		"usage": PROPERTY_USAGE_STORAGE
	})
	return properties

## Serializes all voxels into a packed byte array.
##
## Each voxel occupies 16 bytes: four consecutive int32 values for x, y, z, and
## the voxel ID. An empty array means there are no voxels.
func _get(property: StringName):
	if property == &"_voxel_data":
		var data := PackedByteArray()
		var count := _voxels.size()
		if count == 0:
			return data
		
		data.resize(count * 16)
		var byte_index := 0
		for voxel_position in _voxels:
			data.encode_s32(byte_index, voxel_position.x)
			byte_index += 4
			data.encode_s32(byte_index, voxel_position.y)
			byte_index += 4
			data.encode_s32(byte_index, voxel_position.z)
			byte_index += 4
			data.encode_s32(byte_index, _voxels[voxel_position])
			byte_index += 4
		return data
	
	return null

## Restores all voxels from a packed byte array previously produced by
## [method _get]. Returns true when the property is handled.
func _set(property: StringName, value) -> bool:
	if property == &"_voxel_data":
		_voxels.clear()
		var data: PackedByteArray = value
		var voxel_count := data.size() / 16
		if voxel_count > 0:
			var byte_index := 0
			for i in range(voxel_count):
				var voxel_position := Vector3i(
					data.decode_s32(byte_index),
					data.decode_s32(byte_index + 4),
					data.decode_s32(byte_index + 8)
				)
				var voxel_id := data.decode_s32(byte_index + 12)
				_voxels[voxel_position] = voxel_id
				byte_index += 16
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Loaded %d voxels from serialized data" % _voxels.size())
		return true
	
	return false

## Returns the origin offset of the model.
func get_origin() -> Vector3:
	return origin

## Sets the origin offset and repositions the mesh accordingly.
func set_origin(new_origin: Vector3) -> void:
	if origin != new_origin:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Origin changed: %s -> %s" % [origin, new_origin])
		origin = new_origin
		origin_changed.emit()
		if _is_initialized:
			var mesh_instance := _get_mesh_instance()
			mesh_instance.position = origin * voxel_size
			if Engine.is_editor_hint():
				_queue_rebuild()

## Returns the delimiting shape of the model.
func get_shape() -> Vector3i:
	return shape

## Sets the delimiting shape, pruning any voxels that fall outside the new box.
func set_shape(new_shape: Vector3i) -> void:
	var clamped_shape := new_shape.max(Vector3i(1, 1, 1))
	if clamped_shape != shape:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Shape changed: %s -> %s" % [shape, clamped_shape])
		shape = clamped_shape
		shape_changed.emit()
		for voxel_position in _voxels.keys():
			if not is_voxel_position_valid(voxel_position):
				remove_voxel(voxel_position)
		if Engine.is_editor_hint():
			_queue_rebuild()

## Returns true if the given position lies inside the model's shape box.
func is_voxel_position_valid(voxel_position: Vector3i) -> bool:
	return (voxel_position.x >= 0 and voxel_position.x < shape.x
		and voxel_position.y >= 0 and voxel_position.y < shape.y
		and voxel_position.z >= 0 and voxel_position.z < shape.z)

## Converts a world position to local voxel grid coordinates,
## accounting for the model's origin offset.
func world_to_voxel_position(world_position: Vector3) -> Vector3i:
	var local_position := world_position - origin * voxel_size
	return Vector3i((local_position / voxel_size).round())

## Converts local voxel grid coordinates to a world position,
## accounting for the model's origin offset.
func voxel_to_world_position(voxel_position: Vector3i) -> Vector3:
	return Vector3(voxel_position) * voxel_size + origin * voxel_size

## Raycasts through the voxel grid in WORLD coordinates, offset by the model's
## origin. See [method VoxelNode3D.voxel_raycast] for the result format.
func voxel_raycast(ray_origin: Vector3, direction: Vector3, length: float) -> Dictionary:
	var local_origin := to_local(ray_origin)
	var local_dir := to_local(ray_origin + direction) - local_origin
	return _dda(local_origin - origin * voxel_size, local_dir, length)

## Returns the number of voxels stored in this model.
func get_voxel_count() -> int:
	return _voxels.size()

## Returns the grid positions of every voxel in this model.
func get_voxel_positions_used() -> Array[Vector3i]:
	return _voxels.keys()

## Returns the voxel ID at the given position, or the [Voxel] definition when
## [param return_voxel_objects] is true. Returns null if the position is empty.
func get_voxel(voxel_position: Vector3i, return_voxel_objects: bool = false) -> Variant:
	var voxel_id := _voxels.get(voxel_position)
	if not return_voxel_objects:
		return voxel_id
	elif is_instance_valid(voxel_set):
		return voxel_set.get_voxel(voxel_id)
	return null

## Returns all voxels as a [code]Dictionary[Vector3i, int][/code], or as
## [code]Dictionary[Vector3i, Voxel][/code] when [param return_voxel_objects]
## is true.
func get_voxels(return_voxel_objects: bool = false) -> Dictionary:
	if not return_voxel_objects:
		return _voxels.duplicate()
	
	var result: Dictionary[Vector3i, Voxel] = {}
	for voxel_position in _voxels:
		var voxel: Voxel = voxel_set.get_voxel(_voxels[voxel_position]) if is_instance_valid(voxel_set) else null
		if voxel:
			result[voxel_position] = voxel
	return result

## Sets the voxel ID at the given position. Positions outside the model's
## shape box are ignored.
func set_voxel(voxel_position: Vector3i, voxel_id: int) -> void:
	if is_voxel_position_valid(voxel_position):
		_voxels[voxel_position] = voxel_id

## Adds multiple voxels at once, ignoring any position outside the shape box.
func add_voxels(voxels: Dictionary[Vector3i, int]) -> void:
	var added := 0
	for voxel_position in voxels:
		if is_voxel_position_valid(voxel_position):
			_voxels[voxel_position] = voxels[voxel_position]
			added += 1
	if added > 0:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Added %d voxels" % added)

## Removes the voxel at the given position.
func remove_voxel(voxel_position: Vector3i) -> void:
	if _voxels.erase(voxel_position):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Removed voxel at %s" % voxel_position)

## Removes the voxels at the given positions.
func remove_voxels(voxel_positions: Array[Vector3i]) -> void:
	var count := 0
	for voxel_position in voxel_positions:
		if _voxels.erase(voxel_position):
			count += 1
	if count > 0:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Removed %d voxels" % count)

## Removes all voxels from this model.
func clear_voxels() -> void:
	var count := _voxels.size()
	_voxels.clear()
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, _debug_context, "Cleared %d voxels" % count)

## Locates the [MeshInstance3D] used to render this model, creating one if the
## node doesn't already have a suitable child.
func _get_mesh_instance() -> MeshInstance3D:
	if not _mesh_instance:
		var mesh_instances: Array[Node] = find_children("*", "MeshInstance3D", false, false)
		if not mesh_instances.is_empty():
			_mesh_instance = mesh_instances[0]
		else:
			_mesh_instance = MeshInstance3D.new()
			add_child(_mesh_instance)
			_mesh_instance.name = "MeshInstance3D"
			_mesh_instance.owner = owner
	else:
		_mesh_instance.owner = owner
	return _mesh_instance

## Generates the mesh for all stored voxels using the currently configured
## meshing mode and assigns it to the render mesh instance.
func rebuild_mesh() -> void:
	if not voxel_set:
		push_warning("No VoxelSet assigned to VoxelModel3D")
		return
	
	if _voxels.is_empty():
		# No voxels to render: clear the existing mesh if one exists.
		if _mesh_instance:
			_mesh_instance.mesh = null
		return
	
	var mesher := VoxelMesher.create()
	mesher.begin(voxel_size, voxel_set, include_vertex_colors, include_textures)
	
	match mesh_mode:
		MeshMode.BRUTE:
			mesher.add_all_faces(_voxels)
		MeshMode.GREEDY:
			mesher.add_greedy_faces(_voxels)
		_: # NAIVE default
			mesher.add_culled_faces(_voxels)
	
	var mesh := mesher.commit()
	
	var mesh_instance := _get_mesh_instance()
	mesh_instance.mesh = mesh
	mesh_instance.position = origin * voxel_size
	
	super.rebuild_mesh()
