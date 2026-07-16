@tool
extends EditorPlugin

## Plugin information.
const NAME = "Voxly-Core"
const VERSION = "1.0.0"

const DEBUG_CONTEXT := NAME

## Debug singleton instance.
var voxly_debug = null

## Editor import plugins.
var _voxel_model_3d_importer: EditorImportPlugin = null
var _voxel_set_importer: EditorImportPlugin = null

## State machine managing editor state transitions.
var _state_machine: VoxlyStateMachine = null

## Handles 3D viewport input routing.
var _input_handler: VoxlyInputHandler = null

## Manages bottom panel UI lifecycle.
var _ui_manager: VoxlyUIManager = null

## Current VoxelSet resource being edited (if any).
var _current_voxel_set: VoxelSet = null

func _enter_tree() -> void:
	# Register VoxlyDebug as a global singleton before anything uses
	add_autoload_singleton("VoxlyDebug", "res://addons/voxly-core/utils/voxly_debug.gd")
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_PLUGIN, DEBUG_CONTEXT, "%s %s is active!" % [NAME, VERSION])
	
	# Register import plugins
	_add_importers()
	
	# Initialize state management
	_state_machine = VoxlyStateMachine.new(self)
	_input_handler = VoxlyInputHandler.new(_state_machine)
	_ui_manager = VoxlyUIManager.new(self, _state_machine)
	
	# Connect to state machine changes
	_state_machine.state_changed.connect(_on_state_changed)
	
	# Connect Godot editor signals
	var editor_interface := get_editor_interface()
	if editor_interface:
		var editor_selection := editor_interface.get_selection()
		editor_selection.connect("selection_changed", _on_selection_changed)
	connect("scene_closed", _on_scene_closed)
	connect("main_screen_changed", _on_main_screen_changed)


func _exit_tree() -> void:
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_PLUGIN, DEBUG_CONTEXT, "%s %s is inactive!" % [NAME, VERSION])
	
	remove_autoload_singleton("VoxlyDebug")
	
	# Remove import plugins
	_remove_importers()
	
	# Disconnect signals
	var editor_interface := get_editor_interface()
	if editor_interface:
		var editor_selection := editor_interface.get_selection()
		if editor_selection and editor_selection.is_connected("selection_changed", _on_selection_changed):
			editor_selection.disconnect("selection_changed", _on_selection_changed)
	if is_connected("scene_closed", _on_scene_closed):
		disconnect("scene_closed", _on_scene_closed)
	if is_connected("main_screen_changed", _on_main_screen_changed):
		disconnect("main_screen_changed", _on_main_screen_changed)
	if _state_machine and _state_machine.state_changed.is_connected(_on_state_changed):
		_state_machine.state_changed.disconnect(_on_state_changed)
	
	# Clean up state
	if _ui_manager:
		_ui_manager.hide_all_docks()
	
	_state_machine = null
	_input_handler = null
	_ui_manager = null
	
	# Unregister debug singleton
	if voxly_debug:
		Engine.unregister_singleton("VoxlyDebug")
		voxly_debug = null

func _add_importers() -> void:
	# Register Voxly Model Importer (.vox, .png, .jpg → PackedScene)
	_voxel_model_3d_importer = preload("res://addons/voxly-core/importers/voxel_model_3d_import.gd").new()
	add_import_plugin(_voxel_model_3d_importer)
	
	# Register Voxly Set Importer (.gpl, .aco, .json, .txt, .pal → VoxelSet resource)
	_voxel_set_importer = preload("res://addons/voxly-core/importers/voxel_set_import.gd").new()
	add_import_plugin(_voxel_set_importer)


func _remove_importers() -> void:
	if _voxel_model_3d_importer:
		remove_import_plugin(_voxel_model_3d_importer)
		_voxel_model_3d_importer = null
	
	if _voxel_set_importer:
		remove_import_plugin(_voxel_set_importer)
		_voxel_set_importer = null

func _on_state_changed(transition: VoxlyState.Transition) -> void:
	match transition.to_state:
		VoxlyState.State.VIEWING_VOXEL_SET:
			pass
		
		VoxlyState.State.VIEWING_VOXEL_MODEL:
			pass
		
		VoxlyState.State.EDITING_VOXEL_MODEL:
			pass
		
		VoxlyState.State.IDLE:
			pass

## Called by Godot to determine if this plugin can handle the given object.
func _handles(object: Object) -> bool:
	return _state_machine and _state_machine.can_handle(object)

## Called by Godot to begin editing the given object.
func _edit(object: Object) -> void:
	if not _state_machine:
		return
	
	# Filter only node types we handle
	if object is VoxelModel3D:
		_state_machine.on_selection_changed([object])
	elif object is VoxelSet:
		# VoxelSet doesn't map to a selected node, store and transition
		_current_voxel_set = object
		_state_machine.set_current_voxel_set(object)
		_state_machine.transition_to(VoxlyState.State.VIEWING_VOXEL_SET, null)

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	return _input_handler and _input_handler.handle_input(camera, event)

func _on_selection_changed() -> void:
	if not _state_machine:
		return
	var selection := get_editor_interface().get_selection().get_selected_nodes()
	_state_machine.on_selection_changed(selection)

func _on_main_screen_changed(screen_name: String) -> void:
	if _state_machine:
		_state_machine.on_main_screen_changed(screen_name)

func _on_scene_closed(filepath: String) -> void:
	if _state_machine:
		_state_machine.on_scene_closed(filepath)
