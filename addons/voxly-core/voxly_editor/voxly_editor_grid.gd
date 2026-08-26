@tool
class_name VoxlyEditorGrid
extends Node3D
## Grid/cage overlay for the voxel editor.
##
## Grid modes:
##   FLOOR          - Solid plane at the bottom of the cage
##   FLOOR_WIRED    - Grid lines on the bottom plane
##   BOUNDING       - 12 outer box edges (wireframe skeleton)
##   BOUNDING_WIRED - Grid lines on all 6 cage faces (3D graph paper)
##   BOUNDING_SOLID - Semi-transparent solid faces viewed from inside
##
## Color modes:
##   BY_AXIS       - Lines/faces colored by their dominant axis (X=Red, Y=Green, Z=Blue)
##   CUSTOM_COLOR  - All lines/faces use the specified grid_color

enum GridMode {
	FLOOR = 0,
	FLOOR_WIRED = 1,
	BOUNDING = 2,
	BOUNDING_WIRED = 3,
	BOUNDING_SOLID = 4,
}

enum GridColorMode {
	BY_AXIS = 0,
	CUSTOM_COLOR = 1,
}

## Current grid display mode.
var grid_mode: GridMode = GridMode.BOUNDING_WIRED:
	set = set_grid_mode

## How the grid is colored.
var grid_colored: GridColorMode = GridColorMode.BY_AXIS:
	set = set_grid_colored

## Size of each voxel cell in world units.
var voxel_size: Vector3 = Vector3(1, 1, 1):
	set = set_voxel_size

## Shape/dimensions of the model in voxel units.
var shape: Vector3i = Vector3i(16, 16, 16):
	set = set_shape

## Color of the grid lines (used only when grid_colored == CUSTOM_COLOR).
var grid_color: Color = Color(1, 1, 1, 0.5):
	set = set_grid_color

## Whether the grid is visible.
var grid_visible: bool = true:
	set = set_grid_visible

## Whether the grid is disabled (hidden due to editing state).
var disabled: bool = false:
	set = set_disabled

## Offset applied to the visual mesh (not collision) to align with
## model origin. Set by the controller when editing VoxelModel3D
## nodes that have a non-zero origin.
var origin_offset: Vector3 = Vector3.ZERO:
	set = set_origin_offset

## The world-space size of the cage.
var _cage_size: Vector3 = Vector3.ONE

## Single MeshInstance3D for all grid modes
var _mesh_instance: MeshInstance3D = null

## Collision
var _static_body: StaticBody3D = null
var _collision_shape: CollisionShape3D = null

## Shared shader material
var _material: ShaderMaterial = null

## Cached shader resource
const _GRID_SHADER := preload("res://addons/voxly-core/shaders/grid_shader.gdshader")

func _init() -> void:
	name = "VoxlyEditorGrid"
	_material = ShaderMaterial.new()
	_material.shader = _GRID_SHADER
	_update_shader_params()


func _ready() -> void:
	_setup_nodes()
	_rebuild()

func _setup_nodes() -> void:
	if _mesh_instance:
		return
	
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "GridMesh"
	add_child(_mesh_instance)
	
	_static_body = StaticBody3D.new()
	_static_body.name = "CageCollision"
	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "CageCollisionShape"
	_static_body.add_child(_collision_shape)
	add_child(_static_body)
	
	_static_body.collision_layer = 2

func _rebuild() -> void:
	if not is_inside_tree():
		_needs_rebuild = true
		return
	
	_needs_rebuild = false
	
	var visible_flag := grid_visible and not disabled
	
	_cage_size = Vector3(maxi(shape.x, 1), maxi(shape.y, 1), maxi(shape.z, 1)) * voxel_size
	
	_mesh_instance.visible = false
	
	if not visible_flag:
		_rebuild_collision()
		return
	
	# Enable face culling
	var cull := grid_mode == GridMode.BOUNDING_WIRED or grid_mode == GridMode.BOUNDING_SOLID
	_material.set_shader_parameter("cull_faces", cull)
	
	match grid_mode:
		GridMode.FLOOR:
			_rebuild_floor()
		GridMode.FLOOR_WIRED:
			_rebuild_floor_wired()
		GridMode.BOUNDING:
			_rebuild_cage()
		GridMode.BOUNDING_WIRED:
			_rebuild_cage_faces()
		GridMode.BOUNDING_SOLID:
			_rebuild_cage_solid()
	
	_rebuild_collision()

func _rebuild_floor() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var sx := _cage_size.x
	var sz := _cage_size.z
	var y_pos := -voxel_size.y * 0.01
	
	st.set_normal(Vector3.UP)
	
	st.add_vertex(Vector3(0, y_pos, 0))
	st.add_vertex(Vector3(sx, y_pos, 0))
	st.add_vertex(Vector3(sx, y_pos, sz))
	st.add_vertex(Vector3(0, y_pos, 0))
	st.add_vertex(Vector3(sx, y_pos, sz))
	st.add_vertex(Vector3(0, y_pos, sz))
	
	var mesh := st.commit()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _material
	_mesh_instance.position = origin_offset
	_mesh_instance.visible = true


