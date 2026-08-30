## Extension-based dispatcher that routes file reads to the appropriate reader.
##
## Usage:
## [codeblock]
## var result = VoxlyReader.read_file("path/to/model.vox")
## if result.error == OK:
##     print("Read ", result.voxels.size(), " voxels")
## [/codeblock]
##
## Returned Dictionary format:
## [codeblock]
## {
##   error: int,              # OK or error code
##   voxels: Dictionary,      # {Vector3i: int} grid position = voxel ID
##   palette: Dictionary,     # {int: Voxel} voxel ID = Voxel resource
##   materials: Dictionary,   # {int: Dictionary} material ID = material properties
## }
## [/codeblock]
@tool
class_name VoxlyReader
extends RefCounted

const _debug_context := "VoxlyReader"

## Reads a file by dispatching to the appropriate sub-reader based on extension.
static func read_file(file_path: String, options: Dictionary = {}) -> Dictionary:
	var result := { "error": ERR_FILE_UNRECOGNIZED }
	var extension := file_path.get_extension().to_lower()
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Reading file: '%s' (ext: %s)" % [file_path, extension])
	
	match extension:
		"vox":
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Dispatching to VoxReader for .vox file")
			result = VoxReader.read_file(file_path, options)
		
		"png", "bmp", "dds", "exr", "hdr", "jpg", "jpeg", "tga", "svg", "svgz", "webp":
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Dispatching to ImageReader for image file")
			result = ImageReader.read_file(file_path, options)
		
		"gpl", "txt", "json", "pal", "hex":
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Dispatching to PaletteReader for palette file")
			result = PaletteReader.read_file(file_path, options)
		
		_:
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Unrecognized file extension '%s'" % extension)
	
	if result and result.get("error", 1) == OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Successfully read file: %d voxels, %d palette entries, %d materials" % [
			result.get("voxels", {}).size(),
			result.get("palette", {}).size(),
			result.get("materials", {}).size(),
		])
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Failed to read file: error=%d" % result["error"])
	
	return result

## Reads a file and returns the result as a [VoxelSet] resource.
static func read_file_as_voxel_set(file_path: String, options: Dictionary = {}) -> VoxelSet:
	var result := read_file(file_path, options)
	if result["error"] != OK:
		return null
	
	var voxel_set := VoxelSet.new()
	
	# Add materials if present.
	if result.has("materials") and not result["materials"].is_empty():
		var palette: Dictionary = result.get("palette", {})
		var materials: Dictionary = result["materials"]
		for material_id in materials:
			var material_data: Dictionary = materials[material_id]
			var material := StandardMaterial3D.new()
			
			# Get the palette color for this material.
			var palette_index := int(material_id) - 1
			var palette_color := Color.WHITE
			if palette.has(palette_index):
				var palette_voxel: Voxel = palette[palette_index]
				palette_color = palette_voxel.base_color
			
			# Apply all MagicaVoxel material properties to the Godot material.
			VoxReader.apply_material_properties(material, material_data, palette_color)
			
			material.vertex_color_use_as_albedo = true
			voxel_set.set_material(str(material_id), material)
	
	# Add voxels from the palette.
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
	
	var min_position := Vector3i.ZERO
	var first := true
	for position in voxels:
		var typed_position: Vector3i = position
		if first:
			min_position = typed_position
			first = false
		else:
			min_position = Vector3i(mini(min_position.x, typed_position.x), mini(min_position.y, typed_position.y), mini(min_position.z, typed_position.z))
	
	if min_position == Vector3i.ZERO:
		return Vector3i.ZERO
	
	var shifted: Dictionary = {}
	for position in voxels:
		shifted[position - min_position] = voxels[position]
	voxels.clear()
	for position in shifted:
		voxels[position] = shifted[position]
	
	return min_position

## Calculates the bounding box size of voxels (max - min + 1).
## Returns [constant Vector3i.ONE] for empty dictionaries.
static func calc_voxel_bounds(voxels: Dictionary) -> Vector3i:
	if voxels.is_empty():
		return Vector3i(1, 1, 1)
	
	var min_position := Vector3i.ZERO
	var max_position := Vector3i.ZERO
	var first := true
	for position in voxels:
		var typed_position: Vector3i = position
		if first:
			min_position = typed_position
			max_position = typed_position
			first = false
		else:
			min_position = Vector3i(mini(min_position.x, typed_position.x), mini(min_position.y, typed_position.y), mini(min_position.z, typed_position.z))
			max_position = Vector3i(maxi(max_position.x, typed_position.x), maxi(max_position.y, typed_position.y), maxi(max_position.z, typed_position.z))
	
	return Vector3i(max_position.x - min_position.x + 1, max_position.y - min_position.y + 1, max_position.z - min_position.z + 1)

## Creates a [VoxelModel3D] scene from a read result.
static func read_result_to_scene(result: Dictionary, voxel_size: Vector3 = Vector3(0.5, 0.5, 0.5)) -> PackedScene:
	if result["error"] != OK or not result.has("voxels") or result["voxels"].is_empty():
		return null
	
	var model := VoxelModel3D.new()
	model.voxel_size = voxel_size
	
	if result.has("voxel_set"):
		model.voxel_set = result["voxel_set"]
	
	# Set voxels from the result.
	var voxels: Dictionary = result["voxels"]
	for grid_position in voxels:
		model.set_voxel(grid_position, voxels[grid_position])
	
	model.update()
	
	var scene := PackedScene.new()
	scene.pack(model)
	return scene
