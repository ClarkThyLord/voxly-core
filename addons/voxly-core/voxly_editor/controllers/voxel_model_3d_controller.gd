## Controller for editing [VoxelModel3D] nodes. Handles model-specific overlay
## configuration, raycasting, and UI population.
@tool
class_name VoxelModel3DController
extends VoxelNode3DController

## The VoxelModel3D being edited.
var model: VoxelModel3D:
	get: return target

## Begins editing the given target node.
func start_editing(target_node) -> void:
	super.start_editing(target_node)
	if not is_instance_valid(model):
		return
	
	# Connect model signals.
	if model.voxel_set_changed.is_connected(_on_voxel_set_changed):
		model.voxel_set_changed.disconnect(_on_voxel_set_changed)
	model.voxel_set_changed.connect(_on_voxel_set_changed)
	
	if model.origin_changed.is_connected(_on_model_transform_changed):
		model.origin_changed.disconnect(_on_model_transform_changed)
	model.origin_changed.connect(_on_model_transform_changed)
	
	if model.shape_changed.is_connected(_on_model_transform_changed):
		model.shape_changed.disconnect(_on_model_transform_changed)
	model.shape_changed.connect(_on_model_transform_changed)
	
	if model.voxel_size_changed.is_connected(_on_model_transform_changed):
		model.voxel_size_changed.disconnect(_on_model_transform_changed)
	model.voxel_size_changed.connect(_on_model_transform_changed)
	
	editor.voxel_set = _get_voxel_set()
	
	# Default brush/tool if none set.
	if not editor.active_brush:
		editor.set_active_brush("point")
	if not editor.active_tool:
		editor.set_active_tool("add")
	
	# Restore the last saved active brush/tool (options are applied by the
	# registry on creation). Falls back to the current active if none saved.
	var saved_state: Dictionary = VoxlyConfig.get_section(
		VoxelNode3DController.CONFIG_NAME, "state")
	var saved_brush: String = saved_state.get("brush", "")
	var saved_tool: String = saved_state.get("tool", "")
	if saved_brush != "" and editor.registry.has_brush(saved_brush):
		editor.set_active_brush(saved_brush)
	if saved_tool != "" and editor.registry.has_tool(saved_tool):
		editor.set_active_tool(saved_tool)

## Stops editing and tears down the editor.
func stop_editing() -> void:
	if is_instance_valid(model):
		if model.voxel_set_changed.is_connected(_on_voxel_set_changed):
			model.voxel_set_changed.disconnect(_on_voxel_set_changed)
		if model.origin_changed.is_connected(_on_model_transform_changed):
			model.origin_changed.disconnect(_on_model_transform_changed)
		if model.shape_changed.is_connected(_on_model_transform_changed):
			model.shape_changed.disconnect(_on_model_transform_changed)
		if model.voxel_size_changed.is_connected(_on_model_transform_changed):
			model.voxel_size_changed.disconnect(_on_model_transform_changed)
	super.stop_editing()

## Syncs grid and preview settings to the target.
func _sync_overlay_properties() -> void:
	if not is_instance_valid(model) or not grid or not preview:
		return
	
	grid.voxel_size = model.voxel_size
	grid.shape = model.shape
	# Offset the grid's visual mesh to match the model's mesh position.
	grid.origin_offset = model.origin * model.voxel_size
	
	preview.voxel_size = model.voxel_size
	# Offset the preview's MultiMeshInstance to match the model's mesh position.
	preview.origin_offset = model.origin * model.voxel_size

## Sets the model's origin through UndoRedo (if available).
func set_origin(new_value: Vector3) -> void:
	if not is_instance_valid(model):
		return
	
	var old_value := model.origin
	if new_value != old_value:
		_commit_property_change("origin", old_value, new_value, "Set Origin")

## Sets the model's shape through UndoRedo.
func set_shape(new_value: Vector3i) -> void:
	if not is_instance_valid(model):
		return
	
	var old_value := model.shape
	if new_value != old_value:
		if undo_redo:
			undo_redo.create_action("Set Shape", UndoRedo.MERGE_ENDS, model)
			undo_redo.add_do_property(model, "shape", new_value)
			undo_redo.add_undo_property(model, "shape", old_value)
			# Prune any selected positions that fall outside the new bounds.
			if editor and editor.selection and editor.selection.count() > 0:
				var old_selection := editor.selection.to_array()
				var pruned: Array[Vector3i] = []
				for position in old_selection:
					if position.x >= 0 and position.x < new_value.x \
							and position.y >= 0 and position.y < new_value.y \
							and position.z >= 0 and position.z < new_value.z:
						pruned.append(position)
				if pruned.size() != old_selection.size():
					undo_redo.add_do_method(editor.selection, "set_positions", pruned)
					undo_redo.add_undo_method(editor.selection, "set_positions", old_selection)
			undo_redo.commit_action()
		else:
			model.shape = new_value

## Returns the target node voxel set.
func _get_voxel_set() -> VoxelSet:
	if is_instance_valid(model):
		return model.voxel_set
	return null

