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
	add_child(voxel_model_3d)
	voxel_model_3d.name = "VoxelModel3D"
	voxel_model_3d.owner = self
	
	var vs := VoxelSet.new()
	var rv := Voxel.new()
	rv.set_base_color(Color.RED)
	var gv := Voxel.new()
	gv.set_base_color(Color.GREEN)
	var bv := Voxel.new()
	bv.set_base_color(Color.BLUE)
	
	vs.set_voxel(0, rv)
	vs.set_voxel(1, gv)
	vs.set_voxel(2, bv)
	
	voxel_model_3d.voxel_set = vs
	
	for y in range(3):
		for x in range(3 - y):
			for z in range(3 - y):
				voxel_model_3d.set_voxel(Vector3i(x, y, z), y % 3)
	
	voxel_model_3d.rebuild_mesh()
	
	print("Example scene built successfully!")
