@tool
@abstract
class_name VoxelNode3DController
extends RefCounted
## Base controller that bridges a VoxlyEditor instance with a target voxel node.
## Handles the lifecycle of attaching/detaching editor overlays, raycasting,
## input handling, and UI synchronization.
##
## Subclasses should override raycast(), start_editing(), and stop_editing().

signal editing_started(target)
signal editing_stopped
signal input_handled(handled: bool)

## Emitted when an import begins.
signal import_started(file_name: String)

## Emitted during import.
signal import_progress(stage: String, fraction: float)

## Emitted when an import completes or fails.
signal import_finished(success: bool)

## The VoxlyEditor instance this controller drives.
var editor: VoxlyEditor

## The target node being edited.
var target = null

## Whether editing is currently active.
var is_editing: bool = false:
	get: return editor.editing_enabled

## UndoRedo manager for action history.
var undo_redo: EditorUndoRedoManager = null

## The grid overlay node (attached to target during editing).
var grid: VoxlyEditorGrid = null

## The preview overlay node.
var preview: VoxlyEditorPreview = null ## The preview overlay node.

## Cached reference to the VoxelSet editor UI.
var voxel_set_editor_ui = null

## Mouse-driven interaction models are VoxlyInteractions,
## each owning one interaction lifecycle. The controller is a thin dispatcher:
## it resolves the interaction for the current brush/tool state on press and
## routes subsequent drag/up events to it.
var _interaction: VoxlyInteraction = null
var _stroke_interaction: VoxlyStrokeInteraction = null
var _drag_interaction: VoxlyDragInteraction = null
var _click_interaction: VoxlyClickInteraction = null
var _pattern_select_interaction: VoxlyPatternSelectInteraction = null

func _init() -> void:
	editor = VoxlyEditor.new()


## Called when the controller should start editing a target node.
## Subclasses should call super(). Overlays and _voxly_core_editing_ are 
## NOT attached here; they are attached only when editing is toggled on via set_editing().
func start_editing(target_node) -> void:
	if target_node == target and is_instance_valid(target):
		return
	
	stop_editing()
	target = target_node
	if is_instance_valid(target):
		editor.adapter = VoxlyNodeAdapter.new(target_node)
		editor.voxel_set = _get_voxel_set()
		editor.voxel_shape = _get_voxel_shape()
		editing_started.emit(target_node)
	# Restore the user's saved editor preferences (brush/tool/options).
	load_config()


## Called when the controller should stop editing.
## Detaches overlays if still attached (e.g. editing was left on) and cancels
## any in-flight stroke so its live edits are reverted without an undo action.
func stop_editing() -> void:
	if is_instance_valid(target):
		_detach_overlays()
	
	# Cancel any in-flight interaction/stroke first so live writes are reverted
	# and no stale merge state leaks to the next session.
	if _interaction:
		_interaction.cancel()
		_interaction = null
	editor.cancel_stroke(editor.adapter)
	# Clear persistent selection state so it doesn't leak between targets
	editor.selection.clear()
	# Editing over: restore the node's static body (if requested) with one
	# refresh so the collision matches the edited voxels, or remove it if the
	# flag was toggled off mid-session.
	if is_instance_valid(target):
		target.set_meta("_voxly_core_editing_", false)
		if target.get("attach_static_body"):
			target.create_static_body()
		else:
			target.remove_static_body()
	
	# Persist the user's editor preferences before tearing anything down.
	save_config()
	target = null
	is_editing = false
	editor.set_editing(false)
	editor.adapter = null
	editor.voxel_set = null
	editing_stopped.emit()


