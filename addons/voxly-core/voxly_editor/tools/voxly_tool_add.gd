## Add tool: writes the current palette voxel into every brush position.
@tool
extends VoxlyTool

const ICON := preload("res://addons/voxly-core/assets/icons/add.svg")

const _debug_context := "VoxlyToolAdd"

## Registers the add tool in the registry.
func _init() -> void:
	name = "add"
	display_name = "Add"
	placement = Placement.ON_SURFACE
	edit_intent = EditIntent.ADD
	preview_source = PreviewSource.PALETTE_VOXEL
	hit_resolution = HitResolution.VOXEL
	mirror_modes = 7
	icon = ICON

## Returns whether this tool needs a palette voxel selected to perform edits.
func requires_palette_voxel() -> bool:
	return true

## Sets the palette voxel at each position.
func work(editor: VoxlyEditor, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void:
	if not editor.adapter:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context, "No target to apply to")
		return
	
	var adapter = editor.adapter
	# Check for per-position palette overrides.
	var has_overrides = not editor.pattern_voxel_overrides.is_empty()
	
	var fallback_palette = editor.palette_id
	if not has_overrides and (fallback_palette < 0 or not editor.voxel_set):
		push_warning("VoxlyTool Add: No palette voxel selected")
		editor.palette_voxel_required.emit()
		return
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context,
		"Adding %d voxels, overrides=%s" % [positions.size(), "yes" if has_overrides else "no"])
	
	# During a continuous stroke, record_voxel_change() applies live and buffers
	# the delta; the stroke commits a single undo action on release. Outside a
	# stroke we own a normal per-action lifecycle.
	if not editor.stroke_active:
		undo_redo.create_action("Voxly Add Voxels")
	for position in positions:
		# Use the per-position override if available, otherwise fall back to
		# the palette.
		var palette_id_to_use = fallback_palette
		if has_overrides and editor.pattern_voxel_overrides.has(position):
			palette_id_to_use = editor.pattern_voxel_overrides[position]
		
		var old_id = adapter.voxel_at(position)
		editor.record_voxel_change(adapter, position, palette_id_to_use, old_id, undo_redo)
	
	# Outside a stroke, register the rebuild and commit the action.
	if not editor.stroke_active:
		editor.record_rebuild(undo_redo, adapter)
		undo_redo.commit_action()
	
	# Clean up overrides after applying.
	editor.pattern_voxel_overrides.clear()

## Returns the palette color used for the preview.
func get_preview_color(editor: VoxlyEditor) -> Color:
	if editor.palette_id >= 0 and editor.voxel_set:
		var voxel_data = editor.voxel_set.get_voxel(editor.palette_id)
		if voxel_data:
			var voxel_color: Color = voxel_data.base_color
			if voxel_color.a == 0:
				voxel_color = Color(1, 1, 1, 0.4)
			voxel_color.a = 0.4
			return voxel_color
	return Color(1, 1, 1, 0.6)
