@tool
@icon("res://addons/voxly-core/assets/icons/voxel_set.svg")
class_name VoxelSet
extends Resource
## A Resource that acts as a palette/library of voxel types.
## Manages a texture atlas, materials, and voxel definitions.
## Serves as the central database for all voxel variations.

## Emitted when the texture atlas is changed
signal texture_atlas_changed

## Emitted when the texture atlas cell size is changed
signal texture_atlas_cell_size_changed

## Emitted when the default material is changed
signal default_material_changed

## Emitted when materials are added, removed or modified
signal materials_changed

## Emitted when voxels are added, removed or modified
signal voxels_changed

## The texture atlas containing all voxel textures
@export
var texture_atlas: Texture2D:
	set = set_texture_atlas,
	get = get_texture_atlas

## The size of each cell in the texture atlas (in pixels)
@export
var texture_atlas_cell_size: Vector2i:
	set = set_texture_atlas_cell_size

## Default material applied to all voxels (uses vertex colors by default)
@export
var default_material: BaseMaterial3D = StandardMaterial3D.new():
	set = set_default_material,
	get = get_default_material

## Named materials that can be referenced by voxels via material_id
@export
var materials: Dictionary[String, BaseMaterial3D] = {}:
	set = set_materials,
	get = get_materials

## Internal voxel storage: ID -> Voxel
@export
var _voxels: Dictionary[int, Voxel] = {}:
	get = get_voxels,
	set = set_voxels

var _texture_uv_scale: Vector2 = Vector2.ONE

func _init() -> void:
	default_material.vertex_color_use_as_albedo = true

func get_texture_atlas() -> Texture2D:
	return texture_atlas

func set_texture_atlas(new_texture_atlas: Texture2D) -> void:
	if texture_atlas != new_texture_atlas:
		texture_atlas = new_texture_atlas
		texture_atlas_changed.emit()
		changed.emit()

func is_texture_atlas_position(texture_atlas_position: Vector2i) -> bool:
	if not texture_atlas:
		return false
	if texture_atlas_cell_size.x <= 0 or texture_atlas_cell_size.y <= 0:
		return false

	var atlas_size := texture_atlas.get_size()
	var max_x := atlas_size.x / texture_atlas_cell_size.x
	var max_y := atlas_size.y / texture_atlas_cell_size.y

	return (texture_atlas_position.x >= 0 and texture_atlas_position.x < max_x
		and texture_atlas_position.y >= 0 and texture_atlas_position.y < max_y)

func get_texture_atlas_position_range() -> Vector2i:
	if not texture_atlas or texture_atlas_cell_size.x <= 0 or texture_atlas_cell_size.y <= 0:
		return Vector2i.ZERO

	var atlas_size := texture_atlas.get_size()
	return Vector2i(
		floori(atlas_size.x / texture_atlas_cell_size.x),
		floori(atlas_size.y / texture_atlas_cell_size.y)
	)

func is_texture_ready() -> bool:
	return (texture_atlas != null
		and texture_atlas_cell_size.x > 0
		and texture_atlas_cell_size.y > 0)

func get_texture_uv_scale() -> Vector2:
	return _texture_uv_scale

## Creates an AtlasTexture from the texture atlas at the given cell position.
## Returns null if the position is invalid or the atlas isn't ready.
func get_texture_atlas_sub_texture(texture_position: Vector2i) -> AtlasTexture:
	if not is_texture_ready() or not is_texture_atlas_position(texture_position):
		return null
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = texture_atlas
	atlas_tex.region = Rect2(
		texture_position * texture_atlas_cell_size,
		texture_atlas_cell_size
	)
	return atlas_tex

func set_texture_atlas_cell_size(new_cell_size: Vector2i) -> void:
	if texture_atlas_cell_size != new_cell_size:
		texture_atlas_cell_size = new_cell_size
		if texture_atlas and new_cell_size.x > 0 and new_cell_size.y > 0:
			var atlas_size := texture_atlas.get_size()
			_texture_uv_scale = Vector2(
				float(new_cell_size.x) / atlas_size.x,
				float(new_cell_size.y) / atlas_size.y
			)
		texture_atlas_cell_size_changed.emit()
		changed.emit()

func get_default_material() -> BaseMaterial3D:
	return default_material

func set_default_material(new_default_material: BaseMaterial3D) -> void:
	if new_default_material == null:
		return
	default_material = new_default_material
	default_material_changed.emit()
	changed.emit()

func material_id_exists(material_id: String) -> bool:
	return materials.has(material_id)

func get_material(material_id: String) -> BaseMaterial3D:
	return materials.get(material_id, default_material)

func get_materials() -> Dictionary[String, BaseMaterial3D]:
	return materials

func get_material_ids() -> Array[String]:
	return materials.keys()

func get_materials_count() -> int:
	return materials.size()

func set_material(material_id: String, material: BaseMaterial3D) -> void:
	materials[material_id] = material
	materials_changed.emit()
	changed.emit()

