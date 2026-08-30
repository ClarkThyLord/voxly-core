## State machine for the Voxly editor.
##
## Manages transitions between editor states and provides lifecycle hooks
## ([method _on_enter], [method _on_exit]) for each state transition.
@tool
class_name VoxlyStateMachine
extends RefCounted

## Emitted whenever the editor transitions between states.
signal state_changed(transition: VoxlyState.Transition)

## Emitted when the VoxelSet being edited changes.
signal current_voxel_set_changed(voxel_set: VoxelSet)

const _debug_context := "VoxlyStateMachine"

## Valid state transition table, from source state to list of allowed target states.
## State IDs: 0=IDLE, 1=VIEWING_VOXEL_SET, 2=VIEWING_VOXEL_MODEL, 3=EDITING_VOXEL_MODEL
const _valid_transitions: Dictionary = {
	# From IDLE: can go to any viewing state.
	VoxlyState.State.IDLE: [
		VoxlyState.State.VIEWING_VOXEL_SET,
		VoxlyState.State.VIEWING_VOXEL_MODEL,
	],
	# From VIEWING_VOXEL_SET: can go to IDLE, or directly to VIEWING_VOXEL_MODEL.
	VoxlyState.State.VIEWING_VOXEL_SET: [
		VoxlyState.State.IDLE,
		VoxlyState.State.VIEWING_VOXEL_MODEL,
	],
	# From VIEWING_VOXEL_MODEL: can go to IDLE, EDITING_VOXEL_MODEL, or VIEWING_VOXEL_SET.
	VoxlyState.State.VIEWING_VOXEL_MODEL: [
		VoxlyState.State.IDLE,
		VoxlyState.State.EDITING_VOXEL_MODEL,
		VoxlyState.State.VIEWING_VOXEL_SET,
	],
	# From EDITING_VOXEL_MODEL: can only go back to VIEWING_VOXEL_MODEL or IDLE.
	VoxlyState.State.EDITING_VOXEL_MODEL: [
		VoxlyState.State.VIEWING_VOXEL_MODEL,
		VoxlyState.State.IDLE,
	],
}

## The current editor state.
var current_state: VoxlyState.State = VoxlyState.State.IDLE:
	get = get_current_state

## The VoxelSet resource currently being edited.
## Set by the plugin when a VoxelSet is selected for editing.
var current_voxel_set: VoxelSet

## The editor plugin driving this state machine.
var _editor_plugin: EditorPlugin
## Tracks the current main editor screen (e.g. "3D", "2D", "Script").
var _current_screen: String = "3D"
## Saved editor selection, restored when leaving edit mode.
var _previous_selection: Array[Node] = []

## The node the state machine is currently focused on.
var _current_focused_node: Node = null

## Stores the owning editor plugin.
func _init(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "Initialized (IDLE)")

## Returns the currently active editor state.
func get_current_state() -> VoxlyState.State:
	return current_state

## Sets the current VoxelSet and emits [signal current_voxel_set_changed].
func set_current_voxel_set(voxel_set: VoxelSet) -> void:
	if current_voxel_set != voxel_set:
		current_voxel_set = voxel_set
		current_voxel_set_changed.emit(voxel_set)

## Returns true if the given object is something this state machine can handle.
func can_handle(candidate: Object) -> bool:
	if candidate is VoxelSet:
		return true
	elif candidate is VoxelModel3D:
		return true
	return false

## Returns the state that corresponds to the given node type.
func state_for_node(node: Object) -> VoxlyState.State:
	if node is VoxelSet:
		return VoxlyState.State.VIEWING_VOXEL_SET
	elif node is VoxelModel3D:
		return VoxlyState.State.VIEWING_VOXEL_MODEL
	return VoxlyState.State.IDLE

## Attempts to transition to the given state. Returns true on success.
func transition_to(target_state: VoxlyState.State, node: Node3D = null) -> bool:
	if target_state == current_state:
		return false
	elif not _is_transition_valid(current_state, target_state):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "Invalid transition %s -> %s" % [
			VoxlyState.State.keys()[current_state],
			VoxlyState.State.keys()[target_state]
		])
		return false
	
	var from_state := current_state
	_on_exit(from_state, target_state, node)
	
	current_state = target_state
	
	var transition := VoxlyState.Transition.new(from_state, target_state, _editor_plugin, node)
	_on_enter(from_state, target_state, node)
	
	state_changed.emit(transition)
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "%s" % transition.to_string())
	return true

## Called when the editor switches to/from the 3D viewport.
func on_main_screen_changed(screen_name: String) -> void:
	_current_screen = screen_name
	if screen_name != "3D":
		# Switching away from 3D, close the editor.
		if current_state in [
			VoxlyState.State.VIEWING_VOXEL_MODEL,
			VoxlyState.State.EDITING_VOXEL_MODEL,
		]:
			transition_to(VoxlyState.State.IDLE)
	else:
		# Switching back to 3D, check if we have a stored object to restore.
		_on_return_to_3d()

## Called when a scene is closed.
func on_scene_closed(_filepath: String) -> void:
	transition_to(VoxlyState.State.IDLE)

