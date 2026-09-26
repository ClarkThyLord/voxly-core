## User-selectable options for saving voxel content to a `.vxc` file.
##
## Every option defaults to disabled, so a plain save writes only the voxel
## records. The editor renders [method get_options] through [VoxlyOptionBuilder]
## in the shared options prompt, and [method to_dictionary] feeds the
## [method VoxelModel3D.save_voxels] API.
@tool
class_name VoxlyVoxelContentSaveOptions
extends RefCounted

## Writes the model's shape into the file.
var include_shape: bool = false

## Writes the model's origin offset into the file.
var include_origin: bool = false

## Writes the model's voxel size into the file.
var include_voxel_size: bool = false

## Writes the source [VoxelSet] resource path so it can be re-assigned on load.
var reference_voxel_set: bool = false

## Saves only the current selection instead of every voxel.
var selection_only: bool = false

## Voxel position storage width: 0 = Auto, 1 = 16-bit, 2 = 32-bit.
var position_width: int = 0

## Compresses the file with Zstd.
var compress: bool = false

## Returns the option schema used by the editor's shared options prompt.
func get_options() -> Array[Dictionary]:
	return [
		{
			"label": "Include Shape",
			"property": "include_shape",
			"type": TYPE_BOOL,
		},
		{
			"label": "Include Origin",
			"property": "include_origin",
			"type": TYPE_BOOL,
		},
		{
			"label": "Include Voxel Size",
			"property": "include_voxel_size",
			"type": TYPE_BOOL,
		},
		{
			"label": "Reference VoxelSet",
			"property": "reference_voxel_set",
			"type": TYPE_BOOL,
		},
		{
			"label": "Selection Only",
			"property": "selection_only",
			"type": TYPE_BOOL,
		},
		{
			"label": "Position Width",
			"property": "position_width",
			"type": TYPE_INT,
			"hint": "0=Auto,1=16-bit,2=32-bit",
		},
		{
			"label": "Compress",
			"property": "compress",
			"type": TYPE_BOOL,
		},
	]

## Returns the options as a plain dictionary for the save API.
func to_dictionary() -> Dictionary:
	return {
		"include_shape": include_shape,
		"include_origin": include_origin,
		"include_voxel_size": include_voxel_size,
		"reference_voxel_set": reference_voxel_set,
		"selection_only": selection_only,
		"position_width": position_width,
		"compress": compress,
	}
