@tool
class_name DotTeamSet
extends Resource

## The sides a session has, in order, with the presets that cover most games.

const CHANNEL := "team.set"

## The id used for "has not picked yet", which is not the same as spectating.
const UNASSIGNED := &"unassigned"

## The id used for watching.
const SPECTATOR := &"spectator"

@export var id: StringName = &""

@export var teams: Array[DotTeamDef] = []

var _by_id: Dictionary = {}
var _built: bool = false


func build() -> DotResult:
	_by_id.clear()

	if teams.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "A team set with no teams.")

	for t in teams:
		if t == null or t.id == &"":
			return DotResult.fail(DotError.CODE_INVALID, "A team with no id.")

		if _by_id.has(t.id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Two teams are called '%s'." % String(t.id),
				"Every lookup would answer about the second one, silently."
			)

		_by_id[t.id] = t

	if playing_teams().is_empty():
		return DotResult.fail(
			DotError.CODE_INVALID,
			"No team in this set plays.",
			"A round whose only sides are spectators cannot end: nobody can be "
			+ "eliminated and nobody can score."
		)

	_built = true
	return DotResult.success(null)


func _ensure_built() -> void:
	if not _built or _by_id.size() != teams.size():
		var res := build()
		if not res.ok:
			DotLog.error(CHANNEL, "team set unusable", {"why": res.error.message})


func has_team(team_id: StringName) -> bool:
	_ensure_built()
	return _by_id.has(team_id)


func get_team(team_id: StringName) -> DotTeamDef:
	_ensure_built()
	return _by_id.get(team_id, null)


## Every side that actually plays, in declared order.
func playing_teams() -> Array[DotTeamDef]:
	var out: Array[DotTeamDef] = []

	for t in teams:
		if t != null and t.playing:
			out.append(t)

	return out


func playing_ids() -> Array[StringName]:
	var out: Array[StringName] = []

	for t in playing_teams():
		out.append(t.id)

	return out


func ids() -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []

	for t in teams:
		if t != null:
			out.append(t.id)

	return out


func is_playing(team_id: StringName) -> bool:
	var t := get_team(team_id)
	return t != null and t.playing


## Whether two sides are enemies.
##
## False for the same side, false when either is not playing, and false for anything
## unknown. A spectator is nobody's enemy, and a hit registration that asked
## "is this not my team?" would treat them as one.
func are_enemies(a: StringName, b: StringName) -> bool:
	if a == b:
		return false

	return is_playing(a) and is_playing(b)


## The colour of a side, or white.
func colour_of(team_id: StringName) -> Color:
	var t := get_team(team_id)
	return t.colour if t != null else Color.WHITE


func display_of(team_id: StringName) -> String:
	var t := get_team(team_id)
	return t.display_name if t != null else String(team_id)


## The sides in scoreboard order: sort_order, then id, with non-playing last.
func sorted_teams() -> Array[DotTeamDef]:
	var out := teams.duplicate()

	out.sort_custom(func(a: DotTeamDef, b: DotTeamDef) -> bool:
		if a.playing != b.playing:
			return a.playing
		if a.sort_order != b.sort_order:
			return a.sort_order < b.sort_order
		return String(a.id) < String(b.id)
	)

	var typed: Array[DotTeamDef] = []
	for t: Variant in out:
		typed.append(t as DotTeamDef)

	return typed


func describe_lines() -> PackedStringArray:
	_ensure_built()
	var out := PackedStringArray()
	out.append("team set %s: %d teams" % [String(id), teams.size()])

	for t in teams:
		if t != null:
			out.append("  " + t.describe())

	return out


func describe() -> String:
	return "DotTeamSet(%s, %d teams)" % [String(id), teams.size()]


func _to_string() -> String:
	return describe()


# --- Presets ----------------------------------------------------------------

## Two sides, plus spectators and an unassigned holding pen.
##
## [b]Four entries, not two, and the two extras are the ones that get forgotten.[/b] A
## player who has connected but not chosen is not on a team and is not a spectator, and
## a set with no id for that state ends up representing it as the empty string — which
## then matches nothing, or matches everything, depending on which comparison runs.
static func standard_pair(
	a: StringName = &"blue",
	b: StringName = &"red"
) -> DotTeamSet:
	var set := DotTeamSet.new()
	set.id = &"pair"
	set.teams = [
		_holding_pen(),
		DotTeamDef.make(a, String(a).capitalize(), Color(0.35, 0.55, 0.95)),
		DotTeamDef.make(b, String(b).capitalize(), Color(0.90, 0.35, 0.30)),
		_spectators(),
	]
	set.teams[1].sort_order = 1
	set.teams[2].sort_order = 2
	var _res := set.build()
	return set


## One playing side. What a deathmatch, a co-operative mode or a timer server has.
##
## Free-for-all is not "no teams": it is one team, with friendly fire on. Modelling it
## as no teams means every consumer branches on whether teams exist, and the branch
## nobody wrote is the one that matters.
static func free_for_all() -> DotTeamSet:
	var set := DotTeamSet.new()
	set.id = &"ffa"

	var all := DotTeamDef.make(&"players", "Players", Color(0.85, 0.85, 0.85))
	all.friendly_fire = true
	all.sort_order = 1

	set.teams = [_holding_pen(), all, _spectators()]
	var _res := set.build()
	return set


## Two playing sides with roles: one attacks, one defends.
static func attack_defend(
	attackers: StringName = &"attackers",
	defenders: StringName = &"defenders"
) -> DotTeamSet:
	var set := standard_pair(attackers, defenders)
	set.id = &"attack_defend"
	set.get_team(attackers).attributes = {"attacks": true}
	set.get_team(defenders).attributes = {"attacks": false}
	return set


## Four sides, for a squad mode or a large objective map.
static func four_way() -> DotTeamSet:
	var set := DotTeamSet.new()
	set.id = &"four_way"
	set.teams = [
		_holding_pen(),
		DotTeamDef.make(&"blue", "Blue", Color(0.35, 0.55, 0.95)),
		DotTeamDef.make(&"red", "Red", Color(0.90, 0.35, 0.30)),
		DotTeamDef.make(&"green", "Green", Color(0.35, 0.80, 0.45)),
		DotTeamDef.make(&"yellow", "Yellow", Color(0.95, 0.82, 0.30)),
		_spectators(),
	]

	for i in range(1, 5):
		set.teams[i].sort_order = i

	var _res := set.build()
	return set


static func _holding_pen() -> DotTeamDef:
	var t := DotTeamDef.make(UNASSIGNED, "Unassigned", Color(0.6, 0.6, 0.6), false)
	t.short_name = "—"
	t.sort_order = 100
	return t


static func _spectators() -> DotTeamDef:
	var t := DotTeamDef.make(SPECTATOR, "Spectators", Color(0.55, 0.55, 0.65), false)
	t.short_name = "SPEC"
	t.sort_order = 101
	return t


static func presets() -> Dictionary:
	return {
		&"pair": Callable(DotTeamSet, "standard_pair"),
		&"ffa": Callable(DotTeamSet, "free_for_all"),
		&"attack_defend": Callable(DotTeamSet, "attack_defend"),
		&"four_way": Callable(DotTeamSet, "four_way"),
	}


static func preset(p_id: StringName) -> DotTeamSet:
	var table := presets()

	if not table.has(p_id):
		return null

	var fn: Callable = table[p_id]
	return fn.call() as DotTeamSet
