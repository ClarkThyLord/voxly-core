@tool
class_name VoxlyReader
extends RefCounted
## Extension-based dispatcher that routes file reads to the appropriate reader.
##
## Usage:
##   var result = VoxlyReader.read_file("path/to/model.vox")
##   if result.error == OK:
##       print("Read ", result.voxels.size(), " voxels")
##
## Returned Dictionary format:
##   {
##       error: int,              # OK or error code
##       voxels: Dictionary,      # {Vector3i: int} — grid position -> voxel ID (optional)
##       palette: Dictionary,     # {int: Voxel} — voxel ID -> Voxel resource (optional)
##       materials: Dictionary,   # {int: Dictionary} — material ID -> material properties (optional)
##   }

const DEBUG_CONTEXT := "VoxlyReader"

## Reads a file by dispatching to the appropriate sub-reader based on extension.
## @param file_path: Path to the file to read
## @param options: Optional dictionary of reader-specific options
## @return: Dictionary with read results
static func read_file(file_path: String, options: Dictionary = {}) -> Dictionary:
	var result := { "error": ERR_FILE_UNRECOGNIZED }
	var ext := file_path.get_extension().to_lower()
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Reading file: '%s' (ext: %s)" % [file_path, ext])
	
	match ext:
		"vox":
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Dispatching to VoxReader for .vox file")
			result = VoxReader.read_file(file_path, options)
		
		"png", "bmp", "dds", "exr", "hdr", "jpg", "jpeg", "tga", "svg", "svgz", "webp":
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Dispatching to ImageReader for image file")
			result = ImageReader.read_file(file_path, options)
		
		"gpl", "txt", "json", "pal", "hex":
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Dispatching to PaletteReader for palette file")
			result = PaletteReader.read_file(file_path, options)
		
		_:
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Unrecognized file extension '%s'" % ext)
	
	if result and result.get("error", 1) == OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Successfully read file: %d voxels, %d palette entries, %d materials" % [
			result.get("voxels", {}).size(),
			result.get("palette", {}).size(),
			result.get("materials", {}).size(),
		])
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Failed to read file: error=%d" % result["error"])
	
	return result

## Reads a file and returns the result as a VoxelSet resource.
## @param file_path: Path to the file to read
## @param options: Optional reader-specific options dictionary
## @return: VoxelSet resource if successful, null otherwise
static func read_file_as_voxel_set(file_path: String, options: Dictionary = {}) -> VoxelSet:
	var result := read_file(file_path, options)
	if result["error"] != OK:
		return null
	
	var voxel_set := VoxelSet.new()
	
	# Add materials if present
	if result.has("materials") and not result["materials"].is_empty():
		var materials_dict: Dictionary = result["materials"]
		for mat_id in materials_dict:
			var mat_data: Dictionary = materials_dict[mat_id]
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
	
	# Add voxels from palette
	if result.has("palette") and not result["palette"].is_empty():
		var palette: Dictionary = result["palette"]
		for voxel_id in palette:
			var voxel: Voxel = palette[voxel_id]
			voxel_set.set_voxel(int(voxel_id), voxel)
	
	return voxel_set

## Creates a VoxelModel3D scene from a read result.
## @param result: Dictionary returned by read_file()
## @return: PackedScene if voxels exist, null otherwise
static func read_result_to_scene(result: Dictionary, voxel_size: Vector3 = Vector3(0.5, 0.5, 0.5)) -> PackedScene:
	if result["error"] != OK or not result.has("voxels") or result["voxels"].is_empty():
		return null
	
	var model := VoxelModel3D.new()
	model.voxel_size = voxel_size
	
	if result.has("voxel_set"):
		model.voxel_set = result["voxel_set"]
	
	# Set voxels from result
	var voxels: Dictionary = result["voxels"]
	for grid_pos in voxels:
		model.set_voxel(grid_pos, voxels[grid_pos])
	
	model.update_mesh()
	
	var scene := PackedScene.new()
	scene.pack(model)
	return scene