## Sets whether editing mode is active (toggle on/off).
## Attaches overlays when enabling, detaches them when disabling.
func set_editing(enabled: bool) -> void:
	if not is_instance_valid(target):
		return
	
	if not enabled:
		# Abort any in-flight interaction before tearing the overlays down.
		if _interaction:
			_interaction.cancel()
			_interaction = null
		editor.cancel_stroke(editor.adapter)
		# Clear the selection when leaving editing mode so no stale
		# highlighted positions linger on the model.
		editor.selection.clear()
	editor.set_editing(enabled)
	is_editing = enabled
	
	# Keep the node's editing flag accurate: only an ACTIVE edit session
	# defers collision work (no regeneration, existing shape disabled).
	# While the node is merely selected (dock open, editing off), changes
	# to attach_static_body / create_static_body() take effect immediately.
	target.set_meta("_voxly_core_editing_", enabled)
	if enabled:
		_attach_overlays()
	else:
		_detach_overlays()
	
	# Entering editing disables any existing generated body (deferred, so it
	# can't interfere with sculpt raycasts); leaving editing refreshes it so
	# the collision matches the edited voxels and becomes active again.
	if target.get("attach_static_body"):
		target.create_static_body()
	else:
		target.remove_static_body()
	_update_overlay_visibility()

## Attaches the grid and preview overlays to the target node as internal children
## so they do not appear in the scene tree dock.
func _attach_overlays() -> void:
	if not is_instance_valid(target):
		return
	
	if not grid:
		grid = VoxlyEditorGrid.new()
	if not preview:
		preview = VoxlyEditorPreview.new()
		# Keep the persistent selection outline in sync with selection changes
		if editor.selection.changed.is_connected(_on_selection_changed_for_preview):
			editor.selection.changed.disconnect(_on_selection_changed_for_preview)
		editor.selection.changed.connect(_on_selection_changed_for_preview)
	
	# Apply the user's saved grid/preview overlay settings now that both
	# overlays exist (they may be reused from a previous editing session).
	_apply_overlay_config()
	
	# Only add if they haven't been attached already (or were detached)
	if not grid.get_parent():
		target.add_child(grid, false, Node.INTERNAL_MODE_FRONT)
	if not preview.get_parent():
		target.add_child(preview, false, Node.INTERNAL_MODE_FRONT)
	
	_sync_overlay_properties()
	_update_overlay_visibility()
	# Refresh the selection outline for the newly attached overlay
	_on_selection_changed_for_preview()
	
	# Enable debug visuals if the editor_logic category is on
	if VoxlyDebug.is_category_enabled(VoxlyDebug.CATEGORY_EDITOR_LOGIC):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "Controller", "Debug visuals enabled")
		preview.update_debug_visibility()


## Detaches the overlays from the target.
func _detach_overlays() -> void:
	if grid and is_instance_valid(grid):
		if is_instance_valid(grid.get_parent()):
			grid.get_parent().remove_child(grid)
	if preview and is_instance_valid(preview):
		if is_instance_valid(preview.get_parent()):
			preview.get_parent().remove_child(preview)


## Synchronizes overlay properties (voxel size, shape, etc.) from the target.
@abstract
func _sync_overlay_properties() -> void


## Shows/hides overlays based on editing state. The preview's own visibility
## is a USER preference (settings window) — never clobbered here. We only clear
## any stale ghost when editing turns off.
func _update_overlay_visibility() -> void:
	if grid:
		grid.disabled = not editor.editing_enabled
	if preview and not editor.editing_enabled:
		preview.clear_preview()
		preview.clear_selection_preview()


## Called when the editor's selection changes while overlays are attached.
## Pushes the selection positions to the persistent outline overlay.
func _on_selection_changed_for_preview() -> void:
	if preview and is_instance_valid(preview):
		if editor.selection and editor.selection.count() > 0:
			preview.update_selection_preview(editor.selection.to_array())
		else:
			preview.clear_selection_preview()

## Commits a property change on the target node through UndoRedo when available.
func _commit_property_change(property: String, old_value, new_value, action_name: String) -> void:
	if not is_instance_valid(target):
		return
	if undo_redo:
		undo_redo.create_action(action_name, UndoRedo.MERGE_ENDS, target)
		undo_redo.add_do_property(target, property, new_value)
		undo_redo.add_undo_property(target, property, old_value)
		undo_redo.commit_action()
	else:
		target.set(property, new_value)


