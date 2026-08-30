## Pick tool: samples the voxel at the clicked position and sets it as the
## editor's palette selection.
@tool
extends VoxlyTool

const ICON := preload("res://addons/voxly-core/assets/icons/pick.svg")

const _debug_context := "VoxlyToolPick"

## Registers the pick tool in the registry.
func _init() -> void:
	name = "pick"
	display_name = "Pick"
	placement = Placement.IN_PLACE
	edit_intent = EditIntent.ADD
	hit_resolution = HitResolution.VOXEL
	mirror_modes = 0
	icon = ICON

## Picks the voxel under the cursor.
func work(editor: VoxlyEditor, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void:
	if not editor.adapter or positions.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context, "No target or empty positions")
		return
	
	var adapter = editor.adapter
	var position := positions[0]
	var voxel_id = adapter.voxel_at(position)
	if voxel_id == null:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context, "No voxel at position %s" % str(position))
		return
	
	# Set the palette to the picked voxel.
	editor.palette_id = voxel_id
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context,
		"Picked voxel ID %d at %s" % [voxel_id, str(position)])
	
	# Notify via signal that the palette changed.
	if editor.has_signal("palette_changed"):
		editor.emit_signal("palette_changed", voxel_id)

## Returns the color used for the pick preview.
func get_preview_color(editor: VoxlyEditor) -> Color:
	return Color(1, 1, 1, 0.8)

## Returns whether the pick tool shows a preview.
func show_preview() -> bool:
	return true

## Applies the picked voxel to the palette.
func on_work_complete(editor: VoxlyEditor) -> void:
	# After picking, signal the palette change so the controller can update UI.
	if editor.has_signal("palette_changed"):
		editor.emit_signal("palette_changed", editor.palette_id)
