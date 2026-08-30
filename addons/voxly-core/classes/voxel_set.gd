## A palette/library resource that stores all voxel types of a project.
##
## Acts as the central database for voxel definitions: each entry maps a numeric
## voxel ID to a [Voxel] resource. It also owns the shared texture atlas and the
## named material library that voxels reference through their material IDs.
@tool
@icon("res://addons/voxly-core/assets/icons/voxel_set.svg")
class_name VoxelSet
extends Resource

## Debug context tag used when logging through [VoxlyDebug].
const _debug_context := "VoxelSet"

## Emitted when the texture atlas is changed.
signal texture_atlas_changed

## Emitted when the texture atlas cell size is changed.
signal texture_atlas_cell_size_changed

## Emitted when the default material is changed.
signal default_material_changed

## Emitted when materials are added, removed or modified.
signal materials_changed

## Emitted when voxels are added, removed or modified.
signal voxels_changed

## Inspector button that manually notifies listeners of content changes.
var notify_changed_button = _notify_changed

@export_group("Texture Atlas")

## The texture atlas containing all voxel textures.
## Cells within the atlas are addressed by their grid position (see
## [member texture_atlas_cell_size]).
@export var texture_atlas: Texture2D:
	set = set_texture_atlas,
	get = get_texture_atlas

## The size of each cell in the texture atlas, in pixels.
## A cell is addressed by its 2D grid position, e.g. [code]Vector2i(3, 1)[/code]
## refers to the fourth column on the second row of the atlas.
@export var texture_atlas_cell_size: Vector2i:
	set = set_texture_atlas_cell_size,
	get = get_texture_atlas_cell_size

@export_group("Materials")

## Default material applied to every voxel that has no specific material.
## Enable vertex colors on this material for proper colored rendering.
@export var default_material: BaseMaterial3D = StandardMaterial3D.new():
	set = set_default_material,
	get = get_default_material

## Named materials that voxels reference through their [member Voxel.base_material_id].
@export var materials: Dictionary[String, BaseMaterial3D] = {}:
	set = set_materials,
	get = get_materials

## Internal voxel storage mapping voxel ID to its [Voxel] definition.
## Stored in the resource file but hidden from the inspector; edit voxels
## through the dedicated VoxelSet editor dock instead.
@export_storage var _voxels: Dictionary[int, Voxel] = {}:
	set = set_voxels,
	get = get_voxels

## Cached UV scale mapping one atlas cell to normalized texture coordinates.
## Recomputes whenever the atlas or the cell size changes.
var _texture_uv_scale: Vector2 = Vector2.ONE

## Prepares the default material for vertex-color rendering.
func _init() -> void:
	default_material.vertex_color_use_as_albedo = true

## Returns the shared texture atlas texture.
func get_texture_atlas() -> Texture2D:
	return texture_atlas

## Sets the shared texture atlas texture and emits change signals.
func set_texture_atlas(new_texture_atlas: Texture2D) -> void:
	if texture_atlas != new_texture_atlas:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_SETS, _debug_context, "Texture atlas changed")
		texture_atlas = new_texture_atlas
		texture_atlas_changed.emit()
		changed.emit()

## Returns the size of a single cell in the texture atlas.
func get_texture_atlas_cell_size() -> Vector2i:
	return texture_atlas_cell_size

## Sets the size of a single atlas cell and emits change signals.
func set_texture_atlas_cell_size(new_cell_size: Vector2i) -> void:
	if texture_atlas_cell_size != new_cell_size:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_SETS, _debug_context, "Cell size changed: %s" % new_cell_size)
		texture_atlas_cell_size = new_cell_size
		# Recompute the normalized UV scale so 1.0 maps to exactly one cell.
		if texture_atlas and new_cell_size.x > 0 and new_cell_size.y > 0:
			var atlas_size := texture_atlas.get_size()
			_texture_uv_scale = Vector2(
				float(new_cell_size.x) / atlas_size.x,
				float(new_cell_size.y) / atlas_size.y
			)
		texture_atlas_cell_size_changed.emit()
		changed.emit()

## Returns true if [param texture_cell] lies inside the current atlas grid.
func is_texture_cell_valid(texture_cell: Vector2i) -> bool:
	if not texture_atlas:
		return false
	if texture_atlas_cell_size.x <= 0 or texture_atlas_cell_size.y <= 0:
		return false
	
	var atlas_size := texture_atlas.get_size()
	var max_x := atlas_size.x / texture_atlas_cell_size.x
	var max_y := atlas_size.y / texture_atlas_cell_size.y
	
	return (texture_cell.x >= 0 and texture_cell.x < max_x
		and texture_cell.y >= 0 and texture_cell.y < max_y)

## Returns the number of cells that fit in the atlas on each axis, or
## [constant Vector2i.ZERO] when the atlas is missing or misconfigured.
func get_texture_atlas_cell_count() -> Vector2i:
	if not texture_atlas or texture_atlas_cell_size.x <= 0 or texture_atlas_cell_size.y <= 0:
		return Vector2i.ZERO
	
	var atlas_size := texture_atlas.get_size()
	return Vector2i(
		floori(atlas_size.x / texture_atlas_cell_size.x),
		floori(atlas_size.y / texture_atlas_cell_size.y)
	)

