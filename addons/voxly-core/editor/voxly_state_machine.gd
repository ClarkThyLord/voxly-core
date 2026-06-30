@tool
class_name VoxlyStateMachine
extends RefCounted
## State machine for the Voxly editor. Manages transitions between editor states
## and provides lifecycle hooks for each state transition.

signal state_changed(transition: VoxlyState.Transition)

signal current_voxel_set_changed(voxel_set: VoxelSet)

## Valid state transitions table.
## State IDs: 0=IDLE, 1=VIEWING_VOXEL_SET, 2=VIEWING_VOXEL_MODEL, 3=EDITING_VOXEL_MODEL
const _valid_transitions: Dictionary = {
	# From IDLE: can go to any viewing state
	VoxlyState.State.IDLE: [
		VoxlyState.State.VIEWING_VOXEL_SET,
		VoxlyState.State.VIEWING_VOXEL_MODEL,
	],
	# From VIEWING_VOXEL_SET: can go to IDLE, or directly to VIEWING_VOXEL_MODEL
	VoxlyState.State.VIEWING_VOXEL_SET: [
		VoxlyState.State.IDLE,
		VoxlyState.State.VIEWING_VOXEL_MODEL,
	],
	# From VIEWING_VOXEL_MODEL: can go to IDLE, EDITING_VOXEL_MODEL, or VIEWING_VOXEL_SET
	VoxlyState.State.VIEWING_VOXEL_MODEL: [
		VoxlyState.State.IDLE,
		VoxlyState.State.EDITING_VOXEL_MODEL,
		VoxlyState.State.VIEWING_VOXEL_SET,
	],
	# From EDITING_VOXEL_MODEL: can only go back to VIEWING_VOXEL_MODEL or IDLE
	VoxlyState.State.EDITING_VOXEL_MODEL: [
		VoxlyState.State.VIEWING_VOXEL_MODEL,
		VoxlyState.State.IDLE,
	],
}

## The current editor state.
var current_state: VoxlyState.State = VoxlyState.State.IDLE:
	get = get_current_state

## The VoxelSet resource currently being edited (if any).
## Set by the plugin when a VoxelSet is selected for editing.
var current_voxel_set: VoxelSet = null

## Sets the current VoxelSet and emits the signal.
func set_current_voxel_set(vs: VoxelSet) -> void:
	if current_voxel_set != vs:
		current_voxel_set = vs
		current_voxel_set_changed.emit(vs)

var _editor_plugin: EditorPlugin
var _current_screen: String = "3D" # Track current main screen
var _previous_selection: Array[Node] = [] # Saved selection for edit-mode restore

