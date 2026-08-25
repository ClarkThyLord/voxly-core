@tool
extends Label

## The VoxelSet whose voxels to scan for material usage.
@export
var voxel_set: VoxelSet = null:
	set = _set_voxel_set

## Currently selected material id. Empty string means nothing selected.
@export
var material_id: String = "":
	set = _set_material_id

var _pending_refresh := false

func _set_voxel_set(new_set: VoxelSet) -> void:
	if voxel_set == new_set:
		return
	if voxel_set and voxel_set.voxels_changed.is_connected(_refresh):
		voxel_set.voxels_changed.disconnect(_refresh)
	if voxel_set and voxel_set.materials_changed.is_connected(_refresh):
		voxel_set.materials_changed.disconnect(_refresh)
	voxel_set = new_set
	if voxel_set and not voxel_set.voxels_changed.is_connected(_refresh):
		voxel_set.voxels_changed.connect(_refresh)
	if voxel_set and not voxel_set.materials_changed.is_connected(_refresh):
		voxel_set.materials_changed.connect(_refresh)
	if is_inside_tree():
		_refresh()
	else:
		_pending_refresh = true

func _set_material_id(new_id: String) -> void:
	if new_id == material_id:
		return
	material_id = new_id
	_refresh()

func _ready() -> void:
	if _pending_refresh:
		_refresh()

## Recomputes and displays usage info for the current material.
func refresh() -> void:
	_refresh()

func _refresh() -> void:
	_pending_refresh = false
	
	if not voxel_set:
		text = ""
		return
	
	if material_id.is_empty():
		var default_base_count := 0
		var default_face_refs := 0
		var default_voxels := 0
		for vid in voxel_set.get_voxel_ids():
			var voxel := voxel_set.get_voxel(vid)
			var uses := false
			var base_unset := voxel.get_base_material_id() == Voxel.UNSET_MATERIAL_ID
			if base_unset:
				default_base_count += 1
				uses = true
			for face in Voxel.FACES:
				if base_unset and voxel.get_face_material_id(face, false) == Voxel.UNSET_MATERIAL_ID:
					default_face_refs += 1
					uses = true
			if uses:
				default_voxels += 1
		var lines: PackedStringArray = ["Default material"]
		if default_voxels == 0:
			lines.append("Not used by any voxels")
		else:
			lines.append("Used by: %d / %d voxels" % [default_voxels, voxel_set.get_voxels_count()])
			lines.append("Base: %d · Faces: %d" % [default_base_count, default_face_refs])
		text = "\n".join(lines)
		return
	
	if not voxel_set.material_id_exists(material_id):
		text = "Material not found"
		return
	
	var base_count := 0
	var face_refs := 0
	var voxels_used := 0
	
	for vid in voxel_set.get_voxel_ids():
		var voxel := voxel_set.get_voxel(vid)
		var uses := false
		if voxel.get_base_material_id() == material_id:
			base_count += 1
			uses = true
		for face in Voxel.FACES:
			if voxel.get_face_material_id(face, false) == material_id:
				face_refs += 1
				uses = true
		if uses:
			voxels_used += 1
	
	var lines: PackedStringArray = []
	if voxels_used == 0:
		lines.append("Not used by any voxels")
	else:
		lines.append("Used by: %d / %d voxels" % [voxels_used, voxel_set.get_voxels_count()])
		lines.append("Base: %d · Faces: %d" % [base_count, face_refs])
	text = "\n".join(lines)
