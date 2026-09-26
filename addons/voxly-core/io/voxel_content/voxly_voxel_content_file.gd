## Reads and writes voxel content files (`.vxc`).
##
## The container holds a versioned header, the content's shape / origin /
## voxel-size metadata, an optional [VoxelSet] resource path, and the voxel
## records produced by [VoxlyVoxelContentCodec]. Saving with [code]compress[/code]
## enabled wraps the payload in Godot's compressed container; otherwise the file
## is written as-is. [method load] reads both variants.
@tool
class_name VoxlyVoxelContentFile
extends RefCounted

## Debug context tag used when logging through [VoxlyDebug].
const _debug_context := "VoxlyVoxelContentFile"

## File extension used by voxel content files (without the leading dot).
const EXTENSION := "vxc"

## Four-byte magic identifying a voxel content file (Voxly Content File).
const MAGIC := "VXCF"

## Current container format version.
const VERSION := 1

## Flag: voxel positions are stored as int16 instead of int32.
const FLAG_POS_INT16 := 1

## Flag: the content shape is present in the metadata block.
const FLAG_HAS_SHAPE := 2

## Flag: the content origin offset is present in the metadata block.
const FLAG_HAS_ORIGIN := 4

## Flag: the content voxel size is present in the metadata block.
const FLAG_HAS_VOXEL_SIZE := 8

## Flag: a [VoxelSet] resource path follows the voxel records.
const FLAG_VOXEL_SET_PATH := 16

## Writes [param content] to [param path] as a `.vxc` file.
##
## [param content] uses the keys returned by
## [method VoxelModel3D.get_voxel_content]. [param options] keys:
## [code]include_shape[/code], [code]include_origin[/code],
## [code]include_voxel_size[/code], [code]reference_voxel_set[/code],
## [code]position_width[/code] (0 Auto, 1 16-bit, 2 32-bit), and
## [code]compress[/code]. Returns [constant OK] or an error code.
static func save(path: String, content: Dictionary, options: Dictionary = {}) -> int:
	var voxels: Dictionary = content.get("voxels", {})
	var include_shape: bool = options.get("include_shape", false)
	var include_origin: bool = options.get("include_origin", false)
	var include_voxel_size: bool = options.get("include_voxel_size", false)
	var reference_voxel_set: bool = options.get("reference_voxel_set", false)
	var compress: bool = options.get("compress", false)
	
	var voxel_set_path := ""
	if reference_voxel_set:
		voxel_set_path = str(content.get("voxel_set_path", ""))
	
	# position_width: 0 Auto and 1 16-bit both compact when coordinates fit,
	# 2 32-bit always keeps int32 records.
	var compact := int(options.get("position_width", 0)) != 2 and VoxlyVoxelContentCodec.fits_int16(voxels)
	
	var flags := 0
	if include_shape:
		flags |= FLAG_HAS_SHAPE
	if include_origin:
		flags |= FLAG_HAS_ORIGIN
	if include_voxel_size:
		flags |= FLAG_HAS_VOXEL_SIZE
	if not voxel_set_path.is_empty():
		flags |= FLAG_VOXEL_SET_PATH
	if compact:
		flags |= FLAG_POS_INT16
	
	var shape: Vector3i = content.get("shape", Vector3i.ZERO) if include_shape else Vector3i.ZERO
	var origin: Vector3 = content.get("origin", Vector3.ZERO) if include_origin else Vector3.ZERO
	var voxel_size: Vector3 = content.get("voxel_size", Vector3.ZERO) if include_voxel_size else Vector3.ZERO
	
	var buffer := StreamPeerBuffer.new()
	buffer.put_data(MAGIC.to_ascii_buffer())
	buffer.put_u16(VERSION)
	buffer.put_u16(flags)
	buffer.put_u32(voxels.size())
	buffer.put_32(shape.x)
	buffer.put_32(shape.y)
	buffer.put_32(shape.z)
	buffer.put_float(origin.x)
	buffer.put_float(origin.y)
	buffer.put_float(origin.z)
	buffer.put_float(voxel_size.x)
	buffer.put_float(voxel_size.y)
	buffer.put_float(voxel_size.z)
	buffer.put_data(VoxlyVoxelContentCodec.encode_records(voxels, compact))
	if flags & FLAG_VOXEL_SET_PATH:
		buffer.put_string(voxel_set_path)
	
	var file := _open_for_write(path, compress)
	if file == null:
		var open_error := FileAccess.get_open_error()
		VoxlyDebug.error(_debug_context, "save: cannot open '%s' (error=%d)" % [path, open_error])
		return open_error if open_error != OK else ERR_FILE_CANT_OPEN
	
	file.store_buffer(buffer.data_array)
	file.close()
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IO, _debug_context,
		"Saved %d voxels to '%s' (compact=%s, compressed=%s)" % [
			voxels.size(), path, compact, compress,
		])
	return OK

