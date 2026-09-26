## User-selectable options for loading voxel content from a `.vxc` file.
##
## Every option defaults to disabled, so a plain load swaps only the voxel
## records and keeps the model's current shape, origin, voxel size, and
## [VoxelSet]. The editor renders [method get_options] through
## [VoxlyOptionBuilder] in the shared options prompt.
@tool
class_name VoxlyVoxelContentLoadOptions
extends RefCounted

## How loaded voxels combine with existing content: 0 = Replace, 1 = Append.
var mode: int = 0

## Applies the file's shape to the model.
var apply_shape: bool = false

## Applies the file's origin offset to the model.
var apply_origin: bool = false

## Applies the file's voxel size to the model.
var apply_voxel_size: bool = false

## Assigns the file's referenced [VoxelSet] to the model.
var apply_voxel_set: bool = false

## Returns the option schema used by the editor's shared options prompt.
func get_options() -> Array[Dictionary]:
	return [
		{
			"label": "Mode",
			"property": "mode",
			"type": TYPE_INT,
			"hint": "0=Replace,1=Append",
		},
		{
			"label": "Apply Shape",
			"property": "apply_shape",
			"type": TYPE_BOOL,
		},
		{
			"label": "Apply Origin",
			"property": "apply_origin",
			"type": TYPE_BOOL,
		},
		{
			"label": "Apply Voxel Size",
			"property": "apply_voxel_size",
			"type": TYPE_BOOL,
		},
		{
			"label": "Apply VoxelSet",
			"property": "apply_voxel_set",
			"type": TYPE_BOOL,
		},
	]

## Returns the options as a plain dictionary for the load API.
func to_dictionary() -> Dictionary:
	return {
		"mode": mode,
		"apply_shape": apply_shape,
		"apply_origin": apply_origin,
		"apply_voxel_size": apply_voxel_size,
		"apply_voxel_set": apply_voxel_set,
	}
