@tool
class_name VoxlyUIManager
extends RefCounted
## Manages the lifecycle of docks in Godot editor for the Voxly editor.
## Supports simultaneous display: the VoxelSet editor lives in a side editor dock,
## while VoxelNode3D editor also lives in a bottom editor dock.
##
## Docks are spawned once and reused across node/set switches: switching content
## just re-syncs the existing docks. Each dock independently remembers whether
## they're dismissed (switched to the Inspector, another dock/tab in its
## slot, or closed it via the context popup). While a dock is dismissed, node
## selection syncs its content without re-opening it; however, actions
## (clicking its tab/button, Editor > Editor Docks) or a context change
## (deselect, non-voxel selection, leaving 3D) clear dismissal.
## Ending the editing context fully closes the docks (tabs removed); the cached
## instances are still reused and reopen in their remembered slots on the next
## voxel selection.
##
## VoxelSetEditorDock coordination:
## - If the VoxelNode3D being viewed has a VoxelSet, VoxelSetEditorDock is shown.
## - If the VoxelNode3D has no VoxelSet, only VoxelNode3DEditorDock is shown (with notice).
## - When "Add VoxelSet" is pressed, a new VoxelSet is created and assigned.
##
## Palette coordination:
## - Selecting a single voxel in VoxelSetEditorDock sets it as palette for VoxlyEditor.
## - Selecting none or multiple voxels clears the palette and disables editing.

const DEBUG_CONTEXT := "VoxlyUIManager"

const VOXEL_SET_DOCK_PATH := "res://addons/voxly-core/editor/docks/voxel_set_editor_dock/voxel_set_editor_dock.tscn"
const VOXEL_NODE_3D_DOCK_PATH := "res://addons/voxly-core/editor/docks/voxel_node_3d_editor_dock/voxel_node_3d_editor_dock.tscn"

signal dock_shown(dock_type: String)

signal dock_hidden(dock_type: String)

## Enum of dock types this manager can show.
enum DockType {
	NONE,
	VOXEL_SET_EDITOR,
	VOXEL_OBJECT_EDITOR,
}

var _editor_plugin: EditorPlugin
var _state_machine: VoxlyStateMachine
var _input_handler: VoxlyInputHandler

## Currently active dock Control node.
var _bottom_dock: Control = null
var _bottom_dock_type: DockType = DockType.NONE

## VoxelSet editor dock, managed separately so it can coexist.
var _voxel_set_dock: EditorDock = null

## Spawned docks, keyed by scene path. Docks are created once and reused.
var _spawned_docks: Dictionary = {}

## Docks already added to the editor, keyed by scene path (true when registered).
var _added_docks: Dictionary = {}

## True when the VoxelSet dock was opened because a VoxelNode3D was selected
## (rather than a standalone VoxelSet resource). A coupled dock shares the
## node editor's 3D-only lifetime: leaving the 3D view hides it too.
var _voxel_set_dock_coupled_to_node: bool = false

## Per-dock user dismissal state, keyed by dock scene path. True when the user
## dismissed that dock (closed it via the context popup, or switched to another
## dock/tab in its slot). While dismissed, node/set changes sync the dock's
## content without re-opening it. Resets when the editing context ends
## (deselect, non-voxel selection, leaving 3D) so a fresh context reopens.
var _dock_dismissed: Dictionary = {}

## Per-dock "has ever been shown" state, keyed by dock scene path. Used to
## ignore visibility_changed(false) events that fire during dock creation
## before the dock has ever been shown, only a visible-then-hidden dock
## counts as user-dismissed.
var _dock_has_been_shown: Dictionary = {}

## Guards signal handlers from treating our own dock adds/removes as
## user actions.
var _setting_docks_up: bool = false

## Guards signal handlers from treating our own close()/make_visible() calls
## as user dismissals. Dismissal is only recorded when user moves focus
## away (tab switch, another dock in the slot, context-popup close), never
## our own programmatic sync.
var _syncing_docks: bool = false

## The active VoxlyModelController.
var _active_controller: VoxelNode3DController = null

## Tracks the 3D editor's transform tool mode so we can force Select mode
## while editing voxels and restore the user's previous mode on exit.
var _transform_tracker: VoxlyTransformModeTracker = null

