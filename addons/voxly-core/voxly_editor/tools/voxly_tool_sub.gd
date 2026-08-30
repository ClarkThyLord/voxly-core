## Sub tool: removes voxels at every brush position.
@tool
extends VoxlyTool

const ICON := preload("res://addons/voxly-core/assets/icons/sub.svg")

const _debug_context := "VoxlyToolSub"

## Registers the subtract tool in the registry.
func _init() -> void:
	name = "sub"
	display_name = "Sub"
	placement = Placement.IN_PLACE
	edit_intent = EditIntent.REMOVE
	hit_resolution = HitResolution.VOXEL
	mirror_modes = 7
	icon = ICON

## Removes the voxels at the given positions.
func work(editor: VoxlyEditor, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void:
	if not editor.adapter:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context, "No target to apply to")
		return
	
	var adapter = editor.adapter
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context,
		"Removing %d voxels" % positions.size())
	
	# During a continuous stroke, record_voxel_change() applies live and buffers
	# the delta; the stroke commits a single undo action on release. Outside a
	# stroke we own a normal per-action lifecycle.
	if not editor.stroke_active:
		undo_redo.create_action("Voxly Remove Voxels")
	for position in positions:
		var old_id = adapter.voxel_at(position)
		if old_id != null:
			editor.record_voxel_change(adapter, position, null, old_id, undo_redo)
	if not editor.stroke_active:
		editor.record_rebuild(undo_redo, adapter)
		undo_redo.commit_action()

## Returns the removal preview color.
func get_preview_color(editor: VoxlyEditor) -> Color:
	return Color(1, 0.2, 0.2, 0.5)
