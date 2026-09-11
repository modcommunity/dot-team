class_name DotTeamRoster
extends Node

## Who is on which side, authoritatively on one machine and mirrored on the rest.
##
## [b]Sides that outlive the match.[/b] dot-match's own team manager is scoped to a
## match and resets with it, which is correct for a deathmatch and wrong for a server
## where somebody joins blue, plays four maps and expects to still be blue. This holds
## the assignment for the session, enforces the policy, and can [i]drive[/i] dot-match's
## manager rather than competing with it — see [method bind_match].
##
## It works with or without dot-player. Given a roster, it reads join ticks, scores and
## liveness from the records; given nothing, a game supplies them through the callables
## and everything else is the same.

const CHANNEL := "team"

const SERVICE := &"dot_team_roster"

## Somebody's side changed. [param reason] is [code]&"joined"[/code],
## [code]&"chose"[/code], [code]&"assigned"[/code], [code]&"balanced"[/code] or
## [code]&"forced"[/code].
signal team_changed(key: String, from: StringName, to: StringName, reason: StringName)

## The sides were rebalanced. Carries every move, so a chat line can name them.
signal balanced(moves: Array)

## A switch was refused, and why. Worth a signal: "nothing happened when I clicked" is
## the worst possible answer, and a client that can say "wait 22 more seconds" is a
## client nobody reports a bug about.
signal switch_refused(key: String, to: StringName, why: String)

@export var authoritative: bool = true

@export var teams: DotTeamSet = null

@export var policy: DotTeamPolicy = null

@export var register_service: bool = true

## `func(key: String) -> bool`. Whether somebody is in the world right now.
##
## Left unset, nobody is alive, which makes every switch and every balance move legal.
## That is the right default for a lobby and the wrong one for a match, which is why a
## game that has liveness should say so.
var alive_fn: Callable = Callable()

## `func(key: String) -> float`. For the lowest-score balance rule.
var score_fn: Callable = Callable()

## `func(key: String) -> int`. When somebody joined, for the newest/oldest rules.
var joined_fn: Callable = Callable()

## Whether rounds are live, for [member DotTeamPolicy.lock_when_live].
var live_fn: Callable = Callable()

## `func() -> int`. The current tick, for a bound match manager that wants one.
##
## dot-match records a join tick when it assigns somebody. Zero is survivable — it
## means "joined at the start" — but an idle-kick or a session-length statistic reading
## it would then be wrong for everybody, so a game that has a tick should supply it.
var match_tick_fn: Callable = Callable()

## Seed for the random victim rule. Fixed so two machines choose the same person.
var seed_value: int = 0x7EA

var _team_of: Dictionary = {}
var _last_switch: Dictionary = {}
var _order: PackedStringArray = PackedStringArray()
var _match: Object = null


func _ready() -> void:
	if teams == null:
		teams = DotTeamSet.standard_pair()

	if policy == null:
		policy = DotTeamPolicy.new()

	if register_service and authoritative:
		DotRegistry.register(SERVICE, self)


func setup() -> DotResult:
	if teams == null:
		teams = DotTeamSet.standard_pair()

	if policy == null:
		policy = DotTeamPolicy.new()

	var built := teams.build()

	if not built.ok:
		return built.wrap("This team set was not installed")

	var valid := policy.validate()

	if not valid.ok:
		return valid.wrap("This team policy was not installed")

	if not teams.has_team(policy.initial_team):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The policy starts players on '%s', which this set has no team for."
			% String(policy.initial_team),
			"Everybody would land on a side that does not exist, and every lookup "
			+ "about them would answer null."
		)

	return DotResult.success(null)


# --- Membership -------------------------------------------------------------

## Adds somebody, on the policy's initial side or on the smallest one.
func add(key: String, tick: int = 0) -> DotResult:
	if not authoritative:
		return _refuse_mirror("add")

	if key == "":
		return DotResult.fail(DotError.CODE_INVALID, "A player with no key has no side.")

	if _team_of.has(key):
		return DotResult.success(_team_of[key])

	var team := policy.initial_team

	if policy.auto_assign:
		team = best_team_for(key)

	_team_of[key] = team
	_order.append(key)

	DotLog.debug(CHANNEL, "added", {"key": key, "team": String(team)})
	team_changed.emit(key, &"", team, &"joined")
	_push_to_match(key, team)
	return DotResult.success(team)


