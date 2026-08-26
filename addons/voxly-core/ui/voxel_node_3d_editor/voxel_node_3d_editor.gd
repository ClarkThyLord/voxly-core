@tool
extends BoxContainer

## Emitted when the editing toggle changes.
signal editing_toggled(enabled: bool)

## Emitted when mirror settings change.
signal mirror_changed(mirrors: Vector3i)

## Emitted when the user requests import.
signal import_requested(append: bool)

## Emitted when the user requests to add a new VoxelSet to the target node.
signal add_voxel_set_requested

## Emitted when the user requests to open the VoxelSet Editor dock.
signal voxel_set_editor_requested

## Title text shown in the toolbar. If empty, the title container is hidden.
@export
var title: String = "":
	set = _set_title

@onready
var _title_container: HBoxContainer = %TitleHBoxContainer

@onready
var _title_label: Label = %TitleLabel

# Toolbar
@onready
var _toolbar_container: HBoxContainer = %ToolbarContainer

@onready
var _editing_check_box: CheckBox = %EditingCheckBox

@onready
var _select_menu_button: MenuButton = %SelectMenuButton

@onready
var _edit_menu_button: MenuButton = %EditMenuButton

@onready
var _import_menu_button: MenuButton = %ImportMenuButton

@onready
var _settings_menu_button: MenuButton = %SettingsMenuButton

# Mirroring
@onready
var _mirroring_container: HBoxContainer = %MirroringContainer

@onready
var _x_mirror_check_box: CheckBox = %XMirrorCheckBox

@onready
var _y_mirror_check_box: CheckBox = %YMirrorCheckBox

@onready
var _z_mirror_check_box: CheckBox = %ZMirrorCheckBox

# Brush & Tools
@onready
var _brush_container: HFlowContainer = %BrushContainer

@onready
var _tools_container: HFlowContainer = %ToolsContainer

# Notice area, shown when no VoxelSet attached
@onready
var _notice_hbox_container: HBoxContainer = %NoticeHBoxContainer

@onready
var _notice_label: Label = %NoticeLabel

@onready
var _new_voxel_set_button: Button = %NewVoxelSetButton

@onready
var _voxel_set_editor_button: Button = %VoxelSetEditorButton

# Context panel
@onready
var _brush_options_foldable: FoldableContainer = %BrushOptionsFoldableContainer

@onready
var _brush_options_container: GridContainer = %BrushOptionsGridContainer

@onready
var _tool_options_foldable: FoldableContainer = %ToolOptionsFoldableContainer

@onready
var _tool_options_container: GridContainer = %ToolOptionsGridContainer

var _option_builder = VoxlyOptionBuilder.new()

# Info label
@onready
var _info_label: Label = %InfoLabel

# Node context panel
@onready
var _node_context_container: PanelContainer = %NodeContextContainer

@onready
var _voxel_node_3d_foldable: FoldableContainer = %VoxelNode3DContainer

@onready
var _voxel_model_3d_foldable: FoldableContainer = %VoxelModel3DContextContainer

@onready
var _voxel_size_x_spin_box: SpinBox = %VoxelSizeXSpinBox

@onready
var _voxel_size_y_spin_box: SpinBox = %VoxelSizeYSpinBox

@onready
var _voxel_size_z_spin_box: SpinBox = %VoxelSizeZSpinBox

@onready
var _origin_x_spin_box: SpinBox = %OriginXSpinBox

@onready
var _origin_y_spin_box: SpinBox = %OriginYSpinBox

@onready
var _origin_z_spin_box: SpinBox = %OriginZSpinBox

@onready
var _shape_x_spin_box: SpinBox = %ShapeXSpinBox

@onready
var _shape_y_spin_box: SpinBox = %ShapeYSpinBox

@onready
var _shape_z_spin_box: SpinBox = %ShapeZSpinBox

# Settings window
@onready
var _settings_window: Window = %SettingsWindow

@onready
var _settings_tab_container: TabContainer = %SettingsTabContainer

# Context window
@onready
var _context_window: Window = %ContextWindow

@onready
var _context_window_grid: GridContainer = %ContextWindowGridContainer

@onready
var _context_window_ok_button: Button = %ContextWindowOkButton

@onready
var _context_window_cancel_button: Button = %ContextWindowCancelButton

# Import progress window
@onready
var _progress_window: Window = %ProgressWindow

@onready
var _import_progress_bar: ProgressBar = %ImportProgressBar

@onready
var _import_label: Label = %ImportLabel

# Grid settings
@onready
var _grid_settings_container: MarginContainer = %GridSettingsContainer

@onready
var _grid_visible_check_box: CheckBox = %GridVisibleCheckBox

@onready
var _grid_colored_option_button: OptionButton = %GridColoredOptionButton

@onready
var _grid_color_picker_button: ColorPickerButton = %GridColorPickerButton

@onready
var _grid_mode_option_button: OptionButton = %GridModeOptionButton

@onready
var _reset_grid_settings_button: Button = %ResetGridSettingsButton

# Preview settings
@onready
var _preview_settings_container: MarginContainer = %PreviewSettingsContainer

@onready
var _preview_visible_check_box: CheckBox = %PreviewVisibleCheckBox

@onready
var _preview_mirrored_check_box: CheckBox = %PreviewMirroredCheckBox

@onready
var _reset_preview_settings_button: Button = %ResetPreviewSettingsButton

# Cached data
var mirrors: Vector3i = Vector3i.ZERO
var _pending_update: bool = false
var _update_timer: float = 0.0
var _last_palette_id: int = -1
var _last_hit_info: String = ""
var _last_voxel_set_name: String = ""

