@tool
class_name VoxlyEditorPreview
extends Node3D
## Preview overlay for the voxel editor. Uses a MultiMeshInstance3D to
## show voxels at the brush positions, giving visual feedback
## of what will be modified before commited.
##
## The preview source is fully determined by the active tool's declared
## PreviewSource (resolved through VoxlyEditor.get_preview_source()):
##   - PALETTE_VOXEL — the accurate palette voxel mesh with ghost materials
##   - FLAT_COLOR    — a simple colored box, color from the tool
##
## Also hosts the persistent selection overlay: a second MultiMeshInstance3D
## rendering wireframe box outlines around every selected voxel. This layer
## is fully separate from the normal preview so it survives tool/brush
## changes and mouse-outs.
##
## Debug visualization (requires editor_logic category):
##   - Voxel (0,0,0) origin marker (pink)
##   - DDA traversal cells along the ray (yellow)
##   - Hit position marker (green)
##   - Ray line from camera to hit (orange)
##
## All debug boxes are rendered in the same MultiMesh as the preview.

## Whether mirrored preview positions are shown (visual-only ghost mirroring;
## commits always mirror via the editor's mirror axes). The setter writes the
## backing field; the getter reads it so the property stays the source of truth.
var preview_mirrored: bool:
	get = get_preview_mirrored,
	set = set_preview_mirrored

## Backing field for preview_mirrored (avoids recursive setter calls).
var _preview_mirrored: bool = true

## Color for pattern selection highlight.
var selection_color: Color = Color(0.2, 0.5, 1, 0.6)

## Color for pattern drag/hover preview.
var drag_preview_color: Color = Color(1, 1, 1, 0.3)

## Color for the persistent selection outline overlay.
var selection_outline_color: Color = Color(0.2, 1.0, 0.8, 0.9):
	set = set_selection_outline_color

## Thickness of the persistent selection outline.
var selection_outline_thickness: float = 0.08:
	set = set_selection_outline_thickness

## Size of each preview voxel box.
var voxel_size: Vector3 = Vector3(1, 1, 1):
	set = set_voxel_size

## Whether preview is visible.
var preview_visible: bool = true:
	set = set_preview_visible

## Maximum number of preview instances.
var max_instances: int = 5120

## Maximum number of selection outline instances.
var max_selection_instances: int = 5120

# Internal
var _multi_mesh_instance: MultiMeshInstance3D = null
var _multi_mesh: MultiMesh = null
var _box_mesh: BoxMesh = null
var _positions: Array[Vector3i] = []
var _needs_update: bool = false
var _needs_rebuild: bool = true

## True while the preview MultiMesh is showing the palette-voxel mesh.
## While active, per-instance colors are disabled so the mesher's baked
## per-face vertex colors / UVs show through cleanly.
var _textured_active: bool = false

## Cache key for the current preview source so we only rebuild when the
## inputs actually change.
var _textured_key: String = ""

## Tracks the atlas + uv-scale combo so the per-voxel mesh cache is reset
## when the texture atlas or cell size changes.
var _textured_atlas_key: String = ""

## Tracks the voxel size so the per-voxel mesh cache is reset when the
## model's voxel size changes.
## Starts as an impossible sentinel so the first build always regenerates
## meshes with the current centered convention.
var _textured_voxel_size_key: Vector3 = Vector3(INF, INF, INF)

## Cached palette preview meshes, keyed by voxel ID. Each mesh keeps its own
## clean per-surface preview materials, so switching palette voxels shows the 
## correct texture per voxel.
var _textured_meshes: Dictionary = {}

## Flat vertex-color material (used when not showing the palette voxel mesh).
var _flat_material: StandardMaterial3D = null

## Clean palette-voxel preview materials. These replace every surface material
## on the generated palette-voxel mesh so no user PBR/emissive/transparency
## baggage leaks into the ghost preview. Textured surfaces use a standard
## material with the atlas as albedo (the mesher's BRUTE path writes direct
## atlas-space UVs); non-textured surfaces use the vertex-color ghost material,
## which renders the mesher's baked per-face colors accurately and translucent.
var _palette_textured_material: StandardMaterial3D = null
var _palette_ghost_material: StandardMaterial3D = null