func _init(plugin: EditorPlugin, state_machine: VoxlyStateMachine) -> void:
	_editor_plugin = plugin
	_state_machine = state_machine
	_input_handler = plugin._input_handler
	_transform_tracker = VoxlyTransformModeTracker.new(plugin)
	_state_machine.state_changed.connect(_on_state_changed)
	_state_machine.current_voxel_set_changed.connect(_on_current_voxel_set_changed)
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Initialized")

## Returns the currently active dock control.
func get_current_dock() -> Control:
	return _bottom_dock

## Returns the type of the currently active dock.
func get_current_dock_type() -> DockType:
	return _bottom_dock_type

## Returns the active controller.
func get_active_controller() -> VoxelNode3DController:
	return _active_controller

## Show a dock for the given dock type and optional node.
func show_dock(dock_type: DockType, node: Node3D = null) -> void:
	match dock_type:
		DockType.VOXEL_SET_EDITOR:
			_show_voxel_set_dock(node)
		DockType.VOXEL_OBJECT_EDITOR:
			_hide_voxel_node_dock()
			_show_voxel_node_editor_dock(node)
		_:
			return

## Hides and cleans up the current bottom dock only.
## Does not affect the VoxelSet right-side dock.
func hide_current_dock() -> void:
	_hide_voxel_node_dock()

## Closes all docks, ending the current editing context. The cached instances
## are reused and reopen on the next voxel selection.
func hide_all_docks() -> void:
	_hide_voxel_node_dock()
	_hide_voxel_set_dock()

## Should only be called on plugin exit, disposes all docks and resets the spawn cache.
func dispose_all_docks() -> void:
	_setting_docks_up = true
	if _voxel_set_dock != null:
		if _added_docks.has(VOXEL_SET_DOCK_PATH):
			_editor_plugin.remove_dock(_voxel_set_dock)
		_voxel_set_dock.queue_free()
		_voxel_set_dock = null
	if _bottom_dock != null:
		if _added_docks.has(VOXEL_NODE_3D_DOCK_PATH):
			_editor_plugin.remove_dock(_bottom_dock)
		_bottom_dock.queue_free()
		_bottom_dock = null
		_cleanup_controller()
	_bottom_dock_type = DockType.NONE
	_voxel_set_dock_coupled_to_node = false
	_spawned_docks.clear()
	_added_docks.clear()
	_setting_docks_up = false
	_syncing_docks = false
	_dock_has_been_shown.clear()
	_dock_dismissed.clear()

## Returns whether the VoxelSet right-side dock is currently visible.
func is_voxel_set_dock_visible() -> bool:
	return _voxel_set_dock != null and _voxel_set_dock.visible

## Called when the editor's main screen changes. The VoxelNode3D editor dock
## is 3D-only and is always hidden when leaving 3D. A VoxelSet dock that was
## opened via a node shares that context and is hidden too, while a
## standalone VoxelSet dock remains open across all views.
func on_main_screen_changed(screen_name: String) -> void:
	if screen_name == "3D":
		return
	
	_hide_voxel_node_dock()
	if _voxel_set_dock_coupled_to_node:
		_hide_voxel_set_dock()

func _on_state_changed(transition: VoxlyState.Transition) -> void:
	# Leaving editing mode also restore the user's previous transform tool mode.
	if transition.from_state == VoxlyState.State.EDITING_VOXEL_MODEL:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT,
			"Leaving editing, restoring transform tool mode")
		if _transform_tracker:
			_transform_tracker.set_buttons_enabled(true)
			_transform_tracker.restore_saved()
	
	match transition.to_state:
		VoxlyState.State.IDLE:
			hide_all_docks()
		
		VoxlyState.State.VIEWING_VOXEL_SET:
			_show_voxel_set_dock(transition.selected_node)
		
		VoxlyState.State.VIEWING_VOXEL_MODEL:
			var node := transition.selected_node as VoxelNode3D
			if not node:
				return
			
			if _active_controller and _active_controller.target == node and _bottom_dock != null:
				_sync_voxel_set_for_node(node)
				return
			
			# Reuse the existing docks, no hide-then-show dance. Stopping the
			# old controller and re-syncing content in place means switching
			# nodes never flickers, never jumps tabs, and never fabricates a
			# user dismissal.
			_cleanup_controller()
			_show_voxel_node_editor_dock(node)
			if node.voxel_set:
				_show_voxel_set_dock_for_node(node)
			else:
				_hide_voxel_set_dock()
		
		VoxlyState.State.EDITING_VOXEL_MODEL:
			# Entering editing mode also remember the user's transform tool and
			# force Select mode so the transform gizmo doesn't fight painting.
			VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT,
				"Entering editing, snapshot + force Select mode")
			if _transform_tracker:
				_transform_tracker.refresh()
				_transform_tracker.snapshot_mode()
				# Only disable the toolbar if Select mode was actually applied;
				# otherwise, we'd leave the user with no active transform tool.
				if _transform_tracker.force_select():
					_transform_tracker.set_buttons_enabled(false)

