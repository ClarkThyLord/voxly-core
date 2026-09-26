## Contextual toolbar menus for the Voxly-Core editor plugin.
##
## Builds one [MenuButton] per registered menu and shows them in the 3D editor's
## toolbar ([constant EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU]) based on the
## object currently being edited.
##
## Menus are data-driven so extending the toolbar is a single registration:
## [codeblock]
## toolbar.register_menu({
##     "id": "my_menu",
##     "label": "My Menu",
##     "is_available": func(context): return context["node"] != null,
##     "get_items": func(context): return [
##         { "label": "Do Thing", "callback": some_callable },
##     ],
## })
## [/codeblock]
##
## Each item is [code]{ label: String, callback: Callable, enabled: bool }[/code];
## optional keys are [code]separator: bool[/code] and [code]tooltip: String[/code].
##
## The context passed to [code]is_available[/code] / [code]get_items[/code] is:
## [code]object[/code] (the edited object), [code]node[/code] (the [VoxelNode3D]
## when the context is a node), and [code]voxel_set[/code] (the edited set, or
## the node's set).
@tool
class_name VoxlyToolbar
extends RefCounted

## Debug context tag used when logging through [VoxlyDebug].
const _debug_context := "VoxlyToolbar"

## The editor plugin owning this toolbar.
var _plugin: EditorPlugin = null

## The state machine driving the editor context.
var _state_machine: VoxlyStateMachine = null

## The UI manager used to show docks.
var _ui_manager: VoxlyUIManager = null

## Toolbar container the menu buttons are added to (3D editor toolbar).
var _container = EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU

## Registered menu specs, keyed by id: { label, is_available, get_items }.
var _menus: Dictionary[String, Dictionary] = {}

## Menu buttons, keyed by menu id.
var _buttons: Dictionary[String, MenuButton] = {}

## Items currently shown per menu id; the array index is the popup item id.
var _items: Dictionary[String, Array] = {}

## The object currently being edited by the plugin, or null.
var _current_object: Object = null

## Whether the editor asked this plugin's UI to be visible.
var _visible: bool = false

## Node whose [signal VoxelNode3D.voxel_set_changed] is currently connected.
var _connected_node: VoxelNode3D = null

## Stores the collaborators and registers the built-in menus.
func _init(plugin: EditorPlugin, state_machine: VoxlyStateMachine, ui_manager: VoxlyUIManager) -> void:
	_plugin = plugin
	_state_machine = state_machine
	_ui_manager = ui_manager
	_register_default_menus()
	if _state_machine:
		_state_machine.state_changed.connect(_on_state_changed)

## Registers a toolbar menu and creates its [MenuButton].
##
## [param spec] keys: [code]id[/code], [code]label[/code], [code]is_available[/code]
## (Callable taking the context, returning a bool), and [code]get_items[/code]
## (Callable taking the context, returning the item array).
## Returns the created button, or null when the id is missing or duplicated.
func register_menu(spec: Dictionary) -> MenuButton:
	var menu_id: String = spec.get("id", "")
	if menu_id.is_empty() or _menus.has(menu_id):
		push_error("VoxlyToolbar: invalid or duplicate menu id '%s'" % menu_id)
		return null
	
	var button := MenuButton.new()
	button.name = "Voxly%sMenu" % menu_id.to_pascal_case()
	button.text = spec.get("label", menu_id.capitalize())
	button.get_popup().id_pressed.connect(_on_menu_item_pressed.bind(menu_id))
	if _plugin:
		_plugin.add_control_to_container(_container, button)
	# Custom container controls must be hidden manually.
	button.hide()
	
	_menus[menu_id] = spec
	_buttons[menu_id] = button
	_items[menu_id] = []
	return button

## Sets the object currently being edited and refreshes the toolbar.
func set_current_object(object: Object) -> void:
	if _current_object == object:
		_refresh()
		return
	_disconnect_current_node()
	_current_object = object
	_connect_current_node()
	_refresh()

## Sets whether the editor requested this plugin's toolbar to be visible.
func set_visible(visible: bool) -> void:
	_visible = visible
	_refresh()

## Removes the toolbar buttons from the editor and frees them.
func dispose() -> void:
	_disconnect_current_node()
	if _state_machine and _state_machine.state_changed.is_connected(_on_state_changed):
		_state_machine.state_changed.disconnect(_on_state_changed)
	for menu_id in _buttons:
		var button: MenuButton = _buttons[menu_id]
		if is_instance_valid(button):
			if _plugin:
				_plugin.remove_control_from_container(_container, button)
			button.queue_free()
	_buttons.clear()
	_menus.clear()
	_items.clear()
	_current_object = null
	_visible = false

## Registers the built-in toolbar menus.
func _register_default_menus() -> void:
	register_menu({
		"id": "voxel_node",
		"label": "Voxel Node",
		"is_available": _is_node_context,
		"get_items": _get_node_items,
	})
	register_menu({
		"id": "voxel_set",
		"label": "Voxel Set",
		"is_available": _is_voxel_set_context,
		"get_items": _get_voxel_set_items,
	})

## Recomputes visibility and items for every registered menu.
func _refresh() -> void:
	var context := _build_context()
	for menu_id in _menus:
		var button: MenuButton = _buttons.get(menu_id)
		if not is_instance_valid(button):
			continue
		var spec: Dictionary = _menus[menu_id]
		var is_available: Callable = spec.get("is_available", Callable())
		var available := _visible and is_available.is_valid() and bool(is_available.call(context))
		button.visible = available
		if available:
			_rebuild_items(menu_id, button, spec, context)

