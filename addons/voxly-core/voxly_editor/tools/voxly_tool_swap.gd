## Swap tool: replaces the voxels at every brush position with the currently
## selected palette voxel (leaving empty cells untouched).
@tool
extends VoxlyTool

const ICON := preload("res://addons/voxly-core/assets/icons/swap.svg")

const _debug_context := "VoxlyToolSwap"

## Registers the swap tool in the registry.
func _init() -> void:
	name = "swap"
	display_name = "Swap"
	placement = Placement.IN_PLACE
	edit_intent = EditIntent.ADD
	preview_source = PreviewSource.PALETTE_VOXEL
	hit_resolution = HitResolution.VOXEL
	mirror_modes = 7
	icon = ICON

## Returns whether this tool needs a palette voxel selected to perform edits.
func requires_palette_voxel() -> bool:
	return true

## Swaps the voxel IDs at the given positions.
func work(editor: VoxlyEditor, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void:
	if editor.palette_id < 0 or not editor.voxel_set:
		push_warning("VoxlyTool Swap: No palette voxel selected")
		editor.palette_voxel_required.emit()
		return
	if not editor.adapter:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context, "No target to apply to")
		return
	
	var adapter = editor.adapter
	var palette_id := editor.palette_id
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context,
		"Swapping %d voxels to palette=%d" % [positions.size(), palette_id])
	
	# During a continuous stroke, record_voxel_change() applies live and buffers
	# the delta; the stroke commits a single undo action on release. Outside a
	# stroke we own a normal per-action lifecycle.
	if not editor.stroke_active:
		undo_redo.create_action("Voxly Swap Voxels")
	for position in positions:
		var old_id = adapter.voxel_at(position)
		if old_id != null and old_id != palette_id:
			editor.record_voxel_change(adapter, position, palette_id, old_id, undo_redo)
	if not editor.stroke_active:
		editor.record_rebuild(undo_redo, adapter)
		undo_redo.commit_action()

## Returns the swap preview color.
func get_preview_color(editor: VoxlyEditor) -> Color:
	if editor.palette_id >= 0 and editor.voxel_set:
		var voxel_data = editor.voxel_set.get_voxel(editor.palette_id)
		if voxel_data:
			var voxel_color: Color = voxel_data.base_color
			if voxel_color.a == 0:
				voxel_color = Color(1, 1, 1, 0.4)
			voxel_color.a = 0.4
			return voxel_color
	return Color(0.2, 0.6, 1, 0.6)
