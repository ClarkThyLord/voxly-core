## MagicaVoxel (.vox) file reader.
@tool
class_name VoxReader
extends RefCounted

const _debug_context := "VoxReader"

## Scene graph node types.
enum NodeType {
	TRANSFORM,
	GROUP,
	SHAPE,
}

## Default MagicaVoxel palette (256 colors).
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
static func read(file: FileAccess) -> Dictionary:
	var result := {
		"error": OK,
		"scene_models": [],
		"voxels": {},
		"palette": {},
		"materials": {},
	}
	
	# Read the header.
	var header: String = file.get_buffer(4).get_string_from_ascii()
	var version: int = file.get_32()
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Reading VOX file - header='%s' version=%d" % [header, version])
	
	if header != "VOX " or (version != 150 and version != 200):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Unrecognized VOX file: header='%s' version=%d (expected 150 or 200)" % [header, version])
		result["error"] = ERR_FILE_UNRECOGNIZED
		return result
	
	if version == 200:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "VOX version 200 detected")
	
	# Raw models from XYZI chunks (size + voxels).
	var raw_models: Array[Dictionary] = []
	
	# Scene graph nodes indexed by node_id.
	var nodes: Dictionary = {}
	
	var pending_size: Vector3i = Vector3i.ZERO
	
	while file.get_position() < file.get_length():
		var chunk_id: String = file.get_buffer(4).get_string_from_ascii()
		var chunk_size: int = file.get_32()
		var chunk_child_size: int = file.get_32()
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Chunk: id='%s' size=%d child_size=%d pos=%d" % [chunk_id, chunk_size, chunk_child_size, file.get_position()])
		
		match chunk_id:
			"MAIN":
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Found MAIN chunk with %d bytes of children" % chunk_child_size)
				pass
			
			"SIZE":
				pending_size.x = file.get_32()
				pending_size.z = file.get_32()
				pending_size.y = file.get_32()
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "SIZE chunk: %s" % pending_size)
			
			"XYZI":
				var model := { "size": pending_size, "voxels": {} }
				var num_voxels: int = file.get_32()
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "XYZI chunk: num_voxels=%d size=%s" % [num_voxels, pending_size])
				for i in num_voxels:
					var x: int = pending_size.x - file.get_8() - 1
					var z: int = file.get_8()
					var y: int = file.get_8()
					var voxel_id: int = file.get_8() - 1
					model["voxels"][Vector3i(x, y, z)] = voxel_id
				raw_models.append(model)
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Parsed model %d with %d voxels" % [raw_models.size() - 1, model["voxels"].size()])
			
			"RGBA":
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "RGBA chunk: reading 256-color palette")
				for i in 256:
					var color := Color8(file.get_8(), file.get_8(), file.get_8(), file.get_8())
					var voxel := Voxel.new()
					voxel.base_color = color
					result["palette"][i] = voxel
			
			"MATL":
				var material_id: int = file.get_32()
				var material_dict := _read_dict(file)
				var material_props: Dictionary = { "id": material_id }
				
				# Read the material type (all MagicaVoxel materials store _type
				# to identify their category).
				if material_dict.has("_type"):
					material_props["type"] = material_dict["_type"].get_string_from_utf8()
				
				# _diffuse: some files store an RGBA color override string
				# "r g b a" (optional).
				if material_dict.has("_diffuse"):
					var parsed_color := _parse_color_string(material_dict["_diffuse"].get_string_from_utf8())
					if parsed_color: material_props["color"] = parsed_color
				
				# MagicaVoxel MATL specular key is _sp (float 0.0-1.0), not _specular.
				if material_dict.has("_sp"):
					var specular_string = material_dict["_sp"].get_string_from_utf8()
					if specular_string.is_valid_float():
						material_props["_sp"] = clampf(specular_string.to_float(), 0.0, 1.0)
				
				# MagicaVoxel MATL roughness key is _rough (float 0.0-1.0), not _roughness.
				if material_dict.has("_rough"):
					var roughness_string = material_dict["_rough"].get_string_from_utf8()
					if roughness_string.is_valid_float():
						material_props["_rough"] = clampf(roughness_string.to_float(), 0.0, 1.0)
				
				# MagicaVoxel MATL metallic key is _metal (float 0.0-1.0), not _metallic.
				if material_dict.has("_metal"):
					var metalness_string = material_dict["_metal"].get_string_from_utf8()
					if metalness_string.is_valid_float():
						material_props["_metal"] = clampf(metalness_string.to_float(), 0.0, 1.0)
				
				# Also parse _weight (used by _diffuse for blend strength, by
				# _emit for emission blend).
				if material_dict.has("_weight"):
					var weight_string = material_dict["_weight"].get_string_from_utf8()
					if weight_string.is_valid_float():
						material_props["_weight"] = clampf(weight_string.to_float(), 0.0, 1.0)
				
				# Emission handling per the MagicaVoxel spec.
				var material_type: String = material_props.get("type", "")
				if material_type == "_emit":
					material_props["emission"] = true
					
					# _flux is the preferred emission power value (modern format,
					# stored as a float string).
					var emission_value := 1.0
					if material_dict.has("_flux"):
						var flux_string = material_dict["_flux"].get_string_from_utf8()
						if flux_string.is_valid_float():
							emission_value = flux_string.to_float()
					
					# Fall back to _emit if _flux is not present (legacy format,
					# 0-65535 integer).
					if not material_dict.has("_flux") and material_dict.has("_emit"):
						var emission_string = material_dict["_emit"].get_string_from_utf8()
						if emission_string.is_valid_float():
							# MagicaVoxel stores _emit as an integer 0-65535.
							# Normalize to 0.0-1.0 range, but ensure minimum
							# visible emission.
							emission_value = maxf(emission_string.to_float() / 65535.0, 1.0)
					
					var emission_weight: float = material_props.get("_weight", 1.0)
					material_props["emission_flux"] = emission_value
					material_props["emission_weight"] = emission_weight
				
				# Legacy fallback: some files may set _emit without _type.
				elif material_dict.has("_emit"):
					material_props["emission"] = true
					var emission_string = material_dict["_emit"].get_string_from_utf8()
					if emission_string.is_valid_float():
						material_props["emission_flux"] = maxf(emission_string.to_float() / 65535.0, 1.0)
					else:
						material_props["emission_flux"] = 1.0
					material_props["emission_weight"] = material_props.get("_weight", 1.0)
				
				result["materials"][material_id] = material_props
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "MATL chunk: material %d with type '%s'" % [material_id, material_props.get("type", "(unset)")])
			
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
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "nTRN node %d: name='%s' child=%d" % [node_id, name, child_id])
			
			"nGRP":
				var node_id: int = file.get_32()
				var _node_dict := _read_dict(file)
				var child_count: int = file.get_32()
				var child_ids: PackedInt32Array = []
				child_ids.resize(child_count)
				for i in child_count:
					child_ids[i] = file.get_32()
				nodes[node_id] = { "type": NodeType.GROUP, "child_ids": child_ids }
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "nGRP node %d: %d children" % [node_id, child_count])
			
			"nSHP":
				var node_id: int = file.get_32()
				var _node_dict := _read_dict(file)
				var _model_count: int = file.get_32()
				var model_id: int = file.get_32()
				var _model_dict := _read_dict(file)
				nodes[node_id] = { "type": NodeType.SHAPE, "model_id": model_id }
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "nSHP node %d: model_id=%d" % [node_id, model_id])
			
			"IMAP", "LAYR", "MATT", "rOBJ", "rCAM", "NOTE", "META":
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Skipping known chunk '%s' (%d bytes)" % [chunk_id, chunk_size])
				if chunk_size > 0:
					file.get_buffer(chunk_size)
			
			_:
				if chunk_size > 0:
					file.get_buffer(chunk_size)
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "End of file: %d raw models, %d nodes" % [raw_models.size(), nodes.size()])
	
	# Build the palette from the custom chunk or the default.
	if result["palette"].is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Using default MagicaVoxel palette")
		for i in 256:
			var voxel := Voxel.new()
			voxel.base_color = MAGICA_VOXEL_PALETTE[i]
			result["palette"][i] = voxel
	else:
		var first_voxel: Voxel = result["palette"][0]
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Loaded palette: %d colors (index 0 alpha=%.2f)" % [result["palette"].size(), first_voxel.base_color.a])
	
	# Apply materials to the palette.
	# MATL material_ids are 1-indexed (1-256) but palette is 0-indexed (0-255).
	# Material 1 corresponds to palette index 0, material 2 to palette index 1, etc.
	if not result["materials"].is_empty():
		for material_id in result["materials"]:
			var palette_index := int(material_id) - 1
			if result["palette"].has(palette_index):
				var voxel: Voxel = result["palette"][palette_index]
				voxel.base_material_id = str(material_id)
	
	# Build the scene tree.
	var tree: Dictionary = {}
	if nodes.size() > 0:
		var root_id = nodes.keys().front()
		tree = _build_tree(root_id, nodes, raw_models)
	elif raw_models.size() > 0:
		tree = { "type": "SHAPE", "model": raw_models.front() }
	else:
		result["error"] = ERR_FILE_EOF
		return result
	
	# Collect individual scene models with transforms applied.
	result["scene_models"] = _collect_scene_models(tree)
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Collected %d scene models" % result["scene_models"].size())
	
	# Build the flat merged voxels.
	var all_voxels: Dictionary = {}
	for scene_model in result["scene_models"]:
		for position in scene_model["voxels"]:
			all_voxels[position] = scene_model["voxels"][position]
	result["voxels"] = all_voxels
	
	return result

