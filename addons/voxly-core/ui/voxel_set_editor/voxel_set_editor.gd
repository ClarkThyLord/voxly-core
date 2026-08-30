## Combined VoxelSet editor panel.
##
## Composes the voxel viewer, inspector, and material editor, wiring their
## signals together and sharing a single undo/redo stack.
@tool
extends BoxContainer

## Emitted when the selection of voxels changes in the viewer.
## Provides the list of selected voxel IDs.
signal selected_voxels_changed(selected_ids: Array)

## The VoxelSet being edited.
@export var voxel_set: VoxelSet = null:
	set = set_voxel_set

## Exposed so external components can latch on to these children.
@onready var voxel_editor := %VoxelEditor

## Exposed so external components can latch on to these children.
@onready var voxel_inspector := %VoxelInspector

## Exposed so external components can latch on to these children.
@onready var voxel_set_viewer := %VoxelSetViewer

## Main split container.
@onready var _split_container: SplitContainer = %SplitContainer
## Container holding the voxel viewer.
@onready var _voxel_container: SplitContainer = %VoxelContainer
## Label showing summary information.
@onready var _info_label: Label = %InfoLabel

## Stores the last-seen voxel set so label refreshes can detect swapped sets.
var _last_label_voxel_set: VoxelSet = null

## UndoRedo for standalone use. Either this or _undo_redo_manager should be set.
var _undo_redo: UndoRedo = null

## EditorUndoRedoManager for editor plugin integration. Takes priority if set.
var _undo_redo_manager: EditorUndoRedoManager = null

## Currently selected voxel IDs.
var _selected_voxel_ids: Array = []

## True while a voxel-set update is queued.
var _pending_update: bool = false

## Sets a plain UndoRedo for standalone usage. Propagated to children.
func set_undo_redo(undo_redo: UndoRedo) -> void:
	_undo_redo = undo_redo
	_propagate_undo_redo()

## Sets an EditorUndoRedoManager for editor plugin integration. Propagated to
## children.
func set_undo_redo_manager(manager: EditorUndoRedoManager) -> void:
	_undo_redo_manager = manager
	_propagate_undo_redo()

## Shares the undo/redo stack with child editors.
func _propagate_undo_redo() -> void:
	if not is_inside_tree():
		return
	# Children use whichever is set on us.
	voxel_set_viewer.undo_redo = _undo_redo_manager
	voxel_editor.set_undo_redo(_undo_redo)
	voxel_editor.set_undo_redo_manager(_undo_redo_manager)
	voxel_inspector.set_undo_redo(_undo_redo)
	voxel_inspector.set_undo_redo_manager(_undo_redo_manager)

## Sets the voxel set edited by this panel.
func set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if new_voxel_set == voxel_set:
		return
	voxel_set = new_voxel_set
	_selected_voxel_ids.clear()
	
	if not voxel_set_viewer or not voxel_editor or not voxel_inspector:
		_pending_update = true
		return
	
	_apply_voxel_set()

## Applies the current voxel set to all child editors.
func _apply_voxel_set() -> void:
	_pending_update = false
	
	# Propagate to all children.
	voxel_set_viewer.voxel_set = voxel_set
	voxel_set_viewer.undo_redo = _undo_redo_manager
	voxel_editor.voxel_set = voxel_set
	voxel_inspector.voxel_set = voxel_set
	
	# Track the voxel set so the info label can refresh on changes.
	if _last_label_voxel_set and _last_label_voxel_set.changed.is_connected(_on_voxel_set_changed):
		_last_label_voxel_set.changed.disconnect(_on_voxel_set_changed)
	if voxel_set and not voxel_set.changed.is_connected(_on_voxel_set_changed):
		voxel_set.changed.connect(_on_voxel_set_changed)
	_last_label_voxel_set = voxel_set
	
	# Sync the voxel container orientation with the root BoxContainer.
	_voxel_container.vertical = vertical
	
	# Show/hide the voxel container based on selection.
	_update_edit_panel_visibility()
	_update_info_label()

## Wires the child widget signals together.
func _ready() -> void:
	# Wire viewer selection, editor + inspector.
	voxel_set_viewer.selected_voxels_changed.connect(_on_viewer_selection_changed)
	
	# Wire editor changes, viewer refresh.
	voxel_editor.changed.connect(_on_child_changed)
	voxel_inspector.changed.connect(_on_child_changed)
	
	# When the inspector changes a voxel ID, refresh the viewer and re-sync the
	# editor.
	voxel_inspector.changed_id.connect(_on_inspector_id_changed)
	
	# Hide the voxel container initially.
	_update_edit_panel_visibility()
	
	_split_container.vertical = vertical
	_voxel_container.vertical = vertical
	
	# Propagate undo/redo to children now that they exist.
	_propagate_undo_redo()
	
	# Apply any voxel_set that was set before _ready() fired.
	if _pending_update:
		_apply_voxel_set()

## Accepts the vertical property for layout compatibility.
func _set(property: StringName, value) -> bool:
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

## Tracks selection changes coming from the viewer.
func _on_viewer_selection_changed(selected_ids: Array) -> void:
	_selected_voxel_ids = selected_ids.duplicate()
	
	if selected_ids.size() == 1:
		var voxel_id: int = selected_ids[0]
		voxel_editor.voxel_id = voxel_id
		voxel_inspector.voxel_id = voxel_id
	else:
		voxel_editor.voxel_id = -1
		voxel_inspector.voxel_id = -1
	
	_update_edit_panel_visibility()
	_update_info_label()
	
	# Propagate the selection change upward so the dock can emit
	# palette_voxel_changed.
	selected_voxels_changed.emit(_selected_voxel_ids)

## Updates the tracked selection when a voxel ID changes.
func _on_inspector_id_changed(old_voxel_id: int, new_voxel_id: int) -> void:
	# Update the tracked selection to the new ID.
	if old_voxel_id in _selected_voxel_ids:
		_selected_voxel_ids.erase(old_voxel_id)
		_selected_voxel_ids.append(new_voxel_id)
	
	# Rebuild the viewer to reflect the ID change.
	voxel_set_viewer._rebuild()
	
	# Re-sync the editor to the new ID.
	if _selected_voxel_ids.size() == 1:
		voxel_editor.voxel_id = new_voxel_id

## Refreshes the info label when a single voxel changes.
func _on_child_changed() -> void:
	if _selected_voxel_ids.size() == 1:
		voxel_set_viewer.update_button(_selected_voxel_ids[0])
	_update_info_label()

## Refreshes the info label when the set changes.
func _on_voxel_set_changed() -> void:
	_update_info_label()

## Updates the info label with contextual VoxelSet information: total voxel
## count and the current selection count.
func _update_info_label() -> void:
	if not _info_label:
		return
	if not voxel_set:
		_info_label.text = "No VoxelSet"
		return
	var parts: PackedStringArray = []
	var selection_count := _selected_voxel_ids.size()
	if selection_count > 0:
		parts.append("Selected: %d" % selection_count)
	parts.append("Voxels: %d" % voxel_set.get_voxels_count())
	parts.append("Materials: %d" % voxel_set.get_materials_count())
	_info_label.text = " | ".join(parts)
