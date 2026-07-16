@tool
class_name VoxReader
extends RefCounted
## MagicaVoxel (.vox) file reader.
##
## Parses the VOX format (version 150-200) and returns:
##   - "voxels": Single flat dictionary of ALL voxels merged together (backward compat)
##   - "scene_models": Array per-scene-model data with transforms applied
##   - "palette": {int -> Voxel} palette entries
##   - "materials": {int -> Dictionary} material properties
##
## Each scene_model entry: { voxels: {Vector3i: int}, transform: Transform3D, size: Vector3i }

const DEBUG_CONTEXT := "VoxReader"

enum NodeType {
	TRANSFORM,
	GROUP,
	SHAPE,
}

## Default MagicaVoxel palette (256 colors)
const MAGICA_VOXEL_PALETTE: Array[Color] = [
	Color("00000000"), Color("ffffffff"), Color("ffccffff"), Color("ff99ffff"),
	Color("ff66ffff"), Color("ff33ffff"), Color("ff00ffff"), Color("ffffccff"),
	Color("ffccccff"), Color("ff99ccff"), Color("ff66ccff"), Color("ff33ccff"),
	Color("ff00ccff"), Color("ffff99ff"), Color("ffcc99ff"), Color("ff9999ff"),
	Color("ff6699ff"), Color("ff3399ff"), Color("ff0099ff"), Color("ffff66ff"),
	Color("ffcc66ff"), Color("ff9966ff"), Color("ff6666ff"), Color("ff3366ff"),
	Color("ff0066ff"), Color("ffff33ff"), Color("ffcc33ff"), Color("ff9933ff"),
	Color("ff6633ff"), Color("ff3333ff"), Color("ff0033ff"), Color("ffff00ff"),
	Color("ffcc00ff"), Color("ff9900ff"), Color("ff6600ff"), Color("ff3300ff"),
	Color("ff0000ff"), Color("ffffffcc"), Color("ffccffcc"), Color("ff99ffcc"),
	Color("ff66ffcc"), Color("ff33ffcc"), Color("ff00ffcc"), Color("ffffcccc"),
	Color("ffcccccc"), Color("ff99cccc"), Color("ff66cccc"), Color("ff33cccc"),
	Color("ff00cccc"), Color("ffff99cc"), Color("ffcc99cc"), Color("ff9999cc"),
	Color("ff6699cc"), Color("ff3399cc"), Color("ff0099cc"), Color("ffff66cc"),
	Color("ffcc66cc"), Color("ff9966cc"), Color("ff6666cc"), Color("ff3366cc"),
	Color("ff0066cc"), Color("ffff33cc"), Color("ffcc33cc"), Color("ff9933cc"),
	Color("ff6633cc"), Color("ff3333cc"), Color("ff0033cc"), Color("ffff00cc"),
	Color("ffcc00cc"), Color("ff9900cc"), Color("ff6600cc"), Color("ff3300cc"),
	Color("ff0000cc"), Color("ffffff99"), Color("ffccff99"), Color("ff99ff99"),
	Color("ff66ff99"), Color("ff33ff99"), Color("ff00ff99"), Color("ffffcc99"),
	Color("ffcccc99"), Color("ff99cc99"), Color("ff66cc99"), Color("ff33cc99"),
	Color("ff00cc99"), Color("ffff9999"), Color("ffcc9999"), Color("ff999999"),
	Color("ff669999"), Color("ff339999"), Color("ff009999"), Color("ffff6699"),
	Color("ffcc6699"), Color("ff996699"), Color("ff666699"), Color("ff336699"),
	Color("ff006699"), Color("ffff3399"), Color("ffcc3399"), Color("ff993399"),
	Color("ff663399"), Color("ff333399"), Color("ff003399"), Color("ffff0099"),
	Color("ffcc0099"), Color("ff990099"), Color("ff660099"), Color("ff330099"),
	Color("ff000099"), Color("ffffff66"), Color("ffccff66"), Color("ff99ff66"),
	Color("ff66ff66"), Color("ff33ff66"), Color("ff00ff66"), Color("ffffcc66"),
	Color("ffcccc66"), Color("ff99cc66"), Color("ff66cc66"), Color("ff33cc66"),
	Color("ff00cc66"), Color("ffff9966"), Color("ffcc9966"), Color("ff999966"),
	Color("ff669966"), Color("ff339966"), Color("ff009966"), Color("ffff6666"),
	Color("ffcc6666"), Color("ff996666"), Color("ff666666"), Color("ff336666"),
	Color("ff006666"), Color("ffff3366"), Color("ffcc3366"), Color("ff993366"),
	Color("ff663366"), Color("ff333366"), Color("ff003366"), Color("ffff0066"),
	Color("ffcc0066"), Color("ff990066"), Color("ff660066"), Color("ff330066"),
	Color("ff000066"), Color("ffffff33"), Color("ffccff33"), Color("ff99ff33"),
	Color("ff66ff33"), Color("ff33ff33"), Color("ff00ff33"), Color("ffffcc33"),
	Color("ffcccc33"), Color("ff99cc33"), Color("ff66cc33"), Color("ff33cc33"),
	Color("ff00cc33"), Color("ffff9933"), Color("ffcc9933"), Color("ff999933"),
	Color("ff669933"), Color("ff339933"), Color("ff009933"), Color("ffff6633"),
	Color("ffcc6633"), Color("ff996633"), Color("ff666633"), Color("ff336633"),
	Color("ff006633"), Color("ffff3333"), Color("ffcc3333"), Color("ff993333"),
	Color("ff663333"), Color("ff333333"), Color("ff003333"), Color("ffff0033"),
	Color("ffcc0033"), Color("ff990033"), Color("ff660033"), Color("ff330033"),
	Color("ff000033"), Color("ffffff00"), Color("ffccff00"), Color("ff99ff00"),
	Color("ff66ff00"), Color("ff33ff00"), Color("ff00ff00"), Color("ffffcc00"),
	Color("ffcccc00"), Color("ff99cc00"), Color("ff66cc00"), Color("ff33cc00"),
	Color("ff00cc00"), Color("ffff9900"), Color("ffcc9900"), Color("ff999900"),
	Color("ff669900"), Color("ff339900"), Color("ff009900"), Color("ffff6600"),
	Color("ffcc6600"), Color("ff996600"), Color("ff666600"), Color("ff336600"),
	Color("ff006600"), Color("ffff3300"), Color("ffcc3300"), Color("ff993300"),
	Color("ff663300"), Color("ff333300"), Color("ff003300"), Color("ffff0000"),
	Color("ffcc0000"), Color("ff990000"), Color("ff660000"), Color("ff330000"),
	Color("ff0000ee"), Color("ff0000dd"), Color("ff0000bb"), Color("ff0000aa"),
	Color("ff000088"), Color("ff000077"), Color("ff000055"), Color("ff000044"),
	Color("ff000022"), Color("ff000011"), Color("ff00ee00"), Color("ff00dd00"),
	Color("ff00bb00"), Color("ff00aa00"), Color("ff008800"), Color("ff007700"),
	Color("ff005500"), Color("ff004400"), Color("ff002200"), Color("ff001100"),
	Color("ffee0000"), Color("ffdd0000"), Color("ffbb0000"), Color("ffaa0000"),
	Color("ff880000"), Color("ff770000"), Color("ff550000"), Color("ff440000"),
	Color("ff220000"), Color("ff110000"), Color("ffeeeeee"), Color("ffdddddd"),
	Color("ffbbbbbb"), Color("ffaaaaaa"), Color("ff888888"), Color("ff777777"),
	Color("ff555555"), Color("ff444444"), Color("ff222222"), Color("ff111111"),
]


