## Imports voxel files (.vox, .png, .jpg, etc.) as a reusable static Mesh
## resource.
##
## The voxel content is baked into the mesh, so it is not editable voxel data.
## Unlike the VoxelModel3D importer, this produces a plain Mesh (ArrayMesh) that
## can be dropped onto any MeshInstance3D, CSGMesh, GridMap, or other mesh
## consumer.
@tool
extends VoxelNode3DImportPlugin

const __debug_context := "VoxelMeshImport"

## Returns the display name shown in the import dialog.
func _get_visible_name() -> String:
	return "Voxel Mesh"

## Returns the unique importer identifier.
func _get_importer_name() -> String:
	return "Voxly-Core.VoxelMesh"

## Returns the type of resource produced by this importer.
func _get_resource_type() -> String:
	return "Mesh"

## Returns the extension used for imported resources.
func _get_save_extension() -> String:
	return "mesh"

## Returns the import options shown in the import dialog for the given path.
func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = [
		{
			"name": "snap_to_ground",
			"default_value": false,
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
	# Image options only apply to image sources.
	if option_name in PackedStringArray(["alpha_threshold", "depth", "flip_x", "flip_y"]):
		return is_image_file(path)
	
	# Palette options only apply to non-image sources.
	if option_name in PackedStringArray(["palette_mode", "reference_voxel_set_path"]):
		return not is_image_file(path)
	
	return true

## Imports the source file into a Mesh resource and saves it to the destination path.
func _import(source_file: String, save_path: String, options: Dictionary, r_platform_variants: Array, r_gen_files: Array) -> int:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Importing file: '%s' -> '%s'" % [source_file, save_path])
	
	# Read the file and build the VoxelSet.
	var content := read_voxel_content(source_file, options)
	if content["error"] != OK:
		return content["error"]
	
	var voxel_set: VoxelSet = content["voxel_set"]
	var voxels: Dictionary = content["voxels"]
	
	if voxels.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "No voxels available, aborting")
		return ERR_FILE_EOF
	
	# Optionally snap the lowest voxel to the Y=0 ground plane.
	voxels = maybe_snap_voxels_to_ground(voxels, options.get("snap_to_ground", false))
	
	# Build the mesh using the configured mesh_mode.
	var mesh := build_array_mesh(voxels, voxel_set, options)
	if mesh.get_surface_count() == 0:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Mesh built with no surfaces, aborting")
		return ERR_CANT_CREATE
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Saving Mesh to '%s.%s'..." % [save_path, _get_save_extension()])
	var error := ResourceSaver.save(mesh, "%s.%s" % [save_path, _get_save_extension()])
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Failed to save Mesh: error=%d" % error)
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, __debug_context, "Successfully imported '%s' as Voxel Mesh" % source_file)
	
	return error
