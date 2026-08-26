@tool
extends VoxlyTool

const ICON := preload("res://addons/voxly-core/assets/icons/swap.svg")

func _init() -> void:
	name = "swap"
	display_name = "Swap"
	placement = Placement.IN_PLACE
	edit_intent = EditIntent.ADD
	preview_source = PreviewSource.PALETTE_VOXEL
	hit_resolution = HitResolution.VOXEL
	mirror_modes = 7
	icon = ICON

func work(editor, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void:
	if editor.palette_id < 0 or not editor.voxel_set:
		push_warning("VoxlyTool Swap: No palette voxel selected")
		return
	if not editor.adapter:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "ToolSwap", "No target to apply to")
		return
	
	var adapter = editor.adapter
	var palette = editor.palette_id

	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "ToolSwap",
		"Swapping %d voxels to palette=%d" % [positions.size(), palette])
	
	# During a continuous stroke, record_voxel_change() applies live and buffers
	# the delta; the stroke commits a single undo action on release. Outside a
	# stroke we own a normal per-action lifecycle.
	if not editor.stroke_active:
		undo_redo.create_action("Voxly Swap Voxels")
	for pos in positions:
		var old_id = adapter.voxel_at(pos)
		if old_id != null and old_id != palette:
			editor.record_voxel_change(adapter, pos, palette, old_id, undo_redo)
	if not editor.stroke_active:
		editor.record_rebuild(undo_redo, adapter)
		undo_redo.commit_action()

func get_preview_color(editor) -> Color:
	if editor.palette_id >= 0 and editor.voxel_set:
		var voxel_data = editor.voxel_set.get_voxel(editor.palette_id)
		if voxel_data:
			var voxel_color : Color = voxel_data.base_color
			if voxel_color.a == 0:
				voxel_color = Color(1, 1, 1, 0.4)
			voxel_color.a = .4
			return voxel_color
	return Color(0.2, 0.6, 1, 0.6)
