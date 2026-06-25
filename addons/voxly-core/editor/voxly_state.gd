@tool
class_name VoxlyState
extends RefCounted
## Defines the editor state machine states and transition data for the Voxly editor.

## All possible states the editor can be in.
enum State {
	IDLE, ## Nothing selected, no editors open
	VIEWING_VOXEL_SET, ## A VoxelSet is selected and its inspector/panel is visible
	VIEWING_VOXEL_MODEL, ## A VoxelModel3D is selected, panel is visible, gizmo active
	EDITING_VOXEL_MODEL, ## Actively editing a VoxelModel3D (painting), gizmo suppressed
}

## Describes a state transition. Passed with the state_changed signal so listeners
## can react to what changed.
class Transition:
	var from_state: State
	var to_state: State
	var editor_plugin: EditorPlugin
	var selected_node: Node3D # The node that was selected (if any)
	
	func _init(
		p_from: State,
		p_to: State,
		p_plugin: EditorPlugin,
		p_node: Node3D = null
	) -> void:
		from_state = p_from
		to_state = p_to
		editor_plugin = p_plugin
		selected_node = p_node
	
	func _to_string():
		var from_name = State.keys()[from_state]
		var to_name = State.keys()[to_state]
		var node_name := selected_node.name if selected_node else "null"
		return "[%s] %s -> %s" % [node_name, from_name, to_name]
