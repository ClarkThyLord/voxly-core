@tool
extends VoxelNode3DImportPlugin
## Imports voxel files (.vox, .png, .jpg) as a singular VoxelNode3d node or 
## composed scenes.
##
## Creates a complete VoxelModel3D node with voxels, palette, and materials
## from the imported file. Supports voxel size and palette modes:
## Full (all palette), Compact (used only), and Reference (point to external VoxelSet).

func _init() -> void:
	DEBUG_CONTEXT = "VoxelModel3DImport"

func _get_visible_name() -> String:
	return "VoxelModel3D"

func _get_importer_name() -> String:
	return "Voxly-Core.VoxelModel3D"

func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	var is_image := _is_image_file(path)
	
	var options: Array[Dictionary] = [
		{
			"name": "name",
			"default_value": "",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "import_mode",
			"default_value": 0,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "Merged (VoxelModel3D),Hierarchical (Node3D with VoxelModel3Ds)",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "bounds_mode",
			"default_value": 0,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "Fit to Voxels,Original Chunk Size",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
	]
	
	# Image-specific import options (only shown for image files)
	if is_image:
		options.append({
			"name": "alpha_threshold",
			"default_value": 0.1,
			"property_hint": PROPERTY_HINT_RANGE,
			"hint_string": "0.0, 1.0, 0.01",
			"usage": PROPERTY_USAGE_DEFAULT,
		})
		options.append({
			"name": "depth",
			"default_value": 1,
			"property_hint": PROPERTY_HINT_RANGE,
			"hint_string": "1, 64, 1",
			"usage": PROPERTY_USAGE_DEFAULT,
		})
		options.append({
			"name": "flip_x",
			"default_value": false,
			"usage": PROPERTY_USAGE_DEFAULT,
		})
		options.append({
			"name": "flip_y",
			"default_value": false,
			"usage": PROPERTY_USAGE_DEFAULT,
		})
	
	options.append_array(get_shared_options(preset_index))
	return options

func _is_image_file(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext in PackedStringArray(["png", "jpg", "jpeg", "bmp", "tga", "webp"])

func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	# Hide palette_mode and related options for image files (not relevant)
	var image_only_opts := PackedStringArray(["alpha_threshold", "depth", "flip_x", "flip_y"])
	if option_name in image_only_opts:
		return _is_image_file(path)
	
	# Show palette_mode only for non-image files
	if option_name in PackedStringArray(["palette_mode", "reference_voxel_set_path"]):
		return not _is_image_file(path)
	
	return true

func _import(source_file: String, save_path: String, options: Dictionary, r_platform_variants: Array, r_gen_files: Array) -> int:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Importing file: '%s' -> '%s'" % [source_file, save_path])
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Import options: %s" % options)
	
	# Read the file
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Reading file with VoxlyReader...")
	var read_result := VoxlyReader.read_file(source_file, options)
	var error: int = read_result.get("error", ERR_FILE_CORRUPT)
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Failed to read file: error=%d" % error)
		return error
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Read result: voxels=%d, palette=%d, materials=%d" % [
		read_result.get("voxels", {}).size(),
		read_result.get("palette", {}).size(),
		read_result.get("materials", {}).size(),
	])
	
	# Collect palette_mode and palette options
	var palette_mode: int = options.get("palette_mode", PaletteMode.FULL)
	var reference_path: String = options.get("reference_voxel_set_path", "")
	
	# Collect used voxel IDs for Compact mode
	var used_voxel_ids: Array = []
	if palette_mode == PaletteMode.COMPACT:
		var all_voxels: Dictionary = read_result.get("voxels", {})
		var seen: Dictionary = {}
		for pos in all_voxels:
			var vid: int = all_voxels[pos]
			if not seen.has(vid):
				seen[vid] = true
				used_voxel_ids.append(vid)
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Compact mode: %d unique palette IDs used by %d voxels" % [used_voxel_ids.size(), all_voxels.size()])
	
	# Create the VoxelSet
	var voxel_set: VoxelSet = null
	
	if palette_mode == PaletteMode.REFERENCE:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Reference mode: loading VoxelSet from '%s'" % reference_path)
		voxel_set = create_voxel_set(read_result, palette_mode, [], reference_path)
		if voxel_set == null:
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Failed to load reference VoxelSet, aborting")
			return ERR_FILE_CANT_OPEN
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Creating VoxelSet from read result (mode: %s)..." % ["Full", "Compact"][palette_mode])
		voxel_set = create_voxel_set(read_result, palette_mode, used_voxel_ids)
	
	if voxel_set:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "VoxelSet ready with %d voxels and %d materials" % [
			voxel_set.get_voxels_count(),
			voxel_set.get_materials_count(),
		])
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "No VoxelSet available, aborting")
		return ERR_FILE_CANT_OPEN
	
	# Create root node
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Creating root node...")
	var name: String = options.get("name", "")
	if name.is_empty():
		name = source_file.get_file().replace("." + source_file.get_extension(), "")
	
	var voxel_size_value: float = options.get("voxel_size", 0.5)
	var mesh_mode_value: int = options.get("mesh_mode", 2) # GREEDY
	var import_mode: int = options.get("import_mode", 0) # 0=Merged, 1=Hierarchical
	var bounds_mode: int = options.get("bounds_mode", 0) # 0=Fit to Voxels, 1=Original Chunk Size
	
	# Get scene models from reader
	var scene_models: Array = read_result.get("scene_models", [])
	var model: Node
	
	if import_mode == 1 and scene_models.size() > 0:
		# Hierarchical: Node3D parent with child VoxelModel3D per scene model
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Hierarchical import with %d scene models" % scene_models.size())
		
		var parent := Node3D.new()
		parent.name = name
		
		for i in scene_models.size():
			var sm: Dictionary = scene_models[i]
			var sm_voxels: Dictionary = sm["voxels"].duplicate()
			
			var child_shift := _shift_to_non_negative(sm_voxels)
			
			var child := VoxelModel3D.new()
			var scene_name: String = sm.get("name", "")
			if scene_name.is_empty():
				child.name = "Model_%d" % i
			else:
				child.name = scene_name
			child.voxel_set = voxel_set
			child.voxel_size = Vector3(voxel_size_value, voxel_size_value, voxel_size_value)
			child.mesh_mode = mesh_mode_value as VoxelNode3D.MeshMode
			child.voxels_colored = options.get("voxels_colored", true)
			child.voxels_textured = options.get("voxels_textured", true)
			
			# Determine shape based on bounds_mode
			if bounds_mode == 1 and sm.has("size"):
				# Original Chunk Size: use the original SIZE chunk dimensions
				var original_size: Vector3i = sm["size"]
				var fitted := _calc_bounds(sm_voxels)
				# Ensure shape is at least as large as the actual voxel bounds
				child.shape = Vector3i(
					max(original_size.x, fitted.x),
					max(original_size.y, fitted.y),
					max(original_size.z, fitted.z)
				)
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Original chunk size: %s, fitted: %s -> shape=%s" % [original_size, fitted, child.shape])
			else:
				# Fit to Voxels: tight bounding of actual voxel positions (default)
				child.shape = _calc_bounds(sm_voxels)
			
			child.origin = Vector3(child_shift)
			
			for pos in sm_voxels:
				child.set_voxel(pos, sm_voxels[pos])
			
			parent.add_child(child)
			child.owner = parent
			child.rebuild_mesh()
			# Override MeshInstance3D owner from parent back to child so
			# PackedScene.pack(parent) correctly serializes the grandchild tree.
			for grandchild in child.get_children():
				grandchild.owner = parent
		
		model = parent
	
	else:
		# Merged (default): single VoxelModel3D with all voxels merged together
		var flat_voxels: Dictionary = read_result.get("voxels", {}).duplicate()
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Merged import with %d voxels" % flat_voxels.size())
		
		var single := VoxelModel3D.new()
		single.name = name
		single.voxel_set = voxel_set
		single.voxel_size = Vector3(voxel_size_value, voxel_size_value, voxel_size_value)
		single.mesh_mode = mesh_mode_value as VoxelNode3D.MeshMode
		single.voxels_colored = options.get("voxels_colored", true)
		single.voxels_textured = options.get("voxels_textured", true)
		
		if not flat_voxels.is_empty():
			var shift := _shift_to_non_negative(flat_voxels)
			single.shape = _calc_bounds(flat_voxels)
			single.origin = Vector3(shift)
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Shift applied: origin=%s shape=%s" % [single.origin, single.shape])
		
		for pos in flat_voxels:
			single.set_voxel(pos, flat_voxels[pos])
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Rebuilding mesh (%d voxels set)..." % flat_voxels.size())
		single.rebuild_mesh()
		# Ensure MeshInstance3D child is owned by the model so PackedScene.pack()
		# includes it (and its mesh) in the serialized scene.
		for child in single.get_children():
			child.owner = single
		model = single
	
	# Pack into scene
	var scene := PackedScene.new()
	error = scene.pack(model)
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Failed to pack scene: error=%d" % error)
		model.free()
		return error

	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Saving scene to '%s.%s'..." % [save_path, _get_save_extension()])
	error = ResourceSaver.save(scene, "%s.%s" % [save_path, _get_save_extension()])
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Failed to save scene: error=%d" % error)
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Successfully imported '%s'" % source_file)
	
	model.free()
	return error