# Selection outline layer
var _selection_multi_mesh_instance: MultiMeshInstance3D = null
var _selection_multi_mesh: MultiMesh = null
var _selection_box_mesh: BoxMesh = null
var _selection_material: ShaderMaterial = null
var _selection_positions: Array[Vector3i] = []

## Offset applied to the MultiMeshInstance to align with model origin.
## Set by the controller when editing VoxelModel3D nodes with a non-zero origin.
var origin_offset: Vector3 = Vector3.ZERO:
	set = set_origin_offset

# Debug ray line (separate node since it's a line mesh, not boxes)
var _debug_ray_line: MeshInstance3D = null
var _debug_ray_initialized: bool = false

var _debug_slots: Dictionary = {}
var _debug_enabled: bool = false

const _BOX_OUTLINE_SHADER := preload("res://addons/voxly-core/shaders/box_outline.gdshader")

func _init() -> void:
	name = "VoxlyEditorPreview"

func _ready() -> void:
	_setup_nodes()

func _setup_nodes() -> void:
	if _multi_mesh_instance:
		return
	
	# Create a simple cube mesh
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	
	# MultiMesh for efficient rendering
	_multi_mesh = MultiMesh.new()
	_multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_multi_mesh.use_colors = true
	_multi_mesh.instance_count = max_instances
	_multi_mesh.visible_instance_count = 0
	_multi_mesh.mesh = _box_mesh
	
	_multi_mesh_instance = MultiMeshInstance3D.new()
	_multi_mesh_instance.name = "Preview"
	_multi_mesh_instance.multimesh = _multi_mesh
	add_child(_multi_mesh_instance)
	
	# Create a transparent material for preview boxes
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flat_material = mat
	_multi_mesh_instance.material_override = mat
	
	_selection_box_mesh = BoxMesh.new()
	_selection_box_mesh.size = Vector3.ONE
	
	_selection_material = ShaderMaterial.new()
	_selection_material.shader = _BOX_OUTLINE_SHADER
	_selection_material.set_shader_parameter("outline_color", selection_outline_color)
	_selection_material.set_shader_parameter("outline_thickness", selection_outline_thickness)
	# Depth testing is disabled via the shader's render_mode (depth_test_disabled).
	_selection_box_mesh.material = _selection_material
	
	_selection_multi_mesh = MultiMesh.new()
	_selection_multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_selection_multi_mesh.use_colors = false
	_selection_multi_mesh.instance_count = max_selection_instances
	_selection_multi_mesh.visible_instance_count = 0
	_selection_multi_mesh.mesh = _selection_box_mesh
	
	_selection_multi_mesh_instance = MultiMeshInstance3D.new()
	_selection_multi_mesh_instance.name = "SelectionPreview"
	_selection_multi_mesh_instance.multimesh = _selection_multi_mesh
	add_child(_selection_multi_mesh_instance)
	
	# Ray line (separate since it's a line, not a box mesh)
	_debug_ray_line = MeshInstance3D.new()
	_debug_ray_line.name = "DebugRayLine"
	add_child(_debug_ray_line)
	_debug_ray_line.visible = false

## Sets whether the preview MultiMesh uses per-instance colors. Godot requires
## the instance count to be 0 before toggling this flag, so the buffer is
## reset around the change. Callers must re-apply transforms afterward (the
## update paths already do).
func _set_multimesh_use_colors(enabled: bool) -> void:
	if not _multi_mesh or _multi_mesh.use_colors == enabled:
		return
	
	_multi_mesh.instance_count = 0
	_multi_mesh.use_colors = enabled
	_multi_mesh.instance_count = max_instances
	_multi_mesh.visible_instance_count = 0

