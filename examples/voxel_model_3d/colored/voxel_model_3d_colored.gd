## Example scene: colored voxel pyramid built at runtime.
##
## Rebuilds the scene by generating a fresh VoxelModel3D with three colored
## voxels (red, green, blue) arranged in a stepped pyramid.
@tool
extends Node3D

## Inspector tool button that triggers the scene rebuild.
@export_tool_button("Rebuild Scene")
var _rebuild_scene_button = _rebuild_scene

## The generated VoxelModel3D node.
var voxel_model_3d: VoxelModel3D

## Rebuilds the example scene: recreates the VoxelModel3D node, populates the
## voxel set with three colored voxels, and fills a stepped pyramid.
func _rebuild_scene() -> void:
	voxel_model_3d = find_child("VoxelModel3D")
	if voxel_model_3d:
		remove_child(voxel_model_3d)
		voxel_model_3d.queue_free()
	
	voxel_model_3d = VoxelModel3D.new()
	add_child(voxel_model_3d)
	voxel_model_3d.name = "VoxelModel3D"
	voxel_model_3d.owner = self
	
	var voxel_set := VoxelSet.new()
	var red_voxel := Voxel.new()
	red_voxel.set_base_color(Color.RED)
	var green_voxel := Voxel.new()
	green_voxel.set_base_color(Color.GREEN)
	var blue_voxel := Voxel.new()
	blue_voxel.set_base_color(Color.BLUE)
	
	voxel_set.set_voxel(0, red_voxel)
	voxel_set.set_voxel(1, green_voxel)
	voxel_set.set_voxel(2, blue_voxel)
	
	voxel_model_3d.voxel_set = voxel_set
	
	for y in range(3):
		for x in range(3 - y):
			for z in range(3 - y):
				voxel_model_3d.set_voxel(Vector3i(x, y, z), y % 3)
	
	voxel_model_3d.update()
	
	print("Example scene built successfully!")