## Sets the target node's voxel size through UndoRedo (if available).
## The node's own setter clamps to a minimum of (0.1, 0.1, 0.1).
func set_voxel_size(new_value: Vector3) -> void:
	if not is_instance_valid(target):
		return
	var old_value = target.voxel_size
	if new_value != old_value:
		_commit_property_change("voxel_size", old_value, new_value, "Set Voxel Size")

## Number of voxels registered per batch before yielding a frame — keeps the
## editor responsive and lets the progress window repaint during large imports.
const _PROGRESS_BATCH := 500

## Imports a voxel file (.vox / .png / .jpg / ...) into the target node.
##
## `append` overlays the imported voxels at the origin (normalized positions,
## matching the user's chosen behavior). Otherwise the target's existing
## voxels are replaced. Palette entries and materials are merged into the
## target's VoxelSet (creating one if none exists) with conflicting IDs
## remapped so nothing is overwritten.
##
## All changes (VoxelSet merge, shape expansion, voxel writes, mesh rebuild)
## are recorded in a single undoable action.
##
## Runs as a chunked coroutine, so the editor stays responsive and the UI drives 
## its progress window from the import_started / import_progress / import_finished signals.
func import_file(path: String, append: bool) -> void:
	if not is_instance_valid(target) or not undo_redo:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "Controller", "import_file: no valid target/undo_redo")
		import_finished.emit(false)
		return
	
	import_started.emit(path.get_file())
	
	# Let the progress window paint before the (potentially slow) read starts.
	import_progress.emit("Reading file", 0.0)
	await _await_frame()
	
	var result: Dictionary = VoxlyImporter.read_for_editor(path)
	var error: int = result.get("error", ERR_FILE_CORRUPT)
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "Controller",
			"import_file: failed to read '%s' (error=%d)" % [path, error])
		import_finished.emit(false)
		return
	
	var imported_voxels: Dictionary = result.get("voxels", {})
	if imported_voxels.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "Controller", "import_file: no voxels to import")
		import_finished.emit(false)
		return
	
	var palette: Dictionary = result.get("palette", {})
	var materials: Dictionary = result.get("materials", {})
	
	import_progress.emit("Preparing palette", 0.08)
	await _await_frame()
	
	undo_redo.create_action("Voxly Import %s" % path.get_file())
	
	# Ensure the target has a VoxelSet (undoable create)
	var voxel_set: VoxelSet = _get_voxel_set()
	if not voxel_set:
		voxel_set = VoxelSet.new()
		undo_redo.add_do_property(target, "voxel_set", voxel_set)
		undo_redo.add_undo_property(target, "voxel_set", null)
	
	# Merge palette/materials into the VoxelSet (ID remap on conflict)
	var merge_result: Dictionary = VoxlyImporter.merge_into_voxel_set(voxel_set, palette, materials)
	VoxlyImporter.register_voxel_set_merge(undo_redo, voxel_set, merge_result)
	
	# Apply the voxel ID remap to the imported voxel map
	var voxel_remap: Dictionary = merge_result["voxel_remap"]
	var final_voxels: Dictionary = {}
	for pos in imported_voxels:
		var voxel_id: int = imported_voxels[pos]
		final_voxels[pos] = voxel_remap.get(voxel_id, voxel_id)
	
	# Replace mode: clear existing voxels first
	if not append:
		var existing_voxels: Dictionary = target.get_voxels()
		var cleared: int = 0
		var clear_total := max(existing_voxels.size(), 1)
		for pos in existing_voxels:
			undo_redo.add_do_method(target, "remove_voxel", pos)
			undo_redo.add_undo_method(target, "set_voxel", pos, existing_voxels[pos])
			cleared += 1
			if cleared % _PROGRESS_BATCH == 0:
				import_progress.emit("Clearing existing voxels", 0.15 + 0.15 * float(cleared) / float(clear_total))
				await _await_frame()
	
	# Expand the shape to fit the union of existing + incoming voxels
	var old_shape: Vector3i = target.shape if "shape" in target else Vector3i(1, 1, 1)
	var new_shape := _calc_import_shape(target, final_voxels, old_shape)
	if new_shape != old_shape:
		undo_redo.add_do_property(target, "shape", new_shape)
		undo_redo.add_undo_property(target, "shape", old_shape)
	
	# Write imported voxels in chunks so the editor stays responsive
	var total := max(final_voxels.size(), 1)
	var written: int = 0
	for pos in final_voxels:
		var old_id = target.get_voxel(pos)
		undo_redo.add_do_method(target, "set_voxel", pos, final_voxels[pos])
		if old_id != null:
			undo_redo.add_undo_method(target, "set_voxel", pos, old_id)
		else:
			undo_redo.add_undo_method(target, "remove_voxel", pos)
		written += 1
		if written % _PROGRESS_BATCH == 0:
			import_progress.emit("Writing voxels", 0.3 + 0.65 * float(written) / float(total))
			await _await_frame()
	
	import_progress.emit("Rebuilding mesh", 0.97)
	await _await_frame()
	
	# Refresh the mesh (and optional collision) on apply + undo
	undo_redo.add_do_method(target, "update")
	undo_redo.add_undo_method(target, "update")
	
	# Select the imported voxels; is undoable, so restores the previous
	# selection on undo.
	var old_selection := editor.selection.to_array()
	var imported_positions: Array[Vector3i] = []
	for pos in final_voxels:
		imported_positions.append(pos)
	undo_redo.add_do_method(editor.selection, "set_positions", imported_positions)
	undo_redo.add_undo_method(editor.selection, "set_positions", old_selection)
	
	# Keep the editor's voxel_set reference in sync.
	editor.voxel_set = voxel_set
	
	undo_redo.commit_action()
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "Controller",
		"import_file: imported %d voxels ('%s', append=%s)" % [final_voxels.size(), path, append])
	
	import_progress.emit("Done", 1.0)
	import_finished.emit(true)