## Selects and caches the mesh/material used for every preview instance.
##
## Palette path: When the tool declares PreviewSource.PALETTE_VOXEL.
## Flat path: When the tool declares PreviewSource.FLAT_COLOR or missing palette voxel.
func build_preview_source(voxel_id: int, voxel_set: VoxelSet, preview_source: int) -> void:
	if not _multi_mesh_instance or not _multi_mesh or not _box_mesh:
		return
	
	var use_palette := preview_source == VoxlyTool.PreviewSource.PALETTE_VOXEL
	var key := ""
	if voxel_set != null and use_palette and voxel_set.voxel_id_exists(voxel_id):
		var atlas_id := -1 if voxel_set.texture_atlas == null else voxel_set.texture_atlas.get_instance_id()
		key = "%d|%s|%s|%s|%d" % [
			voxel_id,
			voxel_set.get_instance_id(),
			atlas_id,
			voxel_set.get_texture_uv_scale(),
			preview_source
		]
	else:
		var set_id := -1 if voxel_set == null else voxel_set.get_instance_id()
		key = "flat|%s|%d" % [set_id, preview_source]
	
	if key == _textured_key:
		return
	
	_textured_key = key
	
	if use_palette and voxel_set != null and voxel_set.voxel_id_exists(voxel_id):
		var atlas_id := -1 if voxel_set.texture_atlas == null else voxel_set.texture_atlas.get_instance_id()
		# If the atlas or cell size changed, drop the per-voxel mesh cache so
		# freshly generated meshes pick up the new UV mapping.
		var atlas_key := "%s|%s" % [atlas_id, voxel_set.get_texture_uv_scale()]
		if atlas_key != _textured_atlas_key:
			_textured_atlas_key = atlas_key
			_textured_meshes.clear()
		
		# If the model's voxel size changed, drop the per-voxel mesh cache so
		# meshes built under a different scale/offset convention are rebuilt.
		if voxel_size != _textured_voxel_size_key:
			_textured_voxel_size_key = voxel_size
			_textured_meshes.clear()
		
		# Generate the 6-face textured mesh for this palette voxel.
		var mesh: ArrayMesh = _textured_meshes.get(voxel_id)
		if mesh == null:
			mesh = VoxelPreview.generate(voxel_id, voxel_set, 1.0)
			if mesh != null:
				_textured_meshes[voxel_id] = mesh
		if mesh != null:
			_multi_mesh.mesh = mesh
			_apply_textured_surface_materials(mesh, voxel_set)
			_multi_mesh_instance.material_override = null
			_textured_active = true
			_set_multimesh_use_colors(false)
			return
	
	# Flat path: restore the box mesh + vertex-color material, and instance
	# colors for the tool's per-instance preview color.
	_multi_mesh.mesh = _box_mesh
	_multi_mesh_instance.material_override = _flat_material
	_textured_active = false
	_set_multimesh_use_colors(true)


## Assigns clean preview materials to every surface of the generated voxel mesh.
func _apply_textured_surface_materials(mesh: ArrayMesh, voxel_set: VoxelSet) -> void:
	if _palette_textured_material == null:
		_palette_textured_material = StandardMaterial3D.new()
		_palette_textured_material.vertex_color_use_as_albedo = true
		_palette_textured_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_palette_textured_material.no_depth_test = true
		_palette_textured_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_palette_textured_material.albedo_color = Color(1, 1, 1, 0.6)
	if _palette_ghost_material == null:
		_palette_ghost_material = _palette_textured_material.duplicate()
	
	# Atlas may have changed (or been removed) — keep the textured material in
	# sync. The ghost material always stays texture-free so baked per-face
	# vertex colors render cleanly.
	_palette_textured_material.albedo_texture = voxel_set.texture_atlas
	_palette_ghost_material.albedo_texture = null
	
	for i in mesh.get_surface_count():
		var surface_name: String = mesh.surface_get_name(i)
		# The mesher names surfaces "<material_id>_textured" /
		# "<material_id>_not_textured" (after trim_prefix). With an empty
		# material_id they become exactly "textured" / "not_textured".
		# "_not_textured" also ends with "_textured", so exclude both forms.
		var textured := false
		if surface_name == "not_textured" or surface_name.ends_with("_not_textured"):
			textured = false
		elif surface_name == "textured" or surface_name.ends_with("_textured"):
			textured = true
		mesh.surface_set_material(i, _palette_textured_material if textured else _palette_ghost_material)

## Updates the preview with the given world positions and color.
## The color is fully determined by the caller.
func update_preview(positions: Array[Vector3i], color: Color) -> void:
	_positions = positions
	_preview_color = color
	_apply_update()


