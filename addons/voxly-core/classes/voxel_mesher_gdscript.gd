@tool
class_name VoxelMesherGDScript
extends VoxelMesher
## GDScript implementation of the voxel mesher.
## Handles brute-force, culled (naive), and greedy meshing modes.
##
## Surfaces are separated by material_id AND by whether a face uses a texture.
## This ensures each surface has consistent vertex attributes (all UV or no UV),
## and that textured surfaces have the atlas texture applied to their material.

## SurfaceTool tracking material assigned to it and the running vertex count.
class MeshSurface extends SurfaceTool:
	var material: Material
	var vertex_count: int

	func _init(p_material: Material) -> void:
		begin(Mesh.PRIMITIVE_TRIANGLES)
		set_material(p_material)
		material = p_material
		vertex_count = 0

var _began: bool = false
var _voxel_size: Vector3 = Vector3.ONE
var _voxel_set: VoxelSet = null
var _add_color: bool = true
var _add_uv: bool = true
var _surfaces: Dictionary[String, MeshSurface] = {}

const _GREEDY_MESHING_TEXTURED_SHADER = preload("res://addons/voxly-core/shaders/greedy_meshing_textured.gdshader")

# Tag for surface that are textured
const _SURFACE_TEXTURED := "_textured"

 # Tag for surface that are not textured
const _SURFACE_NOT_TEXTURED := "_not_textured"

func _init() -> void:
	DEBUG_CONTEXT = "VoxelMesherGDScript"

func begin(voxel_size: Vector3, voxel_set: VoxelSet, add_color: bool = true, add_uv: bool = true) -> void:
	_began = true
	_voxel_size = voxel_size
	_voxel_set = voxel_set
	_add_color = add_color
	_add_uv = add_uv
	_surfaces.clear()
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "Begun: size=%s add_color=%s add_uv=%s" % [voxel_size, add_color, add_uv])

func clear() -> void:
	_began = false
	_surfaces.clear()

func commit() -> ArrayMesh:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return ArrayMesh.new()
	
	var array_mesh := ArrayMesh.new()
	
	for surface_key in _surfaces:
		var ms: MeshSurface = _surfaces[surface_key]
		var arrays: Array = ms.commit_to_arrays()
		if arrays.is_empty():
			continue
	
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
		if ms.material:
			array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, ms.material)
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "Committed mesh: %d surfaces" % array_mesh.get_surface_count())
	return array_mesh

