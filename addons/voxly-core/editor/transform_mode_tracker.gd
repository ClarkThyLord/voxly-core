## Tracks the active 3D viewport transform tool mode (Select/Move/Rotate/Scale)
## by finding and monitoring Godot's internal toolbar buttons.
##
## The tool-mode toolbar buttons are uniquely identified by their shortcut
## resource name (e.g. "Move Mode", "Rotate Mode", "Scale Mode"). Icon paths are
## optimized away and tooltip keybind tokens vary, so the shortcut name is the
## reliable fingerprint in this Godot build.
@tool
class_name VoxlyTransformModeTracker
extends RefCounted

## Debug context tag used when logging through [VoxlyDebug].
const _debug_context := "VoxlyTransformModeTracker"

## The 3D viewport's transform tool modes.
enum SpatialToolMode {
	SELECT = 0,
	TRANSFORM = 1,
	MOVE = 2,
	ROTATE = 3,
	SCALE = 4,
}

## Shortcut resource names that identify each mode's toolbar button.
const _SHORTCUT_NAMES := {
	SpatialToolMode.SELECT: ["Select Mode"],
	SpatialToolMode.TRANSFORM: ["Transform Mode"],
	SpatialToolMode.MOVE: ["Move Mode"],
	SpatialToolMode.ROTATE: ["Rotate Mode"],
	SpatialToolMode.SCALE: ["Scale Mode"],
}

## Found toolbar buttons, keyed by [enum SpatialToolMode].
var _buttons: Dictionary[int, Button] = {}
## The spatial tool mode to restore after editing finishes.
var _saved_mode: SpatialToolMode = SpatialToolMode.SELECT
## Reference to the editor plugin owning this tracker.
var _plugin: EditorPlugin = null

## Stores the owning editor plugin.
func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	refresh()

## Re-scans the editor tree for the transform-mode toolbar buttons.
func refresh() -> void:
	_buttons.clear()
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "refresh: START")
	if _plugin == null:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "refresh: _plugin is null, aborting")
		return
	
	var base_control := _plugin.get_editor_interface().get_base_control()
	if base_control == null:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "refresh: base_control is null, aborting")
		return
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context,
		"refresh: base_control class=%s name=%s children=%d" % [
			base_control.get_class(), base_control.name, base_control.get_child_count()])
	
	var search_root := _find_node_by_class(base_control, "Node3DEditor")
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context,
		"refresh: _find_node_by_class('Node3DEditor') found=%s" % [search_root != null])
	if search_root == null:
		search_root = base_control
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "refresh: falling back to base_control")
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context,
			"refresh: search_root class=%s name=%s children=%d" % [
				search_root.get_class(), search_root.name, search_root.get_child_count()])
	
	# Buttons are found by their shortcut resource name.
	var shortcut_found := 0
	for mode in _SHORTCUT_NAMES:
		var found := _find_button_by_shortcut(search_root, _SHORTCUT_NAMES[mode])
		if found is Button:
			_buttons[mode] = found
			shortcut_found += 1
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context,
			"refresh shortcut: mode=%s names=%s found=%s" % [
				SpatialToolMode.keys()[mode], _SHORTCUT_NAMES[mode], found != null])
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context,
		"refresh: shortcut pass found %d/%d buttons" % [shortcut_found, _SHORTCUT_NAMES.size()])

## Returns the currently pressed toolbar mode, or [constant SpatialToolMode.TRANSFORM]
## when no mode button is found or pressed.
func get_current_mode() -> SpatialToolMode:
	for mode in _buttons:
		var button: Button = _buttons[mode]
		if is_instance_valid(button) and button.button_pressed:
			return mode
	return SpatialToolMode.TRANSFORM

## Remembers the current mode so it can be restored later.
func snapshot_mode() -> void:
	_saved_mode = get_current_mode()
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context,
		"snapshot_mode: cached_buttons=%d saved=%s" % [_buttons.size(), SpatialToolMode.keys()[_saved_mode]])

## Forces Select mode on the 3D viewport toolbar.
##
## Returns true if the Select button was found and pressed. If the button can't
## be found, the toolbar is left as-is (rather than disabling every tool button
## and leaving the user with no active mode).
func force_select() -> bool:
	if not has_mode_button(SpatialToolMode.SELECT):
		VoxlyDebug.warn(_debug_context,
			"force_select: SELECT button not found: transform tools left as-is (cached=%d)" % _buttons.size())
		return false
	_press_mode(SpatialToolMode.SELECT)
	return true

## Enables or disables all cached transform toolbar buttons.
func set_buttons_enabled(enabled: bool) -> void:
	# If disabling the toolbar, make sure we actually have a usable button set;
	# otherwise, we'd leave the user with no active transform tool at all.
	if not enabled and not has_mode_button(SpatialToolMode.SELECT):
		VoxlyDebug.warn(_debug_context,
			"set_buttons_enabled(false): no SELECT button available: toolbar left enabled")
		return
	for mode in _buttons:
		var button: Button = _buttons[mode]
		if button is Button and is_instance_valid(button):
			button.disabled = not enabled

## Restores the user's saved transform tool mode.
## Returns true if the saved mode's button was found and pressed.
func restore_saved() -> bool:
	if not has_mode_button(_saved_mode):
		VoxlyDebug.warn(_debug_context,
			"restore_saved: no button for saved mode=%s: transform tool enabled" % [
				SpatialToolMode.keys()[_saved_mode], _buttons.size()])
		_press_mode(SpatialToolMode.TRANSFORM)
		return false
	_press_mode(_saved_mode)
	return true

## Returns true if the button for the given mode has been found and is valid.
func has_mode_button(mode: SpatialToolMode) -> bool:
	var button = _buttons.get(mode)
	return button is Button and is_instance_valid(button)

## Presses the toolbar button for the given mode, emitting its pressed signal so
## Godot actually switches the transform tool.
func _press_mode(mode: SpatialToolMode) -> bool:
	var button: Button = _buttons.get(mode)
	if button is Button and is_instance_valid(button):
		var connections: int = button.pressed.get_connections().size()
		# Set the visual toggle state first.
		button.button_pressed = true
		if connections > 0:
			button.emit_signal("pressed")
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context,
			"pressed mode=%s (pressed_signal_connections=%d)" % [
				SpatialToolMode.keys()[mode], connections])
		return true
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context,
			"_press_mode MISSING BUTTON for mode=%s (cached=%d)" % [SpatialToolMode.keys()[mode], _buttons.size()])
		return false

## Recursively finds the first node with the given class name.
func _find_node_by_class(node: Node, target_class: String) -> Node:
	if node.get_class() == target_class:
		return node
	for child in node.get_children():
		var found := _find_node_by_class(child, target_class)
		if found != null:
			return found
	return null

## Deep-searches the tree for a [Button] whose shortcut resource name matches
## one of [param names]. Stops early once found.
func _find_button_by_shortcut(node: Node, names: Array) -> Button:
	if node is Button:
		var button := node as Button
		if button.shortcut != null and button.shortcut.resource_name in names:
			return button
	for child in node.get_children():
		var found := _find_button_by_shortcut(child, names)
		if found is Button:
			return found
	return null
