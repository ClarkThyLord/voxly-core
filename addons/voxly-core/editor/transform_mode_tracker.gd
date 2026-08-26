@tool
class_name VoxlyTransformModeTracker
extends RefCounted
## Tracks the active 3D viewport transform tool mode (Select/Move/Rotate/Scale)
## by finding and monitoring Godot's internal toolbar buttons.
##
## The tool-mode toolbar buttons are uniquely identified by their
## shortcut resource name (e.g. "Move Mode", "Rotate Mode", "Scale Mode").
## Icon paths are optimized away and tooltip keybind tokens vary, so the
## shortcut name is the reliable fingerprint in this Godot build.

enum SpatialToolMode {
	SELECT = 0,
	TRANSFORM = 1,
	MOVE = 2,
	ROTATE = 3,
	SCALE = 4,
}

## Shortcut resource names that identify each mode's toolbar button.
## "Transform Mode" and "Select Mode" both map to the SELECT bucket.
const _SHORTCUT_NAMES := {
	SpatialToolMode.SELECT: ["Select Mode"],
	SpatialToolMode.TRANSFORM: ["Transform Mode"],
	SpatialToolMode.MOVE: ["Move Mode"],
	SpatialToolMode.ROTATE: ["Rotate Mode"],
	SpatialToolMode.SCALE: ["Scale Mode"],
}

var _buttons: Dictionary[int, Button] = {}
var _saved_mode: int = SpatialToolMode.SELECT
var _plugin: EditorPlugin = null

func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	refresh()

func refresh() -> void:
	_buttons.clear()
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker", "refresh: START")
	if _plugin == null:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker", "refresh: _plugin is null, aborting")
		return
	
	var base_control := _plugin.get_editor_interface().get_base_control()
	if base_control == null:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker", "refresh: base_control is null, aborting")
		return
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
		"refresh: base_control class=%s name=%s children=%d" % [
			base_control.get_class(), base_control.name, base_control.get_child_count()])
	
	var search_root := _find_node_by_class(base_control, "Node3DEditor")
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
		"refresh: _find_node_by_class('Node3DEditor') found=%s" % [search_root != null])
	if search_root == null:
		search_root = base_control
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker", "refresh: falling back to base_control")
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
			"refresh: search_root class=%s name=%s children=%d" % [
				search_root.get_class(), search_root.name, search_root.get_child_count()])
	
	# Buttons by shortcut resource name.
	var shortcut_found := 0
	for mode in _SHORTCUT_NAMES:
		var found := _find_button_by_shortcut(search_root, _SHORTCUT_NAMES[mode])
		if found is Button:
			_buttons[mode] = found
			shortcut_found += 1
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
			"refresh shortcut: mode=%s names=%s found=%s" % [
				SpatialToolMode.keys()[mode], _SHORTCUT_NAMES[mode], found != null])
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
		"refresh: shortcut pass found %d/%d buttons" % [shortcut_found, _SHORTCUT_NAMES.size()])

func get_current_mode() -> int:
	for mode in _buttons:
		var btn: Button = _buttons[mode]
		if is_instance_valid(btn) and btn.button_pressed:
			return mode
	return SpatialToolMode.SELECT

func snapshot_mode() -> void:
	_saved_mode = get_current_mode()
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
		"snapshot_mode: cached_buttons=%d saved=%s" % [_buttons.size(), SpatialToolMode.keys()[_saved_mode]])

## Forces Select mode on the 3D viewport toolbar.
## Returns true if the Select button was found and pressed.
## If the button can't be found, the toolbar is left as-is (rather than
## disabling every tool button and leaving the user with no active mode).
func force_select() -> bool:
	if not has_mode_button(SpatialToolMode.SELECT):
		VoxlyDebug.warn("TransformModeTracker",
			"force_select: SELECT button not found: transform tools left as-is (cached=%d)" % _buttons.size())
		return false
	_press_mode(SpatialToolMode.SELECT)
	return true

func set_buttons_enabled(enabled: bool) -> void:
	# If disabling the toolbar, make sure we actually have a usable button set;
	# otherwise, we'd leave the user with no active transform tool at all.
	if not enabled and not has_mode_button(SpatialToolMode.SELECT):
		VoxlyDebug.warn("TransformModeTracker",
			"set_buttons_enabled(false): no SELECT button available: toolbar left enabled")
		return
	for mode in _buttons:
		var btn: Button = _buttons[mode]
		if btn is Button and is_instance_valid(btn):
			btn.disabled = not enabled

