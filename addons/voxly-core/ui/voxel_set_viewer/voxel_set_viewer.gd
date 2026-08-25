@tool
extends VBoxContainer

## Emitted when selection changes. Sends the full list of selected IDs.
signal selected_voxels_changed(selected_ids: Array)

const VoxelButtonScene := preload("res://addons/voxly-core/ui/voxel_button/voxel_button.tscn")
const MaterialEditorWindowScript := preload("res://addons/voxly-core/ui/material_editor_window/material_editor_window.gd")

@onready
var _title_container : HBoxContainer = %TitleHBoxContainer

@onready
var _title_label : Label = %TitleLabel

## Title text shown in the toolbar. If empty, the title container is hidden.
@export
var title: String = "":
	set = _set_title

@onready
var search: LineEdit = %Search

@onready
var list: HFlowContainer = %List

@onready
var _tool_bar: HBoxContainer = %ToolBar

@onready
var _add_menu_button : MenuButton = %AddMenuButton

@onready
var _select_menu_button : MenuButton = %SelectMenuButton

@onready
var _remove_menu_button : MenuButton = %RemoveMenuButton

@onready
var _import_menu_button: MenuButton = %ImportMenuButton

@onready
var _materials_button: Button = %MaterialsButton

@onready
var _material_editor_window := %MaterialEditorWindow

@export
var voxel_set: VoxelSet = null:
	set = set_voxel_set

## Show or hide the toolbar (Add, Remove, Select, Import buttons).
@export
var show_toolbar: bool = true:
	set = _set_show_toolbar

@export
var show_search: bool = true:
	set = _set_show_search

## Enable/disable editing of the voxel set. When disabled, toolbar menu buttons
## are disabled so the user can still browse but not modify.
@export
var editing_enabled: bool = true:
	set = _set_editing_enabled

@export
var selection_enabled: bool = true:
	set = _set_selection_enabled

@export_range(0, 100, 1, "or_greater")
var selection_min: int = 0:
	set = _set_selection_min

@export_range(-1, 100, 1, "or_greater")
var selection_max: int = -1:
	set = _set_selection_max

## Optional undo/redo for editor integration.
## Set from the outside; forwarded to the material editor window.
var undo_redo: EditorUndoRedoManager = null:
	set = _set_undo_redo

enum ContextAction {
	ADD,
	SELECT,
	UNSELECT,
	SELECT_ALL,
	UNSELECT_ALL,
	ERASE,
	DUPLICATE,
	ERASE_SELECTED,
	DUPLICATE_SELECTED,
}

var selected_ids: Array[int] = []
var _buttons: Array = []
var _pending_rebuild := false
var _search_panel: PanelContainer = null
var _context_menu: PopupMenu = null
var _context_voxel_id: int = -1

# Import dialog shared across the component
var _import_file_dialog: FileDialog = null

func set_voxel_set(new_voxel_set: VoxelSet) -> void:
	if new_voxel_set == voxel_set:
		return
	if voxel_set and voxel_set.voxels_changed.is_connected(_rebuild):
		voxel_set.voxels_changed.disconnect(_rebuild)
	voxel_set = new_voxel_set
	if _material_editor_window:
		_material_editor_window.voxel_set = new_voxel_set
	clear_selection()
	if voxel_set and not voxel_set.voxels_changed.is_connected(_rebuild):
		voxel_set.voxels_changed.connect(_rebuild)
	if not is_inside_tree():
		_pending_rebuild = true
	else:
		_rebuild()

func _set_undo_redo(manager: EditorUndoRedoManager) -> void:
	undo_redo = manager
	if _material_editor_window:
		_material_editor_window.set_undo_redo_manager(manager)

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

func _set_editing_enabled(value: bool) -> void:
	editing_enabled = value
	_update_toolbar_button_states()

func _update_editing_state() -> void:
	_update_toolbar_button_states()

## Updates toolbar button states based on editing_enabled.
## When editing is disabled, all buttons are forced disabled.
## When editing is enabled, buttons follow their normal context-aware state.
func _update_toolbar_button_states() -> void:
	if not _tool_bar:
		return
	if not editing_enabled:
		_add_menu_button.disabled = true
		_remove_menu_button.disabled = true
		_select_menu_button.disabled = true
		_import_menu_button.disabled = true
		_materials_button.disabled = true
	else:
		# Re-run the context-aware updates so each button gets its correct state
		_update_toolbar_add_menu()
		_update_toolbar_remove_menu()
		_update_toolbar_select_menu()
		# Import and Materials are only disabled when editing is off
		_import_menu_button.disabled = false
		_materials_button.disabled = voxel_set == null

