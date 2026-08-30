## Abstract interface for voxel mesh generators.
##
## Defines the contract that every mesher backend implements, whether it is the
## built-in [VoxelMesherGDScript] or a native GDExtension backend. At runtime,
## [method create] automatically selects the best available backend.
##
## A mesh build happens in three steps:
## 1. [method begin] configures the build (voxel size, palette, and attribute flags).
## 2. One of the face-add methods populates the surfaces ([method add_all_faces],
##    [method add_culled_faces], or [method add_greedy_faces]).
## 3. [method commit] finalizes and returns the resulting [ArrayMesh].
@tool
@abstract
@icon("res://addons/voxly-core/assets/icons/voxel_mesher.svg")
class_name VoxelMesher
extends RefCounted

## Whether a native mesher backend (GDExtension) is available at runtime.
static var native_available: bool:
	get:
		return ClassDB.class_exists("VoxelMesherGDExtension")

## Creates a mesher instance, preferring the native GDExtension backend when it
## is available and falling back to [VoxelMesherGDScript] otherwise.
static func create() -> VoxelMesher:
	if native_available:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, "VoxelMesher", "Using native GDExtension mesher")
		return ClassDB.instantiate("VoxelMesherGDExtension")
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, "VoxelMesher", "Using GDScript mesher")
	return VoxelMesherGDScript.new()

## Begins a new mesh build and resets all internal state.
##
## [param voxel_size]: World-space size of a single voxel.
## [param voxel_set]: The palette providing voxel definitions, materials, and textures.
## [param include_vertex_colors]: Whether generated vertices carry vertex colors.
## [param include_textures]: Whether generated vertices carry UV coordinates.
@abstract
func begin(voxel_size: Vector3, voxel_set: VoxelSet, include_vertex_colors: bool = true, include_textures: bool = true) -> void

## Adds all six faces for every voxel in [param voxels] (brute-force, no culling).
@abstract
func add_all_faces(voxels: Dictionary[Vector3i, int]) -> void

## Adds only the faces that are not hidden by an opaque neighboring voxel.
@abstract
func add_culled_faces(voxels: Dictionary[Vector3i, int]) -> void

## Adds faces using greedy meshing, merging adjacent coplanar faces into quads.
@abstract
func add_greedy_faces(voxels: Dictionary[Vector3i, int]) -> void

## Adds a single quad for one face of a voxel.
##
## [param voxel_position]: Grid position of the voxel.
## [param voxel_id]: ID of the voxel type in the palette.
## [param face_normal]: The direction the face points (one of [constant Voxel.FACES]).
## [param quad_scale]: How many voxels the quad spans on each of its local axes.
@abstract
func add_face(voxel_position: Vector3i, voxel_id: int, face_normal: Vector3i, quad_scale: Vector2i = Vector2i.ONE) -> void

## Commits all accumulated surfaces into a single [ArrayMesh].
@abstract
func commit() -> ArrayMesh

## Clears all accumulated data and resets the build state.
@abstract
func clear() -> void
