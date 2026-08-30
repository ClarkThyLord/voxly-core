## Imports palette files (.gpl, .json, .txt, .pal, .hex) as a VoxelSet.
## Also imports image files (.png, .jpg, etc.) and .vox files as a VoxelSet.
## The VoxelSet always imports the complete palette; for compact/reference
## options, use the VoxelModel3D importer instead.
@tool
extends EditorImportPlugin

const __debug_context := "VoxelSetImport"

## Returns the display name shown in the import dialog.
func _get_visible_name() -> String:
	return "VoxelSet"

## Returns the unique importer identifier.
func _get_importer_name() -> String:
	return "Voxly-Core.VoxelSet"

## Returns the file extensions this importer handles.
func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["vox", "gpl", "json", "txt", "pal", "hex", "png", "bmp", "jpg", "jpeg", "tga"])

## Returns the type of resource produced by this importer.
func _get_resource_type() -> String:
	return "Resource"

## Returns the extension used for imported resources.
func _get_save_extension() -> String:
	return "tres"

## Returns the number of import presets offered.
func _get_preset_count() -> int:
	return 1

## Returns the display name of the given import preset.
func _get_preset_name(preset: int) -> String:
	return "Default"

## Returns the import options shown in the import dialog for the given path.
func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	var extension := path.get_extension().to_lower()
	var options: Array[Dictionary] = []
	
	# Allow repeated colors option.
	var is_palette_or_image := extension in ["gpl", "json", "txt", "pal", "hex", "png", "bmp", "jpg", "jpeg", "tga"]
	if is_palette_or_image:
		options.append({
			"name": "allow_repeated",
			"default_value": false,
			"usage": PROPERTY_USAGE_DEFAULT,
		})
	
	# If importing a .vox file as a set.
	if path.ends_with(".vox"):
		options.append({
			"name": "import_mode",
			"default_value": 0,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "Palette Only,With Materials",
			"usage": PROPERTY_USAGE_DEFAULT,
		})
	
	return options

## Controls whether the given import option is visible.
func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true

## Imports the source file into a VoxelSet resource and saves it to the destination path.
func _import(source_file: String, save_path: String, options: Dictionary, r_platform_variants: Array, r_gen_files: Array) -> int:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Importing file: '%s' -> '%s'" % [source_file, save_path])
	
	# Read the file.
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Reading file with VoxlyReader...")
	var read_result := VoxlyReader.read_file(source_file, options)
	var error: int = read_result.get("error", ERR_FILE_CORRUPT)
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Failed to read file: error=%d" % error)
		return error
	
	# Create the VoxelSet.
	var voxel_set := VoxelSet.new()
	
	# Add materials if present and import_mode >= 1.
	var include_materials: bool = options.get("import_mode", 0) >= 1 or not source_file.get_extension().to_lower() == "vox"
	if include_materials and read_result.has("materials") and not read_result["materials"].is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Adding %d materials to VoxelSet" % read_result["materials"].size())
		var materials: Dictionary = read_result["materials"]
		var palette: Dictionary = read_result.get("palette", {})
		for material_id in materials:
			var material_data: Dictionary = materials[material_id]
			var material := StandardMaterial3D.new()
			
			# Get the palette color for this material (MATL material_ids are
			# 1-indexed, palette keys are 0-indexed).
			var palette_index := int(material_id) - 1
			var palette_color := Color.WHITE
			if palette.has(palette_index):
				var palette_voxel: Voxel = palette[palette_index]
				palette_color = palette_voxel.base_color
			
			# Apply all MagicaVoxel material properties to the Godot material.
			VoxReader.apply_material_properties(material, material_data, palette_color)
			
			material.vertex_color_use_as_albedo = true
			voxel_set.set_material(str(material_id), material)
	
	# Add voxels from the palette (always the full palette for VoxelSet import).
	if read_result.has("palette") and not read_result["palette"].is_empty():
		var palette: Dictionary = read_result["palette"]
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Adding %d palette entries to VoxelSet" % palette.size())
		for voxel_id in palette:
			var voxel: Voxel = palette[voxel_id]
			voxel_set.set_voxel(int(voxel_id), voxel)
	
	if voxel_set.get_voxels_count() == 0:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "No voxels in palette, returning EOF error")
		return ERR_FILE_EOF
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "VoxelSet created with %d voxels and %d materials, saving..." % [voxel_set.get_voxels_count(), voxel_set.get_materials_count()])
	
	# Save as a .tres resource.
	error = ResourceSaver.save(voxel_set, "%s.%s" % [save_path, _get_save_extension()])
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Failed to save VoxelSet: error=%d" % error)
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Successfully imported '%s'" % source_file)
	return error
