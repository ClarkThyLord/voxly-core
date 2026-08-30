## Base class for all VoxelNode3D import plugins.
## Provides shared import options like voxel_size, mesh_mode, and palette mode.
@tool
@abstract
class_name VoxelNode3DImportPlugin
extends EditorImportPlugin

const _debug_context := "VoxelNode3DImportPlugin"

## Import presets offered by this importer.
enum Presets {
	DEFAULT,
}

## How the voxel palette is written into the imported scene.
enum PaletteMode {
	FULL = 0,
	COMPACT = 1,
	REFERENCE = 2,
}

## Returns the display name of the given import preset.
func _get_preset_name(preset: int) -> String:
	return Presets.keys()[preset].capitalize() if preset < Presets.size() else "Unknown"

## Returns the number of import presets offered.
func _get_preset_count() -> int:
	return Presets.size()

## Returns the file extensions this importer handles.
func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["vox", "png", "jpg", "jpeg", "bmp", "tga", "webp", "dds", "exr", "hdr", "svg", "svgz"])

## Returns the type of resource produced by this importer.
func _get_resource_type() -> String:
	return "PackedScene"

## Returns the extension used for imported resources.
func _get_save_extension() -> String:
	return "tscn"

## Returns the shared import options array.
## Subclasses should call this and append their own options.
func get_shared_options(preset: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = [
		{
			"name": "palette_mode",
			"default_value": PaletteMode.FULL,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "Full,Compact,Reference",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "reference_voxel_set_path",
			"default_value": "",
			"property_hint": PROPERTY_HINT_FILE,
			"hint_string": "*.tres,*.res,*.vox",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "mesh_mode",
			"default_value": VoxelNode3D.MeshMode.GREEDY,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "Brute,Naive,Greedy",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "voxel_size",
			"default_value": 0.5,
			"property_hint": PROPERTY_HINT_RANGE,
			"hint_string": "0.01, 1.0, 0.01",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "include_vertex_colors",
			"default_value": true,
			"property_hint": PROPERTY_HINT_NONE,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "include_textures",
			"default_value": true,
			"property_hint": PROPERTY_HINT_NONE,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
	]
	
	# Only the DEFAULT preset for now.
	match preset:
		Presets.DEFAULT:
			pass
	
	return options

## Returns true if the given file path has a recognized image extension.
static func is_image_file(path: String) -> bool:
	var extension := path.get_extension().to_lower()
	return extension in PackedStringArray(["png", "jpg", "jpeg", "bmp", "tga", "webp", "dds", "exr", "hdr", "svg", "svgz"])

## Returns the import options specific to image files.
## Shown only for image sources and passed through to [ImageReader].
static func get_image_import_options() -> Array[Dictionary]:
	return [
		{
			"name": "alpha_threshold",
			"default_value": 0.1,
			"property_hint": PROPERTY_HINT_RANGE,
			"hint_string": "0.0, 1.0, 0.01",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "depth",
			"default_value": 1,
			"property_hint": PROPERTY_HINT_RANGE,
			"hint_string": "1, 64, 1",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "flip_x",
			"default_value": false,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "flip_y",
			"default_value": false,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
	]

## Collects the unique voxel IDs present in a voxel dictionary, in first-seen
## order. Used for Compact palette mode.
static func collect_used_voxel_ids(voxels: Dictionary) -> Array:
	var used: Array = []
	var seen: Dictionary = {}
	for position in voxels:
		var voxel_id: int = voxels[position]
		if not seen.has(voxel_id):
			seen[voxel_id] = true
			used.append(voxel_id)
	return used

## Reads a source file and builds a VoxelSet plus the flattened voxel
## dictionary. Handles Full/Compact/Reference palette modes.
## Returns {"error": int, "voxel_set": VoxelSet, "voxels": Dictionary}.
func read_voxel_content(source_file: String, options: Dictionary) -> Dictionary:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Reading file: '%s'" % source_file)
	var read_result := VoxlyReader.read_file(source_file, options)
	var error: int = read_result.get("error", ERR_FILE_CORRUPT)
	if error != OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Failed to read file: error=%d" % error)
		return { "error": error, "voxel_set": null, "voxels": {} }
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Read result: voxels=%d, palette=%d, materials=%d" % [
		read_result.get("voxels", {}).size(),
		read_result.get("palette", {}).size(),
		read_result.get("materials", {}).size(),
	])
	
	var palette_mode: int = options.get("palette_mode", PaletteMode.FULL)
	var reference_path: String = options.get("reference_voxel_set_path", "")
	
	var used_voxel_ids: Array = []
	if palette_mode == PaletteMode.COMPACT:
		used_voxel_ids = collect_used_voxel_ids(read_result.get("voxels", {}))
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Compact mode: %d unique palette IDs used by %d voxels" % [used_voxel_ids.size(), read_result.get("voxels", {}).size()])
	
	var voxel_set: VoxelSet = null
	if palette_mode == PaletteMode.REFERENCE:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Reference mode: loading VoxelSet from '%s'" % reference_path)
		voxel_set = create_voxel_set(read_result, palette_mode, [], reference_path)
		if voxel_set == null:
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Failed to load reference VoxelSet, aborting")
			return { "error": ERR_FILE_CANT_OPEN, "voxel_set": null, "voxels": {} }
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Creating VoxelSet from read result (mode: %s)..." % ["Full", "Compact"][palette_mode])
		voxel_set = create_voxel_set(read_result, palette_mode, used_voxel_ids)
		if voxel_set == null:
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Failed to create VoxelSet, aborting")
			return { "error": ERR_FILE_CANT_OPEN, "voxel_set": null, "voxels": {} }
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "VoxelSet ready with %d voxels and %d materials" % [
		voxel_set.get_voxels_count(),
		voxel_set.get_materials_count(),
	])
	
	return {
		"error": OK,
		"voxel_set": voxel_set,
		"voxels": read_result.get("voxels", {}),
	}

