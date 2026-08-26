@tool
@abstract
class_name VoxlyTool
extends RefCounted
## Base class for all voxly tools, tools apply an operation to a set of voxel
## positions define by brush.

## Unique identifier for this tool type.
var name: String = ""

## Display name for UI (defaults to name capitalized).
var display_name: String:
	get:
		if display_name == "":
			return name.capitalize()
		return display_name

## Where the tool's voxels land relative to the hovered face.
##   IN_PLACE   : edit the hovered cell directly
##   ON_SURFACE : place one cell above the hovered face
enum Placement { IN_PLACE, ON_SURFACE }

## Where this tool's edits land relative to the hovered face.
var placement: Placement = Placement.IN_PLACE

enum EditIntent { ADD, REMOVE }

## Intent of the tool: does it add or remove from the model.
var edit_intent: EditIntent = EditIntent.ADD

## What the editor's ghost preview shows for this tool.
##   FLAT_COLOR    : A simple colored box.
##   PALETTE_VOXEL : The currently-selected palette voxel, rendered with its
##                   accurate per-face colors / textures.
enum PreviewSource { FLAT_COLOR, PALETTE_VOXEL }

## How this tool's ghost preview is rendered.
var preview_source: PreviewSource = PreviewSource.FLAT_COLOR

## Whether this tool operates on the surface of the model
## or on individual voxels.
##   SURFACE : hit the cage
##   VOXEL   : hit existing voxels
enum HitResolution { SURFACE, VOXEL }

## How this tool resolves the cursor hit.
var hit_resolution: HitResolution = HitResolution.SURFACE

## Which mirror axes this tool supports (X=1, Y=2, Z=4, ALL=7).
var mirror_modes: int = 7

## Which brush types this tool supports. Empty means all.
## Names correspond to VoxlyBrush.name values.
var supported_brush_names: PackedStringArray = PackedStringArray()

## Optional icon to display in the tool's UI button.
var icon: Texture2D = null

## Applies the tool operation to the given positions using the editor context.
@abstract
func work(editor, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void

## Offsets a hit position by the tool's placement mode along the hit normal.
## ON_SURFACE moves one cell out along the normal; IN_PLACE returns the
## position unchanged.
func offset_position(pos: Vector3i, normal: Vector3i) -> Vector3i:
	if placement == Placement.ON_SURFACE:
		return pos + normal
	return pos

## Filters brush-generated positions before they are previewed or committed.
## The default returns the positions unchanged. Tools that operate only on
## existing voxels override this to drop empty cells.
func filter_positions(editor, positions: Array[Vector3i]) -> Array[Vector3i]:
	return positions

## Returns the preview color for this tool in its current state.
## The editor provides context: palette, target, etc.
func get_preview_color(editor) -> Color:
	return Color.WHITE

## Returns whether preview voxels should be shown for this tool.
## Pick, for example, might only show a highlight on the targeted voxel.
func show_preview() -> bool:
	return true

## Called after work() completes. Useful for tools that need cleanup
## or additional operations (e.g. updating a VoxelSet).
func on_work_complete(editor) -> void:
	pass

## Returns an array of option dictionaries for the UI context panel.
## Each dictionary describes a configurable property on this tool.
func get_options() -> Array[Dictionary]:
	return []
