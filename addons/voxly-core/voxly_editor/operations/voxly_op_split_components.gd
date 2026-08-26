@tool
extends VoxlyEditOperation
## Split regions of the model and creates one sibling VoxelModel3D per region, 
## removing them from the source.

## Only components with at least this many voxels are extracted.
## Smaller regions stay in the source.
var min_size: int = 1

## When true the original model is removed after extraction.
var delete_original: bool = true

## When true each part's node is centered on its voxel content:
## the node's world position becomes the content center
## and `origin` is set to -shape/2 so the mesh draws centered on the node.
## When false the part keeps corner alignment.
var center_origin: bool = true

func _init() -> void:
	id = "split_components"
	category = "new_model"
	display_name = "Split into Components"
	modifies_voxels = true
	prompts_for_options = true

## Option schema shown in the editor's ContextWindow before executing.
func get_options() -> Array[Dictionary]:
	return [
		{
			"label": "Delete Original Model",
			"property": "delete_original",
			"type": TYPE_BOOL,
		},
		{
			"label": "Center Origin on Content",
			"property": "center_origin",
			"type": TYPE_BOOL,
		},
		{
			"label": "Minimum Component Size",
			"property": "min_size",
			"type": TYPE_INT,
			"min": 1.0,
			"max": 1000000.0,
			"step": 1.0,
			"default": 1,
		},
	]

func is_available(editor) -> bool:
	return _target_has_content(editor)

func execute(editor, undo_redo: EditorUndoRedoManager) -> void:
	var source := _get_target(editor)
	if source == null:
		return
	
	var positions = source.get_voxel_positions_used()
	if positions.is_empty():
		return
	
	# Split into components with BFS
	var components := _label_components(source, positions)
	
	undo_redo.create_action("Voxly Split into Components")
	var extracted_total := 0
	var created_parts: Array[Node] = []
	for component in components:
		if component.size() < maxi(min_size, 1):
			continue
		var part := _extract_component(undo_redo, source, component, created_parts.size())
		if part != null:
			created_parts.append(part)
			extracted_total += component.size()
	
	if extracted_total > 0:
		# Clear selection
		_record_selection_clear(undo_redo, editor)
		if delete_original:
			# Remove the now-empty source model
			var parent := source.get_parent()
			if parent != null:
				undo_redo.add_do_method(parent, "remove_child", source)
				undo_redo.add_undo_method(parent, "add_child", source)
				undo_redo.add_undo_method(source, "set_owner", source.owner)
			_record_rebuild(undo_redo, source)
	undo_redo.commit_action()
	
	if extracted_total > 0 and not created_parts.is_empty():
		# Editing should be off after the split. Selecting the first created
		# part re-targets the editor to a live node.
		_select_node(created_parts[0])
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "OpSplit",
		"Split %d components (%d voxels)" % [components.size(), extracted_total])

## BFS labels 6-connected voxel regions. Returns Array[Array[Vector3i]].
func _label_components(source, positions: Array[Vector3i]) -> Array:
	var occupied: Dictionary[Vector3i, bool] = {}
	for pos in positions:
		occupied[pos] = true
	
	var result: Array = []
	var visited: Dictionary[Vector3i, bool] = {}
	for start in positions:
		if visited.has(start):
			continue
		var component: Array[Vector3i] = []
		var queue: Array[Vector3i] = [start]
		visited[start] = true
		while not queue.is_empty():
			var current: Vector3i = queue.pop_front()
			component.append(current)
			for dir in _neighbors():
				var neighbor := current + dir
				if not occupied.has(neighbor) or visited.has(neighbor):
					continue
				visited[neighbor] = true
				queue.append(neighbor)
		if not component.is_empty():
			result.append(component)
	return result

## Creates a sibling model for one component and removes it from the source.
## Returns the created VoxelModel3D, or null if the source has no parent.
func _extract_component(undo_redo: EditorUndoRedoManager, source, component: Array[Vector3i], part_index: int) -> VoxelModel3D:
	var min_corner := _min_corner(component)
	var max_corner := _max_corner(component)
	var new_shape := max_corner - min_corner + Vector3i.ONE
	
	var voxel_map: Dictionary = {}
	for pos in component:
		var voxel_id = source.get_voxel(pos)
		if voxel_id != null:
			voxel_map[pos - min_corner] = voxel_id
	
	var parent = source.get_parent()
	if parent == null:
		return null
	
	var new_model := VoxelModel3D.new()
	new_model.name = "%s_Part%d" % [source.name, part_index + 1]
	new_model.voxel_set = source.voxel_set
	new_model.voxel_size = source.voxel_size
	new_model.shape = new_shape
	new_model.voxels_colored = source.voxels_colored
	new_model.voxels_textured = source.voxels_textured
	
	if center_origin:
		# Node origin sits at the component's voxel-content center, such that:
		# Transform position = the content center in world space, with the
		# source's basis copied so rotation/scale render identically.
		# origin = -shape/2 so the mesh is drawn centered on the node.
		var center_local = (
			source.origin + Vector3(min_corner) + Vector3(new_shape) * 0.5
		) * source.voxel_size
		new_model.transform = Transform3D(source.transform.basis, source.transform * center_local)
		new_model.origin = -Vector3(new_shape) * 0.5
	else:
		# Content spans shape in the +X+Y+Z octant and
		# the part inherits the source transform wholesale. `origin` is in
		# voxel units, so the min-corner offset is added directly.
		new_model.transform = source.transform
		new_model.origin = source.origin + Vector3(min_corner)
	
	undo_redo.add_do_method(parent, "add_child", new_model)
	undo_redo.add_do_method(new_model, "set_owner", source.owner)
	for voxel_position in voxel_map:
		undo_redo.add_do_method(new_model, "set_voxel", voxel_position, voxel_map[voxel_position])
	undo_redo.add_do_method(new_model, "update")
	undo_redo.add_undo_method(parent, "remove_child", new_model)

	_record_remove_all(undo_redo, source, component)
	return new_model

## Selects a node in the Godot editor so the docks re-target to it.
func _select_node(node: Node) -> void:
	if not node:
		return
	var sel := EditorInterface.get_selection()
	sel.clear()
	EditorInterface.edit_node(node)

func _min_corner(positions: Array[Vector3i]) -> Vector3i:
	var result := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for pos in positions:
		for i in 3:
			result[i] = mini(result[i], pos[i])
	return result

func _max_corner(positions: Array[Vector3i]) -> Vector3i:
	var result := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for pos in positions:
		for i in 3:
			result[i] = maxi(result[i], pos[i])
	return result
