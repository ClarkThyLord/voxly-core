## Window wrapper around the atlas texture picker.
##
## Hosts the picker with Ok/Cancel buttons and enforces the configured
## minimum/maximum selection counts before confirming.
@tool
extends Window

## Emitted when Ok is pressed with a valid selection.
signal confirmed

## Emitted when Cancel is pressed or the window is closed.
signal canceled

## Minimum number of textures that must be selected before Ok is allowed.
@export_range(0, 64, 1)
var min_selection: int = 1:
	set = set_min_selection

## Maximum number of textures that can be selected (-1 = unlimited, 0 = no selection).
@export_range(-1, 64, 1, "or_greater")
var max_selection: int = 1:
	set = set_max_selection

## The embedded atlas texture picker.
@onready var _atlas_texture_picker = %AtlasTexturePicker
## Confirms the current selection.
@onready var _ok_button: Button = %AtlasTexturePickerWindowOkButton
## Dismisses the window without changes.
@onready var _cancel_button: Button = %AtlasTexturePickerWindowCancelButton
## Shown when the selection count is out of range.
@onready var _selection_warning_dialog: AcceptDialog = %AcceptDialog

## Sets the minimum required selection count.
func set_min_selection(value: int) -> void:
	if value == min_selection:
		return
	min_selection = value

## Sets the maximum allowed selection count.
func set_max_selection(value: int) -> void:
	if value == max_selection:
		return
	max_selection = value
	if _atlas_texture_picker:
		_atlas_texture_picker.selection_max = value

## Connects the window buttons.
func _ready() -> void:
	_ok_button.pressed.connect(_on_ok)
	_cancel_button.pressed.connect(_on_cancel)
	close_requested.connect(_on_cancel)
	
	# Apply any exported values that were set before the picker was ready.
	_atlas_texture_picker.selection_max = max_selection

## Configures the window before showing it.
func setup(title: String, ok_text := "Ok", cancel_text := "Cancel") -> void:
	self.title = title
	_ok_button.text = ok_text
	_cancel_button.text = cancel_text

## Returns the underlying AtlasTexturePicker node for advanced customization.
func get_atlas_texture_picker() -> Control:
	return _atlas_texture_picker

## Validates the selection and confirms, or warns when out of range.
func _on_ok() -> void:
	if _atlas_texture_picker.get_selected_texture_cell().size() < min_selection:
		_show_min_selection_warning()
		return
	confirmed.emit()
	hide()

## Emits the canceled signal.
func _on_cancel() -> void:
	canceled.emit()
	hide()

## Shows the selection-count warning dialog.
func _show_min_selection_warning() -> void:
	_selection_warning_dialog.dialog_text = "Select at least %d texture(s) before confirming." % min_selection
	_selection_warning_dialog.popup_centered_clamped()