## Reads a .vox file from disk.
static func read_file(vox_path: String, options: Dictionary = {}) -> Dictionary:
	var result := { "error": OK }
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Opening VOX file: '%s'" % vox_path)
	
	var file := FileAccess.open(vox_path, FileAccess.READ)
	if file == null:
		var open_error: int = FileAccess.get_open_error()
		VoxlyDebug.error(_debug_context, "Failed to open file: error=%d" % [open_error])
		result["error"] = open_error
		return result
	
	result = read(file)
	file.close()
	
	if result["error"] == OK:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Read OK: %d scene models, %d total voxels, %d palette colors" % [
			result.get("scene_models", []).size(),
			result.get("voxels", {}).size(),
			result.get("palette", {}).size()
		])
	
	return result

## Reads a DICTIONARY chunk from the file (key-value pairs of byte buffers).
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

## Unpacks a MagicaVoxel rotation byte and translation string into a Transform3D
## expressed in voxly-core's working coordinates.
##
## MagicaVoxel stores rotations as a single byte encoding a row-major 3x3
## rotation matrix: each 2-bit pair selects which axis that row's +/-1 sits on,
## and bits 4-6 hold the row signs. Godot's Basis treats the three vectors
## passed to its constructor as COLUMNS (axial vectors), so the raw rows must
## be transposed to recover the true MagicaVoxel rotation matrix.
static func _unpack_transform(rotation_raw, translation_raw) -> Transform3D:
	var rot_x := Vector3(1, 0, 0)
	var rot_y := Vector3(0, 1, 0)
	var rot_z := Vector3(0, 0, 1)
	var origin := Vector3.ZERO
	
	if rotation_raw != null:
		var rotation_bits: int = int(rotation_raw.get_string_from_ascii())
		
		var row0_idx: int = rotation_bits & 3
		var row1_idx: int = (rotation_bits >> 2) & 3
		
		# Each row carries its +/-1 in a distinct column (0, 1, or 2).
		# Anything else is a corrupt rotation byte.
		if row0_idx == row1_idx or row0_idx > 2 or row1_idx > 2:
			VoxlyDebug.error(_debug_context, "Invalid rotation byte %d: row indices (%d, %d)" % [rotation_bits, row0_idx, row1_idx])
			return Transform3D.IDENTITY
		var row2_idx := 3 - row0_idx - row1_idx
		
		# Decode the byte into the ROWS of the MV row-major rotation matrix.
		var rows := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
		rows[0][row0_idx] = 1.0 if (rotation_bits & (1 << 4)) == 0 else -1.0
		rows[1][row1_idx] = 1.0 if (rotation_bits & (1 << 5)) == 0 else -1.0
		rows[2][row2_idx] = 1.0 if (rotation_bits & (1 << 6)) == 0 else -1.0
		
		# Basis(rows...) interprets the vectors as COLUMNS, producing R^T.
		# Transposing recovers the true row-major MV rotation matrix.
		var mv_basis := Basis(rows[0], rows[1], rows[2]).transposed()
		
		# Conjugate into voxly-core's coordinate convention C (see doc above).
		# C = diag(-1, swap(y, z)); C^-1 == C.
		var coord_map := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
		var godot_basis := coord_map * mv_basis * coord_map
		
		rot_x = godot_basis.x
		rot_y = godot_basis.y
		rot_z = godot_basis.z
		
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context,
			"Rotation bits=%d rows=%s mv_basis=%s -> godot_basis x=%s y=%s z=%s" % [rotation_bits, rows, mv_basis, rot_x, rot_y, rot_z])
	
	if translation_raw != null:
		var parts = translation_raw.get_string_from_ascii().split_floats(" ")
		if parts.size() >= 3:
			# MV translation to Godot:
			#   origin = C * t_mv = (-t.x, t.z, t.y)
			origin = Vector3(-parts[0], parts[2], parts[1])
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context,
				"Translation: (%d, %d, %d) -> origin=%s" % [parts[0], parts[1], parts[2], origin])
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context,
		"Unpacked transform: rotation=%s origin=%s" % [Basis(rot_x, rot_y, rot_z), origin])
	
	return Transform3D(rot_x, rot_y, rot_z, origin)

