@tool
extends EditorDock

## Emitted when the editing toggle changes in the editor component.
signal editing_toggled(enabled: bool)

## Emitted when the user requests to add a new VoxelSet to the target node.
signal add_voxel_set_requested

## Emitted when the user requests to open the VoxelSet Editor dock.
signal voxel_set_editor_requested

## The VoxelModel3DController driving this dock.
var controller: VoxelModel3DController = null

@onready var _voxel_node_3d_editor := %VoxelNode3DEditor


func set_voxel_set(vs: VoxelSet) -> void:
	if not _voxel_node_3d_editor:
		return
	_voxel_node_3d_editor.set_voxel_set(vs)


## Forwards the current palette selection (or -1 when cleared) to the editor
## component so it can show/update the palette notice.
func set_palette(voxel_id: int) -> void:
	if _voxel_node_3d_editor:
		_voxel_node_3d_editor.set_palette(voxel_id)


## Forwards whether the VoxelSet editor dock is showing a set that doesn't
## belong to the currently active node, so the editor can show a notice.
func set_palette_mismatch(mismatched: bool) -> void:
	if _voxel_node_3d_editor:
		_voxel_node_3d_editor.set_palette_mismatch(mismatched)


func set_editor_title(new_title: String) -> void:
	if _voxel_node_3d_editor:
		_voxel_node_3d_editor.title = new_title


func set_controller(new_controller: VoxelModel3DController) -> void:
	controller = new_controller
	if not _voxel_node_3d_editor or not controller:
		return
	
	# Wire the UI to the controller
	_voxel_node_3d_editor.set_controller(controller)
	
	# Populate brush and tool buttons
	_voxel_node_3d_editor.populate_brushes()
	_voxel_node_3d_editor.populate_tools()


func _on_editor_editing_toggled(enabled: bool) -> void:
	if not is_instance_valid(_voxel_node_3d_editor) or not controller:
		return
	controller.set_editing(enabled)
	editing_toggled.emit(enabled)


func _ready() -> void:
	# Wire the editing toggle from the UI component to this dock
	if _voxel_node_3d_editor:
		_voxel_node_3d_editor.editing_toggled.connect(_on_editor_editing_toggled)
		_voxel_node_3d_editor.add_voxel_set_requested.connect(_on_add_voxel_set_requested)
		_voxel_node_3d_editor.voxel_set_editor_requested.connect(_on_voxel_set_editor_requested)


func _on_add_voxel_set_requested() -> void:
	add_voxel_set_requested.emit()


func _on_voxel_set_editor_requested() -> void:
	voxel_set_editor_requested.emit()


func set_editing_enabled(enabled: bool) -> void:
	if _voxel_node_3d_editor:
		_voxel_node_3d_editor._editing_check_box.button_pressed = enabled