## Updates the preview with per-voxel coloring.
## Takes an array of position+color pairs.
func update_preview_colored(colored_positions: Array[Dictionary]) -> void:
	_positions.clear()
	if _multi_mesh:
		_multi_mesh.visible_instance_count = 0
		_set_multimesh_use_colors(true)
	
	if colored_positions.is_empty():
		clear_preview()
		return
	
	var half := voxel_size / 2.0
	var scale_vec := voxel_size * 0.9
	
	var count := mini(colored_positions.size(), max_instances - 64)
	
	for i in count:
		var entry := colored_positions[i]
		var pos := entry.get("position", Vector3i.ZERO)
		var color := entry.get("color", Color.WHITE)
		
		var world_pos := Vector3(pos) * voxel_size + half
		var t := Transform3D()
		t.origin = world_pos
		t.basis = Basis().scaled(scale_vec)
		_multi_mesh.set_instance_transform(i, t)
		_multi_mesh.set_instance_color(i, color)
	
	var total_count := count
	
	if _debug_enabled:
		total_count = _fill_debug_instances(total_count, half, scale_vec)
	
	_multi_mesh.visible_instance_count = total_count


var _preview_color: Color = Color.WHITE


func _apply_update() -> void:
	if not _multi_mesh:
		return
	
	var half := voxel_size / 2.0
	var scale_vec := voxel_size * 0.9  # Slightly smaller than full voxel
	
	var total_count := 0
	var is_visible := preview_visible
	
	var use_instance_colors := _multi_mesh.use_colors
	
	if is_visible:
		# Count how many instances we need
		var preview_count := mini(_positions.size(), max_instances - 64)
		total_count = preview_count
		
		# Fill in preview positions
		for i in preview_count:
			var pos := Vector3(_positions[i])
			var world_pos := pos * voxel_size + half
			var t := Transform3D()
			t.origin = world_pos
			t.basis = Basis().scaled(scale_vec)
			_multi_mesh.set_instance_transform(i, t)
			if use_instance_colors:
				_multi_mesh.set_instance_color(i, _preview_color)
		
		# Add debug visuals if enabled
		if _debug_enabled:
			total_count = _fill_debug_instances(total_count, half, scale_vec)
	
	_multi_mesh.visible_instance_count = total_count


## Clears the preview.
func clear_preview() -> void:
	_positions.clear()
	if _multi_mesh:
		_multi_mesh.visible_instance_count = 0
	clear_debug_ray()

## Updates the persistent selection outline to show the given positions.
## This is independent of the normal preview and is not cleared by
## clear_preview().
func update_selection_preview(positions: Array[Vector3i]) -> void:
	_selection_positions = positions
	_apply_selection_update()


## Clears the persistent selection outline.
func clear_selection_preview() -> void:
	_selection_positions.clear()
	if _selection_multi_mesh:
		_selection_multi_mesh.visible_instance_count = 0


func _apply_selection_update() -> void:
	if not _selection_multi_mesh:
		return
	
	var visible := preview_visible and not _selection_positions.is_empty()
	if not visible:
		_selection_multi_mesh.visible_instance_count = 0
		return
	
	var half := voxel_size / 2.0
	var scale_vec := voxel_size * 0.96
	
	var count := mini(_selection_positions.size(), max_selection_instances)
	
	for i in count:
		var pos := Vector3(_selection_positions[i])
		var world_pos := pos * voxel_size + half
		var t := Transform3D()
		t.origin = world_pos
		t.basis = Basis().scaled(scale_vec)
		_selection_multi_mesh.set_instance_transform(i, t)
	
	_selection_multi_mesh.visible_instance_count = count

## Toggles debug visualization on/off based on the debug flag.
func update_debug_visibility() -> void:
	_debug_enabled = VoxlyDebug.is_category_enabled(VoxlyDebug.CATEGORY_EDITOR_LOGIC)
	if not _debug_enabled:
		# Clear debug DDA instances
		if _multi_mesh:
			_multi_mesh.visible_instance_count = mini(_multi_mesh.visible_instance_count, _positions.size())
		clear_debug_ray()
	# Rebuild preview to include/exclude debug
	_apply_update()