## Parses the contents of an already-opened .vox file.
## @param file: An open FileAccess in READ mode, positioned at the start of a .vox file
## @return: Dictionary with "error", "voxels", "scene_models", "palette", and "materials" keys
static func read(file: FileAccess) -> Dictionary:
	var result := {
		"error": OK,
		"scene_models": [],
		"voxels": {},
		"palette": {},
		"materials": {},
	}
	
	# Read header
	var header: String = file.get_buffer(4).get_string_from_ascii()
	var version: int = file.get_32()
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Reading VOX file - header='%s' version=%d" % [header, version])
	
	if header != "VOX " or (version != 150 and version != 200):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Unrecognized VOX file: header='%s' version=%d (expected 150 or 200)" % [header, version])
		result["error"] = ERR_FILE_UNRECOGNIZED
		return result
	
	if version == 200:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "VOX version 200 detected")
	
	# Raw models from XYZI chunks (size + voxels)
	var raw_models: Array[Dictionary] = []
	
	# Scene graph nodes indexed by node_id
	var nodes: Dictionary = {}
	
	var pending_size: Vector3i = Vector3i.ZERO
	
	while file.get_position() < file.get_length():
		var chunk_id: String = file.get_buffer(4).get_string_from_ascii()
		var chunk_size: int = file.get_32()
		var chunk_child_size: int = file.get_32()
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Chunk: id='%s' size=%d child_size=%d pos=%d" % [chunk_id, chunk_size, chunk_child_size, file.get_position()])
		
		match chunk_id:
			"MAIN":
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Found MAIN chunk with %d bytes of children" % chunk_child_size)
				pass
			
			"SIZE":
				pending_size.x = file.get_32()
				pending_size.z = file.get_32()
				pending_size.y = file.get_32()
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "SIZE chunk: %s" % pending_size)
			
			"XYZI":
				var model := { "size": pending_size, "voxels": {} }
				var num_voxels: int = file.get_32()
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "XYZI chunk: num_voxels=%d size=%s" % [num_voxels, pending_size])
				for i in num_voxels:
					var x: int = pending_size.x - file.get_8() - 1
					var z: int = file.get_8()
					var y: int = file.get_8()
					var id: int = file.get_8() - 1
					model["voxels"][Vector3i(x, y, z)] = id
				raw_models.append(model)
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Parsed model %d with %d voxels" % [raw_models.size() - 1, model["voxels"].size()])
			
			"RGBA":
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "RGBA chunk: reading 256-color palette")
				for i in 256:
					var color := Color8(file.get_8(), file.get_8(), file.get_8(), file.get_8())
					var voxel := Voxel.new()
					voxel.base_color = color
					result["palette"][i] = voxel
			
			"MATL":
				var mat_id: int = file.get_32()
				var mat_dict := _read_dict(file)
				var mat_props: Dictionary = { "id": mat_id }
				if mat_dict.has("_type"):
					mat_props["type"] = mat_dict["_type"].get_string_from_utf8()
				if mat_dict.has("_diffuse"):
					var rgba := _parse_color_string(mat_dict["_diffuse"].get_string_from_utf8())
					if rgba: mat_props["color"] = rgba
				if mat_dict.has("_specular"):
					mat_props["specular"] = mat_dict["_specular"].get_float()
				if mat_dict.has("_roughness"):
					mat_props["roughness"] = 1.0 - (mat_dict["_roughness"].get_float() / 65535.0)
				if mat_dict.has("_metallic"):
					mat_props["metallic"] = mat_dict["_metallic"].get_float() / 65535.0
				if mat_dict.has("_emit"):
					mat_props["emission"] = true
					mat_props["emission_energy"] = mat_dict["_emit"].get_float() / 65535.0
				result["materials"][mat_id] = mat_props
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "MATL chunk: material %d" % mat_id)
			
			"nTRN":
				var node_id: int = file.get_32()
				var info_dict := _read_dict(file)
				var name: String = ""
				var hidden: bool = false
				if info_dict.has("_name"):
					name = info_dict["_name"].get_string_from_utf8()
				if info_dict.has("_hidden"):
					hidden = info_dict["_hidden"].get_string_from_utf8() == "1"
				var child_id: int = file.get_32()
				var _reserved_id: int = file.get_32()
				var _layer_id: int = file.get_32()
				var _frames: int = file.get_32()
				var transform_dict := _read_dict(file)
				var rotation_raw = null
				var translation_raw = null
				if transform_dict.has("_r"):
					rotation_raw = transform_dict["_r"]
				if transform_dict.has("_t"):
					translation_raw = transform_dict["_t"]
				var transform = _unpack_transform(rotation_raw, translation_raw)
				nodes[node_id] = {
					"type": NodeType.TRANSFORM,
					"name": name,
					"hidden": hidden,
					"child_id": child_id,
					"transform": transform,
				}
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "nTRN node %d: name='%s' child=%d" % [node_id, name, child_id])
			
			"nGRP":
				var node_id: int = file.get_32()
				var _node_dict := _read_dict(file)
				var child_count: int = file.get_32()
				var child_ids: PackedInt32Array = []
				child_ids.resize(child_count)
				for i in child_count:
					child_ids[i] = file.get_32()
				nodes[node_id] = { "type": NodeType.GROUP, "child_ids": child_ids }
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "nGRP node %d: %d children" % [node_id, child_count])
			
			"nSHP":
				var node_id: int = file.get_32()
				var _node_dict := _read_dict(file)
				var _model_count: int = file.get_32()
				var model_id: int = file.get_32()
				var _model_dict := _read_dict(file)
				nodes[node_id] = { "type": NodeType.SHAPE, "model_id": model_id }
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "nSHP node %d: model_id=%d" % [node_id, model_id])
			
			"IMAP", "LAYR", "MATT", "rOBJ", "rCAM", "NOTE", "META":
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Skipping known chunk '%s' (%d bytes)" % [chunk_id, chunk_size])
				if chunk_size > 0:
					file.get_buffer(chunk_size)
			
			_:
				if chunk_size > 0:
					file.get_buffer(chunk_size)
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "End of file: %d raw models, %d nodes" % [raw_models.size(), nodes.size()])
	
	# Build palette from custom chunk or default
	if result["palette"].is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Using default MagicaVoxel palette")
		for i in 256:
			var voxel := Voxel.new()
			voxel.base_color = MAGICA_VOXEL_PALETTE[i]
			result["palette"][i] = voxel
	else:
		var fv: Voxel = result["palette"][0]
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Loaded palette: %d colors (index 0 alpha=%.2f)" % [result["palette"].size(), fv.base_color.a])
	
	# Apply materials to palette
	if not result["materials"].is_empty():
		for mat_id in result["materials"]:
			if result["palette"].has(mat_id):
				var v: Voxel = result["palette"][mat_id]
				v.base_material_id = str(mat_id)
	
	# Build scene tree
	var tree: Dictionary = {}
	if nodes.size() > 0:
		var root_id = nodes.keys().front()
		tree = _build_tree(root_id, nodes, raw_models)
	elif raw_models.size() > 0:
		tree = { "type": "SHAPE", "model": raw_models.front() }
	else:
		result["error"] = ERR_FILE_EOF
		return result
	
	# Collect individual scene models with transforms applied
	result["scene_models"] = _collect_scene_models(tree)
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Collected %d scene models" % result["scene_models"].size())
	
	# Build flat merged voxels
	var all_voxels: Dictionary = {}
	for sm in result["scene_models"]:
		for pos in sm["voxels"]:
			all_voxels[pos] = sm["voxels"][pos]
	result["voxels"] = all_voxels
	
	return result

