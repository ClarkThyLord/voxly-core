## In-editor importer for the VoxelNode3D editor's Import menu.
##
## Reads files through [VoxlyReader] (normalizing voxel positions), then merges
## palette/materials/positions into the target model's VoxelSet + node in a
## single undoable action.
@tool
class_name VoxlyImporter
extends RefCounted

const _debug_context := "VoxlyImporter"

## Reads a file for the in-editor import workflow.
## Wraps [method VoxlyReader.read_file], then normalizes the voxel positions so
## the minimum corner is at (0,0,0) and computes the content's bounding size.
## Returns:
## [codeblock]
## {
##   error: int,
##   voxels: {Vector3i: int},   # normalized copy
##   palette: {int: Voxel},
##   materials: {int: Dictionary},
##   min_corner: Vector3i,      # original minimum position before shift
##   size: Vector3i,            # bounding size of normalized voxels
## }
## [/codeblock]
static func read_for_editor(path: String, options: Dictionary = {}) -> Dictionary:
	var result := VoxlyReader.read_file(path, options)
	if result.get("error", ERR_FILE_CORRUPT) != OK:
		return result
	
	# Normalize positions (mutates our own duplicate, not reader internals).
	var voxels: Dictionary = result.get("voxels", {}).duplicate()
	var min_corner := VoxlyReader.shift_voxels_to_non_negative(voxels)
	var size := VoxlyReader.calc_voxel_bounds(voxels)
	
	result["voxels"] = voxels
	result["min_corner"] = min_corner
	result["size"] = size
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context,
		"Prepared for in-editor import: %d voxels, size=%s, min_corner=%s" % [voxels.size(), size, min_corner])
	return result

## Merges an imported palette + materials into an existing VoxelSet, remapping
## any conflicting IDs to fresh ones.
## Returns:
## [codeblock]
## {
##   voxel_remap: {int: int},        # source voxel ID -> new voxel ID
##   material_remap: {String: String}, # source material ID -> new material ID
##   old_voxels: {int: Voxel},       # snapshot before merge
##   old_materials: {String: BaseMaterial3D},
##   new_voxels: {int: Voxel},       # complete resulting state
##   new_materials: {String: BaseMaterial3D},
## }
## [/codeblock]
static func merge_into_voxel_set(existing: VoxelSet, palette: Dictionary, materials: Dictionary) -> Dictionary:
	var old_voxels: Dictionary = existing.get_voxels().duplicate()
	var old_materials: Dictionary = existing.get_materials().duplicate()
	
	var new_voxels: Dictionary = old_voxels.duplicate()
	var new_materials: Dictionary = old_materials.duplicate()
	
	var voxel_remap: Dictionary = {}
	var material_remap: Dictionary = {}
	
	# Materials first (Voxel entries reference base_material_id by String).
	for source_material_id in materials:
		var material_data: Dictionary = materials[source_material_id]
		var palette_color := Color.WHITE
		var palette_index := int(source_material_id) - 1 # MATL ids are 1-indexed; palette 0-indexed
		if palette.has(palette_index):
			var palette_voxel: Voxel = palette[palette_index]
			palette_color = palette_voxel.base_color
		
		var material := StandardMaterial3D.new()
		VoxReader.apply_material_properties(material, material_data, palette_color)
		material.vertex_color_use_as_albedo = true
		
		var new_material_id := str(source_material_id)
		if new_materials.has(new_material_id):
			var next := existing.next_material_id().to_int()
			while new_materials.has(str(next)):
				next += 1
			new_material_id = str(next)
		material_remap[str(source_material_id)] = new_material_id
		new_materials[new_material_id] = material
	
	# Palette entries.
	for source_voxel_id in palette:
		var voxel: Voxel = palette[source_voxel_id]
		var new_voxel_id := int(source_voxel_id)
		if new_voxels.has(new_voxel_id):
			var next := existing.next_voxel_id()
			while new_voxels.has(next):
				next += 1
			new_voxel_id = next
		voxel_remap[int(source_voxel_id)] = new_voxel_id
		
		# Re-point the voxel's material reference to the remapped material ID.
		if not voxel.base_material_id.is_empty() and material_remap.has(voxel.base_material_id):
			voxel.base_material_id = material_remap[voxel.base_material_id]
		
		new_voxels[new_voxel_id] = voxel
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context,
		"Merged into VoxelSet: %d -> %d voxels, %d -> %d materials" % [
			old_voxels.size(), new_voxels.size(),
			old_materials.size(), new_materials.size(),
		])
	
	return {
		"voxel_remap": voxel_remap,
		"material_remap": material_remap,
		"old_voxels": old_voxels,
		"old_materials": old_materials,
		"new_voxels": new_voxels,
		"new_materials": new_materials,
	}

## Registers do/undo methods that apply a merge result to a VoxelSet.
## [param merge_result] is what [method merge_into_voxel_set] returned.
##
## Per-entry registration keeps every argument a primitive + Object pair, which
## converts cleanly through UndoRedo's method binding (unlike passing a typed
## Dictionary aggregate, see the add_voxels() issue fixed in split/extract).
static func register_voxel_set_merge(undo_redo: EditorUndoRedoManager, voxel_set: VoxelSet, merge_result: Dictionary) -> void:
	var old_voxels: Dictionary = merge_result["old_voxels"]
	var new_voxels: Dictionary = merge_result["new_voxels"]
	var old_materials: Dictionary = merge_result["old_materials"]
	var new_materials: Dictionary = merge_result["new_materials"]
	
	# Voxels.
	for voxel_id in new_voxels:
		if old_voxels.has(voxel_id):
			# Overwritten, restore the previous entry on undo.
			undo_redo.add_do_method(voxel_set, "set_voxel", voxel_id, new_voxels[voxel_id])
			undo_redo.add_undo_method(voxel_set, "set_voxel", voxel_id, old_voxels[voxel_id])
		else:
			# Brand new, remove it on undo.
			undo_redo.add_do_method(voxel_set, "set_voxel", voxel_id, new_voxels[voxel_id])
			undo_redo.add_undo_method(voxel_set, "remove_voxel", voxel_id)
	
	# Materials.
	for material_id in new_materials:
		if old_materials.has(material_id):
			undo_redo.add_do_method(voxel_set, "set_material", material_id, new_materials[material_id])
			undo_redo.add_undo_method(voxel_set, "set_material", material_id, old_materials[material_id])
		else:
			undo_redo.add_do_method(voxel_set, "set_material", material_id, new_materials[material_id])
			undo_redo.add_undo_method(voxel_set, "remove_material", material_id)

## Applies a voxel map {Vector3i: int} to the target node through UndoRedo,
## restoring any pre-existing voxel at each position on undo.
## Per-position registration (Vector3i + int args) converts cleanly through
## UndoRedo's method binding.
static func apply_voxels_undoable(undo_redo: EditorUndoRedoManager, target, voxel_map: Dictionary) -> void:
	for position in voxel_map:
		var old_id = target.get_voxel(position)
		undo_redo.add_do_method(target, "set_voxel", position, voxel_map[position])
		if old_id != null:
			undo_redo.add_undo_method(target, "set_voxel", position, old_id)
		else:
			undo_redo.add_undo_method(target, "remove_voxel", position)
