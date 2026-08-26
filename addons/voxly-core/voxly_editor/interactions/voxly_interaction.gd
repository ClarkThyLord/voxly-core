@tool
class_name VoxlyInteraction
extends RefCounted
## Base class for mouse-driven interaction models in the voxel editor.
## Each concrete interaction owns one model such that controller just dispatches.
##
## Lifecycle:
##   begin()                  : mouse button pressed
##   update()                 : dragged over the model surface
##   on_enter_off_surface()   : dragged off the model
##   finish()                 : mouse button released
##   refresh_preview()        : plain hover (no button)
##   cancel()                 : aborted (tool switch / editing off)

var editor: VoxlyEditor
var preview = null
var undo_redo: EditorUndoRedoManager = null


func _init(p_editor: VoxlyEditor, p_preview = null, p_undo_redo: EditorUndoRedoManager = null) -> void:
	editor = p_editor
	preview = p_preview
	undo_redo = p_undo_redo

func begin(_event: InputEventMouse, _hit: Dictionary) -> void:
	pass


func update(_event: InputEventMouse, _hit: Dictionary) -> void:
	pass


func finish(_event: InputEventMouse, _hit: Dictionary) -> void:
	pass


func refresh_preview(_hit: Dictionary) -> void:
	pass


func cancel() -> void:
	pass


## Called when the cursor leaves the model surface mid-interaction.
func on_enter_off_surface() -> void:
	pass

## Picks the preview mesh source (accurate palette voxel for tools that
## declare PALETTE_VOXEL, flat box otherwise). Cached inside the preview, so
## this is a cheap no-op unless palette / tool / voxel-set actually changed.
func build_preview_source() -> void:
	if preview and preview.has_method("build_preview_source"):
		preview.build_preview_source(editor.palette_id, editor.voxel_set, editor.get_preview_source())


## Renders a plain (single-color) position set through the preview.
func show_positions(positions: Array[Vector3i], color: Color = Color.WHITE) -> void:
	if not preview:
		return
	preview.update_preview(positions, color)


## Clears the preview overlay (no-op when there is no overlay).
func clear_preview() -> void:
	if preview:
		preview.clear_preview()


## Returns brush positions for a preview.
func get_preview_positions(hit: Dictionary = editor.last_hit) -> Array[Vector3i]:
	if preview == null or preview.preview_mirrored:
		return editor.get_mirrored_brush_positions(hit)
	return editor.get_brush_positions(hit)


## Applies the active tool to the current hover hit through the editor.
## Used by click and drag interactions that commit on their final state.
func apply_active_tool() -> void:
	if not undo_redo:
		return
	if editor.last_hit.is_empty():
		return
	var positions := editor.get_mirrored_brush_positions()
	if positions.is_empty():
		return
	editor.apply_tool(editor.adapter, positions, undo_redo)
