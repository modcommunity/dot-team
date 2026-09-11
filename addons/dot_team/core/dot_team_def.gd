@tool
class_name DotTeamDef
extends Resource

## One side, and everything any other addon needs to know about it.
##
## [b]Not called [code]DotTeam[/code].[/b] dot-match already has a class by that name —
## its own, smaller, match-scoped notion of a side — and [code]class_name[/code] is
## global in Godot, so the two would collide in any project that installed both. The
## name is the price of the two addons being independently installable, which they are
## on purpose: a deathmatch needs dot-match's and nothing else.
##
## A definition is [i]data every consumer reads[/i], which is why the attribute list is
## open-ended: dot-chat wants a colour, dot-objective wants to know which side attacks,
## dot-spawn wants a site group, and none of them should need a change here to get it.

## The name everything else uses. [code]&"blue"[/code], [code]&"ct"[/code].
@export var id: StringName = &""

## What a player sees.
@export var display_name: String = ""

## Short form for a scoreboard column or a chat prefix.
@export var short_name: String = ""

## The side's colour, for the HUD, the scoreboard, chat and a minimap.
##
## Here rather than in a theme because five addons want the same answer and a colour
## defined in five places is five colours.
@export var colour: Color = Color.WHITE

@export_group("Role")

## Whether this side plays. False for spectators and for an unassigned holding pen.
##
## [b]The single most-read field in the file.[/b] Balance ignores non-playing sides,
## win conditions ignore them, the scoreboard sorts them last, and a game that treats
## "spectator" as just another team ends up with a round that cannot end because the
## spectators are still alive.
@export var playing: bool = true

## Whether members can hurt each other. Read by dot-combat through the game.
@export var friendly_fire: bool = false

## How many may be on this side. Zero is unlimited.
@export_range(0, 1024, 1) var max_players: int = 0

## Sites on this side, for dot-spawn. Empty means the side's own id is used.
@export var spawn_group: StringName = &""

@export_group("Scoring")

## Multiplier on what this side's kills and objectives are worth.
##
## For asymmetric modes where one side is deliberately outnumbered or outgunned.
@export_range(0.0, 100.0, 0.01) var score_multiplier: float = 1.0

## Where this side sits in a scoreboard, low first. Ties fall back to [member id].
@export var sort_order: int = 0

@export_group("Anything else")

## Open-ended per-side data other addons and the game read.
##
## [code]{"attacks": true}[/code], [code]{"announcer": "blue_wins"}[/code],
## [code]{"icon": "res://ui/blue.png"}[/code]. Deliberately untyped and deliberately
## not a fixed list: the alternative is this file gaining a field every time another
## addon needs one, and then every game re-exporting it.
@export var attributes: Dictionary = {}


static func make(
	p_id: StringName,
	p_display: String = "",
	p_colour: Color = Color.WHITE,
	p_playing: bool = true
) -> DotTeamDef:
	var t := DotTeamDef.new()
	t.id = p_id
	t.display_name = p_display if p_display != "" else String(p_id).capitalize()
	t.short_name = t.display_name.substr(0, 3).to_upper()
	t.colour = p_colour
	t.playing = p_playing
	return t


## The spawn group dot-spawn should ask for.
func spawn_id() -> StringName:
	return spawn_group if spawn_group != &"" else id


## An attribute, with a default rather than a crash.
func attribute(key: String, fallback: Variant = null) -> Variant:
	return attributes.get(key, fallback)


func attribute_is(key: String, want: Variant) -> bool:
	# DotValue rather than ==: attributes come out of a level file or a game mode, so
	# neither side's Variant type is under this file's control, and == on mismatched
	# types is a runtime error that abandons the expression.
	return DotValue.same(attributes.get(key, null), want)


func describe() -> String:
	return "%s (%s)%s%s" % [
		String(id),
		display_name,
		"" if playing else " [not playing]",
		"" if max_players == 0 else " max %d" % max_players,
	]


func _to_string() -> String:
	return "DotTeamDef(%s)" % describe()
