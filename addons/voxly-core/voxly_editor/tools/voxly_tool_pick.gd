@tool
extends VoxlyTool

const ICON := preload("res://addons/voxly-core/assets/icons/pick.svg")

func _init() -> void:
	name = "pick"
	display_name = "Pick"
	placement = Placement.IN_PLACE
	edit_intent = EditIntent.ADD
	hit_resolution = HitResolution.VOXEL
	mirror_modes = 0
	icon = ICON

func work(editor, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void:
	if not editor.adapter or positions.is_empty():
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "ToolPick", "No target or empty positions")
		return
	
	var adapter = editor.adapter
	var pos := positions[0]
	var voxel_id = adapter.voxel_at(pos)
	if voxel_id == null:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "ToolPick", "No voxel at position %s" % str(pos))
		return
	
	# Set the palette to the picked voxel
	editor.palette_id = voxel_id
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "ToolPick",
		"Picked voxel ID %d at %s" % [voxel_id, str(pos)])
	
	# Notify via signal that palette changed
	if editor.has_signal("palette_changed"):
		editor.emit_signal("palette_changed", voxel_id)

func get_preview_color(editor) -> Color:
	return Color(1, 1, 1, 0.8)

func show_preview() -> bool:
	return true

func on_work_complete(editor) -> void:
	# After pick, signal the palette change so the controller can update the UI
	if editor.has_signal("palette_changed"):
		editor.emit_signal("palette_changed", editor.palette_id)