## Recursively builds the scene tree from the node graph, accumulating the
## full transform chain as it descends.
##
## `parent_transform` is the accumulated Transform3D of all ancestor nTRN
## nodes. Every nTRN transform is applied in its parent's space, so a chain
## A -> B -> shape yields T_A * T_B applied to the shape's voxels. Shape
## nodes receive the fully accumulated transform.
static func _build_tree(node_id: int, nodes: Dictionary, models: Array, parent_transform: Transform3D = Transform3D.IDENTITY, inherited_name := "") -> Dictionary:
	if not nodes.has(node_id):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Tree: node %d missing from node graph" % node_id)
		return { "type": "NONE" }
	
	var node = nodes[node_id]
	var tree_node: Dictionary = { "type": "NONE" }
	
	if node.type == NodeType.TRANSFORM and node.has("child_id"):
		# Accumulate this transform into the chain.
		var node_transform: Transform3D = node["transform"]
		var combined: Transform3D = parent_transform * node_transform
		var combined_name := inherited_name
		if combined_name.is_empty():
			combined_name = node.get("name", "")
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context,
			"Tree: nTRN %d -> child %d: accumulated transform=%s name='%s'" % [node_id, node.child_id, combined, combined_name])
		return _build_tree(node.child_id, nodes, models, combined, combined_name)
	
	if node.type == NodeType.GROUP:
		tree_node["type"] = "GROUP"
		tree_node["children"] = []
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Tree: nGRP %d with %d children (chain=%s)" % [node_id, node.child_ids.size(), parent_transform])
		for child_id in node.child_ids:
			tree_node["children"].append(_build_tree(child_id, nodes, models, parent_transform, inherited_name))
	
	elif node.type == NodeType.SHAPE:
		tree_node["type"] = "SHAPE"
		var model_id: int = node.model_id
		if model_id >= 0 and model_id < models.size():
			tree_node["model"] = models[model_id]
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Tree: nSHP %d -> model %d (chain=%s name='%s')" % [node_id, model_id, parent_transform, inherited_name])
		else:
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context, "Tree: nSHP %d references missing model %d" % [node_id, model_id])
		tree_node["transform"] = parent_transform
		tree_node["name"] = inherited_name
	
	return tree_node