func remove(key: String) -> DotResult:
	if not authoritative:
		return _refuse_mirror("remove")

	if not _team_of.has(key):
		return DotResult.fail(DotError.CODE_INVALID, "No such player: '%s'." % key)

	var was: StringName = _team_of[key]
	_team_of.erase(key)
	_last_switch.erase(key)

	var index := _order.find(key)
	if index >= 0:
		_order.remove_at(index)

	team_changed.emit(key, was, &"", &"left")
	return DotResult.success(null)


## The side somebody is on, or [code]&""[/code].
func team_of(key: String) -> StringName:
	return _team_of.get(key, &"")


func has_player(key: String) -> bool:
	return _team_of.has(key)


func keys() -> PackedStringArray:
	return _order.duplicate()


func members(team_id: StringName) -> PackedStringArray:
	var out := PackedStringArray()

	for key in _order:
		if _team_of[key] == team_id:
			out.append(key)

	return out


## How many on each playing side, as the balance functions want it.
func counts() -> Dictionary:
	var out: Dictionary = {}

	for team_id in teams.playing_ids():
		out[team_id] = 0

	for key in _order:
		var team_id: StringName = _team_of[key]
		if out.has(team_id):
			out[team_id] = int(out[team_id]) + 1

	return out


func count_on(team_id: StringName) -> int:
	return int(counts().get(team_id, 0))


func spread() -> int:
	return DotTeamBalance.spread(counts(), teams.playing_ids())


func is_balanced() -> bool:
	return DotTeamBalance.balanced(counts(), teams.playing_ids(), policy.max_difference)


## Whether two players are on opposing playing sides.
##
## The question dot-combat, dot-chat and dot-spectate all ask, answered once here so
## that three addons do not each write "is their team not my team" — which is the
## spelling that makes a spectator everybody's enemy.
func are_enemies(a: String, b: String) -> bool:
	if a == b:
		return false

	return teams.are_enemies(team_of(a), team_of(b))


func are_allies(a: String, b: String) -> bool:
	if a == b:
		return true

	var ta := team_of(a)
	return ta != &"" and ta == team_of(b) and teams.is_playing(ta)


# --- Assignment -------------------------------------------------------------

## The side somebody should join: the smallest playing one with room.
func best_team_for(_key: String) -> StringName:
	var order := teams.playing_ids()
	var c := counts()
	var with_room: Array[StringName] = []

	for team_id in order:
		var def := teams.get_team(team_id)
		if def.max_players <= 0 or int(c.get(team_id, 0)) < def.max_players:
			with_room.append(team_id)

	if with_room.is_empty():
		# Every playing side is full. The holding pen is the honest answer; putting
		# somebody on a full team to avoid an awkward return value is how a side ends
		# up with nine players on a five-slot mode.
		return policy.initial_team

	return DotTeamBalance.smallest(c, with_room)


## A player asking to move. Enforces the whole policy and explains a refusal.
func request_switch(key: String, to: StringName, tick: int = 0) -> DotResult:
	if not authoritative:
		return _refuse_mirror("request_switch")

	if not _team_of.has(key):
		return DotResult.fail(DotError.CODE_INVALID, "No such player: '%s'." % key)

	var from: StringName = _team_of[key]

	if from == to:
		return DotResult.success(to)

	var refusal := _switch_refusal(key, from, to, tick)

	if refusal != "":
		switch_refused.emit(key, to, refusal)
		return DotResult.fail(DotError.CODE_FORBIDDEN, refusal)

	_last_switch[key] = tick
	return force_team(key, to, &"chose")


## Moves somebody regardless of the policy. For a console command or a game mode.
func force_team(key: String, to: StringName, reason: StringName = &"forced") -> DotResult:
	if not authoritative:
		return _refuse_mirror("force_team")

	if not teams.has_team(to):
		return DotResult.fail(
			DotError.CODE_INVALID, "No such team: '%s'." % String(to)
		)

	var from: StringName = _team_of.get(key, &"")

	if not _team_of.has(key):
		_team_of[key] = to
		_order.append(key)
	else:
		if from == to:
			return DotResult.success(to)
		_team_of[key] = to

	DotLog.info(CHANNEL, "team changed", {
		"key": key, "from": String(from), "to": String(to), "reason": String(reason)
	})
	team_changed.emit(key, from, to, reason)
	_push_to_match(key, to)
	return DotResult.success(to)


