@tool
@icon("res://addons/voxly-core/assets/icons/voxel_model_3d.svg")
class_name VoxelModel3D
extends VoxelNode3D
## Voxel model: for small voxel content such as items, weapons, clothing, etc.
## Stores all voxels in memory and renders via a child MeshInstance3D.

## Emitted when the origin offset changes.
signal origin_changed

## Emitted when the model's shape change.
signal shape_changed

## Origin offset for model in voxel units.
@export
var origin: Vector3 = Vector3.ZERO:
	get = get_origin,
	set = set_origin

## Delimiting shape of the model in voxel units.
@export
var shape: Vector3i = Vector3i(16, 16, 16):
	get = get_shape,
	set = set_shape

var _mesh_instance: MeshInstance3D = null

var _voxels: Dictionary[Vector3i, int] = {}

func _init() -> void:
	DEBUG_CONTEXT = "VoxelModel3D"

func _ready() -> void:
	super._ready()
	var mesh_instance := _get_mesh_instance()
	mesh_instance.position = origin * voxel_size

func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	properties.append({
		"name": "_voxel_data",
		"type": TYPE_PACKED_BYTE_ARRAY,
		"usage": PROPERTY_USAGE_STORAGE
	})
	return properties

func _get(property: StringName):
	if property == &"_voxel_data":
		var data := PackedByteArray()
		var count := _voxels.size()
		if count == 0:
			return data
	
		data.resize(count * 16)
		var idx := 0
		for pos in _voxels:
			data.encode_s32(idx, pos.x); idx += 4
			data.encode_s32(idx, pos.y); idx += 4
			data.encode_s32(idx, pos.z); idx += 4
			data.encode_s32(idx, _voxels[pos]); idx += 4
		return data

	return null

func _set(property: StringName, value) -> bool:
	if property == &"_voxel_data":
		_voxels.clear()
		var data: PackedByteArray = value
		var voxel_count := data.size() / 16
		if voxel_count > 0:
			var idx := 0
			for i in range(voxel_count):
				var pos := Vector3i(
					data.decode_s32(idx),
					data.decode_s32(idx + 4),
					data.decode_s32(idx + 8)
				)
				var voxel_id := data.decode_s32(idx + 12)
				_voxels[pos] = voxel_id
				idx += 16
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Loaded %d voxels from serialized data" % _voxels.size())
		return true
	
	return false

func get_origin() -> Vector3:
	return origin

func set_origin(new_origin: Vector3) -> void:
	if origin != new_origin:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Origin changed: %s -> %s" % [origin, new_origin])
		origin = new_origin
		origin_changed.emit()
		if _is_initialized:
			var mesh_instance := _get_mesh_instance()
			mesh_instance.position = origin * voxel_size
			if Engine.is_editor_hint():
				_queue_rebuild()

func get_shape() -> Vector3i:
	return shape

func set_shape(new_shape: Vector3i) -> void:
	var clamped_shape := new_shape.max(Vector3i(1, 1, 1))
	if clamped_shape != shape:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Shape changed: %s -> %s" % [shape, clamped_shape])
		shape = clamped_shape
		shape_changed.emit()
		for voxel_position in _voxels.keys():
			if not is_voxel_position_valid(voxel_position):
				remove_voxel(voxel_position)
		if Engine.is_editor_hint():
			_queue_rebuild()

func is_voxel_position_valid(voxel_position: Vector3i) -> bool:
	return (voxel_position.x >= 0 and voxel_position.x < shape.x
		and voxel_position.y >= 0 and voxel_position.y < shape.y
		and voxel_position.z >= 0 and voxel_position.z < shape.z)

## Converts a world position to local voxel grid coordinates,
## accounting for the model's origin offset.
func world_to_voxel_position(world_position: Vector3) -> Vector3i:
	var local_pos := world_position - origin * voxel_size
	return Vector3i((local_pos / voxel_size).round())

## Converts local voxel grid coordinates to a world position,
## accounting for the model's origin offset.
func voxel_to_world_position(voxel_position: Vector3i) -> Vector3:
	return Vector3(voxel_position) * voxel_size + origin * voxel_size

func voxel_raycast(ray_origin: Vector3, direction: Vector3, length: float) -> Dictionary:
	var local_origin := to_local(ray_origin)
	var local_dir := to_local(ray_origin + direction) - local_origin
	return _dda(local_origin - origin * voxel_size, local_dir, length)

func get_voxel_count() -> int:
	return _voxels.size()

func get_voxel_positions_used() -> Array[Vector3i]:
	return _voxels.keys()

func get_voxel(voxel_position: Vector3i, as_voxel: bool = false):
	var voxel_id := _voxels.get(voxel_position)
	if not as_voxel:
		return voxel_id
	elif is_instance_valid(voxel_set):
		return voxel_set.get_voxel(voxel_id)
	return null

func get_voxels(as_voxel: bool = false):
	if not as_voxel:
		return _voxels.duplicate()
	
	var result: Dictionary[Vector3i, Voxel] = {}
	for pos in _voxels:
		var voxel: Voxel = voxel_set.get_voxel(_voxels[pos]) if is_instance_valid(voxel_set) else null
		if voxel:
			result[pos] = voxel
	return result

func set_voxel(voxel_position: Vector3i, voxel_id: int) -> void:
	if is_voxel_position_valid(voxel_position):
		_voxels[voxel_position] = voxel_id

func add_voxels(voxels: Dictionary[Vector3i, int]) -> void:
	var added := 0
	for voxel_position in voxels:
		if is_voxel_position_valid(voxel_position):
			_voxels[voxel_position] = voxels[voxel_position]
			added += 1
	if added > 0:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Added %d voxels" % added)

func remove_voxel(voxel_position: Vector3i) -> void:
	if _voxels.erase(voxel_position):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Removed voxel at %s" % voxel_position)

func remove_voxels(voxel_positions: Array[Vector3i]) -> void:
	var count := 0
	for pos in voxel_positions:
		if _voxels.erase(pos):
			count += 1
	if count > 0:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Removed %d voxels" % count)

func clear_voxels() -> void:
	var count := _voxels.size()
	_voxels.clear()
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_NODES, DEBUG_CONTEXT, "Cleared %d voxels" % count)

func _get_mesh_instance() -> MeshInstance3D:
	if not _mesh_instance:
		var mesh_instances = find_children("*", "MeshInstance3D", false, false)
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

func rebuild_mesh() -> void:
	if not voxel_set:
		push_warning("No VoxelSet assigned to VoxelModel3D")
		return
	
	if _voxels.is_empty():
		# No voxels to render, clear mesh if exists.
		if _mesh_instance:
			_mesh_instance.mesh = null
		return
	
	var mesher := VoxelMesher.create()
	mesher.begin(voxel_size, voxel_set, voxels_colored, voxels_textured)
	
	var voxel_positions := _voxels.keys()
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
