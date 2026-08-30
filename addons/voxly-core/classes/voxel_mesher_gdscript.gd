## GDScript implementation of the voxel mesher.
##
## Supports all three meshing modes: brute-force, culled (naive), and greedy.
##
## Surfaces are separated by material ID and by whether a face uses a texture.
## This ensures every surface has a consistent vertex attribute layout (all UV
## or no UV), and lets textured surfaces receive the atlas texture on their
## material.
@tool
class_name VoxelMesherGDScript
extends VoxelMesher

## Meshing modes supported by [VoxelMesherGDScript]. They determine how textured
## UVs are generated and sampled:
## - GREEDY writes cell-local UVs plus UV2 (atlas cell position) and uses the
##   [code]greedy_meshing_textured[/code] shader, so merged quads repeat the
##   atlas cell correctly.
## - BRUTE and NAIVE write plain atlas UVs with a standard material, since each
##   face is a single, never-merged cell.
enum MeshingMode {
	BRUTE = 0,
	NAIVE = 1,
	GREEDY = 2,
}

## Debug context tag used when logging through [VoxlyDebug].
const _debug_context: String = "VoxelMesherGDScript"

## Suffix appended to surface keys whose faces carry UV coordinates.
const _SURFACE_TEXTURED := "_textured"

## Suffix appended to surface keys whose faces have no UV coordinates.
const _SURFACE_NOT_TEXTURED := "_not_textured"

## Shader that repeats an atlas cell across greedy-merged quads using cell-local
## UVs plus UV2 (cell grid position).
const _GREEDY_MESHING_TEXTURED_SHADER = preload("res://addons/voxly-core/shaders/greedy_meshing_textured.gdshader")

## True once [method begin] has started a build; resets on [method clear].
var _began: bool = false
## Voxel size in world units used to scale generated geometry.
var _voxel_size: Vector3 = Vector3.ONE
## The voxel set providing materials, textures, and atlas data.
var _voxel_set: VoxelSet
## Whether vertex colors are written into generated meshes.
var _include_vertex_colors: bool = true
## Whether texture coordinates are written into generated meshes.
var _include_textures: bool = true
## Active surfaces, keyed by surface key (material ID + texture suffix).
var _surfaces: Dictionary[String, MeshSurface] = {}
## Caches each voxel type's opacity so it is resolved once per mesh build.
var _opacity_cache: Dictionary[int, bool] = {}
## Meshing strategy used for the current build.
var _meshing_mode: MeshingMode = MeshingMode.GREEDY

## Starts a new mesh build for the given voxel set and output flags.
func begin(voxel_size: Vector3, voxel_set: VoxelSet, include_vertex_colors: bool = true, include_textures: bool = true) -> void:
	_began = true
	_voxel_size = voxel_size
	_voxel_set = voxel_set
	_include_vertex_colors = include_vertex_colors
	_include_textures = include_textures
	_surfaces.clear()
	_opacity_cache.clear()
	_meshing_mode = MeshingMode.GREEDY
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, _debug_context, "Begun: size=%s include_vertex_colors=%s include_textures=%s" % [voxel_size, include_vertex_colors, include_textures])

## Resets the build state so the mesher can be reused.
func clear() -> void:
	_began = false
	_surfaces.clear()

## Finalizes the build and returns the completed [ArrayMesh].
func commit() -> ArrayMesh:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return ArrayMesh.new()
	
	var array_mesh := ArrayMesh.new()
	
	for surface_key in _surfaces:
		var surface: MeshSurface = _surfaces[surface_key]
		var arrays: Array = surface.commit_to_arrays()
		if arrays.is_empty():
			continue
		
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# The surface key is "<material_id>_textured", so stripping the leading
		# underscore yields a clean name like "3_textured".
		var surface_name := surface.surface_id.trim_prefix("_")
		array_mesh.surface_set_name(array_mesh.get_surface_count() - 1, surface_name)
		
		if surface.material:
			array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, surface.material)
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, _debug_context, "Committed mesh: %d surfaces" % array_mesh.get_surface_count())
	return array_mesh

