@tool
extends VBoxContainer

## Emitted when the tag list or selection changes.
signal changed

## Emitted when a tag is toggled on/off.
signal tag_toggled(tag: String, selected: bool)

## Title shown in the toolbar.
@export
var title: String = "Tags":
	set = _set_title

## Maximum number of tags allowed (-1 = unlimited).
@export
var tag_limit: int = -1

## If false, disables all editing (toolbar buttons disabled, toggling blocked).
## The toolbar remains visible so users can still see the buttons.
@export
var disable_editing: bool = false:
	set = _set_disable_editing

## Show or hide the toolbar (Add, Remove, Select buttons).
@export
var show_toolbar: bool = true:
	set = _set_show_toolbar

## Minimum tags that must remain selected.
@export
var selection_min: int = 0

## Maximum tags that can be selected (-1 = unlimited).
@export
var selection_max: int = -1

## Optional regex pattern for tag validation.
## The tag must match this pattern to be valid.
## Example: set to `^[a-zA-Z0-9_]{2,16}$` for 2-16 alphanumeric chars.
@export
var tag_validator: String = ""

## The list of all available tags.
@export
var tags: Array[String] = []:
	set = _set_tags,
	get = _get_tags

## Currently selected tags.
@export
var selected_tags: Array[String] = []:
	set = _set_selected_tags,
	get = _get_selected_tags

@onready
var _toolbar: VBoxContainer = %ToolBarContainer

@onready
var _title_label: Label = %TitleLabel

@onready
var _add_button: MenuButton = %AddButton

@onready
var _remove_button: MenuButton = %RemoveButton

@onready
var _select_button: MenuButton = %SelectButton

@onready
var _tags_container: HFlowContainer = %TagsContainer

@onready
var _name_window: Window = %NameWindow

@onready
var _name_line_edit: LineEdit = %LineEdit

@onready
var _name_ok: Button = %OkButton

@onready
var _name_cancel: Button = %CancelButton

var _tag_buttons: Dictionary[String, Button] = {}
var _context_menu: PopupMenu = null
var _pending_rebuild := false
var _rename_old_tag: String = ""

enum ContextAction {
	TOGGLE_SELECTION,
	RENAME,
	REMOVE,
	SELECT_ALL,
	UNSELECT_ALL,
	REMOVE_SELECTED,
	REMOVE_ALL,
	ADD_TAG,
}

func _set_tags(new_tags: Array[String]) -> void:
	tags = new_tags.duplicate()
	for t in selected_tags.duplicate():
		if t not in tags:
			selected_tags.erase(t)
	if is_inside_tree():
		_rebuild()
	else:
		_pending_rebuild = true

func _get_tags() -> Array[String]:
	return tags

func _set_selected_tags(new_selected: Array[String]) -> void:
	var valid: Array[String] = []
	for t in new_selected:
		if t in tags and t not in valid:
			valid.append(t)
	selected_tags = valid
	_update_button_states()
	changed.emit()

func _get_selected_tags() -> Array[String]:
	return selected_tags

func _set_disable_editing(value: bool) -> void:
	disable_editing = value
	_update_toolbar_disabled_state()

func _set_show_toolbar(value: bool) -> void:
	show_toolbar = value
	if _toolbar:
		_toolbar.visible = value

func _is_single_select() -> bool:
	return selection_max == 1

func _update_toolbar_disabled_state() -> void:
	if not _add_button:
		return
	_update_add_button()
	# Remove: disabled if no tags and no selection, or editing is disabled
	var has_sel := not selected_tags.is_empty()
	var has_tags := not tags.is_empty()
	_remove_button.disabled = (not has_sel and not has_tags) or disable_editing
	# Select: hidden in single-select mode, otherwise disabled if no tags
	if _is_single_select():
		_select_button.hide()
	else:
		_select_button.show()
		_select_button.disabled = not has_tags

func _set_title(value: String) -> void:
	title = value
	if _title_label:
		_title_label.text = value

