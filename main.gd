# SPDX-FileCopyrightText: 2023 Jummit
#
# SPDX-License-Identifier: GPL-3.0-or-later

extends Control

## Demo of the Keymap Screen addon.

@onready var keymap_screen: KeymapScreen = $KeymapScreen

func _ready() -> void:
	keymap_screen.keymap = {
		Actions = {
			"Do Action": "do_action",
			"Revert Action": "revert_action",
			"Advanced": {
				"Advanced Action": "advanced_action",
				"Revert Multiple Actions": "revert_multiple",
			}
		}
	}


func _on_SaveButton_pressed() -> void:
	keymap_screen.save_keymap("user://keymap.json")


func _on_LoadButton_pressed() -> void:
	keymap_screen.load_keymap("user://keymap.json")