## Shifts all voxels so the minimum position becomes (0,0,0).
## Returns the shift amount (original min_pos).
## Modifies the voxels dict in-place.
static func _shift_to_non_negative(voxels: Dictionary) -> Vector3i:
	if voxels.is_empty():
		return Vector3i.ZERO
	
	var min_pos := Vector3i.ZERO
	var first := true
	for pos in voxels:
		var p: Vector3i = pos
		if first:
			min_pos = p
			first = false
		else:
			min_pos = Vector3i(min(min_pos.x, p.x), min(min_pos.y, p.y), min(min_pos.z, p.z))
	
	if min_pos == Vector3i.ZERO:
		return Vector3i.ZERO
	
	var shifted: Dictionary = {}
	for pos in voxels:
		shifted[pos - min_pos] = voxels[pos]
	voxels.clear()
	for pos in shifted:
		voxels[pos] = shifted[pos]
	
	return min_pos

## Calculates the bounding box size of voxels (max - min + 1).
static func _calc_bounds(voxels: Dictionary) -> Vector3i:
	if voxels.is_empty():
		return Vector3i(1, 1, 1)
	
	var min_pos := Vector3i.ZERO
	var max_pos := Vector3i.ZERO
	var first := true
	for pos in voxels:
		var p: Vector3i = pos
		if first:
			min_pos = p
			max_pos = p
			first = false
		else:
			min_pos = Vector3i(min(min_pos.x, p.x), min(min_pos.y, p.y), min(min_pos.z, p.z))
			max_pos = Vector3i(max(max_pos.x, p.x), max(max_pos.y, p.y), max(max_pos.z, p.z))
	
	return Vector3i(max_pos.x - min_pos.x + 1, max_pos.y - min_pos.y + 1, max_pos.z - min_pos.z + 1)
