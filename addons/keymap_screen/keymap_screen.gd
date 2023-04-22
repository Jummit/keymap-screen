extends Panel

## A dialog to configure shortcuts
##
## Set [member keymap] to a dictionary with action and sub-entries.
## [br][br]
## [b]Example:[/b]
## [br]
## [codeblock]
##     keymap = {
##         Application = {
##             "Window": "toggle_fullscreen",
##             "File": {
##                 "Another Action": "save",
##             }
##         }
##     }
## [/codeblock]
## [br]
## The edited keymap can be saved and loaded using [method save_keymap] and [method load_keymap].

## Emitted when the user changes a shortcut or a keymap is loaded.
signal keymap_changed

var keymap : Dictionary:
	set = set_keymap

const POPUP_TEXT := '"%s" conflicts with the shortcut of "%s".\nDo you want to clear the shortcut of this action?'

enum ButtonColumn {
	CLEAR = 1,
	RESET = 2,
}

var _editing_button : Button
var _editing_action : String
var _selected_event : InputEventKey
var _action_to_replace : String

var _filter : String

var _actions : Array
var _action_names : Dictionary
var _defaults : Dictionary
var _cached_scroll : Vector2
var _collapsed : Array
var _listeners : Dictionary

@onready var tree : Tree = $VBoxContainer/Tree
@onready var search_edit : LineEdit = $VBoxContainer/SearchEdit
@onready var reassign_confirmation_dialog: ConfirmationDialog = $ReassignConfirmationDialog

func _ready() -> void:
	search_edit.right_icon = preload("search_icon.svg")


func _input(event : InputEvent) -> void:
	if not _editing_action.is_empty() and is_instance_valid(_editing_button) and event is InputEventKey:
		if event.keycode == KEY_ESCAPE:
			# Cancel shortcut input.
			_editing_action = ""
			set_keymap(keymap)
			return
		_editing_button.text = event.as_text()
		if not event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT]:
			# Action contains an actual key, storing the action.
			_try_set_event(_editing_action, event)
		else:
			# Wait for more input.
			_editing_button.text += "..."
	if tree.get_scroll() != _cached_scroll:
		_update_buttons()
		_cached_scroll = tree.get_scroll()


## Register a menu whose shortcut will be updated when the keymap changes.
## The list of actions represents the items of the menu.
func register_menu(menu : PopupMenu, actions : PackedStringArray) -> void:
	_listeners[menu] = actions


## Register a button whose shortcut will be updated when the keymap changes.
func register_button(button : Button, action : String) -> void:
	_listeners[button] = action


# Register a list of multiple listeners, either MenuButtons, Buttons or
# PopupMenus. Example:
# register_listeners({button: "test", menu: ["action", "stuff"]})
func register_listeners(listeners : Dictionary) -> void:
	for listener in listeners:
		if listener is MenuButton:
			register_menu(listener.get_popup(), listeners[listener])
		elif listener is Button:
			register_button(listener, listeners[listener])
		elif listener is PopupMenu:
			register_menu(listener, listeners[listener])


func set_keymap(to : Dictionary) -> void:
	keymap = to
	_actions.clear()
	_action_names.clear()
	# Prevent collapsed signals.
	tree.set_block_signals(true)
	tree.clear()
	tree.set_column_titles_visible(true)
	tree.set_column_title(0, "Action")
	tree.set_column_title(1, "Shortcut")
	tree.set_column_custom_minimum_width(2, 18)
	tree.set_column_expand(2, false)
	_load_section(keymap, tree.create_item())
	await get_tree().process_frame
	tree.set_block_signals(false)
	_update_buttons()


