@tool
extends Node
## Debug logging utility for Voxly-Core with per-category flags.
##
## This is a singleton registered by the Voxly-Core plugin.
## Access it globally via:
##   VoxlyDebug.log_category(VoxlyDebug.CATEGORY_IMPORTERS, "MyClass", "message")
##   VoxlyDebug.log_context("MyClass", "message")  # routes to CATEGORY_GENERAL
##
## Per-category control from editor console:
##   VoxlyDebug.enable_category("importers")
##   VoxlyDebug.disable_category("readers")
##   VoxlyDebug.get_enabled_categories()
##
## Global control:
##   VoxlyDebug.enable()      # all categories
##   VoxlyDebug.disable()     # all categories
##
## For performance-sensitive hot paths, guard string construction:
##   if VoxlyDebug.is_category_enabled(VoxlyDebug.CATEGORY_MESHER):
##       VoxlyDebug.log_category(VoxlyDebug.CATEGORY_MESHER, "Mesher", "Built %d faces" % count)

# Category constants
const CATEGORY_GENERAL    := "general"
const CATEGORY_IMPORTERS  := "importers"
const CATEGORY_READERS    := "readers"
const CATEGORY_VOXEL_NODES := "voxel_nodes"
const CATEGORY_VOXEL_SETS := "voxel_sets"
const CATEGORY_MESHER     := "mesher"
const CATEGORY_EDITOR_UI  := "editor_ui"
const CATEGORY_PLUGIN     := "plugin"

## All categories in an array for iteration.
const ALL_CATEGORIES := [
	CATEGORY_GENERAL,
	CATEGORY_IMPORTERS,
	CATEGORY_READERS,
	CATEGORY_VOXEL_NODES,
	CATEGORY_VOXEL_SETS,
	CATEGORY_MESHER,
	CATEGORY_EDITOR_UI,
	CATEGORY_PLUGIN,
]

## Set this to true at compile time to enable debug logging permanently.
## When false, categories default to disabled unless VOXLY_DEBUG env var is set.
const DEBUG_ENABLED: bool = true

## Per-category enabled flags.
var _categories: Dictionary = {}

## Global override — when false, all categories are disabled regardless of per-category flags.
var _global_enabled: bool = true

func _init() -> void:
	_update_debug_flag()
	disable_category(CATEGORY_MESHER)

## Updates the internal debug flag from the const or environment variable.
func _update_debug_flag() -> void:
	_global_enabled = DEBUG_ENABLED
	if not _global_enabled:
		_global_enabled = OS.has_environment("VOXLY_DEBUG")
	
	# Initialize all categories to the global enabled state
	for cat in ALL_CATEGORIES:
		_categories[cat] = _global_enabled

## Ensures categories dict is initialized.
func _ensure_init() -> void:
	if _categories.is_empty():
		for cat in ALL_CATEGORIES:
			_categories[cat] = _global_enabled

## Returns true if the given category is enabled.
func is_category_enabled(category: String) -> bool:
	_ensure_init()
	return _global_enabled and _categories.get(category, false)

## Returns true if debug logging is enabled globally.
func is_enabled() -> bool:
	return _global_enabled

## Prints a debug message prefixed with [Voxly Debug] if the given category is enabled.
## Use this for all new debug logging.
func log_category(category: String, context: String, message: String) -> void:
	_ensure_init()
	if _global_enabled and _categories.get(category, false):
		print("[Voxly Debug][%s][%s] %s" % [category, context, message])

## Prints a debug message prefixed with [Voxly Debug].
## Routes through CATEGORY_GENERAL. For new code, prefer log_category().
func log(message: String) -> void:
	log_category(CATEGORY_GENERAL, "", message)

## Prints a debug message with the caller's context.
## Routes through CATEGORY_GENERAL. For new code, prefer log_category().
func log_context(context: String, message: String) -> void:
	log_category(CATEGORY_GENERAL, context, message)

## Prints a warning-level debug message (always shown regardless of debug flag).
func warn(context: String, message: String) -> void:
	push_warning("[Voxly Debug][%s] %s" % [context, message])

## Prints an error message (always shown).
func error(context: String, message: String) -> void:
	push_error("[Voxly Debug][%s] %s" % [context, message])

## Enables a specific category.
func enable_category(category: String) -> void:
	_ensure_init()
	_categories[category] = true
	print("[Voxly Debug] Enabled category: %s" % category)

## Disables a specific category.
func disable_category(category: String) -> void:
	_ensure_init()
	_categories[category] = false
	print("[Voxly Debug] Disabled category: %s" % category)

## Convenience to enable all debug logging at runtime.
func enable() -> void:
	_global_enabled = true
	for cat in ALL_CATEGORIES:
		_categories[cat] = true
	print("[Voxly Debug] All categories enabled")

## Convenience to disable all debug logging at runtime.
func disable() -> void:
	_global_enabled = false
	for cat in ALL_CATEGORIES:
		_categories[cat] = false
	print("[Voxly Debug] All categories disabled")

## Returns a string showing which categories are currently enabled/disabled.
func get_enabled_categories() -> String:
	_ensure_init()
	var parts: PackedStringArray = []
	for cat in ALL_CATEGORIES:
		var status := "ON" if _categories.get(cat, false) else "OFF"
		parts.append("%s=%s" % [cat, status])
	var result := "VoxlyDebug categories: [%s]" % ", ".join(parts)
	print(result)
	return result
