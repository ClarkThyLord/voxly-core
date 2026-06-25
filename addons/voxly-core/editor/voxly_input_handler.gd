@tool
class_name VoxlyInputHandler
extends RefCounted
## Handles 3D viewport input forwarding for the Voxly editor.
## Routes input events to the appropriate editor based on the current state.

## Callable that handles input events during editing mode.
## Set by whoever owns the active editing tool.
## Should return true if the event was consumed.
var editing_input_handler: Callable

var _state_machine: VoxlyStateMachine

func _init(state_machine: VoxlyStateMachine) -> void:
	_state_machine = state_machine
	print("VoxlyInputHandler: Initialized")

## Returns true if the input was consumed, false to let Godot handle it.
func handle_input(camera: Camera3D, event: InputEvent) -> int:
	match _state_machine.current_state:
		VoxlyState.State.EDITING_VOXEL_MODEL:
			# In editing mode, forward input to the active editing tool.
			# Only consume left-click and left-drag events.
			# Middle-click, right-click, and wheel events pass through for camera control.
			if event is InputEventMouse:
				var mouse_event := event as InputEventMouse
				if event is InputEventMouseButton:
					var btn := event as InputEventMouseButton
					if btn.button_index != MOUSE_BUTTON_LEFT:
						return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
				elif event is InputEventMouseMotion:
					var motion := event as InputEventMouseMotion
					if motion.button_mask & MOUSE_BUTTON_MASK_RIGHT or motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
						return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
			
			if editing_input_handler.is_valid():
				var handled := editing_input_handler.call(camera, event)
				if handled:
					return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_STOP
			return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
		
		VoxlyState.State.VIEWING_VOXEL_MODEL:
			# In viewing mode, we don't consume input — let Godot's transform gizmo work
			return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
		
		_: # IDLE, VIEWING_VOXEL_SET
			return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
