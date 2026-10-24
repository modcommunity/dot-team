@tool
class_name DotTeamBlockConfig
extends DotConfig

## Whether players stop at each other, by relation. The boot defaults of the `mp_teamblock`
## family of cvars; [DotTeamBlockRules.bind_cvars] makes them live.

## Whether teammates stop at each other. Off: they walk through.
@export var team_block: bool = false

## Whether enemies stop at each other.
@export var enemy_block: bool = true

## Who may type the block commands: 0 nobody, 1 admins, 2 everyone.
@export_range(0, 2, 1) var command_mode: int = 2

## Which relations the commands may change: 1 teammates, 2 enemies, 3 both. Passing through
## an enemy is a gameplay change, so the default leaves it to the server.
@export_range(1, 3, 1) var command_relations: int = 1

## Whose collision a command changes: 0 the caller's own, 1 the caller's whole team.
@export_range(0, 1, 1) var scope: int = 0

## The permission an admin needs when [member command_mode] is 1.
@export var admin_permission: String = "generic"


func env_prefix() -> String:
	return "DOT_TEAM_BLOCK_"


func cli_prefix() -> String:
	return "--team-block-"
