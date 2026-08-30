## Handles 3D viewport input forwarding for the Voxly editor.
## Routes input events to the appropriate editor based on the current state.
@tool
class_name VoxlyInputHandler
extends RefCounted

const _debug_context := "VoxlyInputHandler"

## Callable that handles input events during editing mode.
## Set by whoever owns the active editing tool.
## Should return true if the event was consumed.
var editing_input_handler: Callable

## The state machine that input events are routed to.
var _state_machine: VoxlyStateMachine

## Stores the state machine to route input to.
func _init(state_machine: VoxlyStateMachine) -> void:
	_state_machine = state_machine
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "Initialized")

## Routes a 3D viewport input event to the active editing tool.
##
## Returns an [enum EditorPlugin.AfterGUIInput] value:
## - [constant EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_STOP] when the event
##   was consumed by the editing tool.
## - [constant EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS] when the event
##   should continue through to Godot (camera controls, gizmos, etc.).
func handle_input(camera: Camera3D, event: InputEvent) -> int:
	match _state_machine.current_state:
		VoxlyState.State.EDITING_VOXEL_MODEL:
			# In editing mode, forward input to the active editing tool, but only
			# consume left-click and left-drag events. Middle-click, right-click,
			# and wheel events pass through for camera control.
			if event is InputEventMouse:
				if event is InputEventMouseButton:
					var mouse_button := event as InputEventMouseButton
					if mouse_button.button_index != MOUSE_BUTTON_LEFT:
						return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
				elif event is InputEventMouseMotion:
					var mouse_motion := event as InputEventMouseMotion
					if mouse_motion.button_mask & MOUSE_BUTTON_MASK_RIGHT or mouse_motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
						return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
			
			if editing_input_handler.is_valid():
				var handled := editing_input_handler.call(camera, event)
				if handled:
					return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_STOP
			return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
		
		VoxlyState.State.VIEWING_VOXEL_MODEL:
			# In viewing mode, we don't consume input, let Godot's transform
			# gizmo work.
			return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
		
		_: # IDLE, VIEWING_VOXEL_SET
			return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