func _rebuild_floor_wired() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	
	var sx := _cage_size.x
	var sz := _cage_size.z
	var y_pos := -voxel_size.y * 0.01
	
	st.set_normal(Vector3.UP)
	
	for z_step in range(shape.z + 1):
		var z_pos := z_step * voxel_size.z
		st.add_vertex(Vector3(0, y_pos, z_pos))
		st.add_vertex(Vector3(sx, y_pos, z_pos))
	
	for x_step in range(shape.x + 1):
		var x_pos := x_step * voxel_size.x
		st.add_vertex(Vector3(x_pos, y_pos, 0))
		st.add_vertex(Vector3(x_pos, y_pos, sz))
	
	var mesh := st.commit()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _material
	_mesh_instance.position = origin_offset
	_mesh_instance.visible = true

func _rebuild_cage() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	
	var sx := _cage_size.x
	var sy := _cage_size.y
	var sz := _cage_size.z
	
	var corners := [
		Vector3(0, 0, 0), Vector3(sx, 0, 0), Vector3(sx, 0, sz), Vector3(0, 0, sz),
		Vector3(0, sy, 0), Vector3(sx, sy, 0), Vector3(sx, sy, sz), Vector3(0, sy, sz),
	]
	
	var edge_data := [
		[0, 1, Vector3.RIGHT], [3, 2, Vector3.RIGHT],
		[4, 5, Vector3.RIGHT], [7, 6, Vector3.RIGHT],
		[0, 4, Vector3.UP], [1, 5, Vector3.UP],
		[2, 6, Vector3.UP], [3, 7, Vector3.UP],
		[0, 3, Vector3.BACK], [1, 2, Vector3.BACK],
		[4, 7, Vector3.BACK], [5, 6, Vector3.BACK],
	]
	
	for edge in edge_data:
		st.set_normal(edge[2])
		st.add_vertex(corners[edge[0]])
		st.add_vertex(corners[edge[1]])
	
	var mesh := st.commit()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _material
	_mesh_instance.position = origin_offset
	_mesh_instance.visible = true

func _rebuild_cage_faces() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	
	var sx := _cage_size.x
	var sy := _cage_size.y
	var sz := _cage_size.z
	
	# Right face (X = sx): normal = LEFT
	st.set_normal(Vector3.LEFT)
	for y in range(shape.y + 1):
		var y_pos := y * voxel_size.y
		st.add_vertex(Vector3(sx, y_pos, 0))
		st.add_vertex(Vector3(sx, y_pos, sz))
	for z in range(shape.z + 1):
		var z_pos := z * voxel_size.z
		st.add_vertex(Vector3(sx, 0, z_pos))
		st.add_vertex(Vector3(sx, sy, z_pos))
	
	# Left face (X = 0): normal = RIGHT
	st.set_normal(Vector3.RIGHT)
	for y in range(shape.y + 1):
		var y_pos := y * voxel_size.y
		st.add_vertex(Vector3(0, y_pos, 0))
		st.add_vertex(Vector3(0, y_pos, sz))
	for z in range(shape.z + 1):
		var z_pos := z * voxel_size.z
		st.add_vertex(Vector3(0, 0, z_pos))
		st.add_vertex(Vector3(0, sy, z_pos))
	
	# Top face (Y = sy): normal = DOWN
	st.set_normal(Vector3.DOWN)
	for x in range(shape.x + 1):
		var x_pos := x * voxel_size.x
		st.add_vertex(Vector3(x_pos, sy, 0))
		st.add_vertex(Vector3(x_pos, sy, sz))
	for z in range(shape.z + 1):
		var z_pos := z * voxel_size.z
		st.add_vertex(Vector3(0, sy, z_pos))
		st.add_vertex(Vector3(sx, sy, z_pos))
	
	# Bottom face (Y = 0): normal = UP
	st.set_normal(Vector3.UP)
	for x in range(shape.x + 1):
		var x_pos := x * voxel_size.x
		st.add_vertex(Vector3(x_pos, 0, 0))
		st.add_vertex(Vector3(x_pos, 0, sz))
	for z in range(shape.z + 1):
		var z_pos := z * voxel_size.z
		st.add_vertex(Vector3(0, 0, z_pos))
		st.add_vertex(Vector3(sx, 0, z_pos))
	
	# Front face (Z = sz): normal = FORWARD
	st.set_normal(Vector3.FORWARD)
	for x in range(shape.x + 1):
		var x_pos := x * voxel_size.x
		st.add_vertex(Vector3(x_pos, 0, sz))
		st.add_vertex(Vector3(x_pos, sy, sz))
	for y in range(shape.y + 1):
		var y_pos := y * voxel_size.y
		st.add_vertex(Vector3(0, y_pos, sz))
		st.add_vertex(Vector3(sx, y_pos, sz))
	
	# Back face (Z = 0): normal = BACK
	st.set_normal(Vector3.BACK)
	for x in range(shape.x + 1):
		var x_pos := x * voxel_size.x
		st.add_vertex(Vector3(x_pos, 0, 0))
		st.add_vertex(Vector3(x_pos, sy, 0))
	for y in range(shape.y + 1):
		var y_pos := y * voxel_size.y
		st.add_vertex(Vector3(0, y_pos, 0))
		st.add_vertex(Vector3(sx, y_pos, 0))
	
	var mesh := st.commit()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _material
	_mesh_instance.position = origin_offset
	_mesh_instance.visible = true

