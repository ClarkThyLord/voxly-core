@tool
extends Window

## Emitted when the user clicks Ok with the selected color.
signal color_confirmed(color: Color)

## Emitted when the user clicks Cancel or closes the window.
signal color_canceled

@export
var color: Color = Color.WHITE:
	set(v):
		color = v
		if _color_picker:
			_color_picker.color = v
	get:
		return _color_picker.color if _color_picker else color

## Whether the alpha channel can be edited.
@export
var edit_alpha: bool = true:
	set(v):
		edit_alpha = v
		if _color_picker:
			_color_picker.edit_alpha = v
	get:
		return _color_picker.edit_alpha if _color_picker else edit_alpha

@export
var color_mode: ColorPicker.ColorModeType = ColorPicker.ColorModeType.MODE_RGB:
	set(v):
		color_mode = v
		if _color_picker:
			_color_picker.color_mode = v
	get:
		return _color_picker.color_mode if _color_picker else color_mode

@export
var picker_shape: ColorPicker.PickerShapeType = ColorPicker.PickerShapeType.SHAPE_HSV_RECTANGLE:
	set(v):
		picker_shape = v
		if _color_picker:
			_color_picker.picker_shape = v
	get:
		return _color_picker.picker_shape if _color_picker else picker_shape

## Whether the user can add swatches to the picker.
@export
var can_add_swatches: bool = true:
	set(v):
		can_add_swatches = v
		if _color_picker:
			_color_picker.can_add_swatches = v
	get:
		return _color_picker.can_add_swatches if _color_picker else can_add_swatches

@onready
var _color_picker: ColorPicker = %ColorPicker

@onready
var _ok_button: Button = %Ok

@onready
var _cancel_button: Button = %Cancel

func _ready() -> void:
	_ok_button.pressed.connect(_on_ok)
	_cancel_button.pressed.connect(_on_cancel)
	close_requested.connect(_on_cancel)

## Configure the window before showing it.
## @param title: Window title bar text
## @param initial_color: Starting color for the picker
## @param ok_text: Text for the Ok button
## @param cancel_text: Text for the Cancel button
func setup(title: String, initial_color: Color, ok_text := "Ok", cancel_text := "Cancel") -> void:
	self.title = title
	if _color_picker:
		_color_picker.color = initial_color
	if _ok_button:
		_ok_button.text = ok_text
	if _cancel_button:
		_cancel_button.text = cancel_text

## Returns the underlying ColorPicker node for advanced customization.
func get_color_picker() -> ColorPicker:
	return _color_picker

func _on_ok() -> void:
	color_confirmed.emit(_color_picker.color)
	hide()

func _on_cancel() -> void:
	color_canceled.emit()
	hide()
