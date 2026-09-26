## Codec for voxel content.
##
## Voxel content is stored by grid position followed by its voxel ID. Positions use
## either int32 (16 bytes per record) or int16 (10 bytes per record) storage,
## selected by [method encode_records].
@tool
class_name VoxlyVoxelContentCodec
extends RefCounted

## Bytes per voxel record when positions are stored as int32.
const RECORD_SIZE_I32 := 16

## Bytes per voxel record when positions are stored as int16.
const RECORD_SIZE_I16 := 10

## Encodes voxel content into a packed byte array.
##
## Returns an empty array when there are no voxels. When [param compact] is true 
## and every coordinate fits into a int16, positions are stored as int16 to shrink 
## each record from 16 to 10 bytes.
static func encode_records(voxels: Dictionary, compact := false) -> PackedByteArray:
	var data := PackedByteArray()
	if voxels.is_empty():
		return data
	
	var use_compact := compact and fits_int16(voxels)
	var record_size := RECORD_SIZE_I16 if use_compact else RECORD_SIZE_I32
	var positions := voxels.keys()
	positions.sort_custom(_position_less)
	
	data.resize(positions.size() * record_size)
	var byte_index := 0
	for voxel_position in positions:
		var typed_position: Vector3i = voxel_position
		var voxel_id := int(voxels[typed_position])
		if use_compact:
			data.encode_s16(byte_index, typed_position.x)
			data.encode_s16(byte_index + 2, typed_position.y)
			data.encode_s16(byte_index + 4, typed_position.z)
			data.encode_s32(byte_index + 6, voxel_id)
		else:
			data.encode_s32(byte_index, typed_position.x)
			data.encode_s32(byte_index + 4, typed_position.y)
			data.encode_s32(byte_index + 8, typed_position.z)
			data.encode_s32(byte_index + 12, voxel_id)
		byte_index += record_size
	
	return data

## Decodes records produced by [method encode_records] back into a
## [code]Dictionary[Vector3i, int][/code]. [param compact] must match the value
## used when encoding.
static func decode_records(data: PackedByteArray, compact := false) -> Dictionary[Vector3i, int]:
	var voxels: Dictionary[Vector3i, int] = {}
	var record_size := RECORD_SIZE_I16 if compact else RECORD_SIZE_I32
	var voxel_count := data.size() / record_size
	if voxel_count <= 0:
		return voxels
	
	var byte_index := 0
	for i in range(voxel_count):
		var voxel_position: Vector3i
		var voxel_id: int
		if compact:
			voxel_position = Vector3i(
				data.decode_s16(byte_index),
				data.decode_s16(byte_index + 2),
				data.decode_s16(byte_index + 4)
			)
			voxel_id = data.decode_s32(byte_index + 6)
		else:
			voxel_position = Vector3i(
				data.decode_s32(byte_index),
				data.decode_s32(byte_index + 4),
				data.decode_s32(byte_index + 8)
			)
			voxel_id = data.decode_s32(byte_index + 12)
		voxels[voxel_position] = voxel_id
		byte_index += record_size
	
	return voxels

## Returns true when every voxel position fits in the int16 range on all axes.
static func fits_int16(voxels: Dictionary) -> bool:
	for voxel_position in voxels:
		var typed_position: Vector3i = voxel_position
		if (
			typed_position.x < -32768 or typed_position.x > 32767
			or typed_position.y < -32768 or typed_position.y > 32767
			or typed_position.z < -32768 or typed_position.z > 32767
		):
			return false
	return true

## Orders positions by x, then y, then z so encoded bytes are deterministic.
static func _position_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z
