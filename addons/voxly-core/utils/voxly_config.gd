@tool
extends Node
## Global configuration for Voxly-Core.
##
## This is a singleton registered by the Voxly-Core plugin.
## Stores plugin editor settings as JSON files. Sections are logical groups
## (e.g. "brushes", "tools", "grid", "voxel_editor"); each call to `set_value`
## or `set_section` persists immediately.

const DEBUG_CONTEXT := "VoxlyConfig"

## Config files, settings per OS user.
const CONFIG_PATHS := {
	"voxel_node_3d_editor": "user://voxly-core/voxel_node_3d_editor.json",
	"voxel_editor": "user://voxly-core/voxel_editor.json",
}

## Runtime cache.
## Stores raw JSON data as `{ section: { key: value } }`.
var _cache: Dictionary = {}


## Returns the path for a logical config name, or "" if unknown.
func get_config_path(config_name: String) -> String:
	return CONFIG_PATHS.get(config_name, "")


## Returns the raw section dictionary for a config.
func get_section(config_name: String, section: String) -> Dictionary:
	var data := _load(config_name)
	if not data.has(section):
		return {}
	var value = data[section]
	return value if value is Dictionary else {}


## Returns a value from a section.key, or `default` if missing.
func get_value(config_name: String, section: String, key: String, default = null):
	var section_dict := get_section(config_name, section)
	return section_dict.get(key, default)


## Sets a section dictionary and persists it.
func set_section(config_name: String, section: String, values: Dictionary) -> void:
	var data := _load(config_name)
	data[section] = values
	_save(config_name)


## Sets a single value in a section and persists it.
func set_value(config_name: String, section: String, key: String, value) -> void:
	var data := _load(config_name)
	if not data.has(section) or not (data[section] is Dictionary):
		data[section] = {}
	data[section][key] = value
	_save(config_name)


## Writes every loaded config back to disk. Called on plugin unload.
func save_all() -> void:
	for config_name in _cache:
		_save(config_name)


func _load(config_name: String) -> Dictionary:
	if _cache.has(config_name):
		return _cache[config_name]
	var loaded: Dictionary = {}
	var path := get_config_path(config_name)
	if not path.is_empty() and FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var text := file.get_as_text()
			file.close()
			var json := JSON.new()
			if json.parse(text) == OK and json.data is Dictionary:
				loaded = json.data
	_cache[config_name] = loaded
	return _cache[config_name]


func _save(config_name: String) -> void:
	if not _cache.has(config_name):
		return
	var path := get_config_path(config_name)
	if path.is_empty():
		return
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var json := JSON.new()
	var text := json.stringify(_cache[config_name], "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Saved %s" % path)