## The controller driving this editor.
var controller: VoxelNode3DController = null

## Current palette voxel ID (-1 = none selected in the VoxelSet editor).
var palette_voxel_id: int = -1

## True when the VoxelSet editor dock is showing a set that doesn't belong
## to the currently active node (palette updates are blocked in that case).
var _palette_mismatch: bool = false

## Shared selection/tool sources.
var _brush_buttons: Array[Button] = []
var _tool_buttons: Array[Button] = []

func _set(property, value):
	if property == "vertical":
		pass
	return false

## Sets the title text. If empty, the title container is hidden.
func _set_title(new_title: String) -> void:
	title = new_title
	_update_title_visibility()

func _update_title_visibility() -> void:
	if not _title_container or not _title_label:
		return
	var has_title := not title.is_empty()
	_title_container.visible = has_title
	if has_title:
		_title_label.text = title

func _ready() -> void:
	# Apply title visibility
	_update_title_visibility()
	
	# Editing toggle
	_editing_check_box.toggled.connect(_on_editing_toggled)
	
	# Selection is only allowed while editing mode is active.
	_update_editing_state(false)
	
	# Mirror checkboxes
	_x_mirror_check_box.toggled.connect(_on_mirror_toggled.bind(2))
	_y_mirror_check_box.toggled.connect(_on_mirror_toggled.bind(1))
	_z_mirror_check_box.toggled.connect(_on_mirror_toggled.bind(0))
	
	# New VoxelSet button
	_new_voxel_set_button.pressed.connect(_on_new_voxel_set_pressed)
	
	# VoxelSet Editor button
	if _voxel_set_editor_button:
		_voxel_set_editor_button.pressed.connect(_on_voxel_set_editor_button_pressed)
	
	# Settings window close button
	_settings_window.close_requested.connect(_settings_window.hide)
	
	# Context window prompt buttons
	if _context_window_ok_button:
		_context_window_ok_button.pressed.connect(_on_context_window_ok)
	if _context_window_cancel_button:
		_context_window_cancel_button.pressed.connect(_on_context_window_cancel)
	if _context_window:
		_context_window.close_requested.connect(_on_context_window_cancel)
	
	# Populate menus programmatically
	_update_menus()
	
	# Populate all option buttons from enums
	_populate_option_buttons()
	
	# Grid settings
	if _grid_mode_option_button:
		_grid_mode_option_button.item_selected.connect(_on_grid_mode_selected)
	
	if _grid_visible_check_box:
		_grid_visible_check_box.toggled.connect(_on_grid_visible_toggled)
	
	if _grid_colored_option_button:
		_grid_colored_option_button.item_selected.connect(_on_grid_colored_selected)
	
	if _grid_color_picker_button:
		_grid_color_picker_button.color_changed.connect(_on_grid_color_changed)
	
	if _reset_grid_settings_button:
		_reset_grid_settings_button.pressed.connect(_on_reset_grid_settings)
	
	# Preview settings
	if _preview_visible_check_box:
		_preview_visible_check_box.toggled.connect(_on_preview_visible_toggled)
	
	if _preview_mirrored_check_box:
		_preview_mirrored_check_box.toggled.connect(_on_preview_mirrored_toggled)
	
	if _reset_preview_settings_button:
		_reset_preview_settings_button.pressed.connect(_on_reset_preview_settings)
	
	# Node context spinboxes
	_voxel_size_x_spin_box.value_changed.connect(_on_voxel_size_x_changed)
	_voxel_size_y_spin_box.value_changed.connect(_on_voxel_size_y_changed)
	_voxel_size_z_spin_box.value_changed.connect(_on_voxel_size_z_changed)
	_origin_x_spin_box.value_changed.connect(_on_origin_x_changed)
	_origin_y_spin_box.value_changed.connect(_on_origin_y_changed)
	_origin_z_spin_box.value_changed.connect(_on_origin_z_changed)
	_shape_x_spin_box.value_changed.connect(_on_shape_x_changed)
	_shape_y_spin_box.value_changed.connect(_on_shape_y_changed)
	_shape_z_spin_box.value_changed.connect(_on_shape_z_changed)
	
	# Persist brush/tool option edits immediately through VoxlyConfig.
	_option_builder.option_changed.connect(_on_option_changed)


## Populates all settings OptionButtons from their respective enums.
func _populate_option_buttons() -> void:
	# Grid mode options
	if _grid_mode_option_button:
		_grid_mode_option_button.clear()
		_grid_mode_option_button.add_item("Floor", VoxlyEditorGrid.GridMode.FLOOR)
		_grid_mode_option_button.add_item("Floor Wired", VoxlyEditorGrid.GridMode.FLOOR_WIRED)
		_grid_mode_option_button.add_item("Bounding", VoxlyEditorGrid.GridMode.BOUNDING)
		_grid_mode_option_button.add_item("Bounding Wired", VoxlyEditorGrid.GridMode.BOUNDING_WIRED)
		_grid_mode_option_button.add_item("Bounding Solid", VoxlyEditorGrid.GridMode.BOUNDING_SOLID)
	
	# Grid color mode options
	if _grid_colored_option_button:
		_grid_colored_option_button.clear()
		_grid_colored_option_button.add_item("By Axis", VoxlyEditorGrid.GridColorMode.BY_AXIS)
		_grid_colored_option_button.add_item("Custom Color", VoxlyEditorGrid.GridColorMode.CUSTOM_COLOR)

## Running serial for menu item ids (kept unique across all popups).
var _menu_item_serial: int = 0