func _set_selection_enabled(value: bool) -> void:
	selection_enabled = value
	if not value:
		clear_selection()
	_update_toolbar_button_states()
	var cursor := Input.CURSOR_POINTING_HAND if selection_enabled else Input.CURSOR_ARROW
	for btn in _buttons:
		if is_instance_valid(btn):
			btn.toggle_mode = selection_enabled
			btn.mouse_default_cursor_shape = cursor

func _set_selection_min(value: int) -> void:
	selection_min = maxi(value, 0)

func _set_selection_max(value: int) -> void:
	selection_max = value
	if selection_max < 0:
		selection_max = -1
	if selection_enabled and selection_max >= 0 and selected_ids.size() > selection_max:
		while selected_ids.size() > selection_max:
			var last_id: int = selected_ids.pop_back()
			_deselect_button(last_id)
		selected_voxels_changed.emit(selected_ids.duplicate())

func _set_show_search(value: bool) -> void:
	show_search = value
	if _search_panel:
		_search_panel.visible = value

func _set_show_toolbar(value: bool) -> void:
	show_toolbar = value
	if _tool_bar:
		_tool_bar.visible = value

func _ready() -> void:
	# Apply title visibility
	_update_title_visibility()
	
	if search:
		_search_panel = search.get_parent() as PanelContainer
		if _search_panel:
			_search_panel.visible = show_search
	# Apply editing_enabled state
	_update_editing_state()
	search.text_changed.connect(_on_search_changed)
	
	# Context menu
	list.gui_input.connect(_on_list_gui_input)
	_context_menu = PopupMenu.new()
	_context_menu.name = "VoxelSetViewerContextMenu"
	_context_menu.id_pressed.connect(_on_context_menu_action)
	add_child(_context_menu)
	
	# Toolbar: Add
	_add_menu_button.get_popup().about_to_popup.connect(_update_toolbar_add_menu)
	_add_menu_button.get_popup().id_pressed.connect(_on_toolbar_add_action)
	
	# Toolbar: Remove
	_remove_menu_button.get_popup().about_to_popup.connect(_update_toolbar_remove_menu)
	_remove_menu_button.get_popup().id_pressed.connect(_on_toolbar_remove_action)
	
	# Toolbar: Select
	_select_menu_button.get_popup().about_to_popup.connect(_update_toolbar_select_menu)
	_select_menu_button.get_popup().id_pressed.connect(_on_toolbar_select_action)
	_select_menu_button.get_popup().clear(true)
	_select_menu_button.get_popup().add_item("Select All", 0)
	_select_menu_button.get_popup().add_item("Unselect All", 1)
	
	# Toolba: Import
	_import_menu_button.get_popup().id_pressed.connect(_on_toolbar_import_action)
	_import_menu_button.get_popup().clear(true)
	_import_menu_button.get_popup().add_item("Append...", 0)
	_import_menu_button.get_popup().add_item("Replace...", 1)
	
	# Toolbar: Materials
	_materials_button.pressed.connect(_open_material_editor)
	
	# Material editor window
	_material_editor_window.setup("Material Editor", voxel_set, "", MaterialEditorWindowScript.EditMode.EDITABLE)
	if undo_redo:
		_material_editor_window.set_undo_redo_manager(undo_redo)
	
	# Initial toolbar state when no voxels exist
	_remove_menu_button.disabled = true
	_select_menu_button.disabled = true
	
	if _pending_rebuild:
		_rebuild()

func get_selected_ids() -> Array[int]:
	return selected_ids.duplicate()

func select_voxel(voxel_id: int) -> void:
	if not selection_enabled or not voxel_set or not voxel_set.voxel_id_exists(voxel_id):
		return
	_deselect_all_buttons()
	selected_ids = [voxel_id]
	_select_button(voxel_id)
	selected_voxels_changed.emit(selected_ids.duplicate())