## Returns true when the atlas and cell size are set up so that textures
## can be sampled.
func is_texture_ready() -> bool:
	return (texture_atlas != null
		and texture_atlas_cell_size.x > 0
		and texture_atlas_cell_size.y > 0)

## Returns the normalized UV scale that maps one atlas cell to texture space.
func get_texture_uv_scale() -> Vector2:
	return _texture_uv_scale

## Creates an [AtlasTexture] from the texture atlas at the given [param texture_cell].
## Returns null if the cell is invalid or the atlas isn't ready.
func get_texture_atlas_sub_texture(texture_cell: Vector2i) -> AtlasTexture:
	if not is_texture_ready() or not is_texture_cell_valid(texture_cell):
		return null
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = texture_atlas
	atlas_tex.region = Rect2(
		texture_cell * texture_atlas_cell_size,
		texture_atlas_cell_size
	)
	return atlas_tex

## Returns the material used when a voxel has no material ID assigned.
func get_default_material() -> BaseMaterial3D:
	return default_material

## Sets the material used when a voxel has no material ID assigned.
func set_default_material(new_default_material: BaseMaterial3D) -> void:
	if new_default_material == null:
		return
	default_material = new_default_material
	default_material_changed.emit()
	changed.emit()

## Returns true if a material with the given ID is registered.
func material_id_exists(material_id: String) -> bool:
	return materials.has(material_id)

## Returns the material with the given ID, or [member default_material] if the
## ID is not registered.
func get_material(material_id: String) -> BaseMaterial3D:
	return materials.get(material_id, default_material)

## Returns the named material library (material ID to material).
func get_materials() -> Dictionary[String, BaseMaterial3D]:
	return materials

## Returns the IDs of all registered materials.
func get_material_ids() -> Array[String]:
	return materials.keys()

## Returns the number of registered materials.
func get_materials_count() -> int:
	return materials.size()

## Returns the next available numeric material ID.
## Generates the current maximum numeric ID + 1 (or [code]"0"[/code] if no
## materials exist).
func next_material_id() -> String:
	var max_id := -1
	for material_id in materials:
		if material_id.is_valid_int():
			max_id = maxi(max_id, material_id.to_int())
	return str(max_id + 1)

## Adds or updates a material in the library under the given ID.
func set_material(material_id: String, material: BaseMaterial3D) -> void:
	# The empty string is the reserved UNSET_MATERIAL_ID, assigning it breaks usage.
	if material_id == Voxel.UNSET_MATERIAL_ID:
		push_warning("VoxelSet.set_material(): material_id cannot be empty")
		return
	materials[material_id] = material
	materials_changed.emit()
	changed.emit()

## Replaces the entire material library.
func set_materials(new_materials: Dictionary[String, BaseMaterial3D]) -> void:
	materials = new_materials
	materials_changed.emit()
	changed.emit()

## Registers multiple materials at once, keyed by material ID.
func add_materials(new_materials: Dictionary[String, BaseMaterial3D]) -> void:
	for material_id in new_materials:
		materials[material_id] = new_materials[material_id]
	materials_changed.emit()
	changed.emit()

## Removes a single material and returns it (or null if it wasn't registered).
func remove_material(material_id: String) -> BaseMaterial3D:
	var material: BaseMaterial3D = materials.get(material_id)
	if materials.erase(material_id):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_SETS, _debug_context, "Removed material: %s" % material_id)
		materials_changed.emit()
		changed.emit()
	return material

## Removes multiple materials at once and returns the removed entries.
func remove_materials(material_ids: Array[String]) -> Dictionary[String, BaseMaterial3D]:
	var removed: Dictionary[String, BaseMaterial3D] = {}
	for material_id in material_ids:
		if materials.has(material_id):
			removed[material_id] = materials[material_id]
			materials.erase(material_id)
	if not removed.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_SETS, _debug_context, "Removed %d materials" % removed.size())
		materials_changed.emit()
		changed.emit()
	return removed

## Removes all materials from the library.
func clear_materials() -> void:
	if not materials.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_SETS, _debug_context, "Cleared all materials")
		materials.clear()
		materials_changed.emit()
		changed.emit()

## Returns the next available numeric voxel ID (current maximum + 1, or 0 if
## the set is empty).
func next_voxel_id() -> int:
	if _voxels.is_empty():
		return 0
	return _voxels.keys().max() + 1

## Returns true if a voxel with the given ID exists.
func voxel_id_exists(voxel_id: int) -> bool:
	return _voxels.has(voxel_id)

## Returns the voxel palette (voxel ID to [Voxel]).
func get_voxels() -> Dictionary[int, Voxel]:
	return _voxels

## Returns the voxel definition for the given ID, or null if it doesn't exist.
func get_voxel(voxel_id: int) -> Voxel:
	return _voxels.get(voxel_id)

