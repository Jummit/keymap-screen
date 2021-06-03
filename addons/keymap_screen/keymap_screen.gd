extends Panel

"""
A dialog to configure shortcuts

Set `keymap` to a dictionary with action and sub-entries.

Example:
```
keymap = {
		Section = {
			"Action Name": "action_name",
			SubSection = {
				"Another Action": "another_action",
			}
		}
	}
```

The edited keymap can be saved and loaded using `save_keymap` and `load_keymap`.
"""

var keymap : Dictionary setget set_keymap

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

var NO_EVENT := InputEventKey.new()

onready var tree : Tree = $VBoxContainer/Tree
onready var search_edit : LineEdit = $VBoxContainer/SearchEdit

func _ready() -> void:
	search_edit.right_icon = preload("search_icon.svg")


func _input(event : InputEvent) -> void:
	if _editing_action and is_instance_valid(_editing_button) and event is InputEventKey:
		if event.scancode == KEY_ESCAPE:
			# Cancel shortcut input.
			_editing_action = ""
			set_keymap(keymap)
			return
		_editing_button.text = event.as_text()
		if not event.scancode in [KEY_SHIFT, KEY_CONTROL, KEY_ALT]:
			# Action contains an actual key, storing the action.
			_try_set_event(_editing_action, event)
		else:
			# Wait for more input.
			_editing_button.text += "..."


func set_keymap(to : Dictionary) -> void:
	keymap = to
	_actions.clear()
	_action_names.clear()
	tree.clear()
	tree.set_column_titles_visible(true)
	tree.set_column_title(0, "Action")
	tree.set_column_title(1, "Shortcut")
	tree.set_column_min_width(2, 18)
	tree.set_column_expand(2, false)
	_load_section(keymap, tree.create_item())
	yield(get_tree(), "idle_frame")
	_update_buttons()

# Stores the current keymap in a json file.
func save_keymap(path : String) -> void:
	var file := File.new()
	file.open(path, File.WRITE)
	var data := {}
	for action in _actions:
		var event := _get_action_event(action)
		data[action] = "" if event == NO_EVENT else var2str(event)
	file.store_string(to_json(data))
	file.close()


# Loads a keymap from a json file.
func load_keymap(path : String) -> void:
	var file := File.new()
	file.open(path, File.READ)
	var data : Dictionary = parse_json(file.get_as_text())
	for action in data:
		if not data[action]:
			InputMap.action_erase_events(action)
		else:
			_set_event(action, str2var(data[action]))
	file.close()
	set_keymap(keymap)


# Constructs the tree of a keymap section.
func _load_section(section : Dictionary, root : TreeItem) -> bool:
	var did_add_action := false
	for key in section:
		var value = section[key]
		if value is Dictionary:
			var section_root := tree.create_item(root)
			section_root.set_text(0, key)
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
			key_item.set_metadata(0, value)
			var action := _get_action_event(value)
			if action != NO_EVENT:
				key_item.add_button(ButtonColumn.CLEAR,
						preload("clear_icon.svg"), -1, false,
						"Clear the shortcut")
			if value in _defaults:
				# Show reset button if the shortcut was changed.
				if action.get_scancode_with_modifiers() !=\
						_defaults[value].get_scancode_with_modifiers():
					key_item.add_button(ButtonColumn.RESET,
							preload("reset_icon.svg"), -1, false,
							"Reset to default shortcut")
			else:
				# Store the default shortcut for this action.
				_defaults[value] = action
	return did_add_action


# Add buttons to visible action tree items.
func _update_buttons() -> void:
	for child in tree.get_children():
		if child is Button:
			child.queue_free()
	var item := tree.get_root().get_children()
	while item != null:
		var data = item.get_metadata(0)
		if data:
			var button := Button.new()
			var actions := InputMap.get_action_list(data)
			if actions.size():
				button.text = actions.front().as_text()
			var rect := tree.get_item_area_rect(item, 1)
			rect.size.x -= 50
			tree.add_child(button)
			button.rect_position = rect.position
			button.rect_size = rect.size
			button.hint_tooltip = 'Configure the shortcut of "%s"' %\
					_action_names[data]
			button.connect("pressed", self, "_on_KeyButton_pressed", [button,
					data])
		item = item.get_next_visible()


# Tries to set the shortcut of an action, showing a dialog if any duplicates
# where found.
func _try_set_event(action : String, event : InputEventKey) -> void:
	if event == NO_EVENT:
		# Clear the shortcut.
		InputMap.action_erase_events(action)
		set_keymap(keymap)
		return
	# Check for duplicates.
	var duplicate_of : String
	for dup_action in _actions:
		if dup_action == action:
			continue
		if event.get_scancode_with_modifiers() ==\
				_get_action_event(dup_action).get_scancode_with_modifiers():
			duplicate_of = dup_action
			break
	if duplicate_of:
		$ReassignConfirmationDialog.dialog_text = POPUP_TEXT % [
				event.as_text(), _action_names[duplicate_of]]
		$ReassignConfirmationDialog.popup()
		_action_to_replace = duplicate_of
		_editing_action = action
		_selected_event = event
	else:
		_set_event(action, event)
		set_keymap(keymap)


func _set_event(action : String, event : InputEventKey) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)


func _get_action_event(action : String) -> InputEventKey:
	return NO_EVENT if not InputMap.get_action_list(action).size()\
					else InputMap.get_action_list(action).front()


func _on_KeyButton_pressed(button : Button, action : String) -> void:
	_editing_action = action
	_editing_button = button
	_editing_button.text = "Input..."


func _on_Tree_item_collapsed(item: TreeItem) -> void:
	_update_buttons()


func _on_ReassignConfirmationDialog_confirmed() -> void:
	InputMap.action_erase_events(_action_to_replace)
	_set_event(_editing_action, _selected_event)
	set_keymap(keymap)
	_editing_action = ""


func _on_ReassignConfirmationDialog_hide() -> void:
	set_keymap(keymap)


func _on_Tree_button_pressed(item : TreeItem, column : int, _id : int) -> void:
	match column:
		ButtonColumn.RESET:
			_try_set_event(item.get_metadata(0), _defaults[item.get_metadata(0)])
		ButtonColumn.CLEAR:
			_try_set_event(item.get_metadata(0), NO_EVENT)
	set_keymap(keymap)


func _on_SearchEdit_text_changed(new_text : String) -> void:
	_filter = new_text.to_lower()
	set_keymap(keymap)


func _on_resized() -> void:
	if tree.get_root():
		_update_buttons()
