## Base class for all brushes. A brush defines a set of voxel positions
## relative to a hit position; the active tool then acts on those positions.
@tool
@abstract
class_name VoxlyBrush
extends RefCounted

## Unique identifier for this brush type.
var name: String = ""

## Display name shown in the UI (defaults to the capitalized [member name]).
var display_name: String:
	get:
		if display_name == "":
			return name.capitalize()
		return display_name

## Whether this brush requires a drag interaction.
var requires_drag: bool = false

## Whether this brush paints continuously while the mouse is held and dragged.
## When enabled (and the brush does not require a drag interaction), the brush
## is applied repeatedly to each new voxel the cursor passes over, and every
## stamp in the stroke is merged into a single undoable action.
var continuous: bool = false

## Maximum number of voxels this brush can produce.
var max_voxels: int = -1

## How brushes resolve the cursor hit.
enum HitResolution {
	## Hit the model's bounding cage surface.
	SURFACE,
	## Hit existing voxels (DDA raycast).
	VOXEL,
}

## How this brush resolves the cursor hit.
var hit_resolution: HitResolution = HitResolution.SURFACE

## Optional icon to display in the brush's UI button.
var icon: Texture2D = null

## Returns true when this brush supports the continuous painting mode.
## Brushes that define their shape with a drag interaction (box, line, extrude)
## override this to return false since "continuous" conflicts with "drag to
## define the shape".
func supports_continuous() -> bool:
	return true

## Returns an array of voxel positions based on the current hit and editor state.
## The editor provides context (mirrors, active voxel set, etc.).
@abstract
## Returns the voxel positions the brush covers for the given hit.
func get_positions(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]

## Offsets a hit position by the active tool's placement along the hit normal,
## but only for voxel-level hits (DDA). Cage wall hits already resolve to the
## correct interior cell and must not be offset.
func offset_for_tool(editor: VoxlyEditor, position: Vector3i, normal: Vector3i, is_dda_hit: bool) -> Vector3i:
	if editor and editor.active_tool and is_dda_hit:
		return editor.active_tool.offset_position(position, normal)
	return position

## Returns whether preview voxels should be shown for this brush.
## Brushes that generate expensive positions (e.g. flood fill) can override
## this to disable per-frame hover preview, or gate it behind an option.
func show_preview() -> bool:
	return true

## Called when a drag starts. Stores the origin position.
func on_drag_start(editor: VoxlyEditor, hit: Dictionary) -> void:
	pass

## Called during a drag to update positions from origin to the current hit.
func on_drag_move(editor: VoxlyEditor, hit: Dictionary) -> Array[Vector3i]:
	return []

## Called when a drag ends.
func on_drag_end() -> void:
	pass

## Returns a preview color for this brush's current state.
## The tool can override this for mode-specific coloring.
func get_preview_color(editor: VoxlyEditor) -> Color:
	return Color.WHITE

## Returns an array of option dictionaries for the UI context panel.
## Each dictionary describes a configurable property on this brush.
## Keys: "label" (String), "property" (String), "type" (TYPE_* int),
##       "default", "min", "max", "step" (optional).
func get_options() -> Array[Dictionary]:
	return []

## Returns a short info string about the current brush state
## (e.g. line length, box dimensions).
func get_drag_info() -> String:
	return ""