## Why a switch is not allowed, or "" if it is.
func _switch_refusal(key: String, from: StringName, to: StringName, tick: int) -> String:
	if not policy.allow_switch:
		return "Switching sides is off on this server."

	if not teams.has_team(to):
		return "There is no team called '%s'." % String(to)

	if not policy.allow_choice and teams.is_playing(to):
		return "This server assigns sides; it does not let you pick one."

	if policy.lock_when_live and _is_live():
		return "Sides are locked while a round is live."

	if not policy.allow_switch_while_alive and _is_alive(key):
		return (
			"You cannot switch while you are alive — a living body moved to the other "
			+ "side's spawn is either a teleport into their base or a free escape."
		)

	var cooldown := policy.switch_cooldown_ticks()

	if cooldown > 0 and _last_switch.has(key):
		var since := tick - int(_last_switch[key])
		if since < cooldown:
			var left := float(cooldown - since) / float(maxi(1, policy.tick_rate))
			return "You switched recently. %.0f seconds to go." % ceilf(left)

	var def := teams.get_team(to)

	if def.max_players > 0 and count_on(to) >= def.max_players:
		return "%s is full (%d)." % [def.display_name, def.max_players]

	if (
		policy.enforce_balance_on_switch
		and teams.is_playing(to)
		and teams.is_playing(from)
		and DotTeamBalance.would_unbalance(
			_counts_without(key), teams.playing_ids(), to, policy.max_difference
		)
	):
		return "That would leave the sides uneven."

	return ""


# --- Balancing --------------------------------------------------------------

## Moves people until the sides are even. Returns what it did.
##
## [b]Deterministic and explainable, on purpose.[/b] Being moved is, from the player's
## point of view, being punished for the server's arithmetic — so every move can be
## printed with [method DotTeamBalance.explain], and two servers running the same
## session make the same moves.
func rebalance(tick: int = 0) -> Array[Dictionary]:
	var done: Array[Dictionary] = []

	if not authoritative or not policy.autobalance:
		return done

	var order := teams.playing_ids()
	var before := spread()
	var plan := DotTeamBalance.moves_to_balance(counts(), order, policy.max_difference)

	if plan.is_empty():
		return done

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ (tick * 2654435761)

	for move in plan:
		var from: StringName = move["from"]
		var to: StringName = move["to"]
		var victim := DotTeamBalance.choose_victim(
			_candidates(from), policy.balance_victim, policy.autobalance_while_alive, rng
		)

		if victim == "":
			# Everybody on the oversized side is alive and the policy forbids moving
			# the living. Correct, and worth stopping on rather than looping: the next
			# move in the plan comes from the same side.
			DotLog.debug(CHANNEL, "nobody eligible to move", {"from": String(from)})
			break

		var res := force_team(victim, to, &"balanced")

		if res.ok:
			done.append({"key": victim, "from": from, "to": to})

	if not done.is_empty():
		DotLog.info(CHANNEL, "rebalanced", {"moves": done.size(), "spread_before": before})
		balanced.emit(done)

	return done


func _candidates(team_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	for key in members(team_id):
		out.append({
			"key": key,
			"alive": _is_alive(key),
			"score": _score(key),
			"joined_tick": _joined(key),
		})

	return out


func _counts_without(key: String) -> Dictionary:
	var c := counts()
	var team_id: StringName = _team_of.get(key, &"")

	if c.has(team_id):
		c[team_id] = maxi(0, int(c[team_id]) - 1)

	return c


# --- dot-match ---------------------------------------------------------------

## Binds a dot-match team manager so assignments made here reach it.
##
## [b]Duck-typed on purpose.[/b] dot-team must not depend on dot-match — a lobby, a
## timer server and a sandbox all want sides and none of them wants a match loop — and
## dot-match must keep working with nobody driving it. So this takes an [Object], calls
## [code]assign[/code] on it if it has one, and does nothing at all otherwise.
##
## The direction matters: this is the authority and dot-match is told. Two systems both
## deciding which side somebody is on is the bug this addon was written to remove.
func bind_match(manager: Object) -> DotResult:
	if manager == null:
		_match = null
		return DotResult.success(null)

	if not manager.has_method("assign"):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"That object has no assign() and cannot be driven as a team manager.",
			"dot-match's DotTeamManager has one. Anything else needs the same shape: "
			+ "assign(key: String, tick: int, team: int)."
		)

	_match = manager

	for key in _order:
		_push_to_match(key, _team_of[key])

	return DotResult.success(null)


