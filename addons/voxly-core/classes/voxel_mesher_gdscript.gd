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
	var id: String
	var material: Material
	var vertex_count: int
	
	func _init(id, material: Material) -> void:
		self.id = id
		self.material = material
		vertex_count = 0
		
		begin(Mesh.PRIMITIVE_TRIANGLES)
		set_material(self.material)

var _began: bool = false
var _voxel_size: Vector3 = Vector3.ONE
var _voxel_set: VoxelSet = null
var _voxels_colored: bool = true
var _voxels_textured: bool = true
var _surfaces: Dictionary[String, MeshSurface] = {}
var _opacity_cache: Dictionary[int, bool] = {}
var _meshing_mode: MeshingMode = MeshingMode.GREEDY

const _GREEDY_MESHING_TEXTURED_SHADER = preload("res://addons/voxly-core/shaders/greedy_meshing_textured.gdshader")

## Meshing modes supported by VoxelMesherGDScript, determine how textured UVs 
## are generated and sampled. GREEDY uses cell-local UVs + UV2 with the 
## greedy_meshing_textured shader so merged quads repeat the atlas cell. 
## BRUTE and NAIVE use plain atlas UVs with a standard material, since each 
## face is a single non-merged cell.
enum MeshingMode {
	BRUTE = 0,
	NAIVE = 1,
	GREEDY = 2
}

# Tag for surface that are textured.
const _SURFACE_TEXTURED := "_textured"

 # Tag for surface that are not textured.
const _SURFACE_NOT_TEXTURED := "_not_textured"

func _init() -> void:
	DEBUG_CONTEXT = "VoxelMesherGDScript"

func begin(voxel_size: Vector3, voxel_set: VoxelSet, voxels_colored: bool = true, voxels_textured: bool = true) -> void:
	_began = true
	_voxel_size = voxel_size
	_voxel_set = voxel_set
	_voxels_colored = voxels_colored
	_voxels_textured = voxels_textured
	_surfaces.clear()
	_opacity_cache.clear()
	_meshing_mode = MeshingMode.GREEDY
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "Begun: size=%s voxels_colored=%s voxels_textured=%s" % [voxel_size, voxels_colored, voxels_textured])

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
		var surface_name := ms.id.trim_prefix("_")
		array_mesh.surface_set_name(array_mesh.get_surface_count() - 1, surface_name)
		
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
	#   1. The global voxels_textured flag is enabled
	#   2. The voxel face has valid texture coordinate assigned (x>=0,y>=0)
	#   3. The VoxelSet has a texture atlas ready to use
	var has_texture: bool = (_voxels_textured
		and voxel.has_face_texture_xy(voxel_face)
		and _voxel_set.is_texture_ready())
	var surface_key: String = _build_surface_key(material_id, has_texture)
	var ms: MeshSurface = _get_surface(surface_key, has_texture)
	
	ms.set_normal(voxel_face)
	
	if _voxels_colored:
		var voxel_color := voxel.get_face_color(voxel_face)
		if voxel_color.a == 0:
			voxel_color = Color.WHITE
		ms.set_color(voxel_color)
	
	var face_texture: Vector2i = voxel.get_face_texture_xy(voxel_face)
	
	# For GREEDY, textured faces write cell-local UVs (0..scale_by) + UV2 (atlas
	# cell position) so the greedy_meshing_textured shader attached to surface
	# can repeat the cell across greedy-merged quads.
	# For BRUTE/NAIVE, faces are never merged, so we write atlas UVs directly 
	# and use a plain material with the atlas texture as albedo.
	var cell_uv := Vector2(face_texture)
	
	match voxel_face:
		Voxel.FACE_RIGHT:
			_set_face_uv(ms, Vector2(scale_by.y, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT + Vector3i.UP * scale_by.x) * _voxel_size)
			_set_face_uv(ms, Vector2(scale_by.y, scale_by.x), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT) * _voxel_size)
			_set_face_uv(ms, Vector2(0, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i(1, 1 * scale_by.x, 1 * scale_by.y)) * _voxel_size)
			_set_face_uv(ms, Vector2(0, scale_by.x), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT + Vector3i.BACK * scale_by.y) * _voxel_size)
		
		Voxel.FACE_LEFT:
			_set_face_uv(ms, Vector2(0, scale_by.x), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position) * _voxel_size)
			_set_face_uv(ms, Vector2(0, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP * scale_by.x) * _voxel_size)
			_set_face_uv(ms, Vector2(scale_by.y, scale_by.x), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.BACK * scale_by.y) * _voxel_size)
			_set_face_uv(ms, Vector2(scale_by.y, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP * scale_by.x + Vector3i.BACK * scale_by.y) * _voxel_size)
		
		Voxel.FACE_TOP:
			_set_face_uv(ms, Vector2(0, scale_by.y), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP + Vector3i.BACK * scale_by.y) * _voxel_size)
			_set_face_uv(ms, Vector2(0, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP) * _voxel_size)
			_set_face_uv(ms, Vector2(scale_by), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i(1 * scale_by.x, 1, 1 * scale_by.y)) * _voxel_size)
			_set_face_uv(ms, Vector2(scale_by.x, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.x + Vector3i.UP) * _voxel_size)
		
		Voxel.FACE_BOTTOM:
			_set_face_uv(ms, Vector2(0, scale_by.y), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.x + Vector3i.BACK * scale_by.y) * _voxel_size)
			_set_face_uv(ms, Vector2(0, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.x) * _voxel_size)
			_set_face_uv(ms, Vector2(scale_by), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.BACK * scale_by.y) * _voxel_size)
			_set_face_uv(ms, Vector2(scale_by.x, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position) * _voxel_size)
		
		Voxel.FACE_FRONT:
			_set_face_uv(ms, Vector2(scale_by.y, scale_by.x), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.y) * _voxel_size)
			_set_face_uv(ms, Vector2(scale_by.y, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.y + Vector3i.UP * scale_by.x) * _voxel_size)
			_set_face_uv(ms, Vector2(0, scale_by.x), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position) * _voxel_size)
			_set_face_uv(ms, Vector2(0, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP * scale_by.x) * _voxel_size)
		
		Voxel.FACE_BACK:
			_set_face_uv(ms, Vector2(scale_by.y, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i(1 * scale_by.y, 1 * scale_by.x, 1)) * _voxel_size)
			_set_face_uv(ms, Vector2(scale_by.y, scale_by.x), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * scale_by.y + Vector3i.BACK) * _voxel_size)
			_set_face_uv(ms, Vector2(0, 0), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.UP * scale_by.x + Vector3i.BACK) * _voxel_size)
			_set_face_uv(ms, Vector2(0, scale_by.x), cell_uv, has_texture)
			ms.add_vertex(Vector3(voxel_position + Vector3i.BACK) * _voxel_size)
	
	# Add indices (two triangles forming a quad).
	var new_count: int = ms.vertex_count + 4
	ms.add_index(ms.vertex_count)
	ms.add_index(ms.vertex_count + 1)
	ms.add_index(ms.vertex_count + 2)
	ms.add_index(ms.vertex_count + 1)
	ms.add_index(ms.vertex_count + 3)
	ms.add_index(ms.vertex_count + 2)
	ms.vertex_count = new_count