## Reads the `.vxc` file at [param path].
##
## Returns a dictionary shaped like [method VoxelModel3D.get_voxel_content] plus
## an [code]error[/code] key ([constant OK] on success). The metadata keys
## [code]shape[/code], [code]origin[/code], [code]voxel_size[/code], and
## [code]voxel_set_path[/code] are only present when the file carries them.
static func load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var open_error := FileAccess.get_open_error()
		VoxlyDebug.error(_debug_context, "load: cannot open '%s' (error=%d)" % [path, open_error])
		return { "error": open_error if open_error != OK else ERR_FILE_CANT_OPEN }
	
	var bytes := file.get_buffer(file.get_length())
	file.close()
	
	# Plain files start with the voxel magic; anything else may be wrapped in
	# Godot's compressed container, so re-read it through open_compressed.
	if bytes.size() < MAGIC.length() or bytes.slice(0, MAGIC.length()).get_string_from_ascii() != MAGIC:
		var compressed := FileAccess.open_compressed(path, FileAccess.READ)
		if compressed != null:
			bytes = compressed.get_buffer(compressed.get_length())
			compressed.close()
	
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	
	var magic_bytes := PackedByteArray()
	for i in range(MAGIC.length()):
		magic_bytes.append(buffer.get_u8())
	if magic_bytes.get_string_from_ascii() != MAGIC:
		VoxlyDebug.error(_debug_context, "load: '%s' is not a voxel content file" % path)
		return { "error": ERR_FILE_UNRECOGNIZED }
	
	var version := buffer.get_u16()
	if version > VERSION:
		VoxlyDebug.error(_debug_context, "load: '%s' uses unsupported version %d" % [path, version])
		return { "error": ERR_FILE_CANT_READ }
	
	var flags := buffer.get_u16()
	var voxel_count := buffer.get_u32()
	
	var result: Dictionary = { "error": OK, "voxels": {} }
	
	var shape_x := buffer.get_32()
	var shape_y := buffer.get_32()
	var shape_z := buffer.get_32()
	if flags & FLAG_HAS_SHAPE:
		result["shape"] = Vector3i(shape_x, shape_y, shape_z)
	
	var origin_x := buffer.get_float()
	var origin_y := buffer.get_float()
	var origin_z := buffer.get_float()
	if flags & FLAG_HAS_ORIGIN:
		result["origin"] = Vector3(origin_x, origin_y, origin_z)
	
	var size_x := buffer.get_float()
	var size_y := buffer.get_float()
	var size_z := buffer.get_float()
	if flags & FLAG_HAS_VOXEL_SIZE:
		result["voxel_size"] = Vector3(size_x, size_y, size_z)
	
	var compact := (flags & FLAG_POS_INT16) != 0
	var record_size := VoxlyVoxelContentCodec.RECORD_SIZE_I16 if compact else VoxlyVoxelContentCodec.RECORD_SIZE_I32
	if voxel_count > 0:
		var records := buffer.get_data(voxel_count * record_size)
		if records[0] != OK:
			VoxlyDebug.error(_debug_context, "load: '%s' is truncated" % path)
			return { "error": ERR_FILE_CORRUPT }
		result["voxels"] = VoxlyVoxelContentCodec.decode_records(records[1], compact)
	
	if flags & FLAG_VOXEL_SET_PATH:
		result["voxel_set_path"] = buffer.get_string()
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IO, _debug_context,
		"Loaded %d voxels from '%s'" % [result["voxels"].size(), path])
	return result

## Opens [param path] for writing, creating a `user://` parent directory when
## needed. Wraps the stream in Godot's Zstd container when [param compress] is
## set; otherwise writes a plain file. Both variants are readable through
## [method load].
static func _open_for_write(path: String, compress: bool) -> FileAccess:
	if path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if compress:
		return FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	else:
		return FileAccess.open(path, FileAccess.WRITE)