## Maps menu int id to Dictionary with "op" (and optional "param") metadata.
## Populated while building the Select/Edit menus, read by the generic handler.
var _op_menu_meta: Dictionary = {}

## Operation awaiting confirmation via the ContextWindow prompt.
var _pending_prompt_op = null

## Resets menu item id generation + metadata at the start of a rebuild.
func _reset_menu_item_ids() -> void:
	_menu_item_serial = 0
	_op_menu_meta = {}

## Returns a unique int id for a menu item.
func _next_menu_item_id() -> int:
	_menu_item_serial += 1
	return 1000 + _menu_item_serial

## Clears and populates all MenuButton popups programmatically.
func _update_menus() -> void:
	# Select & Edit menus are built from registered VoxlyEditOperation classes.
	_reset_menu_item_ids()
	_build_select_menu()
	_build_edit_menu()
	
	# Import menu
	var import_popup := _import_menu_button.get_popup()
	import_popup.clear()
	_connect_popup_id(import_popup, _on_import_action)
	import_popup.add_item("Append...", 0)
	import_popup.add_item("Replace...", 1)
	
	# Settings menu
	var settings_popup := _settings_menu_button.get_popup()
	settings_popup.clear()
	_connect_popup_id(settings_popup, _on_settings_action)
	settings_popup.add_item("Grid Settings", 0)
	settings_popup.add_item("Preview Settings", 1)


## Builds the Select menu from registered "selection" category operations.
func _build_select_menu() -> void:
	var select_popup := _select_menu_button.get_popup()
	select_popup.clear()
	for sub in select_popup.get_children():
		sub.queue_free()
	_connect_popup_id(select_popup, _on_operation_pressed)
	_connect_popup_about(select_popup, _refresh_operation_menus)
	
	if not controller or not controller.editor:
		return
	var registry := controller.editor.registry
	var names_by_category := registry.get_operations_by_category()
	var selection_ops: PackedStringArray = names_by_category.get("selection", PackedStringArray())
	
	for op_id in selection_ops:
		var op = registry.create_operation(op_id)
		if op == null:
			continue
		var count_entries := op.get_count_entries()
		if not count_entries.is_empty():
			var sub := _create_count_submenu(op, count_entries)
			select_popup.add_child(sub)
			select_popup.add_submenu_item(op.display_name, sub.name)
			sub.add_separator()
			_add_operation_item(sub, op, {"prompt": true, "label": "Other..."})
		else:
			_add_operation_item(select_popup, op)

## Builds the Edit menu from registered edit operations, grouped into submenus.
func _build_edit_menu() -> void:
	var edit_popup := _edit_menu_button.get_popup()
	edit_popup.clear()
	for sub in edit_popup.get_children():
		sub.queue_free()
	_connect_popup_id(edit_popup, _on_operation_pressed)
	_connect_popup_about(edit_popup, _refresh_operation_menus)
	
	if not controller or not controller.editor:
		return
	var registry := controller.editor.registry
	var names_by_category := registry.get_operations_by_category()
	
	_add_operation_groups(edit_popup, registry, names_by_category, ["clipboard"])
	if names_by_category.has("clipboard") and not names_by_category["clipboard"].is_empty():
		edit_popup.add_separator()
	
	_add_operation_groups(edit_popup, registry, names_by_category, ["model", "new_model"])
	
	var edit_ops: PackedStringArray = names_by_category.get("edit", PackedStringArray())
	for op_id in edit_ops:
		var op = registry.create_operation(op_id)
		if op:
			_add_operation_item(edit_popup, op)
	if not edit_ops.is_empty():
		edit_popup.add_separator()
	
	_build_param_submenus(edit_popup, registry)
	_build_prompt_ops(edit_popup, registry, ["transform"])


## Adds submenu groups for the given ordered category names. Each category that
## has operations renders as a named submenu populated with its ops.
func _add_operation_groups(parent: PopupMenu, registry, names_by_category: Dictionary, categories: Array[String]) -> void:
	var group_titles := {
		"clipboard": "Clipboard",
		"model": "Model",
		"new_model": "New Model",
	}
	for category in categories:
		var ops: PackedStringArray = names_by_category.get(category, PackedStringArray())
		if ops.is_empty():
			continue
		var sub := PopupMenu.new()
		sub.name = category
		_connect_popup_id(sub, _on_operation_pressed)
		parent.add_child(sub)
		parent.add_submenu_item(group_titles.get(category, category.capitalize()), sub.name)
		for op_id in ops:
			var op = registry.create_operation(op_id)
			if op == null:
				continue
			_add_operation_item(sub, op)


## Builds one submenu per operation that declares parameterized entries
## (e.g. Align / Mirror / Rotate / Flip), driven by op.get_param_entries().
func _build_param_submenus(parent: PopupMenu, registry) -> void:
	var names_by_category: Dictionary = registry.get_operations_by_category()
	var seen: Dictionary[String, bool] = {}
	for category in names_by_category:
		for op_id in names_by_category[category]:
			var op = registry.create_operation(op_id)
			if op == null:
				continue
			var entries: Array[Dictionary] = op.get_param_entries()
			if entries.is_empty() or seen.has(op.id):
				continue
			seen[op.id] = true
			var sub := PopupMenu.new()
			sub.name = op.id
			_connect_popup_id(sub, _on_operation_pressed)
			for entry in entries:
				if entry.get("separator", false):
					sub.add_separator()
					continue
				_add_operation_item(sub, op, {
					"param": entry.get("param", ""),
					"param_label": entry.get("label", ""),
				})
			parent.add_child(sub)
			parent.add_submenu_item(op.display_name, sub.name)

