## Side editor dock hosting the VoxelSet editor component.
##
## Forwards the active VoxelSet to the editor, syncs the viewer selection to
## the palette signal, stores the undo/redo manager for the child editor, and
## marks the set as edited when it changes.
@tool
extends EditorDock

## Emitted when the user selects a single voxel in the voxel set viewer.
## Passes the voxel ID (-1 if none or multiple selected).
signal palette_voxel_changed(voxel_id: int)

## The embedded voxel set editor widget.
@onready var _voxel_set_editor := %VoxelSetEditor

## The voxel set currently shown in the dock.
var _current_voxel_set: VoxelSet

## Cached undo/redo manager. The UI manager sets this before the dock is added
## to the tree (and before @onready vars exist), so it's stored and applied
## once the dock is ready.
var _pending_undo_redo_manager: EditorUndoRedoManager

## Returns the VoxelSet currently shown in the dock.
func get_current_voxel_set() -> VoxelSet:
	return _current_voxel_set

## Sets the voxel set shown by the dock, avoiding redundant re-application.
func set_voxel_set(voxel_set: VoxelSet) -> void:
	# Avoid redundant re-application that would clobber the current selection.
	if voxel_set == _current_voxel_set:
		# Same-set reuse (e.g. re-selecting the same node): the auto-select in
		# _propagate_voxel_set won't run, so re-sync the palette from the
		# viewer's current selection; otherwise, a fresh node controller stays
		# at -1 and the bottom dock shows no palette.
		if _voxel_set_editor and _voxel_set_editor.voxel_set_viewer:
			var viewer = _voxel_set_editor.voxel_set_viewer
			if viewer.selected_ids.is_empty() and voxel_set:
				var ids := voxel_set.get_voxel_ids()
				if not ids.is_empty():
					select_voxel(ids[0]) # emits palette_voxel_changed up the chain
					return
			_on_selected_voxels_changed(viewer.selected_ids.duplicate())
		return
	
	# Disconnect from the previous voxel set's changed signal.
	if _current_voxel_set and _current_voxel_set.changed.is_connected(_on_voxel_set_changed):
		_current_voxel_set.changed.disconnect(_on_voxel_set_changed)
	
	_current_voxel_set = voxel_set
	
	# Guard: children may not be ready yet (e.g., set before entering the tree).
	if not _voxel_set_editor:
		return
	
	_propagate_voxel_set(voxel_set)

## Propagates the set to the editor, wires the changed signal, and auto-selects
## the first voxel so the dock opens with a valid selection.
func _propagate_voxel_set(voxel_set: VoxelSet) -> void:
	_voxel_set_editor.set_voxel_set(voxel_set)
	
	# Connect to the new voxel set's changed signal to mark it as edited.
	if voxel_set and not voxel_set.changed.is_connected(_on_voxel_set_changed):
		voxel_set.changed.connect(_on_voxel_set_changed)
	
	_auto_select_first_voxel()

## Selects the first voxel in the set when the dock is shown, if any exist.
func _auto_select_first_voxel() -> void:
	if not _voxel_set_editor or not _current_voxel_set:
		return
	var voxel_ids := _current_voxel_set.get_voxel_ids()
	if voxel_ids.is_empty():
		return
	select_voxel(voxel_ids[0])

## Stores the undo/redo manager and forwards it to the editor once it's ready.
func set_undo_redo_manager(undo_redo_manager: EditorUndoRedoManager) -> void:
	_pending_undo_redo_manager = undo_redo_manager
	if _voxel_set_editor:
		_voxel_set_editor.set_undo_redo_manager(undo_redo_manager)

## Connects the editor widget signals to the dock.
func _ready() -> void:
	if _voxel_set_editor:
		_voxel_set_editor.selected_voxels_changed.connect(_on_selected_voxels_changed)
		# Re-apply the undo/redo manager now that children are in-tree and ready
		# (the UI manager sets it before add_dock, when children don't exist yet).
		if _pending_undo_redo_manager:
			_voxel_set_editor.set_undo_redo_manager(_pending_undo_redo_manager)
		# If a set was assigned before _ready(), propagate + auto-select now.
		if _current_voxel_set:
			_propagate_voxel_set(_current_voxel_set)

## Marks the current voxel set as edited so the editor saves it.
func _on_voxel_set_changed() -> void:
	if not _current_voxel_set:
		return
	EditorInterface.set_object_edited(_current_voxel_set, true)

## Forwards the viewer's selection to the palette signal.
func _on_selected_voxels_changed(selected_ids: Array) -> void:
	if selected_ids.size() == 1:
		palette_voxel_changed.emit(selected_ids[0] as int)
	else:
		palette_voxel_changed.emit(-1)

## Programmatically selects a voxel in the viewer, if the editor is ready.
func select_voxel(voxel_id: int) -> void:
	if _voxel_set_editor and _voxel_set_editor.voxel_set_viewer:
		if _voxel_set_editor.voxel_set_viewer.voxel_set and _voxel_set_editor.voxel_set_viewer.voxel_set.voxel_id_exists(voxel_id):
			_voxel_set_editor.voxel_set_viewer.select_voxel(voxel_id)