## Writes the UV (and UV2 for GREEDY) for a textured face vertex.
## - GREEDY: writes cell-local UV (0..scale_by) + UV2 (atlas cell position) so
##   the greedy_meshing_textured shader can repeat the cell across merged quads.
## - BRUTE/NAIVE: writes atlas UVs directly so a plain material with the atlas
##   texture as albedo samples the correct single cell.
func _set_face_uv(ms: MeshSurface, local_uv: Vector2, cell_uv: Vector2, has_texture: bool) -> void:
	if not has_texture:
		return
	if _meshing_mode == MeshingMode.GREEDY:
		ms.set_uv(local_uv)
		ms.set_uv2(cell_uv)
	else:
		ms.set_uv((cell_uv + local_uv) * _voxel_set.get_texture_uv_scale())


func add_all_faces(voxels: Dictionary[Vector3i, int]) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	_meshing_mode = MeshingMode.BRUTE
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "Adding all faces for %d voxels" % voxels.size())
	for p in voxels:
		for face in Voxel.FACES:
			add_face(p, voxels[p], face)


func add_culled_faces(voxels: Dictionary[Vector3i, int]) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	
	_meshing_mode = MeshingMode.NAIVE
	
	var face_count := 0
	for p in voxels:
		for face in Voxel.FACES:
			var neighbor_id = voxels.get(p + face)
			if typeof(neighbor_id) != TYPE_INT or not _is_voxel_id_opaque(neighbor_id):
				add_face(p, voxels[p], face)
				face_count += 1
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "Added %d culled faces for %d voxels" % [face_count, voxels.size()])

