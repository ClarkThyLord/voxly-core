## Example util that reveals the voxel content of a list of [VoxelNode3D]s
## layer by layer, simulating a "build up" effect.
##
## When triggered, either through the "Play Build Up" tool button or
## automatically on scene start, every assigned voxel node is cleared and then
## slowly repopulated along a configurable axis. Layer mode reveals whole
## slices at once; voxel mode reveals a seeded random batch of voxels per step
## within each layer.
@tool
class_name VoxelBuildUp
extends Node

## Emitted when the build up effect starts.
signal build_up_started

## Emitted when the build up effect finishes.
signal build_up_finished

## The axis along which the voxel content is grouped into layers.
enum BuildAxis {
	## Layers are grouped along the X axis.
	X,
	## Layers are grouped along the Y axis (bottom-up).
	Y,
	## Layers are grouped along the Z axis.
	Z,
}

## The reveal strategy used while building up the voxel content.
enum BuildMode {
	## Whole layer slices pop in at once, several per step.
	LAYERS,
	## Voxels pop in one by one within each layer, in a seeded random order.
	VOXEL_BY_VOXEL,
}

## Inspector button that triggers the build up effect.
@export_tool_button("Play Build Up", "Play")
var play_button = play

## The [VoxelNode3D]s to build up, in the order they reveal when
## [member sequential] is enabled.
@export var nodes: Array[VoxelNode3D] = []

## When true, the build up effect starts automatically when the scene runs.
@export var auto_play_on_ready: bool = true

## The axis along which voxel content is grouped into layers
## (see [enum BuildAxis]).
@export var axis: BuildAxis = BuildAxis.Y

## The reveal strategy used while building up (see [enum BuildMode]).
@export var mode: BuildMode = BuildMode.LAYERS

@export_group("Layer Mode")

## How many coordinate slices are revealed per step in
## [code]BuildMode.LAYERS[/code].
##
## For example, a thickness of 2 along [code]BuildAxis.Y[/code] reveals the
## voxels at y=0..1 first, then y=2..3, and so on.
@export var layer_thickness: int = 1

@export_group("Voxel Mode")

## How many random voxels are revealed per step in
## [code]BuildMode.VOXEL_BY_VOXEL[/code].
@export var voxels_per_step: int = 1

## Seed for the random number generator that shuffles the order voxels appear
## within each layer in [code]BuildMode.VOXEL_BY_VOXEL[/code].
@export var random_seed: int = 0

@export_group("Timing")

## Seconds to wait between each reveal step.
@export var seconds_per_step: float = 0.15

## When true, each voxel node fully builds up before the next one starts.
## When false, every voxel node reveals simultaneously.
@export var sequential: bool = true

## True while the build up effect is running.
var _is_playing: bool = false

## Starts the build up effect automatically when the scene runs.
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if auto_play_on_ready:
		play()

## Clears every assigned voxel node and then slowly rebuilds its original
## voxel content along the configured [member axis].
##
## The current voxel content is snapshotted at the start and restored once the
## effect completes, so this method can be called repeatedly. Re-runs while
## the effect is already playing are ignored.
func play() -> void:
	if _is_playing:
		return
	if nodes.is_empty():
		push_warning("VoxelBuildUp: no voxel nodes assigned to build up.")
		return
	
	_is_playing = true
	build_up_started.emit()
	
	# Snapshot the current content plus the editor-only serialized state, so
	# the scene file is not left modified by the in-editor preview.
	var snapshots: Array[Dictionary] = []
	var serialized_data: Array[Variant] = []
	var render_meshes: Array[Variant] = []
	for node in nodes:
		if is_instance_valid(node):
			snapshots.append(node.get_voxels())
			serialized_data.append(_get_serialized_voxel_data(node))
			render_meshes.append(_get_render_mesh(node))
		else:
			snapshots.append({})
			serialized_data.append(null)
			render_meshes.append(null)
	
	# Clear every voxel node so the build up starts from an empty set.
	for node in nodes:
		if is_instance_valid(node):
			node.clear_voxels()
			node.update()
	
	# Precompute the reveal steps for every node
	var schedules: Array = []
	for i in range(nodes.size()):
		schedules.append(_build_schedule(snapshots[i]))
	
	if sequential:
		for i in range(nodes.size()):
			await _reveal_schedule(nodes[i], schedules[i])
			if i < nodes.size() - 1:
				await get_tree().create_timer(seconds_per_step).timeout
	else:
		await _reveal_parallel(nodes, schedules)
	
	# In the editor, restore the exact serialized voxel data and the original
	# render mesh so saving the scene keeps the original content.
	if Engine.is_editor_hint():
		for i in range(nodes.size()):
			_restore_node_in_editor(
				nodes[i],
				snapshots[i],
				serialized_data[i],
				render_meshes[i]
			)
	
	_is_playing = false
	build_up_finished.emit()

## Builds the reveal schedule for a voxel snapshot: an array of batches, where
## each batch is a [code]Dictionary[Vector3i, int][/code] of voxels revealed in
## a single step.
func _build_schedule(snapshot: Dictionary) -> Array:
	if snapshot.is_empty():
		return []
	
	var layers := _group_voxels_by_axis(snapshot)
	var layer_keys: Array = layers.keys()
	layer_keys.sort()
	
	var schedule: Array = []
	match mode:
		BuildMode.VOXEL_BY_VOXEL:
			_add_voxel_batches(schedule, layers, layer_keys)
		_:
			_add_layer_batches(schedule, layers, layer_keys)
	return schedule