func _on_current_voxel_set_changed(voxel_set: VoxelSet) -> void:
	# Content sync only, never touches visibility. The show paths decide
	# whether to make_visible() based on each dock's dismissal state.
	_sync_voxel_set_dock_state()
	if _voxel_set_dock != null and voxel_set != null and _voxel_set_dock.has_method("set_voxel_set"):
		_voxel_set_dock.set_voxel_set(voxel_set)

func _hide_voxel_node_dock() -> void:
	if _bottom_dock == null:
		return
	
	var old_type := _bottom_dock_type
	_set_dock_visible(_bottom_dock, false, VOXEL_NODE_3D_DOCK_PATH)
	_cleanup_controller()
	_bottom_dock_type = DockType.NONE
	dock_hidden.emit(DockType.keys()[old_type])
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Hidden %s dock" % DockType.keys()[old_type])


func _hide_voxel_set_dock() -> void:
	if _voxel_set_dock == null:
		return
	
	_set_dock_visible(_voxel_set_dock, false, VOXEL_SET_DOCK_PATH)
	_voxel_set_dock_coupled_to_node = false
	dock_hidden.emit("VOXEL_SET_EDITOR")
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Hidden VoxelSet right-side dock")


## Returns true when the user has explicitly dismissed the dock at this path
## (closed it, or switched to another dock/tab in its slot). Dismissed docks
## still sync content, they just don't steal focus.
func _is_dock_dismissed(path: String) -> bool:
	return _dock_dismissed.get(path, false)


## Single choke-point for every programmatic show/hide. All visibility changes
## driven by us go through here so the visibility_changed/closed/opened signal
## handlers can tell our own calls apart from the user's (see _syncing_docks).
## User dismissals are never recorded for programmatic hides.
##
## Programmatic hide always mean the editing context ended (node deselected,
## non-voxel object selected, or left the 3D view), so close() is used and the
## dock's tab is removed too. User dismissals (clicking another tab in the same
## slot) are handled by Godot itself, the tab stays, we just stop auto-showing.
func _set_dock_visible(dock: Control, visible: bool, path: String) -> void:
	if dock == null or path.is_empty():
		return
	
	_syncing_docks = true
	if visible:
		# Only (re)open/focus docks that aren't already visible. A dock that is
		# already open must not steal focus on node switches, selecting a node
		# in the Scene dock shouldn't yank the bottom panel or right dock away
		# from wherever the user is currently looking.
		if dock.visible:
			pass
		elif dock.has_method("make_visible"):
			dock.make_visible()
		else:
			dock.show()
		_dock_has_been_shown[path] = true
	else:
		# Context ended so fully close the dock (tab disappears). The cached
		# instance is still reused: the next voxel selection calls make_visible(),
		# which reopens the dock in its remembered slot. Clear dismissal AND
		# the shown flag so a fresh context always starts with the docks
		# available again, and so any deferred visibility_changed(false) from
		# close() is ignored (it can't re-poison dismissal state).
		_dock_dismissed[path] = false
		_dock_has_been_shown[path] = false
		if dock.has_method("close"):
			dock.close()
		else:
			dock.hide()
	_syncing_docks = false


## Spawns a dock scene once and caches it. Subsequent calls with the same path
## return the cached instance, so docks are reused across node/set switches.
func _create_dock(path: String) -> Control:
	if _spawned_docks.has(path):
		return _spawned_docks[path]
	
	var scene := load(path)
	if scene == null:
		return null
	
	var dock := scene.instantiate() as Control
	if dock == null:
		return null
	
	# Transient docks open/close only when we explicitly show them, layout
	# restores and shortcuts won't auto-open or auto-close them.
	dock.set("transient", true)
	_connect_dock_signals(dock, path)
	if dock.has_method("set_undo_redo_manager"):
		dock.set_undo_redo_manager(_editor_plugin.get_undo_redo())
	_spawned_docks[path] = dock
	return dock


