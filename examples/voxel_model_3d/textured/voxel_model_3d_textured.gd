@tool
extends Node3D

@export_tool_button("Rebuild Scene")
var _rebuild_scene_button = _rebuild_scene

var voxel_model_3d : VoxelModel3D

func _rebuild_scene():
	voxel_model_3d = find_child("VoxelModel3D")
	if voxel_model_3d:
		remove_child(voxel_model_3d)
		voxel_model_3d.queue_free()
	
	voxel_model_3d = VoxelModel3D.new()
	
	var vs := VoxelSet.new()
	vs.texture_atlas = preload("res://assets/textures/kenney_voxel_pack.png")
	vs.texture_atlas_cell_size = Vector2i(128, 128)
	var v1 := Voxel.new()
	v1.set_base_texture_xy(Vector2i(0, 0))
	var v2 := Voxel.new()
	v2.set_base_texture_xy(Vector2i(1, 0))
	var v3 := Voxel.new()
	v3.set_base_texture_xy(Vector2i(2, 0))
	
	vs.set_voxel(0, v1)
	vs.set_voxel(1, v2)
	vs.set_voxel(2, v3)
	
	voxel_model_3d.voxel_set = vs
	voxel_model_3d.voxels_textured = true
	
	for y in range(3):
		for x in range(3 - y):
			for z in range(3 - y):
				voxel_model_3d.set_voxel(Vector3i(x, y, z), y % 3)
	
	add_child(voxel_model_3d)
	voxel_model_3d.name = "VoxelModel3D"
	voxel_model_3d.owner = self
	voxel_model_3d.rebuild_mesh()

	print("Example scene built successfully!")