func select_all() -> void:
	if not selection_enabled or not voxel_set:
		return
	var all_ids := voxel_set.get_voxel_ids()
	if all_ids.is_empty():
		return
	_deselect_all_buttons()
	selected_ids = all_ids
	for vid in all_ids:
		_select_button(vid)
	selected_voxels_changed.emit(selected_ids.duplicate())

func clear_selection() -> void:
	_deselect_all_buttons()
	selected_ids.clear()
	selected_voxels_changed.emit([])

func update_button(voxel_id: int) -> void:
	for btn in _buttons:
		if is_instance_valid(btn) and btn.voxel_id == voxel_id:
			btn.update()
			return

func _rebuild() -> void:
	if not list:
		_pending_rebuild = true
		return
	_pending_rebuild = false
	for btn in _buttons:
		if is_instance_valid(btn):
			list.remove_child(btn)
			btn.queue_free()
	_buttons.clear()
	if not voxel_set:
		return
	var cursor := Input.CURSOR_POINTING_HAND if selection_enabled else Input.CURSOR_ARROW
	for vid in voxel_set.get_voxel_ids():
		var btn = VoxelButtonScene.instantiate()
		btn.voxel_set = voxel_set
		btn.voxel_id = vid
		btn.toggle_mode = selection_enabled
		btn.mouse_default_cursor_shape = cursor
		btn.voxel_selected.connect(_on_btn_selected)
		btn.voxel_unselected.connect(_on_btn_unselected)
		btn.voxel_right_clicked.connect(_on_btn_right_clicked)
		list.add_child(btn)
		_buttons.append(btn)
	for vid in selected_ids:
		_select_button(vid)
	# Validate selection: remove IDs that no longer exist (e.g. after undo/redo)
	if voxel_set:
		var valid_ids: Array[int] = []
		for vid in selected_ids:
			if voxel_set.voxel_id_exists(vid):
				valid_ids.append(vid)
		if valid_ids.size() != selected_ids.size():
			selected_ids = valid_ids
			selected_voxels_changed.emit(selected_ids.duplicate())
	# Refresh toolbar button enabled states now that voxels are loaded
	_update_toolbar_add_menu()
	_update_toolbar_remove_menu()
	_update_toolbar_select_menu()
	_materials_button.disabled = not editing_enabled
	_apply_search()

func _select_button(voxel_id: int) -> void:
	for btn in _buttons:
		if is_instance_valid(btn) and btn.voxel_id == voxel_id:
			btn.button_pressed = true
			return

func _deselect_button(voxel_id: int) -> void:
	for btn in _buttons:
		if is_instance_valid(btn) and btn.voxel_id == voxel_id:
			btn.button_pressed = false
			return

func _deselect_all_buttons() -> void:
	for btn in _buttons:
		if is_instance_valid(btn):
			btn.button_pressed = false

func _add_to_selection(voxel_id: int) -> void:
	if not selection_enabled:
		return
	if voxel_id in selected_ids:
		return
	if selection_max >= 0 and selected_ids.size() >= selection_max:
		# FIFO: remove the oldest selection and add the new one
		var oldest := selected_ids.pop_front()
		_deselect_button(oldest)
		selected_ids.append(voxel_id)
		_select_button(voxel_id)
		selected_voxels_changed.emit(selected_ids.duplicate())
		return
	selected_ids.append(voxel_id)
	_select_button(voxel_id)
	selected_voxels_changed.emit(selected_ids.duplicate())

func _on_btn_selected(voxel_id: int) -> void:
	if not selection_enabled:
		return
	if Input.is_key_pressed(KEY_CTRL) and not selected_ids.is_empty():
		_add_to_selection(voxel_id)
		return
	_deselect_all_buttons()
	selected_ids = [voxel_id]
	_select_button(voxel_id)
	selected_voxels_changed.emit(selected_ids.duplicate())

func _on_btn_unselected(voxel_id: int) -> void:
	if not selection_enabled:
		return
	if selected_ids.size() <= selection_min:
		_select_button(voxel_id)
		return
	selected_ids.erase(voxel_id)
	selected_voxels_changed.emit(selected_ids.duplicate() if not selected_ids.is_empty() else [])