## Returns the dock for the path, adding it to the editor the first time.
func _ensure_dock_added(path: String) -> Control:
	var dock := _create_dock(path)
	if dock == null:
		return null
	
	if not _added_docks.has(path):
		_setting_docks_up = true
		_editor_plugin.add_dock(dock)
		_setting_docks_up = false
		_added_docks[path] = true
	
	return dock


## Connects EditorDock signals that reflect whether the user is actively
## viewing the dock, so node selection can sync content without stealing
## focus once the user has dismissed the dock. Each handler gets the dock's
## scene path so dismissal state stays per-dock.
func _connect_dock_signals(dock, path: String) -> void:
	if dock == null:
		return
	
	if dock.has_signal("closed") and not dock.closed.is_connected(_on_dock_closed):
		dock.closed.connect(_on_dock_closed.bind(path))
	if dock.has_signal("opened") and not dock.opened.is_connected(_on_dock_opened):
		dock.opened.connect(_on_dock_opened.bind(path))
	if not dock.visibility_changed.is_connected(_on_dock_visibility_changed):
		dock.visibility_changed.connect(_on_dock_visibility_changed.bind(path))
	
	# Wire the VoxelSet dock's palette selection to active editor palette. This
	# connection was lost in the dock rework: docks are spawned once and reused.
	if path == VOXEL_SET_DOCK_PATH and dock.has_signal("palette_voxel_changed") \
			and not dock.palette_voxel_changed.is_connected(_on_voxel_set_dock_palette_changed):
		dock.palette_voxel_changed.connect(_on_voxel_set_dock_palette_changed)


## The user closed a dock via its context-popup Close button.
func _on_dock_closed(path: String) -> void:
	if _syncing_docks:
		return
	
	_dock_has_been_shown[path] = true
	_dock_dismissed[path] = true


## The user reopened a dock from the editor.
func _on_dock_opened(path: String) -> void:
	if _syncing_docks:
		return
	
	_dock_dismissed[path] = false


## Fires when a dock's visibility changes (tab switch, menu open/close;
## our own adds/removes/close()/make_visible() calls are guarded by
## _setting_docks_up and _syncing_docks). A dock only becomes "dismissed"
## when the user moves focus away from it, creation-time hidden states
## (before the dock was ever shown) never count.
func _on_dock_visibility_changed(path: String) -> void:
	if _setting_docks_up or _syncing_docks:
		return
	
	var dock: Control = _spawned_docks.get(path, null)
	if dock == null:
		return
	
	if dock.visible:
		_dock_has_been_shown[path] = true
		_dock_dismissed[path] = false
	elif _dock_has_been_shown.get(path, false):
		_dock_dismissed[path] = true


## Standalone VoxelSet flow (direct resource selection). Selecting a set is an
## explicit user action, so the dock's content is always synced. It only
## opens automatically when the dock hasn't been dismissed (first use or
## explicit intent), a dismissed dock refreshes in the background while the
## user stays focused on whatever they were doing (e.g. the Inspector).
func _show_voxel_set_dock(node: Node3D) -> void:
	var vs: VoxelSet = _state_machine.current_voxel_set
	if not vs:
		return
	
	_voxel_set_dock_coupled_to_node = false
	var dock := _ensure_dock_added(VOXEL_SET_DOCK_PATH)
	if not dock:
		return
	_voxel_set_dock = dock
	
	if dock.has_method("set_voxel_set"):
		dock.set_voxel_set(vs)
	_sync_voxel_set_dock_state()
	
	if not _is_dock_dismissed(VOXEL_SET_DOCK_PATH):
		_set_dock_visible(dock, true, VOXEL_SET_DOCK_PATH)
	dock_shown.emit("VOXEL_SET_EDITOR")
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Synced VoxelSet editor right-side dock")