func _ready() -> void:
	_toolbar.visible = show_toolbar
	_title_label.text = title
	_update_toolbar_disabled_state()
	
	# Add button
	_add_button.get_popup().id_pressed.connect(_on_toolbar_add_action)
	_add_button.get_popup().clear(true)
	_add_button.get_popup().add_item("Add New Tag", 0)
	
	# Remove button — rebuild on open to show counts
	_remove_button.get_popup().about_to_popup.connect(_update_remove_menu)
	_remove_button.get_popup().id_pressed.connect(_on_toolbar_remove_action)
	
	# Select button — rebuild on open to show counts
	_select_button.get_popup().about_to_popup.connect(_update_select_menu)
	_select_button.get_popup().id_pressed.connect(_on_toolbar_select_action)
	
	# Name window
	_name_ok.pressed.connect(_on_name_ok)
	_name_cancel.pressed.connect(_on_name_cancel)
	_name_line_edit.text_submitted.connect(_on_name_ok)
	
	# Context menu (tag-specific)
	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_action)
	add_child(_context_menu)
	
	# Right-click on the tags container for global context menu
	_tags_container.gui_input.connect(_on_tags_container_gui_input)
	
	_name_window.hide()
	
	# Init toolbar select menu with default items
	_select_button.get_popup().clear(true)
	_select_button.get_popup().add_item("Select All", ContextAction.SELECT_ALL)
	_select_button.get_popup().add_item("Unselect All", ContextAction.UNSELECT_ALL)
	
	if _pending_rebuild:
		_rebuild()

func get_tag_button(tag: String) -> Button:
	return _tag_buttons.get(tag)

func refresh() -> void:
	_rebuild()

func _rebuild() -> void:
	if not _tags_container:
		_pending_rebuild = true
		return
	_pending_rebuild = false
	
	for btn in _tag_buttons.values():
		if is_instance_valid(btn):
			_tags_container.remove_child(btn)
			btn.queue_free()
	_tag_buttons.clear()
	
	for t in tags:
		var btn := Button.new()
		btn.text = t
		btn.toggle_mode = not disable_editing
		btn.button_pressed = t in selected_tags
		btn.pressed.connect(_on_tag_toggled.bind(t, btn))
		btn.connect("gui_input", _on_tag_gui_input.bind(t, btn))
		_tags_container.add_child(btn)
		_tag_buttons[t] = btn
	
	_update_toolbar_disabled_state()

func _update_button_states() -> void:
	for t in _tag_buttons:
		var btn = _tag_buttons[t]
		if is_instance_valid(btn):
			btn.button_pressed = t in selected_tags

func _on_tag_toggled(tag: String, btn: Button) -> void:
	if disable_editing:
		btn.button_pressed = false
		return
	
	if btn.button_pressed:
		if selection_max >= 0 and selected_tags.size() >= selection_max:
			btn.button_pressed = false
			return
		if tag not in selected_tags:
			selected_tags.append(tag)
			tag_toggled.emit(tag, true)
	else:
		if selected_tags.size() <= selection_min:
			btn.button_pressed = true
			return
		selected_tags.erase(tag)
		tag_toggled.emit(tag, false)
	
	changed.emit()
	_update_toolbar_disabled_state()

