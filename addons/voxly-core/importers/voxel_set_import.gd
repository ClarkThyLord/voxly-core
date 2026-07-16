@tool
extends EditorImportPlugin
## Imports palette files (.gpl, .json, .txt, .pal, .hex) as VoxelSet.
## Also imports image files (.png, .jpg, etc.) and .vox files as VoxelSet.
## The VoxelSet always imports the complete palette — for compact/reference
## options, use the VoxelModel3D importer instead.
##
## Import options:
##   - allow_repeated (bool): When disabled (default), duplicate color values
##     are skipped, keeping only unique colors in the resulting palette.
##     Enable to keep all color entries including duplicate values.

const DEBUG_CONTEXT := "VoxelSetImport"

func _get_visible_name() -> String:
	return "VoxelSet"

func _get_importer_name() -> String:
	return "Voxly-Core.VoxelSet"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["vox", "gpl", "json", "txt", "pal", "hex", "png", "bmp", "jpg", "jpeg", "tga"])

func _get_resource_type() -> String:
	return "Resource"

func _get_save_extension() -> String:
	return "tres"

func _get_preset_count() -> int:
	return 1

func _get_preset_name(preset: int) -> String:
	return "Default"

func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	var ext := path.get_extension().to_lower()
	var options: Array[Dictionary] = []
	
	# Allow repeated colors option (available for all palette/image formats)
	var is_palette_or_image := ext in ["gpl", "json", "txt", "pal", "hex", "png", "bmp", "jpg", "jpeg", "tga"]
	if is_palette_or_image:
		options.append({
			"name": "allow_repeated",
			"default_value": false,
			"usage": PROPERTY_USAGE_DEFAULT,
		})
	
	# If importing a .vox file as a set, add the import_mode option
	if path.ends_with(".vox"):
		options.append({
			"name": "import_mode",
			"default_value": 0,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "Palette Only,With Materials",
			"usage": PROPERTY_USAGE_DEFAULT,
		})
	
	return options

func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true

func _import(source_file: String, save_path: String, options: Dictionary, r_platform_variants: Array, r_gen_files: Array) -> int:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Importing file: '%s' -> '%s'" % [source_file, save_path])
	
	# Read the file
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Reading file with VoxlyReader...")
	var read_result := VoxlyReader.read_file(source_file, options)
	var error: int = read_result.get("error", ERR_FILE_CORRUPT)
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Failed to read file: error=%d" % error)
		return error
	
	# Create the VoxelSet
	var voxel_set := VoxelSet.new()
	
	# Add materials if present and import_mode >= 1
	var include_materials: bool = options.get("import_mode", 0) >= 1 or not source_file.get_extension().to_lower() == "vox"
	if include_materials and read_result.has("materials") and not read_result["materials"].is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Adding %d materials to VoxelSet" % read_result["materials"].size())
		var mat_dict: Dictionary = read_result["materials"]
		for mat_id in mat_dict:
			var mat_data: Dictionary = mat_dict[mat_id]
			var material := StandardMaterial3D.new()
			if mat_data.has("color"):
				material.albedo_color = mat_data["color"]
			if mat_data.has("metallic"):
				material.metallic = mat_data["metallic"]
			if mat_data.has("roughness"):
				material.roughness = mat_data["roughness"]
			if mat_data.has("emission"):
				material.emission = mat_data["emission"]
				material.emission_energy_multiplier = mat_data.get("emission_energy", 1.0)
			material.vertex_color_use_as_albedo = true
			voxel_set.set_material(str(mat_id), material)
	
	# Add voxels from palette (always full palette for VoxelSet import)
	if read_result.has("palette") and not read_result["palette"].is_empty():
		var palette: Dictionary = read_result["palette"]
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Adding %d palette entries to VoxelSet" % palette.size())
		for voxel_id in palette:
			var voxel: Voxel = palette[voxel_id]
			voxel_set.set_voxel(int(voxel_id), voxel)
	
	if voxel_set.get_voxels_count() == 0:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "No voxels in palette, returning EOF error")
		return ERR_FILE_EOF
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "VoxelSet created with %d voxels and %d materials, saving..." % [voxel_set.get_voxels_count(), voxel_set.get_materials_count()])
	
	# Save as .tres resource
	error = ResourceSaver.save(voxel_set, "%s.%s" % [save_path, _get_save_extension()])
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Failed to save VoxelSet: error=%d" % error)
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Successfully imported '%s'" % source_file)
	return error