## Appends layer batches to the schedule, revealing [member layer_thickness]
## coordinate slices per batch.
func _add_layer_batches(schedule: Array, layers: Dictionary, layer_keys: Array) -> void:
	var thickness := maxi(1, layer_thickness)
	for start in range(0, layer_keys.size(), thickness):
		var batch: Dictionary = {}
		for i in range(start, mini(start + thickness, layer_keys.size())):
			_merge_layer_into(batch, layers[layer_keys[i]])
		schedule.append(batch)

## Appends seeded-random voxel batches to the schedule, revealing
## [member voxels_per_step] voxels per batch within each layer.
func _add_voxel_batches(schedule: Array, layers: Dictionary, layer_keys: Array) -> void:
	var batch_size := maxi(1, voxels_per_step)
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for layer_key in layer_keys:
		var layer_voxels: Dictionary = layers[layer_key]
		var positions: Array = layer_voxels.keys()
		_seeded_shuffle(positions, rng)
		for start in range(0, positions.size(), batch_size):
			var batch: Dictionary = {}
			for i in range(start, mini(start + batch_size, positions.size())):
				var voxel_position: Vector3i = positions[i]
				batch[voxel_position] = layer_voxels[voxel_position]
			schedule.append(batch)

## Copies every voxel from a source layer dictionary into a batch dictionary.
func _merge_layer_into(batch: Dictionary, layer_voxels: Dictionary) -> void:
	for voxel_position in layer_voxels:
		batch[voxel_position] = layer_voxels[voxel_position]

## Reveals a schedule one batch at a time, rebuilding the node's mesh after
## each batch and waiting [member seconds_per_step] between batches.
func _reveal_schedule(node: VoxelNode3D, schedule: Array) -> void:
	if not is_instance_valid(node):
		return
	for batch in schedule:
		_apply_batch(node, batch)
		node.update()
		await get_tree().create_timer(seconds_per_step).timeout

## Reveals every node's schedule in lockstep, rebuilding each changed node once
## per step and waiting [member seconds_per_step] between steps.
func _reveal_parallel(nodes: Array[VoxelNode3D], schedules: Array) -> void:
	var max_steps := 0
	for schedule in schedules:
		max_steps = maxi(max_steps, schedule.size())
	for step in range(max_steps):
		var changed_nodes: Array[VoxelNode3D] = []
		for i in range(nodes.size()):
			var node_schedule: Array = schedules[i]
			if step < node_schedule.size() and is_instance_valid(nodes[i]):
				_apply_batch(nodes[i], node_schedule[step])
				changed_nodes.append(nodes[i])
		for node in changed_nodes:
			node.update()
		await get_tree().create_timer(seconds_per_step).timeout

## Adds every voxel from a batch dictionary to the node.
func _apply_batch(node: VoxelNode3D, batch: Dictionary) -> void:
	for voxel_position in batch:
		var voxel_id: int = batch[voxel_position]
		node.set_voxel(voxel_position, voxel_id)

## Groups a voxel snapshot into layers keyed by the coordinate along the
## configured [member axis]. Each layer maps a voxel position to its voxel ID.
func _group_voxels_by_axis(snapshot: Dictionary) -> Dictionary:
	var layers: Dictionary = {}
	for voxel_position in snapshot:
		var layer_index := _get_layer_index(voxel_position)
		if not layers.has(layer_index):
			layers[layer_index] = {}
		layers[layer_index][voxel_position] = snapshot[voxel_position]
	return layers

## Returns the layer index of a voxel position along the configured
## [member axis].
func _get_layer_index(voxel_position: Vector3i) -> int:
	match axis:
		BuildAxis.X:
			return voxel_position.x
		BuildAxis.Z:
			return voxel_position.z
		_:
			return voxel_position.y

## Shuffles an array in place using the provided seeded random generator, so
## the reveal order is reproducible for a given [member random_seed].
func _seeded_shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temporary: Variant = items[i]
		items[i] = items[j]
		items[j] = temporary

## Returns the node's serialized `_voxel_data` property when the node exposes
## it (such as [VoxelModel3D]), otherwise null.
func _get_serialized_voxel_data(node: VoxelNode3D) -> Variant:
	for property in node.get_property_list():
		if property.name == &"_voxel_data":
			return node.get(&"_voxel_data")
	return null

## Returns the mesh currently assigned to the node's render mesh instance, or
## null when the node has no suitable [MeshInstance3D] child.
func _get_render_mesh(node: VoxelNode3D) -> Variant:
	var mesh_instances := node.find_children("*", "MeshInstance3D", false, false)
	for mesh_instance in mesh_instances:
		if not mesh_instance is MultiMeshInstance3D:
			return mesh_instance.get("mesh")
	return null

## Restores a voxel node's original content and render mesh after the in-editor
## preview, so the scene file keeps its original serialized data.
func _restore_node_in_editor(
	node: VoxelNode3D,
	snapshot: Dictionary,
	serialized: Variant,
	render_mesh: Variant
) -> void:
	if not is_instance_valid(node):
		return
	if serialized is PackedByteArray:
		node.set(&"_voxel_data", serialized)
	else:
		node.clear_voxels()
		_apply_batch(node, snapshot)
	node.update()
	if render_mesh != null:
		var mesh_instances := node.find_children("*", "MeshInstance3D", false, false)
		for mesh_instance in mesh_instances:
			if not mesh_instance is MultiMeshInstance3D:
				mesh_instance.set("mesh", render_mesh)
				break
