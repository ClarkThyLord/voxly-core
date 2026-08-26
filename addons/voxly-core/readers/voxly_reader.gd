@tool
class_name VoxlyReader
extends RefCounted
## Extension-based dispatcher that routes file reads to the appropriate reader.
##
## Usage:
## var result = VoxlyReader.read_file("path/to/model.vox")
## if result.error == OK:
##    print("Read ", result.voxels.size(), " voxels")
##
## Returned Dictionary format:
##   {
##    error: int,              # OK or error code
##    voxels: Dictionary,      # {Vector3i: int} — grid position -> voxel ID (optional)
##    palette: Dictionary,     # {int: Voxel} — voxel ID -> Voxel resource (optional)
##    materials: Dictionary,   # {int: Dictionary} — material ID -> material properties (optional)
##   }

const DEBUG_CONTEXT := "VoxlyReader"

## Reads a file by dispatching to the appropriate sub-reader based on extension.
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
static func read_file_as_voxel_set(file_path: String, options: Dictionary = {}) -> VoxelSet:
	var result := read_file(file_path, options)
	if result["error"] != OK:
		return null
	
	var voxel_set := VoxelSet.new()
	
	# Add materials if present
	if result.has("materials") and not result["materials"].is_empty():
		var palette: Dictionary = result.get("palette", {})
		var materials_dict: Dictionary = result["materials"]
		for mat_id in materials_dict:
			var mat_data: Dictionary = materials_dict[mat_id]
			var material := StandardMaterial3D.new()
			
			# Get palette color for this material
			var pal_idx := int(mat_id) - 1
			var palette_color := Color.WHITE
			if palette.has(pal_idx):
				var pal_voxel: Voxel = palette[pal_idx]
				palette_color = pal_voxel.base_color
			
			# Apply all MagicaVoxel material properties to Godot StandardMaterial3D
			VoxReader.apply_material_properties(material, mat_data, palette_color)
			
			material.vertex_color_use_as_albedo = true
			voxel_set.set_material(str(mat_id), material)
	
	# Add voxels from palette
	if result.has("palette") and not result["palette"].is_empty():
		var palette: Dictionary = result["palette"]
		for voxel_id in palette:
			var voxel: Voxel = palette[voxel_id]
			voxel_set.set_voxel(int(voxel_id), voxel)
	
	return voxel_set

## Shifts all voxel positions so the minimum corner becomes (0,0,0).
## Returns the shift amount (the original minimum position).
## Modifies the voxels dictionary in-place.
static func shift_voxels_to_non_negative(voxels: Dictionary) -> Vector3i:
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
## Returns Vector3i(1, 1, 1) for empty dictionaries.
static func calc_voxel_bounds(voxels: Dictionary) -> Vector3i:
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


## Creates a VoxelModel3D scene from a read result.
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
	
	model.update()
	
	var scene := PackedScene.new()
	scene.pack(model)
	return scene
