## Imports voxel files (.vox, .png, .jpg) as a singular [VoxelNode3D] node or
## composed scenes.
@tool
extends VoxelNode3DImportPlugin

const __debug_context := "VoxelModel3DImport"

## Returns the display name shown in the import dialog.
func _get_visible_name() -> String:
	return "VoxelModel3D"

## Returns the unique importer identifier.
func _get_importer_name() -> String:
	return "Voxly-Core.VoxelModel3D"

## Returns the import options shown in the import dialog for the given path.
func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
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
	
	# Image-specific import options.
	if is_image_file(path):
		options.append_array(get_image_import_options())
	
	options.append_array(get_shared_options(preset_index))
	return options

## Controls whether the given import option is visible.
func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	# Hide palette_mode and related options for image files.
	var image_only_opts := PackedStringArray(["alpha_threshold", "depth", "flip_x", "flip_y"])
	if option_name in image_only_opts:
		return is_image_file(path)
	
	# Show palette_mode only for non-image files.
	if option_name in PackedStringArray(["palette_mode", "reference_voxel_set_path"]):
		return not is_image_file(path)
	
	return true

## Imports the source file into a VoxelModel3D scene and saves it.
func _import(source_file: String, save_path: String, options: Dictionary, r_platform_variants: Array, r_gen_files: Array) -> int:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Importing file: '%s' -> '%s'" % [source_file, save_path])
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Import options: %s" % options)
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Reading file with VoxlyReader...")
	var read_result := VoxlyReader.read_file(source_file, options)
	var error: int = read_result.get("error", ERR_FILE_CORRUPT)
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Failed to read file: error=%d" % error)
		return error
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Read result: voxels=%d, palette=%d, materials=%d" % [
		read_result.get("voxels", {}).size(),
		read_result.get("palette", {}).size(),
		read_result.get("materials", {}).size(),
	])
	
	# Collect palette_mode and palette options.
	var palette_mode: int = options.get("palette_mode", PaletteMode.FULL)
	var reference_path: String = options.get("reference_voxel_set_path", "")
	
	# Collect used voxel IDs for Compact mode.
	var used_voxel_ids: Array = []
	if palette_mode == PaletteMode.COMPACT:
		var all_voxels: Dictionary = read_result.get("voxels", {})
		var seen: Dictionary = {}
		for position in all_voxels:
			var voxel_id: int = all_voxels[position]
			if not seen.has(voxel_id):
				seen[voxel_id] = true
				used_voxel_ids.append(voxel_id)
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Compact mode: %d unique palette IDs used by %d voxels" % [used_voxel_ids.size(), all_voxels.size()])
	
	# Create the VoxelSet.
	var voxel_set: VoxelSet = null
	
	if palette_mode == PaletteMode.REFERENCE:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Reference mode: loading VoxelSet from '%s'" % reference_path)
		voxel_set = create_voxel_set(read_result, palette_mode, [], reference_path)
		if voxel_set == null:
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Failed to load reference VoxelSet, aborting")
			return ERR_FILE_CANT_OPEN
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Creating VoxelSet from read result (mode: %s)..." % ["Full", "Compact"][palette_mode])
		voxel_set = create_voxel_set(read_result, palette_mode, used_voxel_ids)
	
	if voxel_set:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "VoxelSet ready with %d voxels and %d materials" % [
			voxel_set.get_voxels_count(),
			voxel_set.get_materials_count(),
		])
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "No VoxelSet available, aborting")
		return ERR_FILE_CANT_OPEN
	
	# Create the root node.
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Creating root node...")
	var name: String = options.get("name", "")
	if name.is_empty():
		name = source_file.get_file().replace("." + source_file.get_extension(), "")
	
	var voxel_size_value: float = options.get("voxel_size", 0.5)
	var mesh_mode_value: int = options.get("mesh_mode", 2) # GREEDY
	var import_mode: int = options.get("import_mode", 0) # 0=Merged, 1=Hierarchical
	var bounds_mode: int = options.get("bounds_mode", 0) # 0=Fit to Voxels, 1=Original Chunk Size
	
	# Get the scene models from the reader.
	var scene_models: Array = read_result.get("scene_models", [])
	var model: Node
	
	if import_mode == 1 and scene_models.size() > 0:
		# Hierarchical: Node3D parent with a child VoxelModel3D per scene model.
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Hierarchical import with %d scene models" % scene_models.size())
		
		var parent := Node3D.new()
		parent.name = name
		
		for i in scene_models.size():
			var scene_model: Dictionary = scene_models[i]
			var scene_model_voxels: Dictionary = scene_model["voxels"].duplicate()
			
			var child_shift := VoxlyReader.shift_voxels_to_non_negative(scene_model_voxels)
			
			var child := VoxelModel3D.new()
			var scene_name: String = scene_model.get("name", "")
			if scene_name.is_empty():
				child.name = "Model_%d" % i
			else:
				child.name = scene_name
			child.voxel_set = voxel_set
			child.voxel_size = Vector3(voxel_size_value, voxel_size_value, voxel_size_value)
			child.mesh_mode = mesh_mode_value as VoxelNode3D.MeshMode
			child.include_vertex_colors = options.get("include_vertex_colors", true)
			child.include_textures = options.get("include_textures", true)
			
			# Determine the shape based on bounds_mode.
			if bounds_mode == 1 and scene_model.has("size"):
				# Original Chunk Size: use the original SIZE chunk dimensions.
				var original_size: Vector3i = scene_model["size"]
				var fitted := VoxlyReader.calc_voxel_bounds(scene_model_voxels)
				# Ensure the shape is at least as large as the actual voxel bounds.
				child.shape = Vector3i(
					maxi(original_size.x, fitted.x),
					maxi(original_size.y, fitted.y),
					maxi(original_size.z, fitted.z)
				)
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Original chunk size: %s, fitted: %s -> shape=%s" % [original_size, fitted, child.shape])
			else:
				# Fit to Voxels: tight bounding of actual voxel positions.
				child.shape = VoxlyReader.calc_voxel_bounds(scene_model_voxels)
			
			child.origin = Vector3(child_shift)
			
			for position in scene_model_voxels:
				child.set_voxel(position, scene_model_voxels[position])
			
			parent.add_child(child)
			child.owner = parent
			child.update()
			# Override the MeshInstance3D owner from the parent back to the child
			# so PackedScene.pack correctly serializes the grandchild tree.
			for grandchild in child.get_children():
				grandchild.owner = parent
		
		model = parent
	
	else:
		# Merged: a single VoxelModel3D with all voxels merged together.
		var flat_voxels: Dictionary = read_result.get("voxels", {}).duplicate()
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Merged import with %d voxels" % flat_voxels.size())
		
		var single := VoxelModel3D.new()
		single.name = name
		single.voxel_set = voxel_set
		single.voxel_size = Vector3(voxel_size_value, voxel_size_value, voxel_size_value)
		single.mesh_mode = mesh_mode_value as VoxelNode3D.MeshMode
		single.include_vertex_colors = options.get("include_vertex_colors", true)
		single.include_textures = options.get("include_textures", true)
		
		if not flat_voxels.is_empty():
			var shift := VoxlyReader.shift_voxels_to_non_negative(flat_voxels)
			single.shape = VoxlyReader.calc_voxel_bounds(flat_voxels)
			single.origin = Vector3(shift)
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Shift applied: origin=%s shape=%s" % [single.origin, single.shape])
		
		for position in flat_voxels:
			single.set_voxel(position, flat_voxels[position])
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Rebuilding mesh (%d voxels set)..." % flat_voxels.size())
		single.update()
		# Ensure the MeshInstance3D child is owned by the model so
		# PackedScene.pack() includes it in the serialized scene.
		for child in single.get_children():
			child.owner = single
		model = single
	
	# Pack into a scene.
	var scene := PackedScene.new()
	error = scene.pack(model)
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Failed to pack scene: error=%d" % error)
		model.free()
		return error
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Saving scene to '%s.%s'..." % [save_path, _get_save_extension()])
	error = ResourceSaver.save(scene, "%s.%s" % [save_path, _get_save_extension()])
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Failed to save scene: error=%d" % error)
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Successfully imported '%s'" % source_file)
	
	model.free()
	return error
