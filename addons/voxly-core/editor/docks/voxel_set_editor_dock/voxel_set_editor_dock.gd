@tool
extends EditorDock

signal close_requested

@onready
var _voxel_set_editor := %VoxelSetEditor

func set_voxel_set(voxel_set: VoxelSet) -> void:
	if not _voxel_set_editor:
		return
	_voxel_set_editor.set_voxel_set(voxel_set)

func set_undo_redo_manager(ur: EditorUndoRedoManager) -> void:
	if not _voxel_set_editor:
		return
	_voxel_set_editor.set_undo_redo_manager(ur)