func add_face(voxel_position: Vector3i, voxel_id: int, voxel_face: Vector3i, scale_by: Vector2i = Vector2i.ONE) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	
	scale_by = scale_by.max(Vector2i.ONE)
	
	var voxel: Voxel = _voxel_set.get_voxel(voxel_id)
	if not is_instance_valid(voxel):
		return
	
	var material_id: String = voxel.get_face_material_id(voxel_face)
	# A face has a texture (uses UV coordinates) only if:
	#   1. The global add_uv flag is enabled
	#   2. The voxel face has a texture coordinate assigned (-Vector2i.ONE means "no texture")
	#   3. The VoxelSet has a texture atlas ready to use
	var has_texture: bool = (_add_uv
		and voxel.has_face_texture_xy(voxel_face)
		and _voxel_set.is_texture_ready())
	var surface_key: String = _build_surface_key(material_id, has_texture)
	var ms: MeshSurface = _get_surface(surface_key, has_texture)
	
	ms.set_normal(voxel_face)
	
	if _add_color:
		ms.set_color(voxel.get_face_color(voxel_face))
	
	var face_texture: Vector2i = voxel.get_face_texture_xy(voxel_face)
	var uv_scale: Vector2 = _voxel_set.get_texture_uv_scale()
	
	# For textured faces, UV holds cell-local coordinates (0..scale_by) for tiling.
	# UV2 holds the atlas cell position (face_texture) so the
	# greedy_meshing_textured shader can compute texture repetition.
	# This lets greedy-merged quads repeat the correct cell across the face.
	var cell_uv := Vector2(face_texture)
	
	match voxel_face:
		Voxel.FACE_RIGHT:
			if has_texture:
				ms.set_uv(Vector2(scale_by.y, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT + Vector3i.UP * scale_by.x) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(scale_by.y, scale_by.x))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(0, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i(1, 1 * scale_by.x, 1 * scale_by.y)) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(0, scale_by.x))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT + Vector3i.BACK * scale_by.y) * _voxel_size)
	
		Voxel.FACE_LEFT:
			if has_texture:
				ms.set_uv(Vector2(0, scale_by.x))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(0, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP * scale_by.x) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(scale_by.y, scale_by.x))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.BACK * scale_by.y) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(scale_by.y, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP * scale_by.x + Vector3i.BACK * scale_by.y) * _voxel_size)
	
		Voxel.FACE_TOP:
			if has_texture:
				ms.set_uv(Vector2(0, scale_by.y))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP + Vector3i.BACK * scale_by.y) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(0, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(scale_by))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i(1 * scale_by.x, 1, 1 * scale_by.y)) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(scale_by.x, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.x + Vector3i.UP) * _voxel_size)
	
		Voxel.FACE_BOTTOM:
			if has_texture:
				ms.set_uv(Vector2(0, scale_by.y))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.x + Vector3i.BACK * scale_by.y) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(0, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.x) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(scale_by))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.BACK * scale_by.y) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(scale_by.x, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position) * _voxel_size)
	
		Voxel.FACE_FRONT:
			if has_texture:
				ms.set_uv(Vector2(scale_by.y, scale_by.x))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.y) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(scale_by.y, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.y + Vector3i.UP * scale_by.x) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(0, scale_by.x))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(0, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP * scale_by.x) * _voxel_size)
	
		Voxel.FACE_BACK:
			if has_texture:
				ms.set_uv(Vector2(scale_by.y, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i(1 * scale_by.y, 1 * scale_by.x, 1)) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(scale_by.y, scale_by.x))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.y + Vector3i.BACK) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(0, 0))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP * scale_by.x + Vector3i.BACK) * _voxel_size)
			if has_texture:
				ms.set_uv(Vector2(0, scale_by.x))
				ms.set_uv2(cell_uv)
			ms.add_vertex(Vector3(voxel_position + Vector3i.BACK) * _voxel_size)
	
	# Add indices (two triangles forming a quad)
	var new_count: int = ms.vertex_count + 4
	ms.add_index(ms.vertex_count)
	ms.add_index(ms.vertex_count + 1)
	ms.add_index(ms.vertex_count + 2)
	ms.add_index(ms.vertex_count + 1)
	ms.add_index(ms.vertex_count + 3)
	ms.add_index(ms.vertex_count + 2)
	ms.vertex_count = new_count


func add_all_faces(voxels: Dictionary[Vector3i, int]) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "Adding all faces for %d voxels" % voxels.size())
	for p in voxels:
		for face in Voxel.FACES:
			add_face(p, voxels[p], face)


func add_culled_faces(voxels: Dictionary[Vector3i, int]) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	
	var face_count := 0
	for p in voxels:
		for face in Voxel.FACES:
			if not voxels.has(p + face):
				add_face(p, voxels[p], face)
				face_count += 1
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "Added %d culled faces for %d voxels" % [face_count, voxels.size()])


func add_greedy_faces(voxels: Dictionary[Vector3i, int]) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	
	# Process each axis separately using the greedy algorithm
	var total_quads := 0
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "Greedy meshing %d voxels" % voxels.size())
	for face in Voxel.FACES:
		var quads := _greedy_by_face(voxels, face)
		total_quads += quads
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "Greedy mesh complete: %d total quads" % total_quads)

