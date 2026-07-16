@tool
@abstract
class_name VoxelNode3DImportPlugin
extends EditorImportPlugin
## Base class for all VoxelNode3D import plugins.
## Provides shared import options like voxel_size, mesh_mode,
## and palette mode (Full, Compact, Reference).

var DEBUG_CONTEXT := "VoxelNode3DImportPlugin"

enum Presets {
	DEFAULT,
}

enum PaletteMode {
	FULL = 0,
	COMPACT = 1,
	REFERENCE = 2,
}

func _get_preset_name(preset: int) -> String:
	return Presets.keys()[preset].capitalize() if preset < Presets.size() else "Unknown"

func _get_preset_count() -> int:
	return Presets.size()

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["vox", "png", "jpg", "jpeg", "bmp", "tga", "webp"])

func _get_resource_type() -> String:
	return "PackedScene"

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
			"name": "voxels_colored",
			"default_value": true,
			"property_hint": PROPERTY_HINT_NONE,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "voxels_textured",
			"default_value": true,
			"property_hint": PROPERTY_HINT_NONE,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
	]
	
	# Only DEFAULT preset for now
	match preset:
		Presets.DEFAULT:
			pass
	
	return options

## Creates a VoxelSet from a reader result's palette and materials.
## palette_mode controls which palette entries are included:
##   FULL      - All palette entries and materials (current default behavior)
##   COMPACT   - Only palette entries referenced by the voxel IDs in used_voxel_ids
##   REFERENCE - Loads an existing VoxelSet from the given reference_path
func create_voxel_set(read_result: Dictionary, palette_mode: int = PaletteMode.FULL, used_voxel_ids: Array = [], reference_path: String = "") -> VoxelSet:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Creating VoxelSet (mode=%d)" % palette_mode)
	
	# Reference mode: load from external file
	if palette_mode == PaletteMode.REFERENCE:
		if reference_path.is_empty():
			push_error("VoxelNode3DImport: Reference mode selected but no reference_voxel_set_path provided")
			return null
		
		var ext := reference_path.get_extension().to_lower()
		if ext == "vox":
			# Load .vox file as a VoxelSet using the reader
			var set_result := VoxlyReader.read_file_as_voxel_set(reference_path)
			if set_result:
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Loaded reference VoxelSet from .vox: %s" % reference_path)
				return set_result
			push_error("VoxelNode3DImport: Failed to read reference .vox file: '%s'" % reference_path)
			return null
		else:
			# Load .tres or .res resource directly
			var loaded := ResourceLoader.load(reference_path, "VoxelSet")
			if loaded is VoxelSet:
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Loaded reference VoxelSet: %s" % reference_path)
				return loaded
			push_error("VoxelNode3DImport: Failed to load reference VoxelSet: '%s'" % reference_path)
			return null
	
	# Full or Compact: create a new VoxelSet from the read result
	var voxel_set := VoxelSet.new()
	
	# Determine which palette/materials to include
	var palette: Dictionary = read_result.get("palette", {})
	var materials_dict: Dictionary = read_result.get("materials", {})
	
	# If compact mode, build a set of IDs to keep
	if palette_mode == PaletteMode.COMPACT and not used_voxel_ids.is_empty():
		var used_set: Dictionary = {} # Use dict for O(1) lookup
		for vid in used_voxel_ids:
			used_set[vid] = true
		
		# Filter palette to only used entries
		var filtered_palette: Dictionary = {}
		for voxel_id in palette:
			if used_set.has(int(voxel_id)):
				filtered_palette[voxel_id] = palette[voxel_id]
		palette = filtered_palette
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "Compact palette: %d entries kept from %d" % [palette.size(), read_result.get("palette", {}).size()])
		
		# Filter materials to only those referenced by kept palette entries
		var needed_material_ids: Dictionary = {}
		for voxel_id in palette:
			var voxel: Voxel = palette[voxel_id]
			if voxel and not voxel.base_material_id.is_empty():
				needed_material_ids[voxel.base_material_id] = true
		
		var filtered_materials: Dictionary = {}
		for mat_id in materials_dict:
			if needed_material_ids.has(str(mat_id)):
				filtered_materials[mat_id] = materials_dict[mat_id]
		materials_dict = filtered_materials
	
	# Add materials
	if not materials_dict.is_empty():
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
	if not palette.is_empty():
		for voxel_id in palette:
			var voxel: Voxel = palette[voxel_id]
			voxel_set.set_voxel(int(voxel_id), voxel)

	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, DEBUG_CONTEXT, "VoxelSet created: %d voxels, %d materials" % [voxel_set.get_voxels_count(), voxel_set.get_materials_count()])
	return voxel_set
