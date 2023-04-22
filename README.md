# Keymap Screen Addon ![Godot v4.1](https://img.shields.io/badge/Godot-v4.1-%23478cbf) ![GitHub](https://img.shields.io/github/license/Jummit/keymap-screen)

A dialog to configure shortcuts. It's primarily made for usage inside of applications, but can be used inside games as well.

Supports searching, sub-sections, conflict resolution and clearing and resetting shortcuts.

## Screenshot

![Screenshot](screenshots/screenshot.png)

## Usage

Set `keymap` to a dictionary with actions and sub-entries.

Example:

```gdscript
keymap = {
	Section = {
		"Action Name": "action_name",
		"SubSection": {
			"Another Action": "another_action",
		}
	}
}
```

The edited keymap can be saved and loaded as json files using `save_keymap` and `load_keymap`.