## Reads a .vox file from disk.
static func read_file(vox_path: String, options: Dictionary = {}) -> Dictionary:
	var result := { "error": OK }
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Opening VOX file: '%s'" % vox_path)
	
	var file := FileAccess.open(vox_path, FileAccess.READ)
	if file == null:
		var open_error: int = FileAccess.get_open_error()
		VoxlyDebug.error(DEBUG_CONTEXT, "Failed to open file: error=%d" % [open_error])
		result["error"] = open_error
		return result
	
	result = read(file)
	file.close()
	
	if result["error"] == OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Read OK: %d scene models, %d total voxels, %d palette colors" % [
			result.get("scene_models", []).size(),
			result.get("voxels", {}).size(),
			result.get("palette", {}).size()
		])
	
	return result

static func _read_dict(file: FileAccess) -> Dictionary:
	var dict := {}
	var pairs: int = file.get_32()
	for i in pairs:
		var key_size: int = file.get_32()
		var key: String = file.get_buffer(key_size).get_string_from_ascii()
		var value_size: int = file.get_32()
		var value := file.get_buffer(value_size)
		dict[key] = value
	return dict

## Unpacks a MagicaVoxel rotation byte and translation string into a Transform3D.
static func _unpack_transform(rotation_raw, translation_raw) -> Transform3D:
	var rot_x := Vector3(1, 0, 0)
	var rot_y := Vector3(0, 1, 0)
	var rot_z := Vector3(0, 0, 1)
	var origin := Vector3.ZERO
	
	if rotation_raw != null:
		var rotation_bits: int = int(rotation_raw.get_string_from_ascii())
		
		var rot_matrix := [
			Vector3(1, 0, 0),
			Vector3(0, 1, 0),
			Vector3(0, 0, 1)
		]
		var row0_idx: int = rotation_bits & 3
		var row1_idx: int = (rotation_bits >> 2) & 3
		var row0 = rot_matrix[row0_idx]
		var row1 = rot_matrix[row1_idx]
		rot_matrix.erase(row0)
		rot_matrix.erase(row1)
		var row2 = rot_matrix.front()
		
		if rotation_bits & (1 << 4): row0 = -row0
		if rotation_bits & (1 << 5): row1 = -row1
		if rotation_bits & (1 << 6): row2 = -row2
		
		# Build the MV rotation matrix (rows from the unpacked rotation byte)
		var mv_basis := Basis(row0, row1, row2)
		var euler := mv_basis.get_euler()
		
		# Convert MV coordinates (+X right, +Y up, +Z forward) to Godot
		# (+X right, +Y up, -Z forward) by swizzling Euler angles:
		#   MV X → Godot X  (pitch)
		#   MV Y → Godot -Z (roll, negated)
		#   MV Z → Godot -Y (yaw, negated)
		var corrected_basis := Basis.from_euler(Vector3(euler.x, -euler.z, -euler.y))
		
		rot_x = corrected_basis.x
		rot_y = corrected_basis.y
		rot_z = corrected_basis.z
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Rotation bits=%d -> basis x=%s y=%s z=%s" % [rotation_bits, rot_x, rot_y, rot_z])
	
	if translation_raw != null:
		var parts = translation_raw.get_string_from_ascii().split_floats(" ")
		if parts.size() >= 3:
			# MV coordinates (+X right, +Y up, +Z forward) → Godot coordinates (+X right, +Y up, -Z forward).
			# X is negated to match the voxel-level x-flip for facing direction.
			# Y maps directly (up is up).
			# Z is negated (MV forward = +Z, Godot forward = -Z).
			origin = Vector3(-parts[0], parts[2], parts[1])
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, DEBUG_CONTEXT, "Translation: (%d, %d, %d) -> origin=%s" % [parts[0], parts[1], parts[2], origin])
	
	return Transform3D(rot_x, rot_y, rot_z, origin)