## Walks the scene tree and collects each shape node with its full transform
## applied. Each entry:
## [codeblock]
## { voxels: {Vector3i: int}, transform: Transform3D, size: Vector3i, name: String }
## [/codeblock]
## The voxels are transformed from local model space to scene space. The pivot
## is applied per model (floor(size / 2)), matching the reference importer.
static func _collect_scene_models(tree: Dictionary) -> Array[Dictionary]:
	var models: Array[Dictionary] = []
	
	if tree.has("model"):
		var entry := _transform_model(tree)
		if entry["voxels"].size() > 0:
			models.append(entry)
			# Log the bounding box of each collected scene model for verification.
			var min_position := Vector3i.ZERO
			var max_position := Vector3i.ZERO
			var first := true
			for position in entry["voxels"]:
				var typed_position: Vector3i = position
				if first:
					min_position = typed_position
					max_position = typed_position
					first = false
				else:
					min_position = Vector3i(mini(min_position.x, typed_position.x), mini(min_position.y, typed_position.y), mini(min_position.z, typed_position.z))
					max_position = Vector3i(maxi(max_position.x, typed_position.x), maxi(max_position.y, typed_position.y), maxi(max_position.z, typed_position.z))
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context,
				"Scene model '%s': %d voxels, bounds min=%s max=%s" % [entry.get("name", ""), entry["voxels"].size(), min_position, max_position])
	
	if tree.has("children"):
		for child in tree["children"]:
			var child_models := _collect_scene_models(child)
			for child_model in child_models:
				models.append(child_model)
	
	return models

