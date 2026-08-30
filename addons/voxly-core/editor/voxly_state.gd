## Defines the states and transition data used by the Voxly editor's state machine.
@tool
class_name VoxlyState
extends RefCounted

## All possible states the editor can be in.
enum State {
	## Nothing selected, no editors open.
	IDLE,
	## A VoxelSet is selected and its inspector/panel is visible.
	VIEWING_VOXEL_SET,
	## A VoxelModel3D is selected, panel is visible, gizmo active.
	VIEWING_VOXEL_MODEL,
	## Actively editing a VoxelModel3D gizmo suppressed.
	EDITING_VOXEL_MODEL,
}

## Describes a state transition. Passed with the
## [signal VoxlyStateMachine.state_changed] signal so listeners can react to
## what changed.
class Transition:
	## The state the editor is leaving.
	var from_state: State
	## The state the editor is entering.
	var to_state: State
	## The editor plugin driving the state machine.
	var editor_plugin: EditorPlugin
	## The node that was selected (may be null for resource-only transitions).
	var selected_node: Node3D
	
	## Creates a transition record with the given states, plugin, and optional selected node.
	func _init(
			from_state: State,
			to_state: State,
			plugin: EditorPlugin,
			selected_node: Node3D = null
		) -> void:
		self.from_state = from_state
		self.to_state = to_state
		editor_plugin = plugin
		self.selected_node = selected_node
	
	## Returns a human-readable description of the transition.
	func _to_string() -> String:
		var from_name: String = State.keys()[from_state]
		var to_name: String = State.keys()[to_state]
		var node_name: String = selected_node.name if selected_node else "null"
		return "[%s] %s -> %s" % [node_name, from_name, to_name]