## Node-coupled VoxelSet flow: the dock shares the node editor's 3D-only
## lifetime. Content is always synced; visibility follows user intent.
func _show_voxel_set_dock_for_node(node: VoxelNode3D) -> void:
	if not node or not node.voxel_set:
		return
	
	var vs: VoxelSet = node.voxel_set
	_state_machine.set_current_voxel_set(vs)
	_voxel_set_dock_coupled_to_node = true
	
	var dock := _ensure_dock_added(VOXEL_SET_DOCK_PATH)
	if not dock:
		return
	_voxel_set_dock = dock
	
	if dock.has_method("set_voxel_set"):
		dock.set_voxel_set(vs)
	_sync_voxel_set_dock_state()
	
	if not _is_dock_dismissed(VOXEL_SET_DOCK_PATH):
		_set_dock_visible(dock, true, VOXEL_SET_DOCK_PATH)
	dock_shown.emit("VOXEL_SET_EDITOR")
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Synced VoxelSet editor for node: %s" % node.name)


## Returns true when the VoxelSet editor dock is showing a set that doesn't
## belong to the currently active node (palette updates must be blocked).
func _is_voxel_set_dock_mismatched() -> bool:
	if not _active_controller or not is_instance_valid(_active_controller.target):
		return false
	if _voxel_set_dock == null or not _voxel_set_dock.has_method("get_current_voxel_set"):
		return false
	var node_set: VoxelSet = _active_controller.target.voxel_set
	var dock_set: VoxelSet = _voxel_set_dock.get_current_voxel_set()
	return node_set != dock_set


## Clears the active editor's palette and syncs the bottom dock display.
func _clear_palette() -> void:
	if _active_controller:
		_active_controller.editor.palette_id = -1
	if _bottom_dock and _bottom_dock.has_method("set_palette"):
		_bottom_dock.set_palette(-1)


## Shows/hides the palette-mismatch notice in the node editor dock.
func _set_palette_mismatch_notice(mismatched: bool) -> void:
	if _bottom_dock and _bottom_dock.has_method("set_palette_mismatch"):
		_bottom_dock.set_palette_mismatch(mismatched)


## Re-evaluates whether the VoxelSet dock matches the active node's set and
## syncs the palette + notice accordingly. If mismatched, the palette is
## cleared (selection events are still ignored by the gate).
func _sync_voxel_set_dock_state() -> void:
	var mismatched := _is_voxel_set_dock_mismatched()
	_set_palette_mismatch_notice(mismatched)
	if mismatched:
		_clear_palette()


## Handles palette changes from the VoxelSetEditorDock.
## Sets the palette voxel ID for the editor. Does not automatically enable editing;
## the user must toggle editing via the VoxelNode3DEditorDock checkbox.
## If the dock is showing a VoxelSet that doesn't belong to the active node,
## the palette update is ignored and the palette is cleared instead.
func _on_voxel_set_dock_palette_changed(voxel_id: int) -> void:
	if not _active_controller:
		return
	
	if _is_voxel_set_dock_mismatched():
		# Dock shows a different VoxelSet than the active node, don't apply
		# the selection as a paint palette; keep it cleared with a notice.
		_set_palette_mismatch_notice(true)
		_clear_palette()
		return
	
	_set_palette_mismatch_notice(false)
	
	# Set the palette (or clear it to -1 when none/multiple are selected).
	# Editing mode is intentionally disabled when the palette is cleared,
	# the user can continue editing; the editor dock's notice reminds them
	# to pick a palette voxel.
	_active_controller.editor.palette_id = voxel_id
	if _bottom_dock and _bottom_dock.has_method("set_palette"):
		_bottom_dock.set_palette(voxel_id)


## Keeps the VoxelSet dock's selection highlighted in sync when the palette
## changes from the 3D view (e.g. the Pick tool picks a voxel).
func _on_editor_palette_changed(voxel_id: int) -> void:
	if _voxel_set_dock and voxel_id >= 0 and _voxel_set_dock.has_method("select_voxel"):
		_voxel_set_dock.select_voxel(voxel_id)


## Single source of truth for keeping the VoxelSet dock in sync with a node.
## Content is always updated; the dock's visibility follows that dock's
## dismissal state via the show path.
func _sync_voxel_set_for_node(node: VoxelNode3D) -> void:
	if not _bottom_dock or not node:
		return
	
	var vs := node.voxel_set
	if _bottom_dock.has_method("set_voxel_set"):
		_bottom_dock.set_voxel_set(vs)
	
	if _active_controller:
		_active_controller.editor.voxel_set = vs
	
	# Show or hide VoxelSetEditorDock based on whether node has a VoxelSet
	if vs:
		_show_voxel_set_dock_for_node(node)
	else:
		_hide_voxel_set_dock()


