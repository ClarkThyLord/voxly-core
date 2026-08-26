@tool
extends VoxlyTool

const ICON := preload("res://addons/voxly-core/assets/icons/add.svg")

func _init() -> void:
	name = "add"
	display_name = "Add"
	placement = Placement.ON_SURFACE
	edit_intent = EditIntent.ADD
	preview_source = PreviewSource.PALETTE_VOXEL
	hit_resolution = HitResolution.VOXEL
	mirror_modes = 7
	icon = ICON

func work(editor, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void:
	if not editor.adapter:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "ToolAdd", "No target to apply to")
		return
	
	var adapter = editor.adapter
	# Check for per-position palette overrides.
	var has_overrides = not editor.pattern_voxel_overrides.is_empty()
	
	var fallback_palette = editor.palette_id
	if not has_overrides and (fallback_palette < 0 or not editor.voxel_set):
		push_warning("VoxlyTool Add: No palette voxel selected")
		return
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, "ToolAdd",
		"Adding %d voxels, overrides=%s" % [positions.size(), "yes" if has_overrides else "no"])
	
	# During a continuous stroke, record_voxel_change() applies live and buffers
	# the delta; the stroke commits a single undo action on release. Outside a
	# stroke we own a normal per-action lifecycle.
	if not editor.stroke_active:
		undo_redo.create_action("Voxly Add Voxels")
	for pos in positions:
		# Use per-position override if available, otherwise fall back to palette
		var palette_id_to_use = fallback_palette
		if has_overrides and editor.pattern_voxel_overrides.has(pos):
			palette_id_to_use = editor.pattern_voxel_overrides[pos]
		
		var old_id = adapter.voxel_at(pos)
		editor.record_voxel_change(adapter, pos, palette_id_to_use, old_id, undo_redo)
	
	# Outside a stroke, register the rebuild and commit the action.
	if not editor.stroke_active:
		editor.record_rebuild(undo_redo, adapter)
		undo_redo.commit_action()
	
	# Clean up overrides after applying
	editor.pattern_voxel_overrides.clear()

func get_preview_color(editor) -> Color:
	if editor.palette_id >= 0 and editor.voxel_set:
		var voxel_data = editor.voxel_set.get_voxel(editor.palette_id)
		if voxel_data:
			var voxel_color : Color = voxel_data.base_color
			if voxel_color.a == 0:
				voxel_color = Color(1, 1, 1, 0.4)
			voxel_color.a = .4
			return voxel_color
	return Color(1, 1, 1, 0.6)