## Tells a bound match manager which side somebody is on.
##
## [b]Translating the id is the whole job, and it is not a cast.[/b] dot-team names its
## sides; dot-match numbers its own with ids a game chose — `standard_pair()` there is
## `1` and `2`, and a spectator team is `31`. So the mapping is by POSITION: the nth
## playing side here is the nth entry in the manager's own team list. Passing dot-team's
## index straight through would assign everybody to team 0 and 1, of which only one
## exists, and the symptom is half the server on a side dot-match refuses to spawn.
func _push_to_match(key: String, team_id: StringName) -> void:
	if _match == null or not is_instance_valid(_match):
		return

	var def := teams.get_team(team_id)

	if def == null or not def.playing:
		return

	var index := teams.playing_ids().find(team_id)

	if index < 0:
		return

	var target := _match_team_id(index)

	if target < 0:
		DotLog.warn(CHANNEL, "the bound manager has no side at that position", {
			"team": String(team_id), "position": index
		})
		return

	var tick := int(match_tick_fn.call()) if match_tick_fn.is_valid() else 0
	var res: Variant = _match.call("assign", key, tick, target)

	if res is DotResult and not (res as DotResult).ok:
		DotLog.debug(CHANNEL, "the bound manager refused an assignment", {
			"key": key, "why": (res as DotResult).error.message
		})


## The bound manager's own id for its nth side, or -1.
func _match_team_id(index: int) -> int:
	var listed: Variant = _match.get("teams")

	if not (listed is Array):
		return -1

	var rows := listed as Array

	if index < 0 or index >= rows.size():
		return -1

	var row: Variant = rows[index]

	if row == null:
		return -1

	var id: Variant = (row as Object).get("id") if row is Object else null
	return int(id) if id != null else -1


# --- Mirroring --------------------------------------------------------------

func to_wire() -> Dictionary:
	var rows: Dictionary = {}

	for key in _order:
		rows[key] = String(_team_of[key])

	return {"teams": rows, "order": _order}


func apply_wire(payload: Dictionary) -> DotResult:
	if authoritative:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN,
			"An authoritative team roster is not told who is on which side."
		)

	var rows: Variant = payload.get("teams", {})

	if not (rows is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "A team payload has no assignments.")

	_team_of.clear()
	_order = PackedStringArray()

	var order: Variant = payload.get("order", [])
	var listed: Array = order if order is Array else (rows as Dictionary).keys()

	for key: Variant in listed:
		var k := String(key)
		if (rows as Dictionary).has(k):
			_team_of[k] = StringName(str((rows as Dictionary)[k]))
			_order.append(k)

	return DotResult.success(_team_of.size())


func clear() -> void:
	_team_of.clear()
	_last_switch.clear()
	_order = PackedStringArray()


# --- Reporting --------------------------------------------------------------

func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("teams: %s, spread %d%s%s" % [
		String(teams.id), spread(),
		", balanced" if is_balanced() else ", UNEVEN",
		"" if authoritative else " [mirror]",
	])

	for def in teams.sorted_teams():
		var m := members(def.id)
		out.append("  %-12s %2d  %s" % [String(def.id), m.size(), ", ".join(m)])

	return out


func describe() -> String:
	return "DotTeamRoster(%d players, spread %d)" % [_team_of.size(), spread()]


# --- Internals --------------------------------------------------------------

func _is_alive(key: String) -> bool:
	return bool(alive_fn.call(key)) if alive_fn.is_valid() else false


func _score(key: String) -> float:
	return float(score_fn.call(key)) if score_fn.is_valid() else 0.0


func _joined(key: String) -> int:
	if joined_fn.is_valid():
		return int(joined_fn.call(key))

	# Without a supplier, join order is the next best thing and is at least stable.
	return _order.find(key)


func _is_live() -> bool:
	return bool(live_fn.call()) if live_fn.is_valid() else false


func _refuse_mirror(what: String) -> DotResult:
	return DotResult.fail(
		DotError.CODE_FORBIDDEN,
		"A mirrored team roster decides nothing; it is told. ('%s')" % what
	)