## Adds a single face quad at the given voxel position facing the given normal.
func add_face(voxel_position: Vector3i, voxel_id: int, face_normal: Vector3i, quad_scale: Vector2i = Vector2i.ONE) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	
	quad_scale = quad_scale.max(Vector2i.ONE)
	
	var voxel: Voxel = _voxel_set.get_voxel(voxel_id)
	if not is_instance_valid(voxel):
		return
	
	var material_id: String = voxel.get_face_material_id(face_normal)
	# A face has a texture (uses UV coordinates) only if all of these hold:
	#   1. The global include_textures flag is enabled.
	#   2. The voxel face has a valid texture cell assigned (x >= 0, y >= 0).
	#   3. The VoxelSet has a texture atlas ready to use.
	var has_texture: bool = (_include_textures
		and voxel.has_face_texture_cell(face_normal)
		and _voxel_set.is_texture_ready())
	var surface_key: String = _build_surface_key(material_id, has_texture)
	var surface: MeshSurface = _get_surface(surface_key, has_texture)
	
	surface.set_normal(face_normal)
	
	if _include_vertex_colors:
		var voxel_color := voxel.get_face_color(face_normal)
		# A fully transparent color means "unset" (no tint); render it white.
		if voxel_color.a == 0:
			voxel_color = Color.WHITE
		surface.set_color(voxel_color)
	
	var texture_cell: Vector2i = voxel.get_face_texture_cell(face_normal)
	
	# For GREEDY, textured faces write cell-local UVs (0..quad_scale) plus UV2
	# (atlas cell position) so the greedy_meshing_textured shader can repeat the
	# cell across merged quads.
	# For BRUTE/NAIVE, faces are never merged, so we write atlas UVs directly
	# and use a plain material with the atlas texture as albedo.
	var cell_uv := Vector2(texture_cell)
	
	match face_normal:
		Voxel.FACE_RIGHT:
			_set_face_uv(surface, Vector2(quad_scale.y, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.RIGHT + Vector3i.UP * quad_scale.x) * _voxel_size)
			_set_face_uv(surface, Vector2(quad_scale.y, quad_scale.x), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.RIGHT) * _voxel_size)
			_set_face_uv(surface, Vector2(0, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i(1, 1 * quad_scale.x, 1 * quad_scale.y)) * _voxel_size)
			_set_face_uv(surface, Vector2(0, quad_scale.x), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.RIGHT + Vector3i.BACK * quad_scale.y) * _voxel_size)
		
		Voxel.FACE_LEFT:
			_set_face_uv(surface, Vector2(0, quad_scale.x), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position) * _voxel_size)
			_set_face_uv(surface, Vector2(0, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.UP * quad_scale.x) * _voxel_size)
			_set_face_uv(surface, Vector2(quad_scale.y, quad_scale.x), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.BACK * quad_scale.y) * _voxel_size)
			_set_face_uv(surface, Vector2(quad_scale.y, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.UP * quad_scale.x + Vector3i.BACK * quad_scale.y) * _voxel_size)
		
		Voxel.FACE_TOP:
			_set_face_uv(surface, Vector2(0, quad_scale.y), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.UP + Vector3i.BACK * quad_scale.y) * _voxel_size)
			_set_face_uv(surface, Vector2(0, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.UP) * _voxel_size)
			_set_face_uv(surface, Vector2(quad_scale), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i(1 * quad_scale.x, 1, 1 * quad_scale.y)) * _voxel_size)
			_set_face_uv(surface, Vector2(quad_scale.x, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * quad_scale.x + Vector3i.UP) * _voxel_size)
		
		Voxel.FACE_BOTTOM:
			_set_face_uv(surface, Vector2(0, quad_scale.y), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * quad_scale.x + Vector3i.BACK * quad_scale.y) * _voxel_size)
			_set_face_uv(surface, Vector2(0, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * quad_scale.x) * _voxel_size)
			_set_face_uv(surface, Vector2(quad_scale), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.BACK * quad_scale.y) * _voxel_size)
			_set_face_uv(surface, Vector2(quad_scale.x, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position) * _voxel_size)
		
		Voxel.FACE_FRONT:
			_set_face_uv(surface, Vector2(quad_scale.y, quad_scale.x), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * quad_scale.y) * _voxel_size)
			_set_face_uv(surface, Vector2(quad_scale.y, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * quad_scale.y + Vector3i.UP * quad_scale.x) * _voxel_size)
			_set_face_uv(surface, Vector2(0, quad_scale.x), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position) * _voxel_size)
			_set_face_uv(surface, Vector2(0, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.UP * quad_scale.x) * _voxel_size)
		
		Voxel.FACE_BACK:
			_set_face_uv(surface, Vector2(quad_scale.y, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i(1 * quad_scale.y, 1 * quad_scale.x, 1)) * _voxel_size)
			_set_face_uv(surface, Vector2(quad_scale.y, quad_scale.x), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.RIGHT * quad_scale.y + Vector3i.BACK) * _voxel_size)
			_set_face_uv(surface, Vector2(0, 0), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.UP * quad_scale.x + Vector3i.BACK) * _voxel_size)
			_set_face_uv(surface, Vector2(0, quad_scale.x), cell_uv, has_texture)
			surface.add_vertex(Vector3(voxel_position + Vector3i.BACK) * _voxel_size)
	
	# Emit the two triangles that form the quad (4 vertices in a fan order).
	var new_count: int = surface.vertex_count + 4
	surface.add_index(surface.vertex_count)
	surface.add_index(surface.vertex_count + 1)
	surface.add_index(surface.vertex_count + 2)
	surface.add_index(surface.vertex_count + 1)
	surface.add_index(surface.vertex_count + 3)
	surface.add_index(surface.vertex_count + 2)
	surface.vertex_count = new_count