func _add_voxel() -> void:
	if not voxel_set:
		return
	var new_id := voxel_set.next_voxel_id()
	var new_voxel := Voxel.new()
	if undo_redo:
		undo_redo.create_action("Add Voxel", UndoRedo.MergeMode.MERGE_DISABLE, voxel_set)
		undo_redo.add_do_method(voxel_set, "set_voxel", new_id, new_voxel)
		undo_redo.add_undo_method(voxel_set, "remove_voxel", new_id)
		undo_redo.commit_action()
	else:
		voxel_set.set_voxel(new_id, new_voxel)
	select_voxel(new_id)

func _duplicate_voxels(voxel_ids: Array[int]) -> void:
	if not voxel_set or voxel_ids.is_empty():
		return
	var new_ids: Array[int] = []
	var first_new := voxel_set.next_voxel_id()
	if undo_redo:
		undo_redo.create_action("Duplicate Voxels", UndoRedo.MergeMode.MERGE_DISABLE, voxel_set)
	for i in range(voxel_ids.size()):
		var src := voxel_set.get_voxel(voxel_ids[i])
		if not src:
			continue
		var new_voxel := Voxel.new()
		new_voxel.copy_from(src)
		var new_id := first_new + i
		new_ids.append(new_id)
		if undo_redo:
			undo_redo.add_do_method(voxel_set, "set_voxel", new_id, new_voxel)
			undo_redo.add_undo_method(voxel_set, "remove_voxel", new_id)
		else:
			voxel_set.set_voxel(new_id, new_voxel)
	if undo_redo:
		undo_redo.commit_action()
	if not new_ids.is_empty():
		# Select all duplicated voxels
		_deselect_all_buttons()
		selected_ids = new_ids
		for vid in new_ids:
			_select_button(vid)
		selected_voxels_changed.emit(selected_ids.duplicate())

func _remove_voxels(voxel_ids: Array[int]) -> void:
	if not voxel_set or voxel_ids.is_empty():
		return
	var removed_data: Dictionary = {}
	for vid in voxel_ids:
		if voxel_set.voxel_id_exists(vid):
			removed_data[vid] = voxel_set.get_voxel(vid)
	if removed_data.is_empty():
		return
	if undo_redo:
		undo_redo.create_action("Remove Voxels", UndoRedo.MergeMode.MERGE_DISABLE, voxel_set)
		for vid in removed_data.keys():
			undo_redo.add_do_method(voxel_set, "remove_voxel", vid)
			undo_redo.add_undo_method(voxel_set, "set_voxel", vid, removed_data[vid])
		undo_redo.commit_action()
	else:
		for vid in removed_data.keys():
			voxel_set.remove_voxel(vid)

var _import_append: bool = true

func _import_palette(append: bool) -> void:
	_import_append = append
	if not _import_file_dialog:
		_import_file_dialog = FileDialog.new()
		_import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_import_file_dialog.add_filter("*.png,*.jpg,*.jpeg,*.vox,*.gpl,*.json,*.txt,*.pal,*.hex;Supported Files")
		_import_file_dialog.add_filter("*.png,*.jpg,*.jpeg;Images")
		_import_file_dialog.add_filter("*.vox;MagicaVoxel")
		_import_file_dialog.add_filter("*.gpl,*.json,*.txt,*.pal,*.hex;Palettes")
		_import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_import_file_dialog.file_selected.connect(_on_import_file_selected)
		add_child(_import_file_dialog)
	_import_file_dialog.popup_centered()

