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
	var rv := Voxel.new()
	rv.set_base_color(Color.RED)
	var gv := Voxel.new()
	gv.set_base_color(Color.GREEN)
	var bv := Voxel.new()
	bv.set_base_color(Color.BLUE)
	
	vs.set_voxel(0, rv)
	vs.set_voxel(1, gv)
	vs.set_voxel(2, bv)
	
	vm.voxel_set = vs
	
	for y in range(3):
		for x in range(3 - y):
			for z in range(3 - y):
				vm.set_voxel(Vector3i(x, y, z), y % 3)
	
	add_child(vm)
	vm.owner = self
	vm.rebuild_mesh()

	print("Example scene built successfully!")