## Returns the IDs of all registered voxels.
func get_voxel_ids() -> Array[int]:
	return _voxels.keys()

## Returns the number of registered voxels.
func get_voxels_count() -> int:
	return _voxels.size()

## Adds or replaces a voxel in the palette under the given ID.
func set_voxel(voxel_id: int, voxel: Voxel) -> void:
	_voxels[voxel_id] = voxel
	voxels_changed.emit()
	changed.emit()

## Replaces the entire voxel palette.
func set_voxels(new_voxels: Dictionary[int, Voxel]) -> void:
	_voxels = new_voxels
	voxels_changed.emit()
	changed.emit()

## Registers multiple voxels at once, keyed by voxel ID.
func add_voxels(new_voxels: Dictionary[int, Voxel]) -> void:
	for voxel_id in new_voxels:
		_voxels[voxel_id] = new_voxels[voxel_id]
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_SETS, _debug_context, "Added %d voxels" % new_voxels.size())
	voxels_changed.emit()
	changed.emit()

## Removes a single voxel and returns it (or null if it wasn't registered).
func remove_voxel(voxel_id: int) -> Voxel:
	var voxel: Voxel = _voxels.get(voxel_id)
	if _voxels.erase(voxel_id):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_SETS, _debug_context, "Removed voxel: %d" % voxel_id)
		voxels_changed.emit()
		changed.emit()
	return voxel

## Removes multiple voxels at once and returns the removed entries.
func remove_voxels(voxel_ids: Array[int]) -> Dictionary[int, Voxel]:
	var removed: Dictionary[int, Voxel] = {}
	for voxel_id in voxel_ids:
		if _voxels.has(voxel_id):
			removed[voxel_id] = _voxels[voxel_id]
			_voxels.erase(voxel_id)
	if not removed.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_SETS, _debug_context, "Removed %d voxels" % removed.size())
		voxels_changed.emit()
		changed.emit()
	return removed

## Removes all voxels from the palette.
func clear_voxels() -> void:
	if not _voxels.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_VOXEL_SETS, _debug_context, "Cleared all voxels")
		_voxels.clear()
		voxels_changed.emit()
		changed.emit()

## Finds the voxel ID matching the given name (case-insensitive, exact match).
## Returns -1 if no voxel has that name.
func find_voxel_by_name(name: String) -> int:
	var target := name.strip_edges().to_lower()
	if target.is_empty():
		return -1
	for voxel_id in _voxels:
		if _voxels[voxel_id].name.strip_edges().to_lower() == target:
			return voxel_id
	return -1

## Returns true if the voxel with the given ID exists and is fully opaque,
## considering both color alpha and any referenced materials' transparency
## and refraction.
func is_voxel_opaque(voxel_id: int) -> bool:
	var voxel: Voxel = _voxels.get(voxel_id)
	if not is_instance_valid(voxel):
		return false
	if voxel.has_translucent_colors():
		return false
	for face in Voxel.FACES:
		var material: BaseMaterial3D = get_material(voxel.get_face_material_id(face))
		if is_instance_valid(material) and material is BaseMaterial3D:
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
					or material.refraction_enabled:
				return false
	return true

## Filters voxels by a query string and returns the matching IDs.
##
## Tokens are comma-separated. Each token can be:
## - A number: matches by voxel ID exactly
## - Plain text: matches by name (substring, case-insensitive)
## - [code]#tagname[/code]: matches by tag (substring, case-insensitive)
##
## All tokens must match. An empty query returns all IDs.
##
## Examples:
## [codeblock]
## query("stone")          # voxels with "stone" in the name
## query("5, 12")          # voxels with ID 5 OR 12
## query("grass, #solid")  # name contains "grass" amd has the "solid" tag
## query("#flammable")     # any voxel with the "flammable" tag
## [/codeblock]
func query(query_string: String) -> Array[int]:
	var tokens: PackedStringArray = query_string.split(",", false)
	if tokens.is_empty():
		return get_voxel_ids()
	
	var results: Array[int] = []
	for voxel_id in _voxels:
		if _matches_query(voxel_id, _voxels[voxel_id], tokens):
			results.append(voxel_id)
	return results

## Emits the [signal changed] signal.
func _notify_changed() -> void:
	changed.emit()

## Returns true if the given voxel satisfies every query token.
func _matches_query(voxel_id: int, voxel: Voxel, tokens: PackedStringArray) -> bool:
	for raw_token in tokens:
		var token: String = raw_token.strip_edges()
		if token.is_empty():
			continue
		
		# Tag filter: #tagname
		if token.begins_with("#"):
			var tag_target: String = token.trim_prefix("#").strip_edges().to_lower()
			var found := false
			for tag in voxel.tags:
				if tag.strip_edges().to_lower().contains(tag_target):
					found = true
					break
			if not found:
				return false
			continue
		
		# Numeric token to exact ID match
		if token.is_valid_int():
			if voxel_id == token.to_int():
				continue
			return false
		
		# Plain text to name substring match
		if not voxel.name.strip_edges().to_lower().contains(token.to_lower()):
			return false
	
	return true