## Transforms a single shape node's voxels by its full accumulated transform
## chain.
##
## MagicaVoxel rotates each model around its own center pivot, and the pivot
## convention depends on the parity of each axis in MagicaVoxel space:
## [codeblock]
##   even s = s/2 - 0.5   (half-voxel boundary between the two middle cells)
##   odd  s = s/2         (whole-voxel center, integer division)
## [/codeblock]
static func _transform_model(tree: Dictionary) -> Dictionary:
	var voxels: Dictionary = tree["model"]["voxels"].duplicate()
	var size: Vector3i = tree["model"]["size"]
	var size_v := Vector3(size)
	
	# Recover the MagicaVoxel-space dimensions.
	var mx := size_v.x
	var mz := size_v.y
	var my := size_v.z
	
	# Per-axis MagicaVoxel pivot:
	# even = half-voxel boundary (s/2 - 0.5);
	# odd  = whole-voxel center (s/2, integer division).
	var cx: float = mx / 2.0 - 0.5 if int(mx) % 2 == 0 else floor(mx / 2.0)
	var cy: float = my / 2.0 - 0.5 if int(my) % 2 == 0 else floor(my / 2.0)
	var cz: float = mz / 2.0 - 0.5 if int(mz) % 2 == 0 else floor(mz / 2.0)
	
	# Map the MV pivot through the XYZI affine flip:
	#   key = (mx-1-bx, bz, by).
	var center_local := Vector3(-cx + (mx - 1.0), cz, cy)
	
	var chain: Transform3D = tree.get("transform", Transform3D.IDENTITY)
	var effective_origin: Vector3 = chain.origin - chain.basis * center_local
	var effective_transform := Transform3D(chain.basis, effective_origin)
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context,
		"Transforming model '%s': size=%s center_local=%s chain=%s origin_eff=%s" % [
			tree.get("name", ""), size, center_local, chain, effective_origin])
	
	var transformed: Dictionary = {}
	for key in voxels:
		var world_pos := effective_transform * Vector3(key)
		var grid_position := Vector3i(floori(world_pos.x), floori(world_pos.y), floori(world_pos.z))
		transformed[grid_position] = voxels[key]
	voxels = transformed
	
	# Log a few sample placements for verification.
	var samples: Array = []
	var sample_keys := voxels.keys()
	for i in mini(3, sample_keys.size()):
		var typed_position: Vector3i = sample_keys[i]
		samples.append(typed_position)
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_READERS, _debug_context,
		"Transformed model '%s': %d voxels, sample positions=%s" % [tree.get("name", ""), voxels.size(), samples])
	
	return {
		"voxels": voxels,
		"transform": effective_transform,
		"size": size,
		"name": tree.get("name", ""),
	}