## Restores the user's saved transform tool mode.
## Returns true if the saved mode's button was found and pressed.
func restore_saved() -> bool:
	if not has_mode_button(_saved_mode):
		VoxlyDebug.warn("TransformModeTracker",
			"restore_saved: no button for saved mode=%s: transform tool enabled" % [
				SpatialToolMode.keys()[_saved_mode], _buttons.size()])
		_press_mode(SpatialToolMode.TRANSFORM)
		return false
	_press_mode(_saved_mode)
	return true

func has_mode_button(mode: int) -> bool:
	var btn = _buttons.get(mode)
	return btn is Button and is_instance_valid(btn)

func _press_mode(mode: int) -> bool:
	var btn: Button = _buttons.get(mode)
	if btn is Button and is_instance_valid(btn):
		var connections: int = btn.pressed.get_connections().size()
		# Set the visual toggle state first.
		btn.button_pressed = true
		if connections > 0:
			btn.emit_signal("pressed")
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
			"pressed mode=%s (pressed_signal_connections=%d)" % [
				SpatialToolMode.keys()[mode], connections])
		return true
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
			"_press_mode MISSING BUTTON for mode=%s (cached=%d)" % [SpatialToolMode.keys()[mode], _buttons.size()])
		return false

func _debug_dump_tree(root: Node, label: String) -> void:
	if root == null:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
			"tree dump [%s]: root is null" % label)
		return
	var stats := {"nodes": 0, "buttons": 0, "tooltip_nodes": 0}
	_debug_collect(root, stats, 0, 5)
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
		"tree dump [%s]: nodes=%d buttons=%d tooltip_nodes=%d" % [
			label, stats["nodes"], stats["buttons"], stats["tooltip_nodes"]])

func _debug_collect(node: Node, stats: Dictionary, depth: int, max_depth: int) -> void:
	stats["nodes"] += 1
	var indent := "  ".repeat(depth)
	var is_button := node is Button
	var tooltip := ""
	if node is Control:
		var t: String = node.tooltip_text
		if not t.is_empty():
			tooltip = t.replace("\n", " ")
			if tooltip.length() > 60:
				tooltip = tooltip.substr(0, 60) + "..."
	if is_button:
		stats["buttons"] += 1
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
			"%sButton class=%s name=%s tooltip=[%s]" % [indent, node.get_class(), node.name, tooltip])
		_debug_button_props(indent, node as Button)
	elif not tooltip.is_empty():
		stats["tooltip_nodes"] += 1
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
			"%sTooltipNode class=%s name=%s tooltip=[%s]" % [indent, node.get_class(), node.name, tooltip])
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
			"%sclass=%s name=%s" % [indent, node.get_class(), node.name])
	if depth >= max_depth:
		return
	for child in node.get_children():
		_debug_collect(child, stats, depth + 1, max_depth)

func _debug_button_props(indent: String, btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var icon_path := ""
	if btn.icon != null:
		icon_path = btn.icon.resource_path
	var group_id := ""
	if btn.button_group != null:
		group_id = str(btn.button_group.get_instance_id())
	var shortcut_name := ""
	if btn.shortcut != null:
		shortcut_name = btn.shortcut.resource_name
	var text := btn.text.replace("\n", " ")
	if text.length() > 40:
		text = text.substr(0, 40) + "..."
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, "TransformModeTracker",
		"%s  props: pressed=%s toggle=%s flat=%s text=[%s] icon=[%s] group_id=%s shortcut=[%s]" % [
			indent, btn.button_pressed, btn.toggle_mode, btn.flat, text, icon_path, group_id, shortcut_name])

func _find_node_by_class(node: Node, target_class: String) -> Node:
	if node.get_class() == target_class:
		return node
	for child in node.get_children():
		var found := _find_node_by_class(child, target_class)
		if found != null:
			return found
	return null

## Deep-searches the tree for a Button whose shortcut resource name matches
## one of `names`. Stops early once found.
func _find_button_by_shortcut(node: Node, names: Array) -> Button:
	if node is Button:
		var btn := node as Button
		if btn.shortcut != null and btn.shortcut.resource_name in names:
			return btn
	for child in node.get_children():
		var found := _find_button_by_shortcut(child, names)
		if found is Button:
			return found
	return null

func _find_button_by_tooltip(node: Node, key: String) -> Button:
	if node is Button and node.tooltip_text and node.tooltip_text.contains(key):
		return node as Button
	for child in node.get_children():
		var found := _find_button_by_tooltip(child, key)
		if found is Button:
			return found
	return null

func _find_button_by_icon(node: Node, icon_name: String) -> Button:
	if node is Button:
		var btn := node as Button
		var icon := btn.icon
		if icon != null and not icon.resource_path.is_empty():
			if icon.resource_path.contains(icon_name):
				return btn
	for child in node.get_children():
		var found := _find_button_by_icon(child, icon_name)
		if found is Button:
			return found
	return null