## Adds a context window operation that declare prompts_for_options
## in the given categories.
func _build_prompt_ops(parent: PopupMenu, registry, categories: Array) -> void:
	var names_by_category: Dictionary = registry.get_operations_by_category()
	var seen: Dictionary[String, bool] = {}
	for category in categories:
		var ops: PackedStringArray = names_by_category.get(category, PackedStringArray())
		for op_id in ops:
			var op = registry.create_operation(op_id)
			if op == null or seen.has(op.id):
				continue
			seen[op.id] = true
			
			if not op.get_param_entries().is_empty():
				continue
			
			if op.prompts_for_options:
				_add_operation_item(parent, op, {"prompt": true})
			else:
				_add_operation_item(parent, op)

## Creates a Grow/Shrink submenu with items 1..5.
func _create_count_submenu(op, count_entries: Array[Dictionary]) -> PopupMenu:
	var sub := PopupMenu.new()
	sub.name = op.id + "_counts"
	sub.id_pressed.connect(_on_count_operation_pressed)
	for entry in count_entries:
		var serial := _next_menu_item_id()
		sub.add_item(entry.get("label", str(entry.get("count", 1))), serial)
		sub.set_item_metadata(sub.item_count - 1, serial)
		_op_menu_meta[serial] = {"op": op.id, "kind": "count", "count": entry.get("count", 1)}
	return sub

## Adds one operation item to a popup with a serial int id and registers metadata.
func _add_operation_item(popup: PopupMenu, op, extra: Dictionary = {}) -> void:
	var serial := _next_menu_item_id()
	var label: String = op.get_display_label(false)
	if extra.has("label"):
		label = extra["label"]
	elif extra.has("param"):
		label = "%s %s" % [op.display_name, extra["param_label"]]
	elif extra.get("prompt", false) or op.prompts_for_options:
		label = "%s..." % op.display_name
	popup.add_item(label, serial)
	if op.shortcut:
		popup.set_item_shortcut(popup.item_count - 1, op.shortcut)
	popup.set_item_metadata(popup.item_count - 1, serial)
	var meta := {"op": op.id}
	meta.merge(extra)
	if op.prompts_for_options and not meta.has("prompt"):
		meta["prompt"] = true
	_op_menu_meta[serial] = meta

func _connect_popup_id(popup: PopupMenu, callable: Callable) -> void:
	if popup.id_pressed.is_connected(callable):
		popup.id_pressed.disconnect(callable)
	popup.id_pressed.connect(callable)

func _connect_popup_about(popup: PopupMenu, callable: Callable) -> void:
	if popup.about_to_popup.is_connected(callable):
		popup.about_to_popup.disconnect(callable)
	popup.about_to_popup.connect(callable)

## Refreshes labels + enabled state right before the menus open.
func _refresh_operation_menus() -> void:
	if not controller or not controller.editor:
		return
	var editor := controller.editor
	var has_selection := editor.selection != null and editor.selection.count() > 0
	_refresh_popup(_select_menu_button.get_popup(), editor, has_selection)
	_refresh_popup(_edit_menu_button.get_popup(), editor, has_selection)

## Recursively refreshes item labels and enabled flags for a popup tree.
func _refresh_popup(popup: PopupMenu, editor, has_selection: bool) -> void:
	for child in popup.get_children():
		if child is PopupMenu:
			_refresh_popup(child, editor, has_selection)
	for i in range(popup.item_count):
		var serial = popup.get_item_metadata(i)
		if not serial is int or not _op_menu_meta.has(serial):
			continue
		var metadata: Dictionary = _op_menu_meta[serial]
		var op = editor.registry.create_operation(metadata["op"])
		if op == null:
			continue
		if metadata.has("kind") and metadata["kind"] == "count":
			popup.set_item_disabled(i, not op.is_available(editor))
			continue
		if metadata.has("label"):
			popup.set_item_text(i, metadata["label"])
		elif metadata.has("param"):
			var target := "Selection" if has_selection else "All Voxels"
			popup.set_item_text(i, "%s %s %s" % [op.display_name, metadata["param_label"], target])
		elif metadata.get("prompt", false):
			popup.set_item_text(i, "%s..." % op.display_name)
		else:
			popup.set_item_text(i, op.get_display_label(has_selection))
		popup.set_item_disabled(i, not op.is_available(editor))

## Generic handler for all operation menu items.
func _on_operation_pressed(item_id: int) -> void:
	if not controller or not controller.editor or not _op_menu_meta.has(item_id):
		return
	var metadata: Dictionary = _op_menu_meta[item_id]
	var editor := controller.editor
	var op = editor.registry.create_operation(metadata["op"])
	if op == null or not op.is_available(editor):
		return
	
	_apply_param(op, metadata.get("param", ""))
	# Operations flagged with "prompt" collect their parameters via the
	# ContextWindow before executing (e.g. Translate).
	if metadata.get("prompt", false):
		_open_context_prompt(op)
		return
	
	op.execute(editor, controller.undo_redo)
	
	# Refresh the menus after Copy/Cut/Paste so shortcuts stay in sync.
	if metadata.get("op", "") in ["copy_voxels", "cut_voxels", "paste_voxels"]:
		_refresh_operation_menus()

## Handler for Grow/Shrink count submenu items.
func _on_count_operation_pressed(item_id: int) -> void:
	if not controller or not controller.editor or not _op_menu_meta.has(item_id):
		return
	
	var metadata: Dictionary = _op_menu_meta[item_id]
	var editor := controller.editor
	var op = editor.registry.create_operation(metadata["op"])
	if op == null or not op.is_available(editor):
		return
	
	if metadata.get("prompt", false):
		_open_context_prompt(op)
		return
	
	op.steps = metadata.get("count", 1)
	op.execute(editor, controller.undo_redo)