## Builds a surface key that separates by material_id AND by texture presence.
## A single voxel can produce up to 2 surfaces per material_id:
##   - One with UV coordinates (for faces that have a texture defined)
##   - One without UV coordinates (for faces with no texture)
## This ensures each surface has consistent vertex attribute layouts.
func _build_surface_key(material_id: String, has_texture: bool) -> String:
	return material_id + (_SURFACE_TEXTURED if has_texture else _SURFACE_NOT_TEXTURED)

## Gets or creates a MeshSurface for the given key.
## When creating a UV-using surface, the material is duplicated and the
## atlas texture is set as its albedo texture, so faces render with the correct
## texture from the atlas texture.
func _get_surface(surface_key: String, has_texture: bool) -> MeshSurface:
	if _surfaces.has(surface_key):
		return _surfaces[surface_key]
	
	# Get the base material from the voxel set
	var base_material: BaseMaterial3D = _voxel_set.get_material(
		_bare_material_id_from_key(surface_key)
	)
	
	var use_material: Material = base_material
	
	if has_texture:
		# Use the greedy_meshing_textured shader that converts cell-local UVs
		# (0..scale_by) + UV2 (cell grid position) into proper atlas UVs.
		# This lets greedy-merged quads correctly repeat the cell texture
		# across the entire merged face without atlas bleeding.
		var shader_material := ShaderMaterial.new()
		shader_material.shader = _GREEDY_MESHING_TEXTURED_SHADER
		shader_material.set_shader_parameter("atlas_texture", _voxel_set.texture_atlas)
		shader_material.set_shader_parameter("uv_scale", _voxel_set.get_texture_uv_scale())
		
		# Inherit base material properties like vertex color usage
		if use_material is Material:
			shader_material.render_priority = use_material.render_priority
			# Copy any other relevant properties as needed
		
		use_material = shader_material
	
	var ms := MeshSurface.new(use_material)
	_surfaces[surface_key] = ms
	return ms

## Extracts the bare material_id from a surface key by stripping the suffix.
func _bare_material_id_from_key(surface_key: String) -> String:
	if surface_key.ends_with(_SURFACE_TEXTURED):
		return surface_key.trim_suffix(_SURFACE_TEXTURED)
	if surface_key.ends_with(_SURFACE_NOT_TEXTURED):
		return surface_key.trim_suffix(_SURFACE_NOT_TEXTURED)
	return surface_key

