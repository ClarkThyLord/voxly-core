@tool
@abstract
@icon("res://addons/voxly-core/assets/icons/voxel_mesher.svg")
class_name VoxelMesher
extends RefCounted
## Abstract class for voxel mesh generators.
## Provides the interface that both GDScript and native C++ backends implement.
## Auto-selects the best available backend at runtime.

var DEBUG_CONTEXT := "VoxelMesher"

## Whether a native mesher (GDExtension) is available.
static var native_available: bool:
	get:
		return ClassDB.class_exists("VoxelMesherGDExtension")

## Creates a VoxelMesher instance, preferring native if available.
static func create() -> VoxelMesher:
	if native_available:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, "VoxelMesher", "Using native GDExtension mesher")
		return ClassDB.instantiate("VoxelMesherGDExtension")
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, "VoxelMesher", "Using GDScript mesher")
	return VoxelMesherGDScript.new()

## Begins a new mesh build.
@abstract
func begin(voxel_size: Vector3, voxel_set: VoxelSet, voxels_colored: bool = true, voxels_textured: bool = true) -> void

## Adds all six faces for each voxel in the dictionary (brute-force, no culling).
@abstract
func add_all_faces(voxels: Dictionary[Vector3i, int]) -> void

## Adds only visible faces by culling those hidden by neighboring voxels.
@abstract
func add_culled_faces(voxels: Dictionary[Vector3i, int]) -> void

## Adds faces using greedy meshing to merge adjacent coplanar faces into quads.
@abstract
func add_greedy_faces(voxels: Dictionary[Vector3i, int]) -> void

## Adds a single face for a voxel.
@abstract
func add_face(voxel_position: Vector3i, voxel_id: int, voxel_face: Vector3i, scale_by: Vector2i = Vector2i.ONE) -> void

## Commits all surfaces into a single ArrayMesh.
@abstract
func commit() -> ArrayMesh

## Clears all data and resets state.
@abstract
func clear() -> void