## Writes the UV (and UV2 for GREEDY) for a textured face vertex.
## - GREEDY: writes cell-local UVs (0..quad_scale) plus UV2 (atlas cell position)
##   so the greedy_meshing_textured shader can repeat the cell across merged quads.
## - BRUTE/NAIVE: writes atlas UVs directly so a plain material with the atlas
##   texture as albedo samples the correct single cell.
func _set_face_uv(surface: MeshSurface, local_uv: Vector2, cell_uv: Vector2, has_texture: bool) -> void:
	if not has_texture:
		return
	if _meshing_mode == MeshingMode.GREEDY:
		surface.set_uv(local_uv)
		surface.set_uv2(cell_uv)
	else:
		surface.set_uv((cell_uv + local_uv) * _voxel_set.get_texture_uv_scale())

## Adds geometry for every voxel in the dictionary without culling.
func add_all_faces(voxels: Dictionary[Vector3i, int]) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	_meshing_mode = MeshingMode.BRUTE
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, _debug_context, "Adding all faces for %d voxels" % voxels.size())
	for voxel_position in voxels:
		for face in Voxel.FACES:
			add_face(voxel_position, voxels[voxel_position], face)

## Adds culled geometry, hiding faces shared with adjacent solid voxels.
func add_culled_faces(voxels: Dictionary[Vector3i, int]) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	
	_meshing_mode = MeshingMode.NAIVE
	
	var face_count := 0
	for voxel_position in voxels:
		for face in Voxel.FACES:
			# Only emit the face when there is no opaque neighbor blocking it.
			var neighbor_id = voxels.get(voxel_position + face)
			if typeof(neighbor_id) != TYPE_INT or not _is_voxel_id_opaque(neighbor_id):
				add_face(voxel_position, voxels[voxel_position], face)
				face_count += 1
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, _debug_context, "Added %d culled faces for %d voxels" % [face_count, voxels.size()])

## Returns whether the voxel with the given ID is fully opaque, using a cache
## so each unique voxel type is resolved only once per mesh build.
## A face is only culled by a neighbor that is opaque; translucent/refractive
## voxels do not hide the faces behind them.
func _is_voxel_id_opaque(voxel_id: int) -> bool:
	if _opacity_cache.has(voxel_id):
		return _opacity_cache[voxel_id]
	var opaque: bool = is_instance_valid(_voxel_set) and _voxel_set.is_voxel_opaque(voxel_id)
	_opacity_cache[voxel_id] = opaque
	return opaque

## Adds greedy-merged geometry for maximum face reduction.
func add_greedy_faces(voxels: Dictionary[Vector3i, int]) -> void:
	if not _began:
		push_error("VoxelMesherGDScript not begun, call begin() first")
		return
	
	_meshing_mode = MeshingMode.GREEDY
	
	# Merge the faces of each axis separately.
	var total_quads := 0
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, _debug_context, "Greedy meshing %d voxels" % voxels.size())
	for face in Voxel.FACES:
		var quads := _greedy_by_face(voxels, face)
		total_quads += quads
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, _debug_context, "Greedy mesh complete: %d total quads" % total_quads)