func _greedy_by_face(voxels: Dictionary[Vector3i, int], voxel_face: Vector3i) -> int:
	# Step 1: Find all uncovered faces in this direction
	var uncovered_faces: Dictionary[Vector3i, int] = {}
	
	for voxel_position in voxels:
		var voxel_id: int = voxels[voxel_position]
		if typeof(voxel_id) == TYPE_INT:
			if typeof(voxels.get(voxel_position + voxel_face)) != TYPE_INT:
				uncovered_faces[voxel_position] = voxel_id
	
	var quad_count := 0
	var last_count: int = -1
	var iteration := 0
	
	# Step 2: Process until all faces are merged
	while not uncovered_faces.is_empty():
		var count: int = uncovered_faces.size()
		iteration += 1
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "  iter %d: face=%s remaining=%d" % [iteration, Voxel.FACE_NAMES.get(voxel_face, str(voxel_face)), count])
		
		if count == last_count:
			var first_pos: Vector3i = uncovered_faces.keys()[0]
			var first_id: int = uncovered_faces[first_pos]
			var face_name: String = Voxel.FACE_NAMES.get(voxel_face, str(voxel_face))
			# Determine if we have a patter, sample a few positions
			var sample_positions: Array = []
			var sample_idx := 0
			for pos in uncovered_faces:
				if sample_idx >= 5:
					break
				sample_positions.append(pos)
				sample_idx += 1
			# Check if any neighbors exist for the first position (zero-growth detection)
			var stuck_pos: Vector3i = uncovered_faces.keys()[0]
			var adj_right := uncovered_faces.get(stuck_pos + Voxel.ADJACENT_FACES[voxel_face][0])
			var adj_left := uncovered_faces.get(stuck_pos + Voxel.ADJACENT_FACES[voxel_face][1])
			var adj_down := uncovered_faces.get(stuck_pos + Voxel.ADJACENT_FACES[voxel_face][2])
			var adj_up := uncovered_faces.get(stuck_pos + Voxel.ADJACENT_FACES[voxel_face][3])
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "LOOP BREAK: face=%s remaining=%d first_pos=%s first_id=%d neighbors(R=%s L=%s D=%s U=%s) samples=%s" % [face_name, count, first_pos, first_id, adj_right, adj_left, adj_down, adj_up, sample_positions])
			push_error("Greedy meshing: uncovered faces count unchanged, breaking loop")
			break
		
		last_count = count
		
		var start_pos: Vector3i = uncovered_faces.keys()[0]
		var voxel_id: int = uncovered_faces[start_pos]
		
		# Determine primary growth direction (right/left adjacent face)
		var offset_by: Vector3i = Voxel.ADJACENT_FACES[voxel_face][1]
		var primary_offset: int = 1
		
		while true:
			var pos: Vector3i = start_pos + offset_by * primary_offset
			var v_id = uncovered_faces.get(pos)
			if v_id == voxel_id:
				primary_offset += 1
			else:
				break
		
		primary_offset -= 1
		start_pos += Voxel.ADJACENT_FACES[voxel_face][1] * primary_offset
		
		var primary_growth_dir: Vector3i = Voxel.ADJACENT_FACES[voxel_face][0]
		var primary_growth_axis: int = primary_growth_dir.max_axis_index()
		var primary_growth: int = 0
		
		while true:
			var v_id = uncovered_faces.get(start_pos + primary_growth_dir * primary_growth)
			if v_id == voxel_id:
				primary_growth += 1
			else:
				break
		
		offset_by = Voxel.ADJACENT_FACES[voxel_face][3]
		var secondary_offset: int = 1
		
		while true:
			var pos: Vector3i = start_pos + offset_by * secondary_offset
			var v_id = uncovered_faces.get(pos)
			if v_id == voxel_id:
				var can_expand: bool = false
				for pg in range(1, primary_growth + 1):
					v_id = uncovered_faces.get(pos + primary_growth_dir * pg)
					if v_id == voxel_id:
						if pg == primary_growth:
							secondary_offset += 1
							can_expand = true
					else:
						break
				if not can_expand:
					break
			else:
				break
		
		secondary_offset -= 1
		start_pos += Voxel.ADJACENT_FACES[voxel_face][3] * secondary_offset
		
		var secondary_growth_dir: Vector3i = Voxel.ADJACENT_FACES[voxel_face][2]
		var secondary_growth_axis: int = secondary_growth_dir.max_axis_index()
		var secondary_growth: int = 0
		
		while true:
			var pos: Vector3i = start_pos + secondary_growth_dir * secondary_growth
			var v_id = uncovered_faces.get(pos)
			if v_id == voxel_id:
				var can_expand: bool = false
				for pg in range(primary_growth):
					var pp: Vector3i = pos + primary_growth_dir * pg
					v_id = uncovered_faces.get(pp)
					if v_id == voxel_id:
						if pg == primary_growth - 1:
							secondary_growth += 1
							can_expand = true
					else:
						break
				if not can_expand:
					break
			else:
				break
		
		var scale_by: Vector2i = Vector2i(primary_growth, secondary_growth).max(Vector2i.ONE)
		
		add_face(start_pos, voxel_id, voxel_face, scale_by)
		
		quad_count += 1
		
		# Erase merged faces
		for x in range(scale_by.x):
			for y in range(scale_by.y):
				var pos: Vector3i = Vector3i(start_pos)
				pos[primary_growth_axis] += x
				pos[secondary_growth_axis] += y
				uncovered_faces.erase(pos)
	
	return quad_count