func _on_tag_gui_input(event: InputEvent, tag: String, btn: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_show_tag_context_menu(tag, btn.get_screen_position() + event.position)
		accept_event()

func _on_tags_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Empty context in container (no specific tag) — show global actions
		_show_global_context_menu(_tags_container.get_screen_position() + event.position)

func _show_tag_context_menu(tag: String, at_position: Vector2) -> void:
	_context_menu.clear()
	
	if tag in selected_tags:
		_context_menu.add_item("Unselect", ContextAction.TOGGLE_SELECTION)
	else:
		_context_menu.add_item("Select", ContextAction.TOGGLE_SELECTION)
	
	if not disable_editing:
		_context_menu.add_item("Rename Tag", ContextAction.RENAME)
		_context_menu.add_item("Remove Tag", ContextAction.REMOVE)
	
	if not disable_editing:
		_context_menu.add_separator()
		_context_menu.add_item("Add New Tag", ContextAction.ADD_TAG)
	
	if not _is_single_select():
		_context_menu.add_separator()
		if selected_tags.size() < tags.size():
			_context_menu.add_item("Select All", ContextAction.SELECT_ALL)
		if selected_tags.size() > 0:
			_context_menu.add_item("Unselect All", ContextAction.UNSELECT_ALL)
	
	if not disable_editing and selected_tags.size() > 0:
		_context_menu.add_item("Remove Selected (%d)" % selected_tags.size(), ContextAction.REMOVE_SELECTED)
	
	_context_menu.set_meta("context_tag", tag)
	_context_menu.reset_size()
	_context_menu.popup(Rect2i(at_position, _context_menu.get_contents_minimum_size()))

func _show_global_context_menu(at_position: Vector2) -> void:
	_context_menu.clear()
	
	if not disable_editing:
		_context_menu.add_item("Add New Tag", ContextAction.ADD_TAG)
	
	if not _is_single_select():
		if selected_tags.size() > 0:
			_context_menu.add_separator()
			_context_menu.add_item("Unselect All (%d)" % selected_tags.size(), ContextAction.UNSELECT_ALL)
		elif tags.size() > 0:
			_context_menu.add_separator()
			_context_menu.add_item("Select All (%d)" % tags.size(), ContextAction.SELECT_ALL)
	
	_context_menu.set_meta("context_tag", "")
	_context_menu.reset_size()
	_context_menu.popup(Rect2i(at_position, _context_menu.get_contents_minimum_size()))

func _on_context_action(action_id: int) -> void:
	var tag: String = _context_menu.get_meta("context_tag", "")
	
	match action_id:
		ContextAction.TOGGLE_SELECTION:
			if tag in selected_tags:
				_deselect_tag(tag)
			else:
				_select_tag(tag)
		
		ContextAction.RENAME:
			_open_rename_window(tag)
		
		ContextAction.REMOVE:
			_remove_tag(tag)
		
		ContextAction.SELECT_ALL:
			for t in tags:
				_select_tag(t)
		
		ContextAction.UNSELECT_ALL:
			for t in selected_tags.duplicate():
				_deselect_tag(t)
		
		ContextAction.REMOVE_SELECTED:
			for t in selected_tags.duplicate():
				_remove_tag(t)
		
		ContextAction.ADD_TAG:
			_on_add_pressed()
	
	changed.emit()

func _select_tag(tag: String) -> void:
	if tag in selected_tags:
		return
	if selection_max >= 0 and selected_tags.size() >= selection_max:
		return
	selected_tags.append(tag)
	var btn = _tag_buttons.get(tag)
	if btn:
		btn.button_pressed = true
	tag_toggled.emit(tag, true)

func _deselect_tag(tag: String) -> void:
	if tag not in selected_tags:
		return
	if selected_tags.size() <= selection_min:
		return
	selected_tags.erase(tag)
	var btn = _tag_buttons.get(tag)
	if btn:
		btn.button_pressed = false
	tag_toggled.emit(tag, false)

func _remove_tag(tag: String) -> void:
	tags.erase(tag)
	selected_tags.erase(tag)
	var btn = _tag_buttons.get(tag)
	if btn:
		_tags_container.remove_child(btn)
		btn.queue_free()
		_tag_buttons.erase(tag)
	_update_toolbar_disabled_state()
	changed.emit()

# ── Toolbar: Add ──

func _on_toolbar_add_action(id: int) -> void:
	if id == 0:
		_on_add_pressed()

func _on_add_pressed() -> void:
	_rename_old_tag = ""
	_name_window.title = "Add Tag"
	_name_ok.text = "Add"
	_name_line_edit.text = ""
	_name_line_edit.placeholder_text = "Tag name..."
	_name_window.popup_centered_clamped()
	_name_line_edit.grab_focus()

func _update_remove_menu() -> void:
	var popup := _remove_button.get_popup()
	popup.clear()
	var has_sel := not selected_tags.is_empty()
	var count := tags.size()
	_remove_button.disabled = (not has_sel and count == 0) or disable_editing
	if has_sel:
		popup.add_item("Remove Selected (%d)" % selected_tags.size(), ContextAction.REMOVE_SELECTED)
		popup.add_item("Remove All (%d)" % count, ContextAction.REMOVE_ALL)
	else:
		popup.add_item("Remove All (%d)" % count, ContextAction.REMOVE_ALL)

func _on_toolbar_remove_action(id: int) -> void:
	match id:
		ContextAction.REMOVE_SELECTED:
			for t in selected_tags.duplicate():
				_remove_tag(t)
		ContextAction.REMOVE_ALL:
			for t in tags.duplicate():
				_remove_tag(t)

func _update_select_menu() -> void:
	var popup := _select_button.get_popup()
	popup.clear()
	var count := tags.size()
	_select_button.disabled = count == 0
	popup.add_item("Select All (%d)" % count, ContextAction.SELECT_ALL)
	if not selected_tags.is_empty():
		popup.add_item("Unselect All (%d)" % selected_tags.size(), ContextAction.UNSELECT_ALL)

func _on_toolbar_select_action(id: int) -> void:
	match id:
		ContextAction.SELECT_ALL:
			for t in tags:
				_select_tag(t)
			changed.emit()
		ContextAction.UNSELECT_ALL:
			for t in selected_tags.duplicate():
				_deselect_tag(t)
			changed.emit()

func _open_rename_window(old_tag: String) -> void:
	_rename_old_tag = old_tag
	_name_window.title = "Rename Tag"
	_name_ok.text = "Rename"
	_name_line_edit.text = old_tag
	_name_line_edit.placeholder_text = "New tag name..."
	_name_window.popup_centered_clamped()
	_name_line_edit.grab_focus()
	_name_line_edit.select_all()

func _update_add_button() -> void:
	if not _add_button:
		return
	if tag_limit >= 0 and tags.size() >= tag_limit:
		_add_button.disabled = true
		_add_button.tooltip_text = "Maximum %d tags reached" % tag_limit
	else:
		_add_button.disabled = disable_editing
		_add_button.tooltip_text = ""

func _on_name_ok() -> void:
	var tag_name := _name_line_edit.text.strip_edges()
	if tag_name.is_empty():
		return
	
	# Run regex validator if set
	if tag_validator:
		var regex := RegEx.new()
		regex.compile(tag_validator)
		if not regex.search(tag_name):
			_name_line_edit.placeholder_text = "Invalid tag format"
			_name_line_edit.text = ""
			_name_line_edit.grab_focus()
			return
	
	if _rename_old_tag != "":
		# Renaming existing tag
		if tag_name == _rename_old_tag:
			_name_window.hide()
			_rename_old_tag = ""
			return
		if tag_name in tags:
			_name_line_edit.placeholder_text = "Already exists"
			_name_line_edit.text = ""
			_name_line_edit.grab_focus()
			return
		var idx := tags.find(_rename_old_tag)
		if idx >= 0:
			tags[idx] = tag_name
		if _rename_old_tag in selected_tags:
			selected_tags.erase(_rename_old_tag)
			selected_tags.append(tag_name)
		_rename_old_tag = ""
		_rebuild()
		_name_window.hide()
		changed.emit()
	else:
		# Adding new tag
		if tag_limit >= 0 and tags.size() >= tag_limit:
			_name_line_edit.placeholder_text = "Maximum %d tags reached" % tag_limit
			_name_line_edit.text = ""
			_name_line_edit.grab_focus()
			return
	
		if tag_name in tags:
			_name_line_edit.placeholder_text = "Already exists"
			_name_line_edit.text = ""
			_name_line_edit.grab_focus()
			return
		
		tags.append(tag_name)
		_rebuild()
		_select_tag(tag_name)
		_name_window.hide()
		changed.emit()

func _on_name_cancel() -> void:
	_rename_old_tag = ""
	_name_window.hide()