## Sets axis/direction parameters on parameterized transform operations.
func _apply_param(op, param: String) -> void:
	if param.is_empty():
		return
	var axis_map := {"x": 0, "y": 1, "z": 2}
	match param:
		"x", "y", "z":
			if "axis" in op:
				op.axis = axis_map[param]
		"right", "left":
			if "clockwise" in op:
				op.clockwise = (param == "right")
		"xyz_center":
			if "axis" in op and "align_mode" in op and "align_all_axes" in op:
				op.axis = 0
				op.align_mode = 1 # center
				op.align_all_axes = true
		"x_min", "x_center", "x_max", "y_min", "y_center", "y_max", "z_min", "z_center", "z_max":
			if "axis" in op and "align_mode" in op:
				var parts := param.split("_")
				op.axis = axis_map[parts[0]]
				op.align_mode = ["min", "center", "max"].find(parts[1])
				if "align_all_axes" in op:
					op.align_all_axes = false

## Opens the ContextWindow prompt for an operation that requires user input.
## Rows are built from the operation's `get_options()` schema via the shared
## VoxlyOptionBuilder; edits write straight back to the op's properties.
func _open_context_prompt(op) -> void:
	_pending_prompt_op = op
	if not _context_window or not _context_window_grid:
		return
	_option_builder.build_into(_context_window_grid, op.get_options(), op)
	_context_window.title = op.display_name
	_context_window.popup_centered()


## Executes the pending operation after the ContextWindow prompt confirms.
## Values were already written to the op's properties by the option builder
## as the user edited them, so no collection pass is needed here.
func _on_context_window_ok() -> void:
	var op = _pending_prompt_op
	_pending_prompt_op = null
	if _context_window:
		_context_window.hide()
	if op == null or not controller or not controller.editor:
		return
	var editor := controller.editor
	if op.is_available(editor):
		op.execute(editor, controller.undo_redo)


## Closes the ContextWindow without executing the pending operation.
func _on_context_window_cancel() -> void:
	_pending_prompt_op = null
	if _context_window:
		_context_window.hide()

## Called when a VoxelSet is assigned to or removed from the target node.
## Toggles the notice area visibility accordingly.
func set_voxel_set(vs: VoxelSet) -> void:
	_update_notice_visibility()


## Called when the palette selection changes (or is cleared to -1).
## Only updates the notice — never affects editing state.
func set_palette(voxel_id: int) -> void:
	palette_voxel_id = voxel_id
	_update_notice_visibility()


## Called when the VoxelSet editor dock's set doesn't match the active node's
## set. While mismatched, palette updates are blocked and a notice is shown.
func set_palette_mismatch(mismatched: bool) -> void:
	_palette_mismatch = mismatched
	_update_notice_visibility()


func _update_notice_visibility() -> void:
	if not _notice_hbox_container:
		return
	
	var has_set := controller != null and controller.editor.voxel_set != null
	var has_palette := has_set and palette_voxel_id >= 0
	
	# Keep the notice container visible while the editor is open; individual
	# children toggle on their own state. The "VoxelSet Editor" button stays
	# available whenever a voxel set is attached.
	_notice_hbox_container.visible = true
	
	if _new_voxel_set_button:
		_new_voxel_set_button.visible = not has_set
	
	if _voxel_set_editor_button:
		_voxel_set_editor_button.visible = has_set
	
	if _notice_label:
		if _palette_mismatch and has_set:
			_notice_label.visible = true
			_notice_label.text = "VoxelSet Editor is showing a different VoxelSet"
		else:
			_notice_label.visible = not has_palette
			if not has_set:
				_notice_label.text = "No VoxelSet attached"
			else:
				_notice_label.text = "Select a voxel in the VoxelSet Editor"


func set_controller(new_controller: VoxelNode3DController) -> void:
	controller = new_controller
	if not controller:
		return
	
	# Connect editor signals
	if controller.editor.brush_changed.is_connected(_on_brush_changed_from_editor):
		controller.editor.brush_changed.disconnect(_on_brush_changed_from_editor)
	controller.editor.brush_changed.connect(_on_brush_changed_from_editor)
	
	if controller.editor.tool_changed.is_connected(_on_tool_changed_from_editor):
		controller.editor.tool_changed.disconnect(_on_tool_changed_from_editor)
	controller.editor.tool_changed.connect(_on_tool_changed_from_editor)
	
	# Rebuild the Select/Edit menus against this controller's registry,
	# then build initial context options.
	_update_menus()
	_update_context_options()
	
	if controller.editor.mirror_changed.is_connected(_on_mirror_changed_from_controller):
		controller.editor.mirror_changed.disconnect(_on_mirror_changed_from_controller)
	controller.editor.mirror_changed.connect(_on_mirror_changed_from_controller)
	
	# Wire import progress signals to the progress window.
	if controller.import_started.is_connected(_on_import_started):
		controller.import_started.disconnect(_on_import_started)
	controller.import_started.connect(_on_import_started)
	
	if controller.import_progress.is_connected(_on_import_progress):
		controller.import_progress.disconnect(_on_import_progress)
	controller.import_progress.connect(_on_import_progress)
	
	if controller.import_finished.is_connected(_on_import_finished):
		controller.import_finished.disconnect(_on_import_finished)
	controller.import_finished.connect(_on_import_finished)
	
	# Wire node-context sync to the target node's change signals
	var target_node := controller.target as Node
	if target_node:
		if target_node.voxel_size_changed.is_connected(_on_target_transform_changed):
			target_node.voxel_size_changed.disconnect(_on_target_transform_changed)
		target_node.voxel_size_changed.connect(_on_target_transform_changed)
		if target_node is VoxelModel3D:
			if target_node.origin_changed.is_connected(_on_target_transform_changed):
				target_node.origin_changed.disconnect(_on_target_transform_changed)
			target_node.origin_changed.connect(_on_target_transform_changed)
			if target_node.shape_changed.is_connected(_on_target_transform_changed):
				target_node.shape_changed.disconnect(_on_target_transform_changed)
			target_node.shape_changed.connect(_on_target_transform_changed)
	
	# Sync palette state and initial notice visibility
	palette_voxel_id = controller.editor.palette_id
	_update_notice_visibility()
	
	# Sync editing-dependent UI state (Select menu disabled while not editing)
	_update_editing_state(controller.editor.editing_enabled)
	
	# Initial sync of node context panel
	_sync_node_context_ui()