func _rebuild_cage_solid() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var sx := _cage_size.x
	var sy := _cage_size.y
	var sz := _cage_size.z
	
	# Normals point INWARD, winding CCW from inside
	var faces := [
		[Vector3(0, 0, sz), Vector3(sx, 0, sz), Vector3(sx, sy, sz), Vector3(0, sy, sz), Vector3.FORWARD],
		[Vector3(sx, 0, 0), Vector3(0, 0, 0), Vector3(0, sy, 0), Vector3(sx, sy, 0), Vector3.BACK],
		[Vector3(0, 0, 0), Vector3(0, 0, sz), Vector3(0, sy, sz), Vector3(0, sy, 0), Vector3.RIGHT],
		[Vector3(sx, 0, sz), Vector3(sx, 0, 0), Vector3(sx, sy, 0), Vector3(sx, sy, sz), Vector3.LEFT],
		[Vector3(0, sy, 0), Vector3(0, sy, sz), Vector3(sx, sy, sz), Vector3(sx, sy, 0), Vector3.DOWN],
		[Vector3(0, 0, sz), Vector3(0, 0, 0), Vector3(sx, 0, 0), Vector3(sx, 0, sz), Vector3.UP],
	]
	
	for face in faces:
		var n: Vector3 = face[4]
		st.set_normal(n)
		st.add_vertex(face[0])
		st.add_vertex(face[1])
		st.add_vertex(face[2])
		st.add_vertex(face[0])
		st.add_vertex(face[2])
		st.add_vertex(face[3])
	
	var mesh := st.commit()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _material
	_mesh_instance.position = origin_offset
	_mesh_instance.visible = true

func _rebuild_collision() -> void:
	var size := _cage_size
	if size.length_squared() <= 0:
		_collision_shape.shape = null
		return
	
	var sx := size.x
	var sy := size.y
	var sz := size.z
	
	# Build a ConcavePolygonShape3D from the same 6 interior faces as the
	# solid visual cage. This allows hits from both inside and outside,
	# always returning the inward-pointing normal.
	var face_verts := PackedVector3Array()
	var faces := [
		[Vector3(0, 0, sz), Vector3(sx, 0, sz), Vector3(sx, sy, sz), Vector3(0, sy, sz)],
		[Vector3(sx, 0, 0), Vector3(0, 0, 0), Vector3(0, sy, 0), Vector3(sx, sy, 0)],
		[Vector3(0, 0, 0), Vector3(0, 0, sz), Vector3(0, sy, sz), Vector3(0, sy, 0)],
		[Vector3(sx, 0, sz), Vector3(sx, 0, 0), Vector3(sx, sy, 0), Vector3(sx, sy, sz)],
		[Vector3(0, sy, 0), Vector3(0, sy, sz), Vector3(sx, sy, sz), Vector3(sx, sy, 0)],
		[Vector3(0, 0, sz), Vector3(0, 0, 0), Vector3(sx, 0, 0), Vector3(sx, 0, sz)],
	]
	for f in faces:
		face_verts.append(f[0])
		face_verts.append(f[1])
		face_verts.append(f[2])
		face_verts.append(f[0])
		face_verts.append(f[2])
		face_verts.append(f[3])

	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(face_verts)
	_collision_shape.shape = concave
	# Position the collision at origin_offset so it aligns with the visual mesh
	# and the model's actual rendered position.
	_static_body.position = origin_offset

func _update_shader_params() -> void:
	if not _material:
		return
	
	_material.set_shader_parameter("color_mode", grid_colored)
	_material.set_shader_parameter("custom_color", grid_color)

var _needs_rebuild: bool = true

func set_grid_mode(mode: GridMode) -> void:
	if grid_mode == mode:
		return
	
	grid_mode = mode
	_rebuild()

func set_grid_colored(colored: GridColorMode) -> void:
	if grid_colored == colored:
		return
	
	grid_colored = colored
	_update_shader_params()

func set_voxel_size(new_size: Vector3) -> void:
	if voxel_size == new_size:
		return
	
	voxel_size = new_size
	_rebuild()

func set_shape(new_shape: Vector3i) -> void:
	if shape == new_shape:
		return
	
	shape = new_shape
	_rebuild()

func set_grid_color(color: Color) -> void:
	grid_color = color
	_update_shader_params()

func set_grid_visible(visible: bool) -> void:
	grid_visible = visible
	_rebuild()

func set_disabled(new_disabled: bool) -> void:
	if disabled == new_disabled:
		return
	
	disabled = new_disabled
	_rebuild()

func set_origin_offset(offset: Vector3) -> void:
	if origin_offset == offset:
		return
	
	origin_offset = offset
	_rebuild()
