@tool
class_name VoxlyRegistry
extends RefCounted
## Registry for dynamically loading brushes, tools, and edit operations.
## Stores class references and creates instances on demand.
## Attached to a VoxlyEditor instance.

## Registered brush classes
var _brush_classes: Dictionary[String, GDScript] = {}

## Registered tool classes
var _tool_classes: Dictionary[String, GDScript] = {}

## Registered edit operation classes
var _operation_classes: Dictionary[String, GDScript] = {}


func _init() -> void:
	register_brush("point", preload("res://addons/voxly-core/voxly_editor/brushes/voxly_brush_point.gd"))
	register_brush("box", preload("res://addons/voxly-core/voxly_editor/brushes/voxly_brush_box.gd"))
	register_brush("extrude", preload("res://addons/voxly-core/voxly_editor/brushes/voxly_brush_extrude.gd"))
	register_brush("line", preload("res://addons/voxly-core/voxly_editor/brushes/voxly_brush_line.gd"))
	register_brush("sphere", preload("res://addons/voxly-core/voxly_editor/brushes/voxly_brush_sphere.gd"))
	register_brush("cube", preload("res://addons/voxly-core/voxly_editor/brushes/voxly_brush_cube.gd"))
	register_brush("cylinder", preload("res://addons/voxly-core/voxly_editor/brushes/voxly_brush_cylinder.gd"))
	register_brush("pattern", preload("res://addons/voxly-core/voxly_editor/brushes/voxly_brush_pattern.gd"))
	register_brush("fill", preload("res://addons/voxly-core/voxly_editor/brushes/voxly_brush_fill.gd"))
	
	register_tool("add", preload("res://addons/voxly-core/voxly_editor/tools/voxly_tool_add.gd"))
	register_tool("sub", preload("res://addons/voxly-core/voxly_editor/tools/voxly_tool_sub.gd"))
	register_tool("swap", preload("res://addons/voxly-core/voxly_editor/tools/voxly_tool_swap.gd"))
	register_tool("pick", preload("res://addons/voxly-core/voxly_editor/tools/voxly_tool_pick.gd"))
	register_tool("select", preload("res://addons/voxly-core/voxly_editor/tools/voxly_tool_select.gd"))
	
	register_operation("erase_voxels", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_erase.gd"))
	register_operation("select_all", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_select_all.gd"))
	register_operation("deselect_all", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_deselect_all.gd"))
	register_operation("invert_selection", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_invert_selection.gd"))
	register_operation("select_by_palette", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_select_by_palette.gd"))
	register_operation("grow_selection", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_grow_selection.gd"))
	register_operation("shrink_selection", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_shrink_selection.gd"))
	register_operation("copy_voxels", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_copy.gd"))
	register_operation("cut_voxels", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_cut.gd"))
	register_operation("paste_voxels", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_paste.gd"))
	register_operation("translate_voxels", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_translate.gd"))
	register_operation("align_voxels", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_align.gd"))
	register_operation("mirror_voxels", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_mirror.gd"))
	register_operation("rotate_voxels", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_rotate.gd"))
	register_operation("flip_voxels", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_flip.gd"))
	register_operation("resize_to_content", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_resize_to_content.gd"))
	register_operation("remove_floating", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_remove_floating.gd"))
	register_operation("extract_selection", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_extract_selection.gd"))
	register_operation("split_components", preload("res://addons/voxly-core/voxly_editor/operations/voxly_op_split_components.gd"))

## Registers a brush class by name. Overwrites existing entry.
## The script must extend VoxlyBrush.
func register_brush(name: String, script: GDScript) -> void:
	_brush_classes[name.to_lower()] = script

## Registers a tool class by name. Overwrites existing entry.
## The script must extend VoxlyTool.
func register_tool(name: String, script: GDScript) -> void:
	_tool_classes[name.to_lower()] = script

## Registers an edit operation class by name. Overwrites existing entry.
## The script must extend VoxlyEditOperation.
func register_operation(name: String, script: GDScript) -> void:
	_operation_classes[name.to_lower()] = script

## Returns true if a brush is registered with the given name.
func has_brush(name: String) -> bool:
	return _brush_classes.has(name.to_lower())

## Returns true if a tool is registered with the given name.
func has_tool(name: String) -> bool:
	return _tool_classes.has(name.to_lower())

## Returns true if an operation is registered with the given name.
func has_operation(name: String) -> bool:
	return _operation_classes.has(name.to_lower())

## Returns all registered brush names.
func get_brush_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for key in _brush_classes:
		names.append(key)
	return names

## Returns all registered tool names.
func get_tool_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for key in _tool_classes:
		names.append(key)
	return names

## Returns all registered operation names.
func get_operation_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for key in _operation_classes:
		names.append(key)
	return names

## Returns operation ids grouped by category, in registration order.
func get_operations_by_category() -> Dictionary:
	var result: Dictionary = {}
	for op_name in get_operation_names():
		var op := create_operation(op_name)
		if op == null:
			continue
		if not result.has(op.category):
			result[op.category] = PackedStringArray()
		var category_ops: PackedStringArray = result[op.category]
		category_ops.append(op_name)
		result[op.category] = category_ops
	return result

## Creates a brush instance by name, applying any saved option values from
## VoxlyConfig so user settings survive brush switches and editor sessions.
## Returns null if not registered.
func create_brush(name: String) -> VoxlyBrush:
	var script: GDScript = _brush_classes.get(name.to_lower())
	if not script:
		push_error("VoxlyRegistry: No brush registered as '%s'" % name)
		return null
	var instance: VoxlyBrush = script.new()
	if not instance:
		push_error("VoxlyRegistry: Failed to instantiate brush '%s'" % name)
		return null
	_apply_saved_options(instance, name.to_lower(), "brushes")
	return instance

## Creates a tool instance by name, applying any saved option values from
## VoxlyConfig so user settings survive tool switches and editor sessions.
## Returns null if not registered.
func create_tool(name: String) -> VoxlyTool:
	var script: GDScript = _tool_classes.get(name.to_lower())
	if not script:
		push_error("VoxlyRegistry: No tool registered as '%s'" % name)
		return null
	var instance: VoxlyTool = script.new()
	if not instance:
		push_error("VoxlyRegistry: Failed to instantiate tool '%s'" % name)
		return null
	_apply_saved_options(instance, name.to_lower(), "tools")
	return instance

## Applies saved option values from VoxlyConfig's `brushes`/`tools` sections
## onto a freshly created instance. Only properties the instance actually has
## are written, so unknown/removed options are ignored safely.
func _apply_saved_options(instance, name: String, section: String) -> void:
	if VoxlyConfig == null:
		return
	
	var section_dict: Dictionary = VoxlyConfig.get_section("voxel_node_3d_editor", section)
	var saved: Dictionary = section_dict.get(name, {})
	if not saved is Dictionary:
		return
	for property in saved:
		if property in instance:
			instance.set(property, saved[property])

## Creates an edit operation instance by name. Returns null if not registered.
func create_operation(name: String) -> VoxlyEditOperation:
	var script: GDScript = _operation_classes.get(name.to_lower())
	if not script:
		push_error("VoxlyRegistry: No operation registered as '%s'" % name)
		return null
	var instance: VoxlyEditOperation = script.new()
	if not instance:
		push_error("VoxlyRegistry: Failed to instantiate operation '%s'" % name)
	return instance

## Registers a list of brush scripts. Each script must have a static
## or class-level `BRUSH_NAME` constant, or we derive from the filename.
func register_brushes(scripts: Array[GDScript]) -> void:
	for script in scripts:
		var name := _derive_name(script)
		if not name.is_empty():
			register_brush(name, script)

## Registers a list of tool scripts.
func register_tools(scripts: Array[GDScript]) -> void:
	for script in scripts:
		var name := _derive_name(script)
		if not name.is_empty():
			register_tool(name, script)

## Registers a list of operation scripts.
func register_operations(scripts: Array[GDScript]) -> void:
	for script in scripts:
		var name := _derive_name(script)
		if not name.is_empty():
			register_operation(name, script)


func _derive_name(script: GDScript) -> String:
	if script.get("name"):
		return script.get("name")
	var path := script.resource_path.get_file().get_basename()
	for prefix in ["voxly_brush_", "voxly_tool_", "voxly_op_", "voxly_"]:
		if path.begins_with(prefix):
			return path.trim_prefix(prefix)
	return path