func _on_target_transform_changed() -> void:
	_sync_node_context_ui()

## Populates the node context spinboxes from the target node.
func _sync_node_context_ui() -> void:
	var target = controller.target if controller else null
	var model := target as VoxelModel3D
	if _voxel_model_3d_foldable:
		_voxel_model_3d_foldable.visible = model != null
	
	if not target:
		if _node_context_container:
			_node_context_container.visible = false
		return
	if _node_context_container:
		_node_context_container.visible = true
	
	if is_instance_valid(target):
		_voxel_size_x_spin_box.set_value_no_signal(target.voxel_size.x)
		_voxel_size_y_spin_box.set_value_no_signal(target.voxel_size.y)
		_voxel_size_z_spin_box.set_value_no_signal(target.voxel_size.z)
	
	if model:
		_origin_x_spin_box.set_value_no_signal(model.origin.x)
		_origin_y_spin_box.set_value_no_signal(model.origin.y)
		_origin_z_spin_box.set_value_no_signal(model.origin.z)
		_shape_x_spin_box.set_value_no_signal(model.shape.x)
		_shape_y_spin_box.set_value_no_signal(model.shape.y)
		_shape_z_spin_box.set_value_no_signal(model.shape.z)


## Builds the full voxel size from the spinboxes and forwards it to the
## controller, which applies it through UndoRedo and lets the node clamp.
func _apply_voxel_size_edit() -> void:
	if not controller or not is_instance_valid(controller.target):
		return
	controller.set_voxel_size(Vector3(
		_voxel_size_x_spin_box.value,
		_voxel_size_y_spin_box.value,
		_voxel_size_z_spin_box.value
	))


## Builds the full origin from the spinboxes and forwards it to the model
## controller, which applies it through UndoRedo.
func _apply_origin_edit() -> void:
	var model_controller := controller as VoxelModel3DController
	if not model_controller or not is_instance_valid(model_controller.target):
		return
	model_controller.set_origin(Vector3(
		_origin_x_spin_box.value,
		_origin_y_spin_box.value,
		_origin_z_spin_box.value
	))


## Builds the full shape from the spinboxes and forwards it to the model
## controller, which applies it through UndoRedo and lets the node clamp.
func _apply_shape_edit() -> void:
	var model_controller := controller as VoxelModel3DController
	if not model_controller or not is_instance_valid(model_controller.target):
		return
	model_controller.set_shape(Vector3i(
		int(_shape_x_spin_box.value),
		int(_shape_y_spin_box.value),
		int(_shape_z_spin_box.value)
	))


func _on_voxel_size_x_changed(_value: float) -> void:
	_apply_voxel_size_edit()


func _on_voxel_size_y_changed(_value: float) -> void:
	_apply_voxel_size_edit()


func _on_voxel_size_z_changed(_value: float) -> void:
	_apply_voxel_size_edit()


func _on_origin_x_changed(_value: float) -> void:
	_apply_origin_edit()


func _on_origin_y_changed(_value: float) -> void:
	_apply_origin_edit()


func _on_origin_z_changed(_value: float) -> void:
	_apply_origin_edit()


func _on_shape_x_changed(_value: float) -> void:
	_apply_shape_edit()


func _on_shape_y_changed(_value: float) -> void:
	_apply_shape_edit()


func _on_shape_z_changed(_value: float) -> void:
	_apply_shape_edit()


## Persists the current editor state (brush/tool options, mirrors, grid,
## preview) through the controller's VoxlyConfig-backed save_config().
## Called on every relevant UI change so settings are always current on disk.
func _persist_settings() -> void:
	if controller:
		controller.save_config()


## Handles VoxlyOptionBuilder.option_changed, instantly persists brush/tool
## option edits. Operation prompt rows (ContextWindow) use a transient op as
## source, so those are ignored.
func _on_option_changed(source, _property: String, _value) -> void:
	if not controller or not controller.editor:
		return
	var editor := controller.editor
	if source == editor.active_brush or source == editor.active_tool:
		_persist_settings()


func populate_brushes() -> void:
	if controller:
		controller.populate_brush_ui(_brush_container)


func populate_tools() -> void:
	if controller:
		controller.populate_tool_ui(_tools_container)