## Returns whether the voxel with the given ID is fully opaque, using a cache
## so each unique voxel type is resolved only once per mesh build.
## A face is only culled by a neighbor that is opaque; 
## translucent / refractive voxels do not hide the faces behind them.
func _is_voxel_id_opaque(voxel_id: int) -> bool:
	if _opacity_cache.has(voxel_id):
		return _opacity_cache[voxel_id]
	var opaque: bool = is_instance_valid(_voxel_set) and _voxel_set.is_voxel_opaque(voxel_id)
	_opacity_cache[voxel_id] = opaque
	return opaque


func add_greedy_faces(voxels: Dictionary[Vector3i, int]) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	
	_meshing_mode = MeshingMode.GREEDY
	
	# Process each axis separately using the greedy algorithm.
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
	
	# Get the base material from the voxel set.
	var base_material: BaseMaterial3D = _voxel_set.get_material(
		_bare_material_id_from_key(surface_key)
	)
	
	var use_material: Material = base_material
	
	if has_texture:
		if _meshing_mode == MeshingMode.GREEDY:
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
			
			use_material = shader_material
		else:
			# BRUTE/NAIVE: faces are never merged, so UVs are already in atlas
			# space. Duplicate the base material (preserving transparency,
			# refraction, etc.) and set the atlas texture as its albedo.
			# Vertex colors tint the texture just like the greedy shader does.
			if use_material is BaseMaterial3D:
				var textured_material := use_material.duplicate() as BaseMaterial3D
				if textured_material:
					textured_material.albedo_texture = _voxel_set.texture_atlas
					textured_material.vertex_color_use_as_albedo = true
					use_material = textured_material
	
	var ms := MeshSurface.new(surface_key, use_material)
	_surfaces[surface_key] = ms
	return ms

## Extracts the bare material_id from a surface key by stripping the suffix.
func _bare_material_id_from_key(surface_key: String) -> String:
	if surface_key.ends_with(_SURFACE_NOT_TEXTURED):
		return surface_key.trim_suffix(_SURFACE_NOT_TEXTURED)
	elif surface_key.ends_with(_SURFACE_TEXTURED):
		return surface_key.trim_suffix(_SURFACE_TEXTURED)
	return surface_key

func _greedy_by_face(voxels: Dictionary[Vector3i, int], voxel_face: Vector3i) -> int:
	# Step 1: Find all uncovered faces in this direction.
	var uncovered_faces: Dictionary[Vector3i, int] = {}
	
	for voxel_position in voxels:
		var voxel_id: int = voxels[voxel_position]
		if typeof(voxel_id) == TYPE_INT:
			var neighbor_id = voxels.get(voxel_position + voxel_face)
			if typeof(neighbor_id) != TYPE_INT or not _is_voxel_id_opaque(neighbor_id):
				uncovered_faces[voxel_position] = voxel_id
	
	var quad_count := 0
	var last_count: int = -1
	var iteration := 0
	
	# Step 2: Process until all faces are merged.
	while not uncovered_faces.is_empty():
		var count: int = uncovered_faces.size()
		iteration += 1
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "  iter %d: face=%s remaining=%d" % [iteration, Voxel.FACE_NAMES.get(voxel_face, str(voxel_face)), count])
		
		if count == last_count:
			var first_pos: Vector3i = uncovered_faces.keys()[0]
			var first_id: int = uncovered_faces[first_pos]
			var face_name: String = Voxel.FACE_NAMES.get(voxel_face, str(voxel_face))
			# Check if any neighbors exist for the first position (zero-growth detection)
			var stuck_pos: Vector3i = uncovered_faces.keys()[0]
			var adj_right := uncovered_faces.get(stuck_pos + Voxel.ADJACENT_FACES[voxel_face][0])
			var adj_left := uncovered_faces.get(stuck_pos + Voxel.ADJACENT_FACES[voxel_face][1])
			var adj_down := uncovered_faces.get(stuck_pos + Voxel.ADJACENT_FACES[voxel_face][2])
			var adj_up := uncovered_faces.get(stuck_pos + Voxel.ADJACENT_FACES[voxel_face][3])
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, DEBUG_CONTEXT, "LOOP BREAK: face=%s remaining=%d first_pos=%s first_id=%d neighbors(R=%s L=%s D=%s U=%s)" % [face_name, count, first_pos, first_id, adj_right, adj_left, adj_down, adj_up])
			push_error("Greedy meshing: uncovered faces count unchanged, breaking loop")
			break
		
		last_count = count
		
		var start_pos: Vector3i = uncovered_faces.keys()[0]
		var voxel_id: int = uncovered_faces[start_pos]
		
		# Determine primary growth direction.
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
