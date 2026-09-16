@tool
extends EditorPlugin

## Editor entry point for dot-team. Registers inspector types only.

const _ICON := "res://addons/dot_team/icon_placeholder.svg"

const _TYPES := [
	["DotTeamRoster", "Node", "res://addons/dot_team/runtime/dot_team_roster.gd"],
	# [b]`dot_team_spectate.gd`, and it said `dot_team.gd` for as long as the file has had
	# its current name.[/b] A rename left this one reference behind, so every project that
	# enables this plugin logged three errors at import — *"Attempt to open script … 'File
	# not found'"*, the failed load, and *"It's not a reference to a valid Script object"* —
	# and `DotTeamSpectate` never appeared in the editor's Create Node dialog.
	#
	# It cost nothing at RUNTIME, which is why it survived: the `class_name` in the script
	# registers the global on its own and has always worked, so every game using the type in
	# code was fine. What was broken is the half only the editor sees, and three errors at
	# the top of an import log are three errors people scroll past.
	["DotTeamSpectate", "Node", "res://addons/dot_team/runtime/dot_team_spectate.gd"],
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