## Fills debug instances into the MultiMesh after the preview positions.
## Returns the new total instance count.
func _fill_debug_instances(start_idx: int, half: Vector3, scale: Vector3) -> int:
	var idx := start_idx
	
	# Debug colors only apply when instance colors are enabled (the palette
	# voxel path runs with use_colors = false so its baked colors show through).
	var use_instance_colors := _multi_mesh.use_colors
	
	# Origin marker at (0,0,0): hot pink
	var origin_pos := Vector3(0, 0, 0) + half
	_multi_mesh.set_instance_transform(idx, Transform3D(Basis().scaled(scale), origin_pos))
	if use_instance_colors:
		_multi_mesh.set_instance_color(idx, Color(1, 0, 1, 0.8))
	idx += 1
	
	# Hit position marker (from _cached_hit): green
	if _cached_hit_position != Vector3i.MAX:
		var hit_pos := Vector3(_cached_hit_position) * voxel_size + half
		_multi_mesh.set_instance_transform(idx, Transform3D(Basis().scaled(scale), hit_pos))
		if use_instance_colors:
			_multi_mesh.set_instance_color(idx, Color(0, 1, 0, 0.7))
		idx += 1
	
	# DDA traversal cells: yellow
	for dda_pos in _cached_dda_positions:
		if idx >= max_instances:
			break
		var dda_world := Vector3(dda_pos) * voxel_size + half
		_multi_mesh.set_instance_transform(idx, Transform3D(Basis().scaled(scale * 0.7), dda_world))
		if use_instance_colors:
			_multi_mesh.set_instance_color(idx, Color(1, 1, 0, 0.35))
		idx += 1
	
	return idx


## Cached debug data set by the controller each frame.
var _cached_hit_position: Vector3i = Vector3i.MAX
var _cached_dda_positions: Array = []

## Stores hit and DDA data for the next _apply_update() call.
func set_debug_hit_data(hit_pos: Vector3i, dda_positions: Array) -> void:
	_cached_hit_position = hit_pos
	_cached_dda_positions = dda_positions


## Shows a debug ray line from camera origin to far point in world space.
## Uses a thin cylinder for better visibility.
func show_debug_ray(camera: Camera3D, screen_pos: Vector2) -> void:
	if not _debug_enabled:
		clear_debug_ray()
		return
	elif not camera:
		return
	
	var from := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var length := 100.0
	
	# Create or reuse the cylinder mesh
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.03
	cylinder.bottom_radius = 0.03
	cylinder.height = length
	
	# Always apply the orange material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.5, 0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	cylinder.material = mat
	_debug_ray_line.mesh = cylinder
	
	# Position the cylinder at its midpoint and align its Y axis with the ray
	var mid_point := from + direction * (length / 2.0)
	
	# Build a basis where Y (cylinder long axis) = direction
	var up_ref := Vector3.UP if abs(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis := up_ref.cross(direction).normalized()
	var y_axis := direction
	var z_axis := x_axis.cross(y_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	_debug_ray_line.transform = Transform3D(basis, mid_point)
	_debug_ray_line.visible = true


## Clears the debug ray line.
func clear_debug_ray() -> void:
	if _debug_ray_line:
		_debug_ray_line.visible = false

func set_voxel_size(new_size: Vector3) -> void:
	voxel_size = new_size


func set_preview_visible(visible: bool) -> void:
	preview_visible = visible
	if not visible:
		clear_preview()
		clear_selection_preview()


func get_preview_mirrored() -> bool:
	return _preview_mirrored

func set_preview_mirrored(mirrored: bool) -> void:
	_preview_mirrored = mirrored


func set_origin_offset(offset: Vector3) -> void:
	if origin_offset == offset:
		return
	
	origin_offset = offset
	if _multi_mesh_instance:
		_multi_mesh_instance.position = offset
	if _selection_multi_mesh_instance:
		_selection_multi_mesh_instance.position = offset


func set_selection_outline_color(color: Color) -> void:
	if selection_outline_color == color:
		return
	
	selection_outline_color = color
	if _selection_material:
		_selection_material.set_shader_parameter("outline_color", color)


func set_selection_outline_thickness(thickness: float) -> void:
	if selection_outline_thickness == thickness:
		return
	
	selection_outline_thickness = thickness
	if _selection_material:
		_selection_material.set_shader_parameter("outline_thickness", thickness)
