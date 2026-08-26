@tool
extends VoxelNode3DImportPlugin
## Imports voxel files (.vox, .png, .jpg, etc.) as a reusable static Mesh resource.
##
## The voxel content is baked into the mesh, as such is not editable voxel data.
## Unlike the VoxelModel3D importer, this produces a plain Mesh (ArrayMesh) that
## can be dropped onto any MeshInstance3D, CSGMesh, GridMap, or other mesh consumer.

func _init() -> void:
	DEBUG_CONTEXT = "VoxelMeshImport"

func _get_visible_name() -> String:
	return "Voxel Mesh"

func _get_importer_name() -> String:
	return "Voxly-Core.VoxelMesh"

func _get_resource_type() -> String:
	return "Mesh"

func _get_save_extension() -> String:
	return "mesh"

func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = [
		{
			"name": "snap_to_ground",
			"default_value": false,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
	]
	
	# Image-specific import options
	if is_image_file(path):
		options.append_array(get_image_import_options())
	
	options.append_array(get_shared_options(preset_index))
	return options

func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	# Image options only apply to image sources
	if option_name in PackedStringArray(["alpha_threshold", "depth", "flip_x", "flip_y"]):
		return is_image_file(path)
	
	# Palette options only apply to non-image sources
	if option_name in PackedStringArray(["palette_mode", "reference_voxel_set_path"]):
		return not is_image_file(path)
	
	return true

func _import(source_file: String, save_path: String, options: Dictionary, r_platform_variants: Array, r_gen_files: Array) -> int:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Importing file: '%s' -> '%s'" % [source_file, save_path])
	
	# Read the file and build the VoxelSet
	var content := read_voxel_content(source_file, options)
	if content["error"] != OK:
		return content["error"]
	
	var voxel_set: VoxelSet = content["voxel_set"]
	var voxels: Dictionary = content["voxels"]
	
	if voxels.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "No voxels available, aborting")
		return ERR_FILE_EOF
	
	# Optionally snap lowest voxel to the Y=0 ground plane.
	voxels = maybe_snap_voxels_to_ground(voxels, options.get("snap_to_ground", false))
	
	# Build the mesh using the configured mesh_mode.
	var mesh := build_array_mesh(voxels, voxel_set, options)
	if mesh.get_surface_count() == 0:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Mesh built with no surfaces, aborting")
		return ERR_CANT_CREATE
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Saving Mesh to '%s.%s'..." % [save_path, _get_save_extension()])
	var error := ResourceSaver.save(mesh, "%s.%s" % [save_path, _get_save_extension()])
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Failed to save Mesh: error=%d" % error)
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Successfully imported '%s' as Voxel Mesh" % source_file)
	
	return error