## Handles selection changes from the Godot editor. The state machine uses this
## to determine if it needs to transition to IDLE (deselected/non-handled node)
## or to an appropriate state for the newly selected node.
##
## Behavior by current state:
##   - Any state + empty/multiple selection to IDLE (close docks, stop editing)
##   - Any state + non-handled node to IDLE (close docks, stop editing)
##   - EDITING + different VoxelNode3D to VIEWING (stop editing, show new node)
##   - VIEWING + same node to no-op
##   - VIEWING + different handled node to update docks for new node
func on_selection_changed(selected_nodes: Array[Node]) -> void:
	# Empty or multiple selection: close everything.
	if selected_nodes.size() != 1:
		transition_to(VoxlyState.State.IDLE)
		return
	
	var selected_node: Node = selected_nodes[0]
	
	# Non-handled node selected: close everything.
	if not can_handle(selected_node):
		transition_to(VoxlyState.State.IDLE)
		return
	
	var target_state := state_for_node(selected_node)
	
	# If not in 3D viewport, then we can't view/edit 3D nodes.
	if _current_screen != "3D" and target_state in [
		VoxlyState.State.VIEWING_VOXEL_MODEL,
	]:
		transition_to(VoxlyState.State.IDLE)
		return
	
	# Currently editing: transition to viewing for the new node.
	if current_state == VoxlyState.State.EDITING_VOXEL_MODEL:
		transition_to(VoxlyState.State.VIEWING_VOXEL_MODEL, selected_node)
		return
	
	# Same state, same node = nothing to do.
	if current_state == target_state:
		if _is_same_object(selected_node):
			return
		
		# Different node in the same state: emit a state change so UI
		# components can react.
		_current_focused_node = selected_node
		var transition := VoxlyState.Transition.new(current_state, target_state, _editor_plugin, selected_node)
		state_changed.emit(transition)
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "%s" % transition.to_string())
		return
	
	# Different state, valid transition.
	transition_to(target_state, selected_node)

## Called when the editing toggle changes in the VoxelModel3D editor.
func toggle_editing_mode(enabled: bool, node: Node3D) -> bool:
	if enabled:
		if current_state != VoxlyState.State.VIEWING_VOXEL_MODEL:
			return false
		return transition_to(VoxlyState.State.EDITING_VOXEL_MODEL, node)
	else:
		if current_state != VoxlyState.State.EDITING_VOXEL_MODEL:
			return false
		return transition_to(VoxlyState.State.VIEWING_VOXEL_MODEL, node)

## Returns true if the transition between the two states is allowed.
func _is_transition_valid(from: VoxlyState.State, to: VoxlyState.State) -> bool:
	if from == to:
		return true # No-op transitions are always valid.
	if not _valid_transitions.has(from):
		return false
	return to in _valid_transitions[from]

## Lifecycle hook called before leaving a state.
func _on_exit(from: VoxlyState.State, to: VoxlyState.State, node: Node3D) -> void:
	match from:
		VoxlyState.State.EDITING_VOXEL_MODEL:
			# Restore the selection so the gizmo reappears.
			_restore_selection()
		VoxlyState.State.VIEWING_VOXEL_MODEL:
			# Save selection before potentially clearing it.
			_save_current_selection()

## Lifecycle hook called after entering a state.
func _on_enter(from: VoxlyState.State, to: VoxlyState.State, node: Node3D) -> void:
	match to:
		VoxlyState.State.IDLE:
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "Entered IDLE")
			_current_focused_node = null
		
		VoxlyState.State.VIEWING_VOXEL_SET:
			if node:
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "Viewing VoxelSet: %s" % node.name)
				_select_node(node)
			else:
				VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "Viewing VoxelSet (resource)")
				# VoxelSet is a Resource, not a Node3D, selection is handled
				# by the VoxelSetController via dock/panel integration.
				_current_focused_node = node
		
		VoxlyState.State.VIEWING_VOXEL_MODEL:
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "Viewing VoxelModel3D: %s" % node.name)
			_select_node(node)
			_current_focused_node = node
		
		VoxlyState.State.EDITING_VOXEL_MODEL:
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "Editing VoxelModel3D: %s" % node.name)
			# Clear selection so the gizmo doesn't conflict with painting input.
			_clear_selection()
			_current_focused_node = node

## Snapshots the current editor selection for later restoration.
func _save_current_selection() -> void:
	var selection := EditorInterface.get_selection()
	_previous_selection = selection.get_selected_nodes()

## Restores the previously saved editor selection.
func _restore_selection() -> void:
	if _previous_selection.is_empty():
		return
	var selection := EditorInterface.get_selection()
	if selection.get_selected_nodes().is_empty():
		for node in _previous_selection:
			if is_instance_valid(node):
				EditorInterface.edit_node(node)
		_previous_selection.clear()

## Clears the current editor selection.
func _clear_selection() -> void:
	var selection := EditorInterface.get_selection()
	_previous_selection = selection.get_selected_nodes().duplicate()
	# selection.clear()

## Selects the given node in the editor.
func _select_node(node: Node3D) -> void:
	if not node:
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	EditorInterface.edit_node(node)

## Independent tracker rather than Godot's selection, because selection_changed
## fires AFTER Godot has already updated its selection to the new node.
func _is_same_object(node: Node3D) -> bool:
	if not node or not is_instance_valid(node):
		return false
	return _current_focused_node == node

## Handles returning to the 3D viewport, restoring editing state if applicable.
func _on_return_to_3d() -> void:
	# Check if we're handling an object we should restore.
	var selection := _editor_plugin.get_editor_interface().get_selection()
	var selected := selection.get_selected_nodes()
	for node in selected:
		if can_handle(node):
			var target_state := state_for_node(node)
			if target_state != current_state:
				transition_to(target_state, node)
			return