static func _build_tree(node_id: int, nodes: Dictionary, models: Array) -> Dictionary:
	var node = nodes[node_id]
	var transform_node: Dictionary = {}
	
	if node.type == NodeType.TRANSFORM and node.has("child_id"):
		transform_node = node
		if nodes.has(node.child_id):
			node = nodes[node.child_id]
		else:
			return { "type": "NONE" }
	
	var tree_node: Dictionary = {}
	if not transform_node.is_empty():
		tree_node = {
			"type": "NONE",
			"name": transform_node.get("name", ""),
			"transform": transform_node["transform"],
		}
	
	if node.type == NodeType.GROUP:
		tree_node["type"] = "GROUP"
		tree_node["children"] = []
		for child_id in node.child_ids:
			tree_node["children"].append(_build_tree(child_id, nodes, models))
	
	elif node.type == NodeType.SHAPE:
		tree_node["type"] = "SHAPE"
		var model_id: int = node.model_id
		if model_id >= 0 and model_id < models.size():
			tree_node["model"] = models[model_id]
	
	return tree_node

## Walks the scene tree and collects each shape node with its full transform applied.
## Each entry: { voxels: {Vector3i: int}, transform: Transform3D, size: Vector3i, name: String }
## The voxels are transformed from local model space to scene space.
## Pivot is applied (per Voxel-Core-3: ceil for X, floor for Y/Z).
static func _collect_scene_models(tree: Dictionary) -> Array[Dictionary]:
	var models: Array[Dictionary] = []
	
	if tree.has("model"):
		var entry := _transform_model(tree)
		if entry["voxels"].size() > 0:
			models.append(entry)
	
	if tree.has("children"):
		for child in tree["children"]:
			var child_models := _collect_scene_models(child)
			for cm in child_models:
				models.append(cm)
	
	return models