func set_materials(new_materials: Dictionary[String, BaseMaterial3D]) -> void:
	materials = new_materials
	materials_changed.emit()
	changed.emit()

func add_materials(new_materials: Dictionary[String, BaseMaterial3D]) -> void:
	for id in new_materials:
		materials[id] = new_materials[id]
	materials_changed.emit()
	changed.emit()

func remove_material(material_id: String) -> BaseMaterial3D:
	var material = materials.get(material_id)
	if materials.erase(material_id):
		materials_changed.emit()
		changed.emit()
	return material

func remove_materials(material_ids: Array[String]) -> Dictionary[String, BaseMaterial3D]:
	var removed := {}
	for id in material_ids:
		if materials.has(id):
			removed[id] = materials[id]
			materials.erase(id)
	if not removed.is_empty():
		materials_changed.emit()
		changed.emit()
	return removed

func clear_materials() -> void:
	if not materials.is_empty():
		materials.clear()
		materials_changed.emit()
		changed.emit()

func next_voxel_id() -> int:
	if _voxels.is_empty():
		return 0
	return _voxels.keys().max() + 1

func voxel_id_exists(voxel_id: int) -> bool:
	return _voxels.has(voxel_id)

func get_voxels() -> Dictionary[int, Voxel]:
	return _voxels

func get_voxel(voxel_id: int) -> Voxel:
	return _voxels.get(voxel_id)

func get_voxel_ids() -> Array:
	return _voxels.keys()

func get_voxels_count() -> int:
	return _voxels.size()

func set_voxel(voxel_id: int, voxel: Voxel) -> void:
	_voxels[voxel_id] = voxel
	voxels_changed.emit()
	changed.emit()

func set_voxels(new_voxels: Dictionary[int, Voxel]) -> void:
	_voxels = new_voxels
	voxels_changed.emit()
	changed.emit()

func add_voxels(new_voxels: Dictionary[int, Voxel]) -> void:
	for id in new_voxels:
		_voxels[id] = new_voxels[id]
	voxels_changed.emit()
	changed.emit()

func remove_voxel(voxel_id: int) -> Voxel:
	var voxel = _voxels.get(voxel_id)
	if _voxels.erase(voxel_id):
		voxels_changed.emit()
		changed.emit()
	return voxel

func remove_voxels(voxel_ids: Array[int]) -> Dictionary[int, Voxel]:
	var removed := {}
	for id in voxel_ids:
		if _voxels.has(id):
			removed[id] = _voxels[id]
			_voxels.erase(id)
	if not removed.is_empty():
		voxels_changed.emit()
		changed.emit()
	return removed

func clear_voxels() -> void:
	if not _voxels.is_empty():
		_voxels.clear()
		voxels_changed.emit()
		changed.emit()

## Finds the voxel ID matching the given name (case-insensitive, exact match).
## Returns -1 if no voxel has that name.
func find_voxel_by_name(name: String) -> int:
	var target := name.strip_edges().to_lower()
	if target.is_empty():
		return -1
	for vid in _voxels:
		if _voxels[vid].name.strip_edges().to_lower() == target:
			return vid
	return -1

## Filters voxels by a query string and returns matching IDs.
##
## Tokens are comma-separated. Each token can be:
##   - A number → matches by voxel ID exactly
##   - Plain text → matches by name (substring, case-insensitive)
##   - `#tagname` → matches by tag (substring, case-insensitive)
##
## All tokens must match (AND logic). An empty query returns all IDs.
##
## Examples:
##   query("stone")          → voxels with "stone" in the name
##   query("5, 12")          → voxels with ID 5 OR 12
##   query("grass, #solid")  → name contains "grass" AND has "solid" tag
##   query("#flammable")     → any voxel with the "flammable" tag
func query(query_string: String) -> Array[int]:
	var tokens: PackedStringArray = query_string.split(",", false)
	if tokens.is_empty():
		return get_voxel_ids()

	var results: Array[int] = []
	for vid in _voxels:
		if _matches_query(vid, _voxels[vid], tokens):
			results.append(vid)
	return results

func _matches_query(vid: int, voxel: Voxel, tokens: PackedStringArray) -> bool:
	for token in tokens:
		var t: String = token.strip_edges()
		if t.is_empty():
			continue

		# Tag filter: #tagname
		if t.begins_with("#"):
			var tag_target: String = t.trim_prefix("#").strip_edges().to_lower()
			var found := false
			for vtag in voxel.tags:
				if vtag.strip_edges().to_lower().contains(tag_target):
					found = true
					break
			if not found:
				return false
			continue

		# Numeric token → exact ID match
		if t.is_valid_int():
			if vid == t.to_int():
				continue
			return false

		# Plain text → name substring match (case-insensitive)
		if not voxel.name.strip_edges().to_lower().contains(t.to_lower()):
			return false

	return true