## Builds a surface key that separates by material ID and by texture presence.
## A single voxel can produce up to 2 surfaces per material ID:
## - One with UV coordinates (for faces that have a texture defined).
## - One without UV coordinates (for faces with no texture).
## This ensures each surface has a consistent vertex attribute layout.
func _build_surface_key(material_id: String, has_texture: bool) -> String:
	return material_id + (_SURFACE_TEXTURED if has_texture else _SURFACE_NOT_TEXTURED)

## Gets or creates the [MeshSurface] for the given key.
##
## When creating a textured surface, the material is set up so the atlas
## texture is sampled correctly (see the mode-specific comments below).
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
			# (0..quad_scale) plus UV2 (cell grid position) into proper atlas UVs.
			# This lets greedy-merged quads correctly repeat the cell texture
			# across the entire merged face without atlas bleeding.
			var shader_material := ShaderMaterial.new()
			shader_material.shader = _GREEDY_MESHING_TEXTURED_SHADER
			shader_material.set_shader_parameter("atlas_texture", _voxel_set.texture_atlas)
			shader_material.set_shader_parameter("uv_scale", _voxel_set.get_texture_uv_scale())
			
			# Inherit base material properties like vertex color usage.
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
	
	var surface := MeshSurface.new(surface_key, use_material)
	_surfaces[surface_key] = surface
	return surface

## Extracts the bare material ID from a surface key by stripping the texture
## suffix.
func _bare_material_id_from_key(surface_key: String) -> String:
	if surface_key.ends_with(_SURFACE_NOT_TEXTURED):
		return surface_key.trim_suffix(_SURFACE_NOT_TEXTURED)
	elif surface_key.ends_with(_SURFACE_TEXTURED):
		return surface_key.trim_suffix(_SURFACE_TEXTURED)
	return surface_key

