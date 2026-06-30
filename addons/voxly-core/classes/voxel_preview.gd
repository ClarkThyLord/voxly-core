@tool
class_name VoxelPreview
extends RefCounted
## Utility to generate a 3D mesh preview of a single voxel type.

## Generates an ArrayMesh preview of the voxel with the given ID from the set.
## The returned mesh has one surface per material, with appropriate vertex colors/UVs.
static func generate(voxel_id: int, voxel_set: VoxelSet, voxel_size: float = 1.0) -> ArrayMesh:
	if not voxel_set or not voxel_set.voxel_id_exists(voxel_id):
		return null
	
	var mesher := VoxelMesher.create()
	mesher.begin(Vector3.ONE * voxel_size, voxel_set, true, voxel_set.is_texture_ready())
	
	for face in Voxel.FACES:
		mesher.add_face(Vector3i.ZERO, voxel_id, face)
	
	return mesher.commit()