## Rebuilds a menu's popup from its spec, storing the items for dispatch.
func _rebuild_items(menu_id: String, button: MenuButton, spec: Dictionary, context: Dictionary) -> void:
	var get_items: Callable = spec.get("get_items", Callable())
	var items: Array = get_items.call(context) if get_items.is_valid() else []
	_items[menu_id] = items
	
	var popup := button.get_popup()
	popup.clear()
	for i in range(items.size()):
		var item: Dictionary = items[i]
		if item.get("separator", false):
			popup.add_separator()
			continue
		popup.add_item(item.get("label", ""), i)
		var index := popup.item_count - 1
		popup.set_item_disabled(index, not bool(item.get("enabled", true)))
		var tooltip: String = item.get("tooltip", "")
		if not tooltip.is_empty():
			popup.set_item_tooltip(index, tooltip)

## Returns the edit context shared with menu specs and their items.
func _build_context() -> Dictionary:
	var node: VoxelNode3D = null
	var voxel_set: VoxelSet = null
	if _current_object is VoxelNode3D:
		node = _current_object
		if is_instance_valid(node):
			voxel_set = node.voxel_set
	elif _current_object is VoxelSet:
		voxel_set = _current_object
	return {
		"object": _current_object,
		"node": node,
		"voxel_set": voxel_set,
	}

## Returns true when the edited object is a [VoxelNode3D].
func _is_node_context(context: Dictionary) -> bool:
	return context.get("node") != null

## Returns true when a [VoxelSet] is being edited, directly or through a node.
func _is_voxel_set_context(context: Dictionary) -> bool:
	return context.get("voxel_set") != null

## Returns the [VoxelNode3D] menu items.
func _get_node_items(context: Dictionary) -> Array:
	var node: VoxelNode3D = context.get("node")
	return [
		{
			"label": "Update",
			"callback": _update_node.bind(node),
			"enabled": is_instance_valid(node),
			"tooltip": "Rebuild the node's mesh and collision.",
		},
		{
			"label": "Show Editor",
			"callback": _show_node_editor.bind(node),
			"enabled": is_instance_valid(node),
			"tooltip": "Open and focus the VoxelNode3D editor dock.",
		},
	]

## Returns the [VoxelSet] menu items.
func _get_voxel_set_items(context: Dictionary) -> Array:
	var voxel_set: VoxelSet = context.get("voxel_set")
	var node: VoxelNode3D = context.get("node")
	return [
		{
			"label": "Emit Update",
			"callback": _emit_voxel_set_update.bind(voxel_set),
			"enabled": is_instance_valid(voxel_set),
			"tooltip": "Notify listeners so dependent nodes rebuild and editors refresh.",
		},
		{
			"label": "Show Editor",
			"callback": _show_voxel_set_editor.bind(node),
			"enabled": _ui_manager != null,
			"tooltip": "Open and focus the VoxelSet editor dock.",
		},
	]

## Dispatches a pressed item to its callback.
func _on_menu_item_pressed(item_id: int, menu_id: String) -> void:
	var items: Array = _items.get(menu_id, [])
	if item_id < 0 or item_id >= items.size():
		return
	var callback: Callable = items[item_id].get("callback", Callable())
	if callback.is_valid():
		callback.call()

## Rebuilds the node's mesh (and collision) on demand.
func _update_node(node: VoxelNode3D) -> void:
	if is_instance_valid(node):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context,
			"Update requested for node: %s" % node.name)
		node.update()

## Opens and focuses the [VoxelNode3D] editor dock.
func _show_node_editor(node: VoxelNode3D) -> void:
	if is_instance_valid(node) and _ui_manager:
		_ui_manager.focus_dock(VoxlyUIManager.DockType.VOXEL_OBJECT_EDITOR, node)

## Notifies the [VoxelSet] so listeners rebuild and editors refresh.
func _emit_voxel_set_update(voxel_set: VoxelSet) -> void:
	if is_instance_valid(voxel_set):
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, _debug_context, "Emit update requested for VoxelSet")
		voxel_set.notify_changed()

## Opens and focuses the [VoxelSet] editor dock.
func _show_voxel_set_editor(node: VoxelNode3D) -> void:
	if _ui_manager:
		_ui_manager.focus_dock(VoxlyUIManager.DockType.VOXEL_SET_EDITOR, node)

## Refreshes the toolbar whenever the editor context changes.
func _on_state_changed(_transition: VoxlyState.Transition) -> void:
	_refresh()

## Connects the current node's voxel_set_changed signal.
func _connect_current_node() -> void:
	if _current_object is VoxelNode3D and is_instance_valid(_current_object):
		_connected_node = _current_object
		if not _connected_node.voxel_set_changed.is_connected(_on_node_voxel_set_changed):
			_connected_node.voxel_set_changed.connect(_on_node_voxel_set_changed)

## Disconnects the previously tracked node's voxel_set_changed signal.
func _disconnect_current_node() -> void:
	if is_instance_valid(_connected_node) \
			and _connected_node.voxel_set_changed.is_connected(_on_node_voxel_set_changed):
		_connected_node.voxel_set_changed.disconnect(_on_node_voxel_set_changed)
	_connected_node = null

## Refreshes the toolbar when the tracked node's VoxelSet changes.
func _on_node_voxel_set_changed() -> void:
	_refresh()