func _on_import_file_selected(path: String) -> void:
	if not voxel_set:
		return
	
	# Read the file into a VoxelSet using the shared reader
	var imported: VoxelSet = VoxlyReader.read_file_as_voxel_set(path, {"allow_repeated": true})
	if not imported or imported.get_voxels_count() == 0:
		return
	
	if _import_append:
		# Append mode: add imported voxels with new IDs to avoid conflicts
		var imported_voxels: Dictionary = imported.get_voxels()
		var imported_materials: Dictionary = imported.get_materials()
		var imported_ids := imported_voxels.keys()
		var first_new_id := voxel_set.next_voxel_id()
		
		if undo_redo:
			undo_redo.create_action("Import Palette (Append)", UndoRedo.MergeMode.MERGE_DISABLE, voxel_set)
		
		for mat_id in imported_materials:
			if not voxel_set.material_id_exists(mat_id):
				if undo_redo:
					undo_redo.add_do_method(voxel_set, "set_material", mat_id, imported_materials[mat_id])
					undo_redo.add_undo_method(voxel_set, "remove_material", mat_id)
				else:
					voxel_set.set_material(mat_id, imported_materials[mat_id])
		
		for i in imported_ids.size():
			var new_id := first_new_id + i
			var voxel: Voxel = imported_voxels[imported_ids[i]]
			if undo_redo:
				undo_redo.add_do_method(voxel_set, "set_voxel", new_id, voxel)
				undo_redo.add_undo_method(voxel_set, "remove_voxel", new_id)
			else:
				voxel_set.set_voxel(new_id, voxel)
		
		if undo_redo:
			undo_redo.commit_action()
	else:
		# Replace mode: clear existing and copy all imported data
		var old_voxels: Dictionary = voxel_set.get_voxels()
		var old_materials: Dictionary = voxel_set.get_materials()
		
		if undo_redo:
			undo_redo.create_action("Import Palette (Replace)", UndoRedo.MergeMode.MERGE_DISABLE, voxel_set)
			undo_redo.add_do_method(voxel_set, "clear_voxels")
			undo_redo.add_do_method(voxel_set, "clear_materials")
			for vid in old_voxels:
				undo_redo.add_undo_method(voxel_set, "set_voxel", vid, old_voxels[vid])
			for mid in old_materials:
				undo_redo.add_undo_method(voxel_set, "set_material", mid, old_materials[mid])
			
			var imported_voxels: Dictionary = imported.get_voxels()
			var imported_materials: Dictionary = imported.get_materials()
			for voxel_id in imported_voxels:
				undo_redo.add_do_method(voxel_set, "set_voxel", int(voxel_id), imported_voxels[voxel_id])
			for mat_id in imported_materials:
				undo_redo.add_do_method(voxel_set, "set_material", str(mat_id), imported_materials[mat_id])
			undo_redo.commit_action()
		else:
			voxel_set.clear_voxels()
			voxel_set.clear_materials()
			var imported_voxels: Dictionary = imported.get_voxels()
			var imported_materials: Dictionary = imported.get_materials()
			for voxel_id in imported_voxels:
				voxel_set.set_voxel(int(voxel_id), imported_voxels[voxel_id])
			for mat_id in imported_materials:
				voxel_set.set_material(str(mat_id), imported_materials[mat_id])
	
	clear_selection()

func _on_btn_right_clicked(voxel_id: int, at_position: Vector2) -> void:
	_context_voxel_id = voxel_id
	_show_context_menu(at_position)

func _on_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_context_voxel_id = -1
		_show_context_menu(list.get_screen_position() + event.position)

func _show_context_menu(at_position: Vector2) -> void:
	if not voxel_set:
		return
	_context_menu.clear()
	var has_selection := not selected_ids.is_empty()
	var on_voxel := _context_voxel_id >= 0
	
	_context_menu.add_item("Add Voxel", ContextAction.ADD)
	if on_voxel:
		_context_menu.add_separator()
		if _context_voxel_id in selected_ids:
			_context_menu.add_item("Unselect", ContextAction.UNSELECT)
		else:
			_context_menu.add_item("Select", ContextAction.SELECT)
		_context_menu.add_item("Erase", ContextAction.ERASE)
		_context_menu.add_item("Duplicate", ContextAction.DUPLICATE)
	
	if has_selection and on_voxel:
		_context_menu.add_separator()
	if has_selection and (not on_voxel or selected_ids.size() > 1):
		_context_menu.add_item("Erase Selected (%d)" % selected_ids.size(), ContextAction.ERASE_SELECTED)
		_context_menu.add_item("Duplicate Selected (%d)" % selected_ids.size(), ContextAction.DUPLICATE_SELECTED)
	elif has_selection and on_voxel and selected_ids.size() == 1:
		_context_menu.add_item("Erase Selected (1)", ContextAction.ERASE_SELECTED)
		_context_menu.add_item("Duplicate Selected (1)", ContextAction.DUPLICATE_SELECTED)
	
	if selection_enabled:
		_context_menu.add_separator()
		if not selected_ids.is_empty():
			_context_menu.add_item("Unselect All", ContextAction.UNSELECT_ALL)
		if voxel_set.get_voxels_count() > 0:
			_context_menu.add_item("Select All", ContextAction.SELECT_ALL)
	_context_menu.popup(Rect2i(at_position, Vector2i.ZERO))

