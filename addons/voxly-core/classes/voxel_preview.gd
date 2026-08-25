@tool
class_name VoxelPreview
extends RefCounted
## Utility to generate a 3D mesh preview of a single voxel type.

## Generates an ArrayMesh preview of the voxel with the given ID from the set.
## The returned mesh has one surface per material, with appropriate vertex colors/UVs.
##
## By default the mesh is centered on its origin, directly at voxel's center.
static func generate(
		voxel_id: int,
		voxel_set: VoxelSet,
		voxel_size: float = 1.0,
		mesh_offset: Vector3 = Vector3.INF
	) -> ArrayMesh:
	if not voxel_set or not voxel_set.voxel_id_exists(voxel_id):
		return null
	
	# Resolve the auto-center sentinel to a voxel-size-aware offset.
	if mesh_offset == Vector3.INF:
		mesh_offset = Vector3(-0.5, -0.5, -0.5) * voxel_size
	
	var mesher := VoxelMesher.create()
	mesher.begin(Vector3.ONE * voxel_size, voxel_set, true, voxel_set.is_texture_ready())
	mesher.add_all_faces({Vector3i.ZERO: voxel_id})
	var mesh := mesher.commit()
	if mesh and mesh_offset != Vector3.ZERO:
		translate_mesh(mesh, mesh_offset)
	
	return mesh


## Translates every surface's vertices of the given ArrayMesh by `offset`,
## preserving surface names, materials, and primitive types.
static func translate_mesh(mesh: ArrayMesh, mesh_offset: Vector3) -> void:
	if not mesh or mesh_offset == Vector3.ZERO:
		return
	
	# Collect all surfaces first, then rebuild, so removing surfaces
	# doesn't shift indices mid-iteration.
	var surface_data: Array[Dictionary] = []
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var has_offset := false
		for v in vertices.size():
			vertices[v] += mesh_offset
			has_offset = true
		if not has_offset:
			continue
		arrays[Mesh.ARRAY_VERTEX] = vertices
		surface_data.append({
			"primitive": mesh.surface_get_primitive_type(i),
			"arrays": arrays,
			"name": mesh.surface_get_name(i),
			"material": mesh.surface_get_material(i),
		})
	
	if surface_data.is_empty():
		return
	
	for i in range(mesh.get_surface_count(), 0, -1):
		mesh.surface_remove(i - 1)
	
	for data in surface_data:
		mesh.add_surface_from_arrays(data["primitive"], data["arrays"])
		mesh.surface_set_name(mesh.get_surface_count() - 1, data["name"])
		var material: Material = data["material"]
		if material:
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