## Transforms a single shape node's voxels by its parent transforms.
## Pivot-centers the model first, then applies the full transform chain.
static func _transform_model(tree: Dictionary) -> Dictionary:
	var voxels: Dictionary = tree["model"]["voxels"].duplicate()
	var size: Vector3i = tree["model"]["size"]
	
	# Apply pivot offset (center model around pivot)
	var center := Vector3(
		ceil(size.x / 2.0),
		floor(size.y / 2.0),
		floor(size.z / 2.0)
	)
	
	# If this shape has a transform, apply it (including pivot adjustment)
	if tree.has("transform"):
		var transform: Transform3D = tree["transform"]
		transform = transform.translated(-center)
		
		var transformed: Dictionary = {}
		for key in voxels:
			var pos := Vector3(key) + Vector3(0.5, 0.5, 0.5)
			pos = transform * pos
			pos -= Vector3(0.5, 0.5, 0.5)
			var grid_pos := Vector3i(roundi(pos.x), roundi(pos.y), roundi(pos.z))
			transformed[grid_pos] = voxels[key]
		voxels = transformed
	else:
		# No transform — just apply pivot offset
		var shifted: Dictionary = {}
		for key in voxels:
			shifted[key - Vector3i(center)] = voxels[key]
		voxels = shifted
	
	return {
		"voxels": voxels,
		"size": size,
		"name": tree.get("name", ""),
	}

static func _parse_color_string(color_str: String) -> Color:
	var parts := color_str.split_floats(" ")
	if parts.size() >= 3:
		if parts.size() >= 4:
			return Color(parts[0], parts[1], parts[2], parts[3])
		return Color(parts[0], parts[1], parts[2], 1.0)
	return Color.WHITE
