## Select tool for the voxel editor.
##
## Adds or removes voxel positions from the editor's persistent selection,
## depending on the selected mode:
## - Auto (default): toggles each voxel in/out based on its current state.
## - Select: always adds voxels to the selection.
## - Deselect: always removes voxels from the selection.
##
## The set of positions comes from the active brush (point, box, cube, sphere,
## line, etc.) via the normal brush pipeline, so selection behavior matches the
## visual brush exactly.
@tool
extends VoxlyTool

const ICON := preload("res://addons/voxly-core/assets/icons/select.svg")

const _debug_context := "VoxlyToolSelect"

## Selection mode: 0 = Auto (toggle), 1 = Select, 2 = Deselect.
var selection_mode: int = 0

## Registers the select tool in the registry.
func _init() -> void:
	name = "select"
	display_name = "Select"
	placement = Placement.IN_PLACE
	edit_intent = EditIntent.ADD
	hit_resolution = HitResolution.VOXEL
	mirror_modes = 7
	icon = ICON
	supported_brush_names = PackedStringArray()

## Returns the select tool options.
func get_options() -> Array[Dictionary]:
	return [
		{"label": "Mode", "property": "selection_mode", "type": TYPE_INT, "hint": "0=Auto, 1=Select, 2=Deselect", "default": 0},
	]

## Selects the voxels at the given positions.
func work(editor: VoxlyEditor, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void:
	if not editor or not editor.selection:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context, "No editor or selection available")
		return
	
	# Selection only applies to existing voxels.
	positions = filter_positions(editor, positions)
	if positions.is_empty():
		return
	
	var mode_name := "Auto"
	match selection_mode:
		1:
			mode_name = "Select"
		2:
			mode_name = "Deselect"
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_LOGIC, _debug_context,
		"Mode=%s, applying to %d positions" % [mode_name, positions.size()])
	
	# During a continuous stroke the selection is mutated live and each toggle
	# is buffered (via record_selection_change) so the whole stroke commits as
	# one undo action on release. Outside a stroke we own a normal action.
	if not editor.stroke_active:
		undo_redo.create_action("Voxly Select Voxels")
	
	match selection_mode:
		1: # Select: always add to the selection.
			_commit_all(editor, positions, true, undo_redo)
		2: # Deselect: always remove from the selection.
			_commit_all(editor, positions, false, undo_redo)
		_: # Auto: toggle each voxel based on its current state.
			_commit_auto(editor, positions, undo_redo)
	
	if not editor.stroke_active:
		undo_redo.commit_action()

## Records the same add/remove pair for every position.
func _commit_all(editor: VoxlyEditor, positions: Array[Vector3i], select: bool, undo_redo: EditorUndoRedoManager) -> void:
	for position in positions:
		var was_selected: bool = editor.selection.has(position)
		if not editor.stroke_active:
			if select:
				undo_redo.add_do_method(editor.selection, "add", position)
				undo_redo.add_undo_method(editor.selection, "remove", position)
			else:
				undo_redo.add_do_method(editor.selection, "remove", position)
				undo_redo.add_undo_method(editor.selection, "add", position)
		else:
			if select and not was_selected:
				editor.record_selection_change(position, was_selected)
			elif not select and was_selected:
				editor.record_selection_change(position, was_selected)

## Records per-position add/remove pairs so each voxel toggles by its current
## selection state. Undo always restores the exact prior state.
func _commit_auto(editor: VoxlyEditor, positions: Array[Vector3i], undo_redo: EditorUndoRedoManager) -> void:
	for position in positions:
		var was_selected: bool = editor.selection.has(position)
		if not editor.stroke_active:
			if was_selected:
				undo_redo.add_do_method(editor.selection, "remove", position)
				undo_redo.add_undo_method(editor.selection, "add", position)
			else:
				undo_redo.add_do_method(editor.selection, "add", position)
				undo_redo.add_undo_method(editor.selection, "remove", position)
		else:
			editor.record_selection_change(position, was_selected)

## Filters out positions that don't currently contain a voxel; selection only
## applies to existing voxels regardless of which brush generated them.
func filter_positions(editor: VoxlyEditor, positions: Array[Vector3i]) -> Array[Vector3i]:
	if not editor.adapter or not editor.adapter.is_valid():
		return []
	var result: Array[Vector3i] = []
	for position in positions:
		if editor.adapter.voxel_at(position) != null:
			result.append(position)
	return result

## Returns the selection highlight color.
func get_preview_color(editor: VoxlyEditor) -> Color:
	return Color(0.2, 0.5, 1.0, 0.5)