## Stores the current keymap in a JSON file.
func save_keymap(path : String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file.get_error() != OK:
		return
	var data := {}
	for action in _actions:
		var event := _get_action_event(action)
		data[action] = "" if not event else var_to_str(event)
	file.store_string(JSON.stringify(data))
	file.close()


## Loads a keymap from a JSON file.
func load_keymap(path : String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file.get_error() != OK:
		return
	var data : Dictionary = JSON.parse_string(file.get_as_text())
	for action in data:
		if data[action] == null:
			InputMap.action_erase_events(action)
		else:
			_set_event(action, str_to_var(data[action]))
	file.close()
	set_keymap(keymap)
	_on_keymap_changed()


## Constructs the tree of a keymap section.
func _load_section(section : Dictionary, root : TreeItem) -> bool:
	var did_add_action := false
	for key in section:
		var value = section[key]
		if value is Dictionary:
			var section_root := tree.create_item(root)
			section_root.set_text(0, key)
			section_root.set_selectable(0, false)
			section_root.set_metadata(0, {section = key})
			section_root.set_selectable(1, false)
			section_root.collapsed = key in _collapsed
			if not _load_section(value, section_root):
				# Remove the section if no actions where added.
				root.remove_child(section_root)
			else:
				did_add_action = true
		else:
			_actions.append(value)
			_action_names[value] = key
			if _filter and not ((_filter in key.to_lower()) or (_filter in value.replace("_", " ").to_lower())):
				continue
			did_add_action = true
			var key_item := tree.create_item(root)
			key_item.set_text(0, key)
			key_item.set_metadata(0, {action = value})
			var action := _get_action_event(value)
			if action:
				key_item.add_button(ButtonColumn.CLEAR,
						preload("clear_icon.svg"), -1, false,
						"Clear the shortcut")
			if value in _defaults:
				# Show reset button if the shortcut was changed.
				var default : InputEventKey = _defaults[value]
				var changed := (not default) != (not action)
				if default and action and action.get_keycode_with_modifiers() != default.get_keycode_with_modifiers():
					changed = true
				if changed:
					key_item.add_button(ButtonColumn.RESET,
							preload("reset_icon.svg"), -1, false,
							"Reset to default shortcut")
			else:
				# Store the default shortcut for this action.
				_defaults[value] = action
	return did_add_action


## Add buttons to visible action tree items.
func _update_buttons() -> void:
	for child in tree.get_children():
		if child is Button:
			child.queue_free()
	var item := tree.get_root().get_first_child()
	while item != null:
		var data : Dictionary = item.get_metadata(0)
		var rect := tree.get_item_area_rect(item, 1)
		rect.position -= tree.get_scroll()
		rect.size.x -= 50
		rect.position.y += 5
		if data.get("action") and rect.position.y > 20:
			var action : String = data.action
			var button := Button.new()
			var events := InputMap.action_get_events(action)
			if events.size():
				button.text = events.front().as_text()
			tree.add_child(button)
			button.position = rect.position
			button.size = rect.size
			button.tooltip_text = 'Configure the shortcut of "%s"' %\
					_action_names[action]
			button.pressed.connect(_on_KeyButton_pressed.bind(button, action))
		item = item.get_next_visible()


## Tries to set the shortcut of an action, showing a dialog if any duplicates
## where found.
func _try_set_event(action : String, event : InputEventKey) -> void:
	if not event:
		# Clear the shortcut.
		InputMap.action_erase_events(action)
		set_keymap(keymap)
		_on_keymap_changed()
		return
	# Check for duplicates.
	var duplicate_of : String
	for dup_action in _actions:
		if dup_action == action:
			continue
		var other := _get_action_event(dup_action)
		if other and event.get_keycode_with_modifiers() == other.get_keycode_with_modifiers():
			duplicate_of = dup_action
			break
	if duplicate_of:
		reassign_confirmation_dialog.dialog_text = tr(POPUP_TEXT) % [
				event.as_text(), _action_names[duplicate_of]]
		reassign_confirmation_dialog.popup()
		_action_to_replace = duplicate_of
		_editing_action = action
		_selected_event = event
	else:
		_set_event(action, event)
		set_keymap(keymap)
		_on_keymap_changed()


func _set_event(action : String, event : InputEventKey) -> void:
	InputMap.action_erase_events(action)
	if event:
		InputMap.action_add_event(action, event)


func _get_action_event(action : String) -> InputEventKey:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return null
	return events.front()


func _on_KeyButton_pressed(button : Button, action : String) -> void:
	_editing_action = action
	_editing_button = button
	_editing_button.text = "Input..."


func _on_keymap_changed() -> void:
	for listener in _listeners:
		if listener is Button:
			var action := _get_action_event(_listeners[listener])
			var shortcut : Shortcut
			if action:
				shortcut = Shortcut.new()
				shortcut.shortcut = action
			listener.shortcut = shortcut
		elif listener is PopupMenu:
			for id in _listeners[listener].size():
				var action := _get_action_event(_listeners[listener][id])
				var shortcut : Shortcut
				if action:
					shortcut = Shortcut.new()
					shortcut.shortcut = action
				listener.set_item_shortcut(id, shortcut)
	emit_signal("keymap_changed")


func _on_Tree_item_collapsed(item : TreeItem) -> void:
	var section : String = item.get_metadata(0).section
	if section in _collapsed:
		_collapsed.erase(section)
	else:
		_collapsed.append(section)
	await get_tree().process_frame
	set_keymap(keymap)


func _on_ReassignConfirmationDialog_confirmed() -> void:
	InputMap.action_erase_events(_action_to_replace)
	_set_event(_editing_action, _selected_event)
	set_keymap(keymap)
	_editing_action = ""


func _on_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	var action : String = item.get_metadata(0).action
	match column:
		ButtonColumn.RESET:
			_try_set_event(action, _defaults[action])
		ButtonColumn.CLEAR:
			_try_set_event(action, null)
	set_keymap(keymap)


func _on_SearchEdit_text_changed(new_text : String) -> void:
	_filter = new_text.to_lower()
	set_keymap(keymap)


func _on_resized() -> void:
	if tree and tree.get_root():
		_update_buttons()


func _on_reassign_confirmation_dialog_visibility_changed() -> void:
	if not reassign_confirmation_dialog.visible:
		set_keymap(keymap)