## Builds an [ArrayMesh] from a flat voxel dictionary using the current
## [VoxelMesher]. The mesh_mode option selects the meshing algorithm
## (Brute/Naive/Greedy). The voxels dictionary is converted to a typed
## [code]Dictionary[Vector3i, int][/code] because the mesher's methods require
## typed dictionaries.
static func build_array_mesh(voxels: Dictionary, voxel_set: VoxelSet, options: Dictionary) -> ArrayMesh:
	var voxel_size_value: float = options.get("voxel_size", 0.5)
	var mesh_mode: int = options.get("mesh_mode", VoxelNode3D.MeshMode.GREEDY)
	
	# Convert to a typed dictionary.
	var typed_voxels: Dictionary[Vector3i, int] = {}
	for position in voxels:
		typed_voxels[position] = voxels[position]
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, _debug_context, "Building ArrayMesh: %d voxels, mesh_mode=%d, voxel_size=%.2f" % [typed_voxels.size(), mesh_mode, voxel_size_value])
	
	var mesher := VoxelMesher.create()
	mesher.begin(
		Vector3(voxel_size_value, voxel_size_value, voxel_size_value),
		voxel_set,
		options.get("include_vertex_colors", true),
		options.get("include_textures", true)
	)
	
	match mesh_mode:
		VoxelNode3D.MeshMode.BRUTE:
			mesher.add_all_faces(typed_voxels)
		VoxelNode3D.MeshMode.NAIVE:
			mesher.add_culled_faces(typed_voxels)
		_: # GREEDY default.
			mesher.add_greedy_faces(typed_voxels)
	
	var mesh := mesher.commit()
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, _debug_context, "Mesh built: %d surfaces" % mesh.get_surface_count())
	return mesh

## Returns a copy of the voxel dictionary shifted so the lowest voxel rests on
## the Y=0 plane. Returns the dictionary unchanged when snapping is disabled.
static func maybe_snap_voxels_to_ground(voxels: Dictionary, enable_snap: bool) -> Dictionary:
	if not enable_snap or voxels.is_empty():
		return voxels
	
	var min_y := 0
	var first := true
	for position in voxels:
		var typed_position: Vector3i = position
		if first:
			min_y = typed_position.y
			first = false
		else:
			min_y = mini(min_y, typed_position.y)
	
	if min_y == 0:
		return voxels
	
	var shifted: Dictionary = {}
	for position in voxels:
		var typed_position: Vector3i = position
		shifted[Vector3i(typed_position.x, typed_position.y - min_y, typed_position.z)] = voxels[position]
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Snapped voxels to ground: min_y=%d, shifted %d voxels" % [min_y, shifted.size()])
	return shifted

