@tool
extends Node3D

@export_tool_button("Rebuild Scene")
var _rebuild_scene_button = _rebuild_scene

func _ready() -> void:
	_rebuild_scene()

func _rebuild_scene():
	for child in get_children():
		remove_child(child)
		child.queue_free()
	
	var vm := VoxelModel3D.new()
	
	var vs := VoxelSet.new()
	vs.texture_atlas = preload("res://assets/textures/kenney_voxel_pack.png")
	vs.texture_atlas_cell_size = Vector2i(128, 128)
	var v1 := Voxel.new()
	v1.set_base_color(Color.RED)
	v1.set_base_texture_xy(Vector2i(0, 0))
	var v2 := Voxel.new()
	v2.set_base_color(Color.GREEN)
	v2.set_base_texture_xy(Vector2i(1, 0))
	var v3 := Voxel.new()
	v3.set_base_color(Color.BLUE)
	v3.set_base_texture_xy(Vector2i(2, 0))
	
	vs.set_voxel(0, v1)
	vs.set_voxel(1, v2)
	vs.set_voxel(2, v3)
	
	vm.voxel_set = vs
	vm.voxels_textured = true
	
	for y in range(3):
		for x in range(3 - y):
			for z in range(3 - y):
				vm.set_voxel(Vector3i(x, y, z), y % 3)
	
	add_child(vm)
	vm.owner = self
	vm.rebuild_mesh()

	print("Example scene built successfully!")