## Merges all coplanar faces facing [param face_normal] into quads and returns
## the number of quads produced.
## Learn more:
## http://web.archive.org/web/20201112011204/https://www.gedge.ca/dev/2014/08/17/greedy-voxel-meshing
##
## Step 1 collects every exposed face in the given direction. Step 2 repeatedly
## finds the largest rectangle of same-voxel faces and emits it as a single
## quad, erasing the merged cells until none remain.
func _greedy_by_face(voxels: Dictionary[Vector3i, int], face_normal: Vector3i) -> int:
	# Step 1: Find all uncovered faces in this direction.
	var uncovered_faces: Dictionary[Vector3i, int] = {}
	
	for voxel_position in voxels:
		var voxel_id: int = voxels[voxel_position]
		if typeof(voxel_id) == TYPE_INT:
			var neighbor_id = voxels.get(voxel_position + face_normal)
			if typeof(neighbor_id) != TYPE_INT or not _is_voxel_id_opaque(neighbor_id):
				uncovered_faces[voxel_position] = voxel_id
	
	var quad_count := 0
	var last_count: int = -1
	var iteration := 0
	
	# Step 2: Process until all faces are merged.
	while not uncovered_faces.is_empty():
		var count: int = uncovered_faces.size()
		iteration += 1
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, _debug_context, "  iter %d: face=%s remaining=%d" % [iteration, Voxel.FACE_NAMES.get(face_normal, str(face_normal)), count])
		
		if count == last_count:
			# Safety net: the count didn't shrink, so merging would loop forever.
			# Log diagnostics about the first cell's neighbors to aid debugging.
			var first_position: Vector3i = uncovered_faces.keys()[0]
			var first_id: int = uncovered_faces[first_position]
			var face_name: String = Voxel.FACE_NAMES.get(face_normal, str(face_normal))
			var stuck_position: Vector3i = uncovered_faces.keys()[0]
			var neighbor_right := uncovered_faces.get(stuck_position + Voxel.ADJACENT_FACES[face_normal][0])
			var neighbor_left := uncovered_faces.get(stuck_position + Voxel.ADJACENT_FACES[face_normal][1])
			var neighbor_down := uncovered_faces.get(stuck_position + Voxel.ADJACENT_FACES[face_normal][2])
			var neighbor_up := uncovered_faces.get(stuck_position + Voxel.ADJACENT_FACES[face_normal][3])
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, _debug_context, "LOOP BREAK: face=%s remaining=%d first_position=%s first_id=%s neighbors(R=%s L=%s D=%s U=%s)" % [face_name, count, first_position, first_id, neighbor_right, neighbor_left, neighbor_down, neighbor_up])
			push_error("Greedy meshing: uncovered faces count unchanged, breaking loop")
			break
		
		last_count = count
		
		var quad_start_position: Vector3i = uncovered_faces.keys()[0]
		var voxel_id: int = uncovered_faces[quad_start_position]
		
		# Determine how far the starting row extends in the "backward" direction,
		# so the quad can start at the far end and grow forward.
		var primary_scan_direction: Vector3i = Voxel.ADJACENT_FACES[face_normal][1]
		var primary_offset: int = 1
		
		while true:
			var probe_position: Vector3i = quad_start_position + primary_scan_direction * primary_offset
			var probe_id = uncovered_faces.get(probe_position)
			if probe_id == voxel_id:
				primary_offset += 1
			else:
				break
		
		primary_offset -= 1
		quad_start_position += Voxel.ADJACENT_FACES[face_normal][1] * primary_offset
		
		# Measure the primary (row) growth: how many same-voxel faces follow in
		# the primary growth direction from the shifted start position.
		var primary_growth_dir: Vector3i = Voxel.ADJACENT_FACES[face_normal][0]
		var primary_growth_axis: int = primary_growth_dir.max_axis_index()
		var primary_growth: int = 0
		
		while true:
			var probe_id = uncovered_faces.get(quad_start_position + primary_growth_dir * primary_growth)
			if probe_id == voxel_id:
				primary_growth += 1
			else:
				break
		
		# Same as above, but for the secondary axis: first find how far the
		# starting column extends backward, then grow forward.
		var secondary_scan_direction: Vector3i = Voxel.ADJACENT_FACES[face_normal][3]
		var secondary_offset: int = 1
		
		while true:
			var probe_position: Vector3i = quad_start_position + secondary_scan_direction * secondary_offset
			var probe_id = uncovered_faces.get(probe_position)
			if probe_id == voxel_id:
				# Each secondary step is only valid if the ENTIRE primary row of
				# the quad also contains this voxel (a full rectangle of faces).
				var can_expand: bool = false
				for offset_index in range(1, primary_growth + 1):
					probe_id = uncovered_faces.get(probe_position + primary_growth_dir * offset_index)
					if probe_id == voxel_id:
						if offset_index == primary_growth:
							secondary_offset += 1
							can_expand = true
						else:
							break
				if not can_expand:
					break
			else:
				break
		
		secondary_offset -= 1
		quad_start_position += Voxel.ADJACENT_FACES[face_normal][3] * secondary_offset
		
		var secondary_growth_dir: Vector3i = Voxel.ADJACENT_FACES[face_normal][2]
		var secondary_growth_axis: int = secondary_growth_dir.max_axis_index()
		var secondary_growth: int = 0
		
		while true:
			var probe_position: Vector3i = quad_start_position + secondary_growth_dir * secondary_growth
			var probe_id = uncovered_faces.get(probe_position)
			if probe_id == voxel_id:
				# A secondary row is only added if every face across the primary
				# axis of the quad contains the same voxel.
				var can_expand: bool = false
				for offset_index in range(primary_growth):
					var row_probe_position: Vector3i = probe_position + primary_growth_dir * offset_index
					probe_id = uncovered_faces.get(row_probe_position)
					if probe_id == voxel_id:
						if offset_index == primary_growth - 1:
							secondary_growth += 1
							can_expand = true
					else:
						break
				if not can_expand:
					break
			else:
				break
		
		var quad_scale: Vector2i = Vector2i(primary_growth, secondary_growth).max(Vector2i.ONE)
		
		add_face(quad_start_position, voxel_id, face_normal, quad_scale)
		
		quad_count += 1
		
		# Erase the merged faces so they aren't processed again.
		for x in range(quad_scale.x):
			for y in range(quad_scale.y):
				var erase_position: Vector3i = Vector3i(quad_start_position)
				erase_position[primary_growth_axis] += x
				erase_position[secondary_growth_axis] += y
				uncovered_faces.erase(erase_position)
	
	return quad_count

## A [SurfaceTool] that also tracks the material assigned to it and the running
## vertex count, so each surface knows where the next quad's indices begin.
class MeshSurface extends SurfaceTool:
	var surface_id: String
	var material: Material
	var vertex_count: int
	
	## Creates a surface tracking the given material and a starting vertex count of zero.
	func _init(surface_id, material: Material) -> void:
		self.surface_id = surface_id
		self.material = material
		vertex_count = 0
		
		begin(Mesh.PRIMITIVE_TRIANGLES)
		set_material(self.material)