## Clears and rebuilds the context options panel based on the active brush/tool,
## using the shared VoxlyOptionBuilder so all consumers share one row renderer.
func _update_context_options() -> void:
	if not controller:
		return
	if not _brush_options_container or not _tool_options_container:
		return
	
	# Collect options from the active brush and tool independently.
	var brush_options: Array[Dictionary] = []
	if controller.editor.active_brush:
		brush_options = controller.editor.active_brush.get_options()
	var tool_options: Array[Dictionary] = []
	if controller.editor.active_tool:
		tool_options = controller.editor.active_tool.get_options()
	
	# Brush section — hide the foldable when the brush exposes no options.
	_brush_options_foldable.visible = not brush_options.is_empty()
	if not brush_options.is_empty():
		_option_builder.build_into(
			_brush_options_container,
			brush_options,
			controller.editor.active_brush,
			Callable(self, "_on_brush_action"),
			Callable(self, "_on_brush_action_toggled"),
		)
	
	# Tool section — hide the foldable when the tool exposes no options.
	_tool_options_foldable.visible = not tool_options.is_empty()
	if not tool_options.is_empty():
		_option_builder.build_into(
			_tool_options_container,
			tool_options,
			controller.editor.active_tool,
			Callable(self, "_on_brush_action"),
			Callable(self, "_on_brush_action_toggled"),
		)


## Handles button-press actions from brushes (e.g., "Set Pattern").
func _on_brush_action(action: String) -> void:
	if not controller or not controller.editor or not controller.editor.active_brush:
		return
	var brush = controller.editor.active_brush
	if brush.has_method(action):
		brush.call(action, controller.editor)
		_update_context_options()


## Handles checkbox toggles for action-type options (e.g., "Use Palette ID").
func _on_brush_action_toggled(enabled: bool, action: String) -> void:
	if not controller or not controller.editor or not controller.editor.active_brush:
		return
	var brush = controller.editor.active_brush
	if brush.has_method(action):
		brush.call(action, controller.editor)
		_update_context_options()


func _on_brush_changed_from_editor(name: String) -> void:
	# Update button states
	for child in _brush_container.get_children():
		if child is Button:
			child.button_pressed = (child.text.to_lower() == name)
	_update_context_options()


func _on_tool_changed_from_editor(name: String) -> void:
	for child in _tools_container.get_children():
		if child is Button:
			child.button_pressed = (child.text.to_lower() == name)
	_update_context_options()

## Enables/disables UI that depends on editing mode being active.
func _update_editing_state(enabled: bool) -> void:
	# Selection should not be allowed outside of editing mode.
	_select_menu_button.disabled = not enabled


func _on_editing_toggled(enabled: bool) -> void:
	_update_editing_state(enabled)
	editing_toggled.emit(enabled)

func _on_mirror_toggled(pressed: bool, axis: int) -> void:
	var value := pressed

	var new_mirrors := mirrors
	match axis:
		0: new_mirrors.x = 1 if value else 0
		1: new_mirrors.y = 1 if value else 0
		2: new_mirrors.z = 1 if value else 0

	if new_mirrors != mirrors:
		mirrors = new_mirrors
		mirror_changed.emit(mirrors)
		if controller:
			controller.editor.set_mirrors(mirrors)
			_persist_settings()


func _on_mirror_changed_from_controller(new_mirrors: Vector3i) -> void:
	mirrors = new_mirrors
	_sync_mirror_ui()


func _sync_mirror_ui() -> void:
	if not is_instance_valid(_x_mirror_check_box):
		return
	# Keep in sync with the swapped X/Z bindings above.
	_x_mirror_check_box.button_pressed = mirrors.z == 1
	_y_mirror_check_box.button_pressed = mirrors.y == 1
	_z_mirror_check_box.button_pressed = mirrors.x == 1

## Syncs all settings UI controls with the current grid/preview state.
func _sync_settings_ui() -> void:
	if not controller:
		return

	# Grid settings
	if controller.grid:
		_grid_visible_check_box.button_pressed = controller.grid.grid_visible
		_grid_mode_option_button.selected = controller.grid.grid_mode
		_grid_colored_option_button.selected = controller.grid.grid_colored
		_grid_color_picker_button.color = controller.grid.grid_color
		_update_grid_color_picker_state()

	# Preview settings
	if controller.preview:
		_preview_visible_check_box.button_pressed = controller.preview.preview_visible
		if _preview_mirrored_check_box:
			_preview_mirrored_check_box.button_pressed = controller.preview.preview_mirrored

func _on_grid_mode_selected(index: int) -> void:
	if controller and controller.grid:
		controller.grid.grid_mode = index as VoxlyEditorGrid.GridMode
		_persist_settings()

func _on_grid_visible_toggled(visible: bool) -> void:
	if controller and controller.grid:
		controller.grid.grid_visible = visible
		_persist_settings()

func _on_grid_colored_selected(index: int) -> void:
	if controller and controller.grid:
		controller.grid.grid_colored = index as VoxlyEditorGrid.GridColorMode
		_update_grid_color_picker_state()
		_persist_settings()

func _update_grid_color_picker_state() -> void:
	if not controller or not controller.grid:
		return
	var is_by_axis := controller.grid.grid_colored == VoxlyEditorGrid.GridColorMode.BY_AXIS
	_grid_color_picker_button.disabled = is_by_axis

func _on_grid_color_changed(color: Color) -> void:
	if controller and controller.grid:
		controller.grid.grid_color = color
		_persist_settings()

func _on_reset_grid_settings() -> void:
	if controller and controller.grid:
		controller.grid.grid_mode = VoxlyEditorGrid.GridMode.BOUNDING_WIRED
		controller.grid.grid_colored = VoxlyEditorGrid.GridColorMode.BY_AXIS
		controller.grid.grid_color = Color(1, 1, 1, 0.5)
		controller.grid.grid_visible = true
		_sync_settings_ui()
		_persist_settings()

