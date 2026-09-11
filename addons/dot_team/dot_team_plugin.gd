@tool
extends EditorPlugin

## Editor entry point for dot-team. Registers inspector types only.

const _ICON := "res://addons/dot_team/icon_placeholder.svg"

const _TYPES := [
	["DotTeamRoster", "Node", "res://addons/dot_team/runtime/dot_team_roster.gd"],
	["DotTeamSpectate", "Node", "res://addons/dot_team/runtime/dot_team.gd"],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