func _show_voxel_node_editor_dock(node: Node3D) -> void:
	if not node:
		return
	
	if node is VoxelModel3D:
		_active_controller = VoxelModel3DController.new()
	else:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Unsupported node type: %s" % node.get_class())
		return
	
	_active_controller.start_editing(node)
	
	_active_controller.undo_redo = _editor_plugin.get_undo_redo()
	
	# Keep the VoxelSet dock's selection in sync when the palette changes
	# from the 3D view (e.g. the Pick tool).
	if _active_controller.editor.palette_changed.is_connected(_on_editor_palette_changed):
		_active_controller.editor.palette_changed.disconnect(_on_editor_palette_changed)
	_active_controller.editor.palette_changed.connect(_on_editor_palette_changed)
	
	# Reuse the dock if it already exists; otherwise spawn + register it.
	var dock := _ensure_dock_added(VOXEL_NODE_3D_DOCK_PATH)
	if not dock:
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Failed to create VoxelNode3D editor dock")
		_cleanup_controller()
		return
	
	_bottom_dock = dock
	_bottom_dock_type = DockType.VOXEL_OBJECT_EDITOR
	
	# Now wire everything, children are guaranteed to be ready
	if dock.has_method("set_controller"):
		dock.set_controller(_active_controller)
	
	# Set the editor title based on node type
	if dock.has_method("set_editor_title"):
		dock.set_editor_title(_get_editor_title_for_node(node))
	
	var vs = _active_controller.editor.voxel_set
	if dock.has_method("set_voxel_set"):
		dock.set_voxel_set(vs)
	
	# Wire the editing toggle from the dock to the state machine
	if dock.editing_toggled.is_connected(_on_dock_editing_toggled):
		dock.editing_toggled.disconnect(_on_dock_editing_toggled)
	dock.editing_toggled.connect(_on_dock_editing_toggled.bind(node, dock))
	
	# Wire the add voxel set request from the dock
	if dock.add_voxel_set_requested.is_connected(_on_dock_add_voxel_set_requested):
		dock.add_voxel_set_requested.disconnect(_on_dock_add_voxel_set_requested)
	dock.add_voxel_set_requested.connect(_on_dock_add_voxel_set_requested.bind(node, dock))
	
	# Wire the "VoxelSet Editor" button from the dock to show the dock
	if dock.voxel_set_editor_requested.is_connected(_on_dock_voxel_set_editor_requested):
		dock.voxel_set_editor_requested.disconnect(_on_dock_voxel_set_editor_requested)
	dock.voxel_set_editor_requested.connect(_on_dock_voxel_set_editor_requested)
	
	# Connect node signal for VoxelSet changes
	if node.voxel_set_changed.is_connected(_on_node_voxel_set_changed):
		node.voxel_set_changed.disconnect(_on_node_voxel_set_changed)
	node.voxel_set_changed.connect(_on_node_voxel_set_changed.bind(node, dock))
	
	# Editing starts disabled, ensure the checkbox reflects that
	if dock.has_method("set_editing_enabled"):
		dock.set_editing_enabled(false)
	
	if not _is_dock_dismissed(VOXEL_NODE_3D_DOCK_PATH):
		_set_dock_visible(dock, true, VOXEL_NODE_3D_DOCK_PATH)
	
	VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Shown VoxelNode3D editor dock for: %s" % node.name)
	dock_shown.emit("VOXEL_OBJECT_EDITOR")


## Handles "VoxelSet Editor" button request from the VoxelNode3DEditorDock.
## Opens the VoxelSet editor dock: creates it if needed, otherwise makes the
## existing dock visible/focused.
func _on_dock_voxel_set_editor_requested() -> void:
	if not _active_controller or not is_instance_valid(_active_controller.target):
		return
	
	var node := _active_controller.target as VoxelNode3D
	if not node or not node.voxel_set:
		return
	
	# User request, clear dismissal so the dock opens again.
	_dock_dismissed[VOXEL_SET_DOCK_PATH] = false
	_show_voxel_set_dock_for_node(node)