func _init(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin
	print("VoxlyStateMachine: Initialized (IDLE)")

func get_current_state() -> VoxlyState.State:
	return current_state

## Returns true if the given node type is something this state machine can handle.
func can_handle(object: Object) -> bool:
	if object is VoxelSet:
		return true
	elif object is VoxelModel3D:
		return true
	return false

## Returns the state that corresponds to the given node type.
func state_for_node(node) -> VoxlyState.State:
	if node is VoxelSet:
		return VoxlyState.State.VIEWING_VOXEL_SET
	elif node is VoxelModel3D:
		return VoxlyState.State.VIEWING_VOXEL_MODEL
	return VoxlyState.State.IDLE

## Attempts to transition to the given state. Returns true on success.
func transition_to(to: VoxlyState.State, node: Node3D = null) -> bool:
	if to == current_state:
		return false
	elif not _is_transition_valid(current_state, to):
		print("VoxlyStateMachine: Invalid transition %s -> %s" % [
			VoxlyState.State.keys()[current_state],
			VoxlyState.State.keys()[to]
		])
		return false
	
	var from := current_state
	_on_exit(from, to, node)
	
	current_state = to
	
	var transition := VoxlyState.Transition.new(from, to, _editor_plugin, node)
	_on_enter(from, to, node)
	
	state_changed.emit(transition)
	print("VoxlyStateMachine: %s" % transition.to_string())
	return true

## Called when the editor switches to/from the 3D viewport.
func on_main_screen_changed(screen_name: String) -> void:
	_current_screen = screen_name
	if screen_name != "3D":
		# Switching away from 3D — close editor
		if current_state in [
			VoxlyState.State.VIEWING_VOXEL_MODEL,
			VoxlyState.State.EDITING_VOXEL_MODEL,
		]:
			transition_to(VoxlyState.State.IDLE)
	else:
		# Switching back to 3D — check if we have a stored object to restore
		_on_return_to_3d()

## Called when a scene is closed.
func on_scene_closed(_filepath: String) -> void:
	transition_to(VoxlyState.State.IDLE)

## Handles selection changes from the Godot editor. The state machine uses this
## to determine if it needs to transition to IDLE (deselected) or to a viewing
## state (new node selected).
func on_selection_changed(selected_nodes: Array[Node]) -> void:
	if selected_nodes.size() != 1:
		transition_to(VoxlyState.State.IDLE)
		return
	
	var node : Node = selected_nodes[0]
	if not can_handle(node):
		node = null
	
	if node == null:
		# Don't interrupt active editing — we may have cleared selection ourselves
		if current_state != VoxlyState.State.EDITING_VOXEL_MODEL:
			transition_to(VoxlyState.State.IDLE)
		return
	
	var target_state := state_for_node(node)
	
	# Don't enter 3D-specific states when not in the 3D viewport
	if _current_screen != "3D" and target_state in [
		VoxlyState.State.VIEWING_VOXEL_MODEL,
	]:
		transition_to(VoxlyState.State.IDLE)
		return
	
	# Don't interrupt active editing
	if current_state == VoxlyState.State.EDITING_VOXEL_MODEL and target_state == VoxlyState.State.VIEWING_VOXEL_MODEL:
		# If the same object and we're editing, stay in editing mode
		if _is_same_object(node):
			return
	
	transition_to(target_state, node)


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

func _is_transition_valid(from: VoxlyState.State, to: VoxlyState.State) -> bool:
	if from == to:
		return true # No-op transitions are always valid
	if not _valid_transitions.has(from):
		return false
	return to in _valid_transitions[from]

func _on_exit(from: VoxlyState.State, to: VoxlyState.State, node: Node3D) -> void:
	match from:
		VoxlyState.State.EDITING_VOXEL_MODEL:
			# Restore the selection so the gizmo reappears
			_restore_selection()
		VoxlyState.State.VIEWING_VOXEL_MODEL:
			# Save selection before potentially clearing it
			_save_current_selection()

func _on_enter(from: VoxlyState.State, to: VoxlyState.State, node: Node3D) -> void:
	match to:
		VoxlyState.State.IDLE:
			print("VoxlyStateMachine: Entered IDLE")
		
		VoxlyState.State.VIEWING_VOXEL_SET:
			if node:
				print("VoxlyStateMachine: Viewing VoxelSet: %s" % node.name)
				_select_node(node)
			else:
				print("VoxlyStateMachine: Viewing VoxelSet (resource)")
				# VoxelSet is a Resource, not a Node3D — selection is handled
				# by the VoxelSetController via dock/panel integration.
		
		VoxlyState.State.VIEWING_VOXEL_MODEL:
			print("VoxlyStateMachine: Viewing VoxelModel3D: %s" % node.name)
			_select_node(node)
		
		VoxlyState.State.EDITING_VOXEL_MODEL:
			print("VoxlyStateMachine: Editing VoxelModel3D: %s" % node.name)
			# Clear selection so gizmo doesn't conflict with painting input
			_clear_selection()

func _save_current_selection() -> void:
	var sel := _editor_plugin.get_editor_interface().get_selection()
	_previous_selection = sel.get_selected_nodes()

func _restore_selection() -> void:
	if _previous_selection.is_empty():
		return
	var sel := _editor_plugin.get_editor_interface().get_selection()
	sel.clear()
	for node in _previous_selection:
		if is_instance_valid(node):
			sel.add_node(node)
	_previous_selection.clear()

func _clear_selection() -> void:
	_previous_selection = _editor_plugin.get_editor_interface().get_selection().get_selected_nodes()
	_editor_plugin.get_editor_interface().get_selection().clear()

func _select_node(node: Node3D) -> void:
	if not node:
		return
	var sel := _editor_plugin.get_editor_interface().get_selection()
	sel.clear()
	sel.add_node(node)

func _is_same_object(node: Node3D) -> bool:
	if not node:
		return false
	var sel := _editor_plugin.get_editor_interface().get_selection()
	var selected := sel.get_selected_nodes()
	return selected.size() == 1 and selected[0] == node

func _on_return_to_3d() -> void:
	# Check if we're handling an object we should restore
	var sel := _editor_plugin.get_editor_interface().get_selection()
	var selected := sel.get_selected_nodes()
	for node in selected:
		if can_handle(node):
			var target_state := state_for_node(node)
			if target_state != current_state:
				transition_to(target_state, node)
			return
