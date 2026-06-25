@tool
class_name VoxlyUIManager
extends RefCounted
## Manages the lifecycle of bottom panel docks for the Voxly editor.
## Supports simultaneous display: the VoxelSet editor lives in the right-side dock,
## while VoxelNode3D editor live in bottom panel.

signal dock_shown(dock_type: String)

signal dock_hidden(dock_type: String)

## Enum of dock types this manager can show.
enum DockType {
	NONE,
	VOXEL_SET_EDITOR,
	VOXEL_OBJECT_EDITOR,
}

## Right-side dock slot used for the VoxelSet editor.
const VOXEL_SET_DOCK_SLOT := EditorPlugin.DOCK_SLOT_RIGHT_BL

var _editor_plugin: EditorPlugin
var _state_machine: VoxlyStateMachine

## Currently active bottom-panel dock Control node, if any.
var _bottom_dock: Control = null
var _bottom_dock_type: DockType = DockType.NONE

## VoxelSet editor dock, managed separately so it can coexist with the bottom panel.
var _voxel_set_dock: Control = null

func _init(plugin: EditorPlugin, state_machine: VoxlyStateMachine) -> void:
	_editor_plugin = plugin
	_state_machine = state_machine
	_state_machine.state_changed.connect(_on_state_changed)
	print("VoxlyUIManager: Initialized")

## Returns the currently active bottom-panel dock control, if any.
func get_current_dock() -> Control:
	return _bottom_dock

## Returns the type of the currently active bottom-panel dock.
func get_current_dock_type() -> DockType:
	return _bottom_dock_type

## Show a dock for the given dock type and optional node.
func show_dock(dock_type: DockType, node: Node3D = null) -> void:
	match dock_type:
		DockType.VOXEL_SET_EDITOR:
			_show_voxel_set_dock(node)
		DockType.VOXEL_OBJECT_EDITOR:
			_hide_bottom_dock()
			_show_voxel_node_editor_dock(node)
		_:
			return

## Hides and cleans up the current bottom-panel dock only.
## Does NOT affect the VoxelSet right-side dock.
func hide_current_dock() -> void:
	_hide_bottom_dock()

## Hides all docks (both bottom panel and VoxelSet).
func hide_all_docks() -> void:
	_hide_bottom_dock()
	_hide_voxel_set_dock()

## Returns whether the VoxelSet right-side dock is currently visible.
func is_voxel_set_dock_visible() -> bool:
	return _voxel_set_dock != null

func _on_state_changed(transition: VoxlyState.Transition) -> void:
	match transition.to_state:
		VoxlyState.State.IDLE:
			hide_all_docks()

		VoxlyState.State.VIEWING_VOXEL_SET:
			# Show the VoxelSet dock in the right panel.
			# Do NOT hide the bottom panel — they can coexist.
			_show_voxel_set_dock(transition.selected_node)

		VoxlyState.State.VIEWING_VOXEL_MODEL:
			# Show the VoxelNode editor in the bottom panel.
			# Keep the VoxelSet dock if it's already visible.
			_hide_bottom_dock()
			_show_voxel_node_editor_dock(transition.selected_node)

		VoxlyState.State.EDITING_VOXEL_MODEL:
			# Dock should already be visible from VIEWING_VOXEL_MODEL
			# The editor tool will connect to input_handler
			pass

func _hide_bottom_dock() -> void:
	if _bottom_dock == null:
		return
	
	var old_type := _bottom_dock_type
	
	_editor_plugin.remove_control_from_bottom_panel(_bottom_dock)
	_bottom_dock.queue_free()
	_bottom_dock = null
	_bottom_dock_type = DockType.NONE
	
	dock_hidden.emit(DockType.keys()[old_type])
	print("VoxlyUIManager: Hidden %s dock" % DockType.keys()[old_type])

func _hide_voxel_set_dock() -> void:
	if _voxel_set_dock == null:
		return

	_editor_plugin.remove_control_from_docks(_voxel_set_dock)
	_voxel_set_dock.queue_free()
	_voxel_set_dock = null

	dock_hidden.emit("VOXEL_SET_EDITOR")
	print("VoxlyUIManager: Hidden VoxelSet right-side dock")

func _create_dock(path: String, node: Node3D) -> Control:
	# Ensure the path exists; load and instance it.
	var scene := load(path)
	if scene == null:
		return null

	var dock := scene.instantiate() as Control
	if dock == null:
		return null
	return dock

func _show_voxel_set_dock(node: Node3D) -> void:
	print("VoxlyUIManager: Shown VoxelSet editor right-side dock")

func _show_voxel_node_editor_dock(node: Node3D) -> void:
	print("VoxlyUIManager: Shown VoxlyEditor editor dock")