## Handles "Add VoxelSet" request from the VoxelNode3DEditorDock.
## Creates a new VoxelSet with a default voxel, assigns it to the target node,
## shows the VoxelSetEditorDock, and auto-selects the default voxel.
func _on_dock_add_voxel_set_requested(node: VoxelNode3D, dock) -> void:
	if not _active_controller or not node:
		return
	
	# Create a new VoxelSet with a default voxel
	var new_set := VoxelSet.new()
	var new_voxel := Voxel.new()
	var first_id := new_set.next_voxel_id() # Will be 0
	
	# For undo/redo support
	var ur := _editor_plugin.get_undo_redo()
	if ur:
		ur.create_action("Add VoxelSet to %s" % node.name, UndoRedo.MERGE_DISABLE, node)
		ur.add_do_property(node, "voxel_set", new_set)
		ur.add_do_method(new_set, "set_voxel", first_id, new_voxel)
		ur.add_undo_method(new_set, "remove_voxel", first_id)
		ur.add_undo_property(node, "voxel_set", null)
		ur.commit_action()
	else:
		node.voxel_set = new_set
		new_set.set_voxel(first_id, new_voxel)
	
	# Update the state machine and controller
	_state_machine.set_current_voxel_set(new_set)
	if _active_controller:
		_active_controller.editor.voxel_set = new_set
	
	# Update the dock notice visibility
	if dock.has_method("set_voxel_set"):
		dock.set_voxel_set(new_set)
	
	# Show the VoxelSetEditorDock with the new set
	_dock_dismissed[VOXEL_SET_DOCK_PATH] = false
	_show_voxel_set_dock_for_node(node)
	
	# Auto-select the first voxel in the dock. Needed because the earlier
	# set_voxel_set() ran against an empty
	# set, the voxel is only added when the undo action executes.
	if _voxel_set_dock and _voxel_set_dock.has_method("select_voxel"):
		_voxel_set_dock.select_voxel(first_id)


## Returns a display title for the given node type.
func _get_editor_title_for_node(node: Node3D) -> String:
	if node is VoxelModel3D:
		return "VoxelModel3D Editor"
	return "VoxelNode3D Editor"


func _on_controller_editing_toggled(enabled: bool, node: Node3D) -> void:
	if not _state_machine:
		return
	
	var result := _state_machine.toggle_editing_mode(enabled, node)
	if result and enabled:
		_wire_input_handler(true)
	elif result and not enabled:
		_wire_input_handler(false)


func _on_dock_editing_toggled(enabled: bool, node: Node3D, dock) -> void:
	if not _active_controller or not _state_machine:
		return
	
	# controller.set_editing() is already called by the dock's handler.
	# Here we just handle state machine transitions and input wiring.
	var result := _state_machine.toggle_editing_mode(enabled, node)
	if result:
		_wire_input_handler(enabled)


func _on_node_voxel_set_changed(node: VoxelNode3D, dock) -> void:
	var vs := node.voxel_set
	
	if vs:
		_state_machine.set_current_voxel_set(vs)
	else:
		_state_machine.set_current_voxel_set(null)
		# Clear palette when voxel set is removed
		if _active_controller:
			_active_controller.editor.palette_id = -1
			_active_controller.set_editing(false)
			if dock.has_method("set_editing_enabled"):
				dock.set_editing_enabled(false)
	
	if dock.has_method("set_voxel_set"):
		dock.set_voxel_set(vs)
	
	if _active_controller:
		_active_controller.editor.voxel_set = vs
	
	# Show or hide VoxelSetEditorDock based on whether node has a VoxelSet
	if vs:
		_show_voxel_set_dock_for_node(node)
	else:
		_hide_voxel_set_dock()


func _wire_input_handler(active: bool) -> void:
	if not _input_handler:
		return
	
	if active and _active_controller:
		_input_handler.editing_input_handler = Callable(_active_controller, "handle_input")
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Input handler wired to controller")
	else:
		_input_handler.editing_input_handler = Callable()
		VoxlyDebug.log_category(VoxlyDebug.CATEGORY_EDITOR_UI, DEBUG_CONTEXT, "Input handler unwired")


func _cleanup_controller() -> void:
	if not _active_controller:
		return
	
	if _active_controller.editor.palette_changed.is_connected(_on_editor_palette_changed):
		_active_controller.editor.palette_changed.disconnect(_on_editor_palette_changed)
	_wire_input_handler(false)
	_active_controller.stop_editing()
	_active_controller = null