## Yields until the next engine frame. Works from a RefCounted 
## controller by reaching the scene tree through the main loop.
func _await_frame() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.process_frame

## Computes the union bounding shape for the target's existing + incoming
## voxels. Never shrinks below the current shape.
func _calc_import_shape(target, incoming_voxels: Dictionary, current_shape: Vector3i) -> Vector3i:
	var max_all := current_shape - Vector3i.ONE
	for pos in incoming_voxels:
		var p: Vector3i = pos
		max_all.x = maxi(max_all.x, p.x)
		max_all.y = maxi(max_all.y, p.y)
		max_all.z = maxi(max_all.z, p.z)
	# Include existing voxel extent (they may exceed current_shape).
	for pos in target.get_voxels():
		var p: Vector3i = pos
		max_all.x = maxi(max_all.x, p.x)
		max_all.y = maxi(max_all.y, p.y)
		max_all.z = maxi(max_all.z, p.z)
	return Vector3i(
		maxi(1, max_all.x + 1),
		maxi(1, max_all.y + 1),
		maxi(1, max_all.z + 1)
	)


## Dual-approach raycasting, such that:
## Raycast against the cage collision (grid) for surface hits
## Or if the tool targets existing voxels, use DDA voxel raycast
##
## Returns a dictionary with "position" (Vector3i) and "normal" (Vector3i).
## Returns an empty dictionary if nothing was hit.
func raycast(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	if not is_instance_valid(target) or not is_instance_valid(camera):
		return {}
	
	# Raycast against physics world
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * 10000.0
	var space_state := camera.get_world_3d().direct_space_state
	
	var ray_query := PhysicsRayQueryParameters3D.create(from, to, 2) # Collision layer 2 = cage
	var hit := space_state.intersect_ray(ray_query)
	if hit.is_empty():
		return {}
	
	# Convert hit to local space, then to voxel position.
	var hit_normal: Vector3 = hit.normal.round()
	var local_point: Vector3 = target.to_local(hit.position)
	var vs: Vector3 = grid.voxel_size
	var origin_offset: Vector3 = grid.origin_offset
	var local_offset: Vector3 = local_point - origin_offset
	var voxel_pos := Vector3i(
		floori(local_offset.x / vs.x),
		floori(local_offset.y / vs.y),
		floori(local_offset.z / vs.z)
	)
	
	# Out-of-bounds correction for cage wall hits
	var shape := grid.shape
	var out_of_bounds := (
		voxel_pos.x < 0 or voxel_pos.x >= shape.x or
		voxel_pos.y < 0 or voxel_pos.y >= shape.y or
		voxel_pos.z < 0 or voxel_pos.z >= shape.z
	)
	if out_of_bounds:
		voxel_pos += Vector3i(hit_normal)
	
	var result: Dictionary = {
		"position": voxel_pos,
		"normal": Vector3i(hit_normal),
	}
	
	# DDA raycast for existing voxels.
	# voxel_raycast expects WORLD coordinates and handles the node-local
	# transform + origin_offset conversion internally.
	if _should_dda_raycast():
		var dir_global := camera.project_ray_normal(screen_position)
		var dda_result: Dictionary = target.voxel_raycast(from, dir_global, 256.0)
		if dda_result and dda_result.hit:
			# The raw DDA normal is already the correct entry face normal
			# (VoxelNode3D._dda tracks the last step axis on hit).
			result["position"] = dda_result.hit_position
			result["normal"] = dda_result.hit_normal
			result["dda_hit"] = true
	
	return result


## Whether the current tool or brush resolves hits against individual voxels
## (DDA) rather than the cage surface. Declared as a capability on each
## tool/brush instead of the controller hardcoding name lists.
func _should_dda_raycast() -> bool:
	if editor.active_tool and editor.active_tool.hit_resolution == VoxlyTool.HitResolution.VOXEL:
		return true
	if editor.active_brush and editor.active_brush.hit_resolution == VoxlyBrush.HitResolution.VOXEL:
		return true
	return false

func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if not is_instance_valid(target) or not editor.editing_enabled:
		return false
	
	if event is InputEventMouse:
		var hit := raycast(camera, event.position)
		editor.set_hit(hit)
		
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if hit.is_empty():
					# Pressed off-model: just clear the ghost; no interaction starts.
					if preview:
						preview.clear_preview()
					return true
				if VoxlyDebug.is_category_enabled(VoxlyDebug.CATEGORY_EDITOR_LOGIC):
					_update_debug_ray(camera, event.position, hit)
				_interaction = _resolve_interaction()
				_interaction.begin(event, hit)
			else:
				if _interaction:
					_interaction.finish(event, hit)
					_interaction = null
			return true
		
		if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			if _interaction:
				_interaction.update(event, hit)
			return true
		
		if event is InputEventMouseMotion:
			if hit.is_empty():
				if preview:
					preview.clear_preview()
			else:
				_resolve_interaction().refresh_preview(hit)
			return true
	
	return false


## Returns true when the active brush is a pattern brush still in capture mode.
func _is_pattern_selecting() -> bool:
	return editor.active_brush is VoxlyBrushPattern and editor.active_brush.is_selecting()


## Returns true when the active brush is in continuous-paint mode.
func _is_continuous_active() -> bool:
	var brush = editor.active_brush
	return brush != null and brush.continuous and brush.supports_continuous() and not brush.requires_drag


## Resolves the interaction model for the current brush/tool state.
## Interaction instances are cached so hover previews can
## resolve fresh per event without losing per-interaction state.
func _ensure_interactions() -> void:
	if _stroke_interaction == null:
		_stroke_interaction = VoxlyStrokeInteraction.new(editor, preview, undo_redo)
	if _drag_interaction == null:
		_drag_interaction = VoxlyDragInteraction.new(editor, preview, undo_redo)
	if _click_interaction == null:
		_click_interaction = VoxlyClickInteraction.new(editor, preview, undo_redo)
	if _pattern_select_interaction == null:
		_pattern_select_interaction = VoxlyPatternSelectInteraction.new(editor, preview, undo_redo)


func _resolve_interaction() -> VoxlyInteraction:
	_ensure_interactions()
	if _is_pattern_selecting():
		return _pattern_select_interaction
	if _is_continuous_active():
		return _stroke_interaction
	if editor.active_brush and editor.active_brush.requires_drag:
		return _drag_interaction
	return _click_interaction


func _update_debug_ray(camera: Camera3D, screen_pos: Vector2, hit: Dictionary) -> void:
	if not preview or not VoxlyDebug.is_category_enabled(VoxlyDebug.CATEGORY_RAYCAST):
		return
	
	preview.show_debug_ray(camera, screen_pos)
	
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var log_cat := VoxlyDebug.CATEGORY_RAYCAST
	
	VoxlyDebug.log_category(log_cat, "Raycast",
		"Camera world pos=(%.2f,%.2f,%.2f)" % [camera.global_position.x, camera.global_position.y, camera.global_position.z])
	VoxlyDebug.log_category(log_cat, "Raycast",
		"Ray origin=(%.2f,%.2f,%.2f) dir=(%.6f,%.6f,%.6f)" % [from.x, from.y, from.z, dir.x, dir.y, dir.z])
	
	var hit_pos_world := from + dir * 10000.0
	VoxlyDebug.log_category(log_cat, "Raycast",
		"Ray start=(%.2f,%.2f,%.2f) end=(%.2f,%.2f,%.2f)" % [from.x, from.y, from.z, hit_pos_world.x, hit_pos_world.y, hit_pos_world.z])
	
	var dda_positions := _compute_dda_positions(from, dir, hit)
	var hit_pos := hit.get("position", Vector3i.MAX)
	preview.set_debug_hit_data(hit_pos, dda_positions)
	
	var dda_log: PackedStringArray = []
	var cage_shape := grid.shape if grid else Vector3i.ZERO
	for d in dda_positions:
		if dda_log.size() >= 64:
			dda_log.append("...")
			break
		if d is Vector3i:
			var mark := ""
			if cage_shape != Vector3i.ZERO:
				if d.x < 0 or d.x >= cage_shape.x or d.y < 0 or d.y >= cage_shape.y or d.z < 0 or d.z >= cage_shape.z:
					mark = " OUT"
			dda_log.append("(%d,%d,%d)%s" % [d.x, d.y, d.z, mark])
	VoxlyDebug.log_category(log_cat, "Raycast",
		"DDA cells (%d steps): %s" % [dda_positions.size(), ", ".join(dda_log)])
	
	var cage_size := Vector3(grid.shape) * grid.voxel_size if grid else Vector3.ONE
	var origin_offset: Vector3 = grid.origin_offset if grid else Vector3.ZERO
	var local_cam: Vector3 = target.to_local(from) if target else from
	var local_cam_offset: Vector3 = local_cam - origin_offset
	var hit_normal := hit.get("normal", Vector3i.ZERO)
	var hit_pos_local := hit.get("position", Vector3i.ZERO)
	
	VoxlyDebug.log_category(log_cat, "Raycast",
		"Hit result: pos=(%d,%d,%d) normal=(%d,%d,%d) dda=%s" % [
			hit_pos_local.x, hit_pos_local.y, hit_pos_local.z,
			hit_normal.x, hit_normal.y, hit_normal.z,
			"true" if hit.get("dda_hit", false) else "false"])
	
	var inside = (
		local_cam_offset.x > 0 and local_cam_offset.x < cage_size.x and
		local_cam_offset.y > 0 and local_cam_offset.y < cage_size.y and
		local_cam_offset.z > 0 and local_cam_offset.z < cage_size.z
	)
	VoxlyDebug.log_category(log_cat, "Raycast",
		"Cage bounds=(%.2f,%.2f,%.2f) camera local=(%.2f,%.2f,%.2f) inside=%s" % [
			cage_size.x, cage_size.y, cage_size.z,
			local_cam.x, local_cam.y, local_cam.z,
			"yes" if inside else "no"])
	
	if editor and editor.active_tool:
		var tool_placement := editor.active_tool.placement
		VoxlyDebug.log_category(log_cat, "Raycast",
			"Tool='%s' placement=%d dda_hit=%s" % [
				editor.active_tool.name, tool_placement,
				"yes" if hit.get("dda_hit", false) else "no"])
		if hit.get("dda_hit", false) and tool_placement == VoxlyTool.Placement.ON_SURFACE:
			var final_pos = hit_pos_local + Vector3i(hit_normal)
			VoxlyDebug.log_category(log_cat, "Raycast",
				"  With placement offset: (%d,%d,%d) -> (%d,%d,%d)" % [
					hit_pos_local.x, hit_pos_local.y, hit_pos_local.z,
					final_pos.x, final_pos.y, final_pos.z])


## Standard DDA traversal. Returns array of all cells the ray passes through.
func _compute_dda_positions(from: Vector3, dir: Vector3, hit: Dictionary) -> Array:
	if not grid:
		return []
	
	var vs := grid.voxel_size
	var origin_offset: Vector3 = grid.origin_offset
	var local_from = target.to_local(from) - origin_offset
	var local_dir = target.to_local(from + dir) - target.to_local(from)
	var max_steps := 64
	
	var positions: Array = []
	var current := Vector3i(
		floori(local_from.x / vs.x),
		floori(local_from.y / vs.y),
		floori(local_from.z / vs.z)
	)
	positions.append(current)
	
	var step := Vector3i.ZERO
	var side_dist := Vector3.ZERO
	var delta_dist := Vector3.ZERO
	
	var axes := ["x", "y", "z"]
	for i in 3:
		var d = local_dir[axes[i]]
		if d == 0:
			delta_dist[i] = INF
			side_dist[i] = INF
			continue
		var vs_val := vs[axes[i]]
		delta_dist[i] = abs(vs_val / d) # t to cross one voxel
		if d < 0:
			step[i] = -1
			side_dist[i] = (local_from[axes[i]] - current[i] * vs_val) * abs(1.0 / d)
		else:
			step[i] = 1
			side_dist[i] = ((current[i] + 1) * vs_val - local_from[axes[i]]) * abs(1.0 / d)
	
	for _i in range(max_steps):
		if side_dist.x < side_dist.y:
			if side_dist.x < side_dist.z:
				current.x += step.x
				side_dist.x += delta_dist.x
			else:
				current.z += step.z
				side_dist.z += delta_dist.z
		else:
			if side_dist.y < side_dist.z:
				current.y += step.y
				side_dist.y += delta_dist.y
			else:
				current.z += step.z
				side_dist.z += delta_dist.z
		positions.append(current)
	
	return positions

func _get_voxel_set():
	return null

## Returns the shape/dimensions of the target node's voxel grid in voxel units.
## Used by the editor for mirror calculations. Subclasses should override.
func _get_voxel_shape() -> Vector3i:
	return Vector3i(16, 16, 16)

func set_palette(voxel_id: int) -> void:
	editor.palette_id = voxel_id

const CONFIG_NAME := "voxel_node_3d_editor"

func get_config_path() -> String:
	return VoxlyConfig.get_config_path(CONFIG_NAME)

## Persists the editor's global state, active brush/tool options, and grid +
## preview overlay settings through the shared VoxlyConfig autoload.
func save_config(config_path: String = "") -> void:
	var state: Dictionary = {
		"mirrors": [editor.mirrors.x, editor.mirrors.y, editor.mirrors.z],
	}
	
	if not editor.brush_name.is_empty():
		state["brush"] = editor.brush_name
	if not editor.tool_name.is_empty():
		state["tool"] = editor.tool_name
	VoxlyConfig.set_section(CONFIG_NAME, "state", state)
	
	# Active brush/tool option values (per-name so switching restores them).
	if editor.active_brush:
		_save_options_section("brushes", editor.brush_name, editor.active_brush)
	if editor.active_tool:
		_save_options_section("tools", editor.tool_name, editor.active_tool)
	
	# Grid overlay settings.
	if grid:
		VoxlyConfig.set_section(CONFIG_NAME, "grid", {
			"mode": grid.grid_mode,
			"colored": grid.grid_colored,
			"color": "#%s" % grid.grid_color.to_html(false),
			"visible": grid.grid_visible,
		})
	
	# Preview overlay settings.
	if preview:
		VoxlyConfig.set_section(CONFIG_NAME, "preview", {
			"visible": preview.preview_visible,
			"mirrored": preview.preview_mirrored,
		})


## Restores the editor's saved state from VoxlyConfig. Brush/tool instances
## are recreated through the registry (which applies their saved options).
## Grid/preview settings are applied by _apply_overlay_config() once the
## overlays exist.
func load_config(config_path: String = "") -> void:
	var state := VoxlyConfig.get_section(CONFIG_NAME, "state")
	var saved_brush := state.get("brush", "") as String
	var saved_tool := state.get("tool", "") as String
	# Only activate saved names that are non-empty and still registered.
	if not saved_brush.is_empty() and editor.registry.has_brush(saved_brush):
		editor.set_active_brush(saved_brush)
	if not saved_tool.is_empty() and editor.registry.has_tool(saved_tool):
		editor.set_active_tool(saved_tool)
	if state.has("mirrors") and typeof(state["mirrors"]) == TYPE_ARRAY:
		var m: Array = state["mirrors"]
		if m.size() >= 3:
			editor.set_mirrors(Vector3i(int(m[0]), int(m[1]), int(m[2])))
	
	# Overlay settings are applied when the overlays are (re)attached.
	_apply_overlay_config()


## Applies the saved grid/preview overlay settings onto the current overlays.
func _apply_overlay_config() -> void:
	if VoxlyConfig == null:
		return
	if grid:
		var grid_settings := VoxlyConfig.get_section(CONFIG_NAME, "grid")
		if grid_settings.has("mode"):
			grid.grid_mode = grid_settings["mode"]
		if grid_settings.has("colored"):
			grid.grid_colored = grid_settings["colored"]
		if grid_settings.has("color"):
			var hex: String = grid_settings["color"]
			if hex.begins_with("#"):
				grid.grid_color = Color(hex.trim_prefix("#"))
		if grid_settings.has("visible"):
			grid.grid_visible = grid_settings["visible"]
	if preview:
		var preview_settings := VoxlyConfig.get_section(CONFIG_NAME, "preview")
		if preview_settings.has("visible"):
			preview.preview_visible = preview_settings["visible"]
		if preview_settings.has("mirrored"):
			preview.preview_mirrored = preview_settings["mirrored"]


## Stores a source's option values under `section` (i.e. brushes/tools) keyed by name.
func _save_options_section(section: String, name: String, source) -> void:
	var section_dict: Dictionary = VoxlyConfig.get_section(CONFIG_NAME, section)
	section_dict[name] = _collect_option_values(source.get_options(), source)
	VoxlyConfig.set_section(CONFIG_NAME, section, section_dict)


## Collects the live values of every property declared in an option schema.
## Non-property rows (actions/buttons) are skipped.
func _collect_option_values(options: Array[Dictionary], source) -> Dictionary:
	var result: Dictionary = {}
	for opt in options:
		var property: String = opt.get("property", "")
		if property.is_empty() or source == null:
			continue
		if source.get(property) != null:
			result[property] = source.get(property)
	return result
