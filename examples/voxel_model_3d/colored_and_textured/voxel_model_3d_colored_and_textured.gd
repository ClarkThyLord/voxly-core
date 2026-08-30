## Example scene: colored and textured voxel pyramid built at runtime.
##
## Rebuilds the scene by generating a fresh VoxelModel3D with three colored,
## textured voxels (red, green, blue) arranged in a stepped pyramid.
@tool
extends Node3D

## Inspector tool button that triggers the scene rebuild.
@export_tool_button("Rebuild Scene")
var _rebuild_scene_button = _rebuild_scene

## The generated VoxelModel3D node.
var voxel_model_3d: VoxelModel3D

## Rebuilds the example scene: recreates the VoxelModel3D node, populates the
## voxel set with three colored, textured voxels, and fills a stepped pyramid.
func _rebuild_scene() -> void:
	voxel_model_3d = find_child("VoxelModel3D")
	if voxel_model_3d:
		remove_child(voxel_model_3d)
		voxel_model_3d.queue_free()
	
	voxel_model_3d = VoxelModel3D.new()
	
	var voxel_set := VoxelSet.new()
	voxel_set.texture_atlas = preload("res://assets/textures/kenney_voxel_pack.png")
	voxel_set.texture_atlas_cell_size = Vector2i(128, 128)
	var voxel_1 := Voxel.new()
	voxel_1.set_base_color(Color.RED)
	voxel_1.set_base_texture_cell(Vector2i(0, 0))
	var voxel_2 := Voxel.new()
	voxel_2.set_base_color(Color.GREEN)
	voxel_2.set_base_texture_cell(Vector2i(1, 0))
	var voxel_3 := Voxel.new()
	voxel_3.set_base_color(Color.BLUE)
	voxel_3.set_base_texture_cell(Vector2i(2, 0))
	
	voxel_set.set_voxel(0, voxel_1)
	voxel_set.set_voxel(1, voxel_2)
	voxel_set.set_voxel(2, voxel_3)
	
	voxel_model_3d.voxel_set = voxel_set
	voxel_model_3d.include_textures = true
	
	for y in range(3):
		for x in range(3 - y):
			for z in range(3 - y):
				voxel_model_3d.set_voxel(Vector3i(x, y, z), y % 3)
	
	add_child(voxel_model_3d)
	voxel_model_3d.name = "VoxelModel3D"
	voxel_model_3d.owner = self
	voxel_model_3d.update()
	
	print("Example scene built successfully!")
