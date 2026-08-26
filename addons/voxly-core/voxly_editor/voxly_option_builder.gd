@tool
class_name VoxlyOptionBuilder
extends RefCounted
## Data-driven builder that renders an option schema into a 2-column GridContainer.
## Shared by the VoxelNode3D editor's brush/tool options panel and the
## operation ContextWindow prompts, so the schema + row rendering live in one place.
##
## Option schema (Dictionary keys):
##   label       : String  - description shown in the left column.
##   property    : String  - property name on `source` to read/write (omitted for pure actions).
##   type        : int     - TYPE_BOOL / TYPE_INT / TYPE_FLOAT (from Variant.Type).
##   min / max   : number  - SpinBox range (int/float rows).
##   step        : number  - SpinBox step (default 1 for int, 0.1 for float).
##   default     : number  - initial SpinBox value when `source` has no property value.
##   hint        : String  - "" for a plain control, or:
##                           - "button": renders a Button; `button_text` is its label and
##                             `action` is fed to the button callable when pressed.
##                           - "action": renders a CheckBox bound to `property`; `action`
##                             is fed to the action callable when toggled.
##                           - an "id=Label,id2=Label2" list for TYPE_INT renders an
##                             OptionButton whose selected item id writes back to `property`.
##   button_text : String  - label for "button" hint rows.
##   action      : String  - action name fed to the button/action callables.
##
## Control types are created through a registry of factories keyed by "TYPE:hint"
## (with a "TYPE:*" wildcard for non-empty-hint variants of a type), so new control
## types can be registered with `register_factory()` without touching this class.

## Registry of factories: "TYPE:hint" or "TYPE:*" -> Callable.
## Factory signature: factory(container: GridContainer, opt: Dictionary, source).
var _factories: Dictionary = {}

## Emitted whenever a user-editable option value is written back to `source`
## (brush, tool, operation). Consumers use this to persist configs instantly.
signal option_changed(source, property: String, value)


func _init() -> void:
	_register_defaults()


## Registers a control factory for the given type and hint combination. `hint`
## can be "*" to match any non-empty hint for that type.
func register_factory(type: int, hint: String, factory: Callable) -> void:
	_factories["%d:%s" % [type, hint]] = factory


## Builds label + control rows for each option into `container`, clearing it first.
## `source` is the object whose properties are read/written (may be null for
## action-only rows). `button_callable(action)` is invoked when a "button" row is
## pressed; `action_callable(enabled, action)` is invoked when an "action" row
## toggles.
func build_into(container: GridContainer, options: Array[Dictionary], source,
		button_callable: Callable = Callable(), action_callable: Callable = Callable()) -> void:
	for child in container.get_children():
		child.queue_free()
	for opt in options:
		_build_row(container, opt, source, button_callable, action_callable)

func _build_row(container: GridContainer, opt: Dictionary, source,
		button_callable: Callable, action_callable: Callable) -> void:
	var hint := opt.get("hint", "")
	
	# Button row
	if hint == "button":
		_add_label(container, opt.get("label", ""))
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = opt.get("button_text", "")
		var action := opt.get("action", "")
		if not action.is_empty() and button_callable.is_valid():
			button.pressed.connect(button_callable.bind(action))
		container.add_child(button)
		return
	
	# Action row
	if hint == "action":
		_add_label(container, opt.get("label", ""))
		var check := CheckBox.new()
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_bool_state(check, source, opt.get("property", ""))
		var action := opt.get("action", "")
		if not action.is_empty() and action_callable.is_valid():
			check.toggled.connect(action_callable.bind(action))
		container.add_child(check)
		return
	
	# Standard row: shared label + factory-built control
	_add_label(container, opt.get("label", ""))
	var factory := _resolve_factory(opt.get("type", TYPE_NIL), hint)
	if factory.is_valid():
		factory.call(container, opt, source)
	else:
		# Fallback so unknown schemas still render something usable.
		_build_spin(container, opt, source, false)


func _add_label(container: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	container.add_child(label)


func _apply_bool_state(check: CheckBox, source, property: String) -> void:
	if property.is_empty() or source == null:
		return
	if source.get(property) != null:
		var val = source.get(property)
		if typeof(val) == TYPE_BOOL:
			check.button_pressed = val


## Resolves the factory for a "TYPE:hint" key, falling back to the "TYPE:*"
## wildcard for non-empty hints, then the plain "TYPE:" key.
func _resolve_factory(type: int, hint: String) -> Callable:
	if _factories.has("%d:%s" % [type, hint]):
		return _factories["%d:%s" % [type, hint]]
	if not hint.is_empty() and _factories.has("%d:*" % [type]):
		return _factories["%d:*" % [type]]
	if _factories.has("%d:" % [type]):
		return _factories["%d:" % [type]]
	return Callable()


func _set_property(source, property: String, value) -> void:
	if source != null and not property.is_empty():
		source.set(property, value)
		option_changed.emit(source, property, value)

func _register_defaults() -> void:
	register_factory(TYPE_BOOL, "", _build_bool_check)
	register_factory(TYPE_INT, "", _build_int_spin)
	register_factory(TYPE_FLOAT, "", _build_float_spin)
	register_factory(TYPE_INT, "*", _build_int_option)


func _build_bool_check(container: GridContainer, opt: Dictionary, source) -> void:
	var check := CheckBox.new()
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_bool_state(check, source, opt.get("property", ""))
	var property := opt.get("property", "")
	check.toggled.connect(_on_bool_changed.bind(source, property))
	container.add_child(check)


func _build_int_spin(container: GridContainer, opt: Dictionary, source) -> void:
	_build_spin(container, opt, source, true)


func _build_float_spin(container: GridContainer, opt: Dictionary, source) -> void:
	_build_spin(container, opt, source, false)


func _build_spin(container: GridContainer, opt: Dictionary, source, is_int: bool) -> void:
	var spin_box := SpinBox.new()
	spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin_box.min_value = opt.get("min", 0 if is_int else 0.0)
	spin_box.max_value = opt.get("max", 100 if is_int else 100.0)
	spin_box.step = opt.get("step", 1 if is_int else 0.1)
	var property := opt.get("property", "")
	if source != null and source.get(property) != null:
		spin_box.value = source.get(property)
	else:
		spin_box.value = opt.get("default", 0)
	spin_box.value_changed.connect(_on_spin_changed.bind(source, property, is_int))
	container.add_child(spin_box)


func _build_int_option(container: GridContainer, opt: Dictionary, source) -> void:
	var option_button := OptionButton.new()
	option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint := opt.get("hint", "")
	for choice in hint.split(","):
		choice = choice.strip_edges()
		var parts: PackedStringArray = choice.split("=")
		if parts.size() == 2:
			option_button.add_item(parts[1], int(parts[0]))
		else:
			option_button.add_item(choice)
	var property := opt.get("property", "")
	if source != null and source.get(property) != null:
		var val: int = source.get(property)
		for idx in range(option_button.item_count):
			if option_button.get_item_id(idx) == val:
				option_button.selected = idx
				break
	option_button.item_selected.connect(_on_item_selected.bind(source, property, option_button))
	container.add_child(option_button)

func _on_bool_changed(value: bool, source, property: String) -> void:
	_set_property(source, property, value)

func _on_spin_changed(value: float, source, property: String, is_int: bool) -> void:
	_set_property(source, property, int(value) if is_int else value)

func _on_item_selected(index: int, source, property: String, option_button: OptionButton) -> void:
	_set_property(source, property, option_button.get_item_id(index))