func _on_context_menu_action(id: int) -> void:
	match id:
		ContextAction.ADD:
			_add_voxel()
		ContextAction.SELECT:
			if selection_enabled:
				_add_to_selection(_context_voxel_id)
		ContextAction.UNSELECT:
			if selection_enabled:
				_on_btn_unselected(_context_voxel_id)
		ContextAction.SELECT_ALL:
			if selection_enabled and voxel_set:
				select_all()
		ContextAction.UNSELECT_ALL:
			if selection_enabled:
				clear_selection()
		ContextAction.ERASE:
			if _context_voxel_id >= 0:
				_remove_voxels([_context_voxel_id])
		ContextAction.DUPLICATE:
			if _context_voxel_id >= 0:
				_duplicate_voxels([_context_voxel_id])
		ContextAction.ERASE_SELECTED:
			if not selected_ids.is_empty():
				_remove_voxels(selected_ids.duplicate())
		ContextAction.DUPLICATE_SELECTED:
			if not selected_ids.is_empty():
				_duplicate_voxels(selected_ids.duplicate())

func _update_toolbar_add_menu() -> void:
	# Add is always enabled when there's a VoxelSet
	_add_menu_button.disabled = voxel_set == null
	var popup := _add_menu_button.get_popup()
	popup.clear()
	popup.add_item("Add New Voxel", ContextAction.ADD)
	if not selected_ids.is_empty():
		popup.add_item("Duplicate Selected (%d)" % selected_ids.size(), ContextAction.DUPLICATE_SELECTED)

func _on_toolbar_add_action(id: int) -> void:
	match id:
		ContextAction.ADD:
			_add_voxel()
		ContextAction.DUPLICATE_SELECTED:
			if not selected_ids.is_empty():
				_duplicate_voxels(selected_ids.duplicate())

func _update_toolbar_remove_menu() -> void:
	var popup := _remove_menu_button.get_popup()
	popup.clear()
	var has_sel := not selected_ids.is_empty()
	var count := voxel_set.get_voxels_count() if voxel_set else 0
	_remove_menu_button.disabled = not has_sel and count == 0
	if has_sel:
		popup.add_item("Remove Selected (%d)" % selected_ids.size(), 0)
		popup.add_item("Remove All (%d)" % count, 1)
	else:
		popup.add_item("Remove All (%d)" % count, 0)

func _on_toolbar_remove_action(id: int) -> void:
	match id:
		0:
			if not selected_ids.is_empty():
				_remove_voxels(selected_ids.duplicate())
			elif voxel_set:
				_remove_voxels(voxel_set.get_voxel_ids())
		1:
			if voxel_set:
				_remove_voxels(voxel_set.get_voxel_ids())

func _update_toolbar_select_menu() -> void:
	var count := voxel_set.get_voxels_count() if voxel_set else 0
	_select_menu_button.disabled = count == 0

func _on_toolbar_select_action(id: int) -> void:
	match id:
		0:
			select_all()
		1:
			clear_selection()

func _on_toolbar_import_action(id: int) -> void:
	_import_palette(id == 0)

func _open_material_editor() -> void:
	if not voxel_set or not editing_enabled:
		return
	_material_editor_window.voxel_set = voxel_set
	_material_editor_window.edit_mode = MaterialEditorWindowScript.EditMode.EDITABLE
	_material_editor_window.picker_allow_unset = false
	_material_editor_window.picker_allow_default = true
	_material_editor_window.popup_centered_clamped()

func _on_search_changed(new_text: String) -> void:
	_apply_search()

func _apply_search() -> void:
	if not voxel_set or not search:
		return
	var query_text: String = search.text.strip_edges()
	if query_text.is_empty():
		for btn in _buttons:
			if is_instance_valid(btn):
				btn.visible = true
		return
	var matching_ids: Array[int] = voxel_set.query(query_text)
	for btn in _buttons:
		if is_instance_valid(btn):
			btn.visible = btn.voxel_id in matching_ids