## Returns the target node voxel shape.
func _get_voxel_shape() -> Vector3i:
	if is_instance_valid(model):
		return model.shape
	return Vector3i(16, 16, 16)

## Refreshes the editor when the voxel set changes.
func _on_voxel_set_changed() -> void:
	editor.voxel_set = _get_voxel_set()
	if voxel_set_editor_ui:
		voxel_set_editor_ui.voxel_set = editor.voxel_set

## Called when the model's origin, shape, or voxel size change while editing.
## Resyncs the grid and preview overlays so they track the updated model.
func _on_model_transform_changed() -> void:
	_sync_overlay_properties()

## Overrides the base raycast with model-specific adjustments.
func raycast(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	var result := super.raycast(camera, screen_position)
	if result.is_empty():
		return result
	
	# Validate that the position is within the model bounds.
	if is_instance_valid(model):
		var position: Vector3i = result.get("position", Vector3i.ZERO)
		if not model.is_voxel_position_valid(position):
			# Clamp to the nearest valid position on the cage face.
			var normal: Vector3i = result.get("normal", Vector3i.ZERO)
			position = _clamp_to_shape(position, normal)
			result["position"] = position
	
	return result

## Clamps a position to the nearest valid voxel position on the given face.
func _clamp_to_shape(position: Vector3i, normal: Vector3i) -> Vector3i:
	if not is_instance_valid(model):
		return position
	
	var shape := model.shape
	# Clamp each axis to the valid range, accounting for the face normal.
	position.x = clampi(position.x, -1 if normal.x == -1 else 0, shape.x - (1 if normal.x == 1 else 0))
	position.y = clampi(position.y, -1 if normal.y == -1 else 0, shape.y - (1 if normal.y == 1 else 0))
	position.z = clampi(position.z, -1 if normal.z == -1 else 0, shape.z - (1 if normal.z == 1 else 0))
	return position

## Populates the brush container with buttons.
## Called by the UI panel when the controller is connected.
func populate_brush_ui(brush_container) -> void:
	if not brush_container:
		return
	
	# Clear existing children.
	for child in brush_container.get_children():
		brush_container.remove_child(child)
		child.queue_free()
	
	var brush_names := editor.registry.get_brush_names()
	for brush_name in brush_names:
		var button := Button.new()
		button.text = brush_name.capitalize()
		button.toggle_mode = true
		button.button_pressed = (brush_name == editor.brush_name)
		
		# Apply the icon from the brush instance if available.
		var brush := editor.registry.create_brush(brush_name)
		if brush and brush.icon:
			button.icon = brush.icon
		
		button.pressed.connect(_on_brush_ui_selected.bind(brush_name, brush_container))
		brush_container.add_child(button)
	
	# Listen for brush changes to update the UI.
	if editor.brush_changed.is_connected(_on_brush_changed):
		editor.brush_changed.disconnect(_on_brush_changed)
	editor.brush_changed.connect(_on_brush_changed.bind(brush_container))

## Populates the tool container with buttons.
func populate_tool_ui(tool_container) -> void:
	if not tool_container:
		return
	for child in tool_container.get_children():
		tool_container.remove_child(child)
		child.queue_free()
	
	var tool_names := editor.registry.get_tool_names()
	for tool_name in tool_names:
		var button := Button.new()
		button.text = tool_name.capitalize()
		button.toggle_mode = true
		button.button_pressed = (tool_name == editor.tool_name)
		
		# Apply the icon from the tool instance if available.
		var tool := editor.registry.create_tool(tool_name)
		if tool and tool.icon:
			button.icon = tool.icon
		
		button.pressed.connect(_on_tool_ui_selected.bind(tool_name, tool_container))
		tool_container.add_child(button)
	
	if editor.tool_changed.is_connected(_on_tool_changed):
		editor.tool_changed.disconnect(_on_tool_changed)
	editor.tool_changed.connect(_on_tool_changed.bind(tool_container))

## Selects the brush clicked in the UI.
func _on_brush_ui_selected(brush_name: String, brush_container) -> void:
	editor.set_active_brush(brush_name)
	for child in brush_container.get_children():
		if child is Button:
			child.button_pressed = (child.text.to_lower() == brush_name)

## Selects the tool clicked in the UI.
func _on_tool_ui_selected(tool_name: String, tool_container) -> void:
	editor.set_active_tool(tool_name)
	for child in tool_container.get_children():
		if child is Button:
			child.button_pressed = (child.text.to_lower() == tool_name)

## Notifies the UI when the active brush changes.
func _on_brush_changed(brush_name: String, brush_container) -> void:
	for child in brush_container.get_children():
		if child is Button:
			child.button_pressed = (child.text.to_lower() == brush_name)

## Notifies the UI when the active tool changes.
func _on_tool_changed(tool_name: String, tool_container) -> void:
	for child in tool_container.get_children():
		if child is Button:
			child.button_pressed = (child.text.to_lower() == tool_name)