## Creates a VoxelSet from a reader result's palette and materials.
## palette_mode controls which palette entries are included:
## - FULL: all palette entries and materials
## - COMPACT: only palette entries referenced by the voxel IDs in used_voxel_ids
## - REFERENCE: loads an existing VoxelSet from the given reference_path
func create_voxel_set(read_result: Dictionary, palette_mode: int = PaletteMode.FULL, used_voxel_ids: Array = [], reference_path: String = "") -> VoxelSet:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Creating VoxelSet (mode=%d)" % palette_mode)
	
	# Reference mode: load from an external file.
	if palette_mode == PaletteMode.REFERENCE:
		if reference_path.is_empty():
			push_error("VoxelNode3DImport: Reference mode selected but no reference_voxel_set_path provided")
			return null
		
		var extension := reference_path.get_extension().to_lower()
		if extension == "vox":
			# Load the .vox file as a VoxelSet using the reader.
			var set_result := VoxlyReader.read_file_as_voxel_set(reference_path)
			if set_result:
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Loaded reference VoxelSet from .vox: %s" % reference_path)
				return set_result
			push_error("VoxelNode3DImport: Failed to read reference .vox file: '%s'" % reference_path)
			return null
		else:
			# Load the .tres or .res resource directly.
			var loaded := ResourceLoader.load(reference_path, "VoxelSet")
			if loaded is VoxelSet:
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Loaded reference VoxelSet: %s" % reference_path)
				return loaded
			push_error("VoxelNode3DImport: Failed to load reference VoxelSet: '%s'" % reference_path)
			return null
	
	# Full or Compact: create a new VoxelSet from the read result.
	var voxel_set := VoxelSet.new()
	
	# Determine which palette/materials to include.
	var palette: Dictionary = read_result.get("palette", {})
	var materials: Dictionary = read_result.get("materials", {})
	
	# If compact mode, build a set of IDs to keep.
	if palette_mode == PaletteMode.COMPACT and not used_voxel_ids.is_empty():
		var used_set: Dictionary = {} # Use a dict for O(1) lookup.
		for voxel_id in used_voxel_ids:
			used_set[voxel_id] = true
		
		# Filter the palette to only used entries.
		var filtered_palette: Dictionary = {}
		for voxel_id in palette:
			if used_set.has(int(voxel_id)):
				filtered_palette[voxel_id] = palette[voxel_id]
		palette = filtered_palette
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Compact palette: %d entries kept from %d" % [palette.size(), read_result.get("palette", {}).size()])
		
		# Filter materials to only those referenced by kept palette entries.
		var needed_material_ids: Dictionary = {}
		for voxel_id in palette:
			var voxel: Voxel = palette[voxel_id]
			if voxel and not voxel.base_material_id.is_empty():
				needed_material_ids[voxel.base_material_id] = true
		
		var filtered_materials: Dictionary = {}
		for material_id in materials:
			if needed_material_ids.has(str(material_id)):
				filtered_materials[material_id] = materials[material_id]
		materials = filtered_materials
	
	# Add materials.
	if not materials.is_empty():
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
			
			if material_data.has("emission"):
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "Material %d: emission enabled, type=%s, energy=%.2f" % [material_id, material_data.get("type", "?"), material.emission_energy_multiplier])
	
	# Add voxels from the palette.
	if not palette.is_empty():
		for voxel_id in palette:
			var voxel: Voxel = palette[voxel_id]
			voxel_set.set_voxel(int(voxel_id), voxel)
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, _debug_context, "VoxelSet created: %d voxels, %d materials" % [voxel_set.get_voxels_count(), voxel_set.get_materials_count()])
	return voxel_set
