@tool
extends BoxContainer

signal close_requested

## The VoxelSet being edited
@export
var voxel_set: VoxelSet = null:
	set = set_voxel_set

## Exposed so external components can latch on to these children.
@onready
var voxel_editor := %VoxelEditor

## Exposed so external components can latch on to these children.
@onready
var voxel_inspector := %VoxelInspector

## Exposed so external components can latch on to these children.
@onready
var voxel_set_viewer := %VoxelSetViewer

@onready
var _split_container : SplitContainer = %SplitContainer

@onready
var _voxel_container : SplitContainer = %VoxelContainer

## UndoRedo for standalone use. Either this or _undo_redo_manager should be set.
var _undo_redo: UndoRedo = null

## EditorUndoRedoManager for editor plugin integration. Takes priority if set.
var _undo_redo_manager: EditorUndoRedoManager = null

var _selected_voxel_ids: Array = []

var _pending_update: bool = false

## Sets a plain UndoRedo for standalone usage. Propagated to children.
func set_undo_redo(undo_redo: UndoRedo) -> void:
	_undo_redo = undo_redo
	_propagate_undo_redo()

## Sets an EditorUndoRedoManager for editor plugin integration. Propagated to children.
func set_undo_redo_manager(manager: EditorUndoRedoManager) -> void:
	_undo_redo_manager = manager
	_propagate_undo_redo()

func _propagate_undo_redo() -> void:
	if not is_inside_tree():
		return
	# Children use whichever is set on us — they check both internally.
	voxel_set_viewer.undo_redo = _undo_redo_manager
	voxel_editor.set_undo_redo(_undo_redo)
	voxel_editor.set_undo_redo_manager(_undo_redo_manager)
	voxel_inspector.set_undo_redo(_undo_redo)
	voxel_inspector.set_undo_redo_manager(_undo_redo_manager)

func set_voxel_set(new_set: VoxelSet) -> void:
	if new_set == voxel_set:
		return
	voxel_set = new_set
	_selected_voxel_ids.clear()
	
	# Guard: children may not be ready yet (e.g., @export fires before _ready)
	if not voxel_set_viewer or not voxel_editor or not voxel_inspector:
		_pending_update = true
		return
	
	_apply_voxel_set()

func _apply_voxel_set() -> void:
	_pending_update = false
	
	# Propagate to all children
	voxel_set_viewer.voxel_set = voxel_set
	voxel_set_viewer.undo_redo = _undo_redo_manager
	voxel_editor.voxel_set = voxel_set
	voxel_inspector.voxel_set = voxel_set
	
	# Sync voxel container orientation with root BoxContainer
	_voxel_container.vertical = vertical
	
	# Show/hide voxel container based on selection
	_update_edit_panel_visibility()

func _ready() -> void:
	# Wire viewer selection → editor + inspector
	voxel_set_viewer.selected_voxels_changed.connect(_on_viewer_selection_changed)
	
	# Wire editor changes → viewer refresh
	voxel_editor.changed.connect(_on_child_changed)
	voxel_inspector.changed.connect(_on_child_changed)
	
	# When inspector changes a voxel ID, refresh viewer and re-sync editor
	voxel_inspector.changed_id.connect(_on_inspector_id_changed)
	
	# Hide voxel container initially
	_update_edit_panel_visibility()
	
	_split_container.vertical = vertical
	_voxel_container.vertical = vertical
	
	# Propagate undo/redo to children now that they exist
	_propagate_undo_redo()
	
	# Apply any voxel_set that was set before _ready() fired
	if _pending_update:
		_apply_voxel_set()

func _set(property, value):
	if property == "vertical":
		if _split_container:
			_split_container.vertical = value
		if _voxel_container:
			_voxel_container.vertical = value
	return false

## Shows the voxel container only when exactly one voxel is selected.
func _update_edit_panel_visibility() -> void:
	var single_selection := _selected_voxel_ids.size() == 1
	_voxel_container.visible = single_selection

func _on_viewer_selection_changed(selected_ids: Array) -> void:
	_selected_voxel_ids = selected_ids.duplicate()
	
	if selected_ids.size() == 1:
		var vid : int = selected_ids[0]
		voxel_editor.voxel_id = vid
		voxel_inspector.voxel_id = vid
	else:
		voxel_editor.voxel_id = -1
		voxel_inspector.voxel_id = -1
	
	_update_edit_panel_visibility()

func _on_inspector_id_changed(old_id: int, new_id: int) -> void:
	# Update the tracked selection to the new ID
	if old_id in _selected_voxel_ids:
		_selected_voxel_ids.erase(old_id)
		_selected_voxel_ids.append(new_id)
	
	# Rebuild the viewer to reflect the ID change
	voxel_set_viewer._rebuild()
	
	# Re-sync editor to the new ID
	if _selected_voxel_ids.size() == 1:
		voxel_editor.voxel_id = new_id

func _on_child_changed() -> void:
	if _selected_voxel_ids.size() == 1:
		voxel_set_viewer.update_button(_selected_voxel_ids[0])