func _on_preview_visible_toggled(visible: bool) -> void:
	if controller and controller.preview:
		controller.preview.preview_visible = visible
		_persist_settings()

func _on_preview_mirrored_toggled(mirrored: bool) -> void:
	if controller and controller.preview:
		controller.preview.preview_mirrored = mirrored
		_persist_settings()

func _on_reset_preview_settings() -> void:
	if controller and controller.preview:
		controller.preview.preview_visible = true
		controller.preview.preview_mirrored = true
		_sync_settings_ui()
		_persist_settings()

## Requests to create and attach a new VoxelSet.
func _on_new_voxel_set_pressed() -> void:
	add_voxel_set_requested.emit()


## Requests to open the VoxelSet Editor dock.
func _on_voxel_set_editor_button_pressed() -> void:
	voxel_set_editor_requested.emit()

var _import_file_dialog: FileDialog = null
var _import_append: bool = true

func _on_import_action(id: int) -> void:
	_import_append = id == 0
	if not _import_file_dialog:
		_import_file_dialog = FileDialog.new()
		_import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_import_file_dialog.add_filter("*.png,*.jpg,*.jpeg,*.vox;Supported Files")
		_import_file_dialog.add_filter("*.png;PNG Image")
		_import_file_dialog.add_filter("*.jpg,*.jpeg;JPEG Image")
		_import_file_dialog.add_filter("*.vox;MagicaVoxel")
		_import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_import_file_dialog.file_selected.connect(_on_import_file_selected)
		add_child(_import_file_dialog)
	_import_file_dialog.popup_centered()


func _on_import_file_selected(path: String) -> void:
	# Notify any external listeners (e.g. dock/UIManager coordination).
	import_requested.emit(_import_append)
	
	# Route to the controller, which applies the import through UndoRedo
	# in a chunked coroutine while the progress window reports stages.
	if controller:
		controller.import_file(path, _import_append)


## Shows the progress window when an import starts.
func _on_import_started(file_name: String) -> void:
	if not _progress_window or not _import_progress_bar or not _import_label:
		return
	
	_import_label.text = "Importing \"%s\"..." % file_name
	_import_progress_bar.value = 0.0
	_progress_window.popup_centered()


## Updates the label + bar during an import from the controller's chunked
## coroutine.
func _on_import_progress(stage: String, fraction: float) -> void:
	if not _progress_window or not _import_progress_bar or not _import_label:
		return
	
	_import_label.text = "%s..." % stage
	_import_progress_bar.value = clampf(fraction, 0.0, 1.0) * 100.0


## Hides the progress window when an import finishes (success or failure).
func _on_import_finished(_success: bool) -> void:
	if _progress_window:
		_progress_window.hide()


func _on_settings_action(id: int) -> void:
	match id:
		0:
			_settings_tab_container.current_tab = 0
		1:
			_settings_tab_container.current_tab = 1
	# Sync settings UI before showing
	_sync_settings_ui()
	_settings_window.popup_centered()


func _process(delta: float) -> void:
	## Throttled info label update (~5 fps) to avoid unnecessary overhead.
	_update_timer += delta
	if _update_timer < 0.2:
		return
	_update_timer = 0.0
	_update_info_label()


func _update_info_label() -> void:
	if not _info_label or not controller:
		return
	
	var editor := controller.editor
	if not editor:
		return
	
	var lines: PackedStringArray = []
	
	# Palette info
	var palette_id := editor.palette_id
	var palette_line := "Palette: None"
	if palette_id >= 0 and editor.voxel_set:
		var v = editor.voxel_set.get_voxel(palette_id)
		palette_line = "Palette: ID %d" % palette_id
		if v and not v.name.is_empty():
			palette_line += "  \"%s\"" % v.name
	lines.append(palette_line)
	
	# Hit position (while editing)
	if editor.editing_enabled and not editor.last_hit.is_empty():
		var pos := editor.last_hit.get("position", Vector3i.ZERO)
		lines.append("Hover: %s" % str(pos))
	
	# Mirror info
	if mirrors != Vector3i.ZERO:
		var mirror_parts: PackedStringArray = []
		if mirrors.x == 1: mirror_parts.append("X")
		if mirrors.y == 1: mirror_parts.append("Y")
		if mirrors.z == 1: mirror_parts.append("Z")
		lines.append("Mirror: %s" % ", ".join(mirror_parts))
	
	# Selection info
	if editor.selection and editor.selection.count() > 0:
		lines.append("Selection: %d" % editor.selection.count())
	
	# Brush & tool info
	if editor.active_brush:
		var brush_info := "Brush: %s" % editor.brush_name.capitalize()
		var drag_info := editor.active_brush.get_drag_info()
		if not drag_info.is_empty():
			brush_info += " (%s)" % drag_info
		
		# Pattern selection count
		var brush = editor.active_brush
		if brush is VoxlyBrushPattern:
			if brush.is_selecting():
				var sel_count = brush.selection_set.size()
				brush_info += " | Selected: %d" % sel_count
			else:
				brush_info += " | Pattern: %d" % brush.pattern_positions.size()
		
		lines.append(brush_info)
	if editor.active_tool:
		lines.append("Tool: %s" % editor.tool_name.capitalize())
	
	# VoxelSet info
	if editor.voxel_set:
		var count = editor.voxel_set.get_voxels_count()
		lines.append("VoxelSet: %d voxels" % count)
	else:
		lines.append("VoxelSet: None attached")
	
	_info_label.text = " | ".join(lines)