## Applies MagicaVoxel material properties to a Godot StandardMaterial3D.
## Translates the MATL chunk dictionary values to Godot's PBR properties
## based on the material _type ("_diffuse", "_metal", "_glass", "_emit").
static func apply_material_properties(
		material: StandardMaterial3D,
		material_data: Dictionary,
		palette_color: Color = Color.WHITE) -> void:
	var material_type: String = material_data.get("type", "_diffuse")
	
	# Read MagicaVoxel raw values with defaults.
	var specular: float = material_data.get("_sp", 0.0)       # specular 0.0-1.0
	var roughness: float = material_data.get("_rough", 0.0)   # roughness 0.0-1.0
	var metalness: float = material_data.get("_metal", 0.0)   # metallic 0.0-1.0
	var weight: float = material_data.get("_weight", 1.0)     # blend/opacity 0.0-1.0
	
	# Use the override color if provided, otherwise use the palette color.
	var albedo: Color = material_data.get("color", palette_color)
	
	# Apply PBR mapping based on the MagicaVoxel material type.
	match material_type:
		"_diffuse":
			# Pure diffuse/matte surface.
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			material.metallic = 0.0
			material.roughness = 1.0
			material.metallic_specular = 0.5  # default
			
			# If weight < 1.0, enable transparency (opacity blend).
			if weight < 1.0:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color = Color(albedo.r, albedo.g, albedo.b, weight)
			else:
				material.albedo_color = albedo
		
		"_metal":
			# Metallic surface. In Godot PBR, metallic is the primary control;
			# _sp is less relevant.
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			if material_data.has("_metal"):
				material.metallic = metalness
			else:
				# Fallback: use _sp as metallic if _metal is missing.
				material.metallic = specular
			material.roughness = roughness if material_data.has("_rough") else 0.1
			material.metallic_specular = 0.5
			material.albedo_color = albedo
		
		"_glass":
			# Dielectric (non-metal) transparent surface.
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			material.metallic = 0.0
			if material_data.has("_rough"):
				material.roughness = roughness
			else:
				# Invert _sp for roughness (shiny = low roughness).
				material.roughness = 1.0 - specular
			material.metallic_specular = specular  # _sp controls reflection intensity for dielectrics.
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(albedo.r, albedo.g, albedo.b, weight)
		
		"_emit":
			# Emissive surface, handled separately below.
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			material.metallic = 0.0
			material.roughness = 1.0
			material.albedo_color = albedo
		
		_:
			# Unknown type or _type missing.
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			material.metallic = 0.0
			material.roughness = 1.0
			material.metallic_specular = 0.5
			material.albedo_color = albedo
	
	# Emission handling.
	if material_data.has("emission"):
		material.set_feature(BaseMaterial3D.FEATURE_EMISSION, true)
		material.emission = albedo
		
		# Convert MagicaVoxel emission to Godot 4's emission_energy_multiplier.
		# Formula: emission_flux * emission_weight * GLOW_SCALE
		# - emission_flux: raw emission power (from _flux or _emit)
		# - emission_weight: blend percentage from _weight (0.0-1.0)
		# - GLOW_SCALE (2.5): adjusts MagicaVoxel's arbitrary intensity to
		#   Godot's PBR-compatible range for realistic bloom/glow.
		const GLOW_SCALE := 2.5
		var emission_flux: float = material_data.get("emission_flux", 1.0)
		var emission_weight: float = material_data.get("emission_weight", 1.0)
		material.emission_energy_multiplier = emission_flux * emission_weight * GLOW_SCALE

## Parses a color from a space-separated "r g b a" string.
static func _parse_color_string(color_str: String) -> Color:
	var parts := color_str.split_floats(" ")
	if parts.size() >= 3:
		if parts.size() >= 4:
			return Color(parts[0], parts[1], parts[2], parts[3])
		return Color(parts[0], parts[1], parts[2], 1.0)
	return Color.WHITE
