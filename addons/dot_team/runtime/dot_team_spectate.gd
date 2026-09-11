class_name DotTeamSpectate
extends Node

## Spectating, with sides. The bridge between dot-team and dot-spectate.
##
## [b]It exists because the two addons describe a side differently, on purpose.[/b]
## dot-spectate's [code]team_fn[/code] answers an integer and zero means "none", which
## is the right shape for an addon that must work with no team system at all; dot-team's
## sides are named, ordered and carry attributes. Something has to compile one into the
## other, and doing it in each game is doing it four times with a different off-by-one
## in one of them.
##
## What it adds on top of the bridge is the API a game actually asks for — is this
## person spectating, who are they watching, who may they watch, put them on the
## spectator side and start them watching in one call — and a policy expressed in terms
## of rounds and sides rather than of camera modes.
##
## [codeblock]
## var spectate := DotTeamSpectate.new()
## spectate.teams = team_roster
## add_child(spectate)
## spectate.setup()
##
## spectate.join_spectators("ada")          # moves them and starts the camera
## spectate.is_spectating("ada")            # true
## spectate.target_of("ada")                # "bob"
## spectate.next(&"ada")                    # cycle
## spectate.advance(tick)                   # once a tick
## [/codeblock]

const CHANNEL := "team.spectate"

const SERVICE := &"dot_team"

## Somebody started watching.
signal began(key: String, target: String)

## Somebody stopped.
signal ended(key: String)

## Somebody was moved to or from the spectator side.
signal side_changed(key: String, to: StringName)

@export var rules: DotTeamSpectateRules = null

## dot-spectate's own rules object, if the game has one to hand over.
##
## Untyped for the reason in the class documentation. Left null, one is built alongside
## the manager with the family's defaults.
var spectator_rules: Object = null

@export var register_service: bool = true

## The side roster. Required.
var teams: DotTeamRoster = null

## The camera and policy half: a `DotSpectatorManager`, or anything the same shape.
##
## Built by [method setup] when dot-spectate is installed and nothing was assigned.
var spectators: Node = null

## `func(key: String) -> bool`. Whether somebody is in the world.
var alive_fn: Callable = Callable()

## `func(key: String) -> Transform3D`. Where their eyes are.
var pose_fn: Callable = Callable()

## `func() -> bool`. Whether a round is under way.
##
## Left unset, a round is always under way, which is the cautious answer: the
## end-of-round relaxation never applies and nobody sees more than they should.
var round_live_fn: Callable = Callable()

var _playing_ids: Array[StringName] = []


func _ready() -> void:
	if rules == null:
		rules = DotTeamSpectateRules.new()

	if register_service:
		DotRegistry.register(SERVICE, self)


## Wires the two addons together. Call once, after assigning [member teams].
func setup() -> DotResult:
	if rules == null:
		rules = DotTeamSpectateRules.new()

	var valid := rules.validate()

	if not valid.ok:
		return valid.wrap("These team-spectate rules were not installed")

	if teams == null:
		return DotResult.fail(
			DotError.CODE_STATE,
			"DotTeamSpectate has no team roster.",
			"Assign `teams` before calling setup(); the whole addon is the bridge "
			+ "between that and dot-spectate."
		)

	if not teams.teams.has_team(rules.spectator_team):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The team set has no side called '%s'." % String(rules.spectator_team),
			"Nobody could be moved to it, so join_spectators would fail for everybody. "
			+ "DotTeamSet.standard_pair() includes one."
		)

	if spectators == null:
		spectators = _make_spectator_manager()

		if spectators == null:
			# Legal, and the common case in a lobby: sides without cameras. Everything
			# in this node that is about assignment still works; everything about
			# watching answers "not set up", which is honest rather than silent.
			DotLog.debug(
				CHANNEL,
				"no spectator manager; the watching half of this node is inert",
				{}
			)
			return DotResult.success(null)

		spectators.name = "Spectators"

		if spectator_rules != null:
			spectators.set("rules", spectator_rules)

		add_child(spectators)

	# The ordering that matters: the playing ids are cached here, once, and
	# team_index() reads the cache. Recomputing per call would be a linear search per
	# viewer per tick, and re-reading the set every call would let a mid-round change
	# renumber the sides underneath dot-spectate — which would silently invert who may
	# watch whom.
	_playing_ids = teams.teams.playing_ids()

	spectators.set("participants_fn", Callable(self, "_participants"))
	spectators.set("team_fn", Callable(self, "_team_index"))
	spectators.set("alive_fn", Callable(self, "_alive"))
	spectators.set("pose_fn", Callable(self, "_pose"))
	spectators.set("target_filter", Callable(self, "_may_watch"))

	var ready: Variant = spectators.call("setup")
	return ready as DotResult if ready is DotResult else DotResult.success(null)


## Builds a `DotSpectatorManager` without naming it.
##
## [b]The same trick dot-core's [code]DotTransportENet[/code] uses, for a related
## reason.[/b] That one reaches ENet through [method ClassDB.instantiate] because a
## script that merely MENTIONS [code]ENetMultiplayerPeer[/code] fails to compile on a
## web export where the class is absent. This one reaches a script class the same way,
## through the global class list, because dot-team must install with dot-core alone.
##
## Returns null when dot-spectate is not installed, which is a supported configuration
## and not an error.
func _make_spectator_manager() -> Node:
	for entry: Variant in ProjectSettings.get_global_class_list():
		var row := entry as Dictionary

		if str(row.get("class", "")) != "DotSpectatorManager":
			continue

		var script := load(str(row.get("path", ""))) as Script

		if script == null:
			return null

		var made: Variant = script.new()
		return made as Node if made is Node else null

	return null


# --- The bridge -------------------------------------------------------------

## dot-spectate's integer for a named side. Zero for "no side".
##
## One-based over the [i]playing[/i] sides, so spectators and the unassigned holding pen
## both come out as zero — which is exactly what dot-spectate's force-camera rule means
## by "no team", and is why that rule then does the right thing without being told
## anything about dot-team.
func team_index(team_id: StringName) -> int:
	var index := _playing_ids.find(team_id)
	return index + 1 if index >= 0 else 0


## The named side for one of dot-spectate's integers.
func team_of_index(index: int) -> StringName:
	if index <= 0 or index > _playing_ids.size():
		return &""

	return _playing_ids[index - 1]


# --- Asking -----------------------------------------------------------------

## Whether somebody is watching rather than playing.
func is_spectating(key: String) -> bool:
	return spectators != null and bool(spectators.call("is_spectating", key))


## Who they are watching, or "".
func target_of(key: String) -> String:
	if spectators == null:
		return ""

	var v: Variant = spectators.call("view", key)
	return str((v as Object).get("target")) if v is Object else ""


## Which camera mode they are in. See dot-spectate's `DotSpectatorView.Mode`.
func mode_of(key: String) -> int:
	if spectators == null:
		return 0

	var v: Variant = spectators.call("view", key)
	return int((v as Object).get("mode")) if v is Object else 0


## Whether somebody is on the spectator side.
##
## Distinct from [method is_spectating]: a dead player is spectating and is still on
## their own side, and a spectator who has not been given a target is on the spectator
## side and is not yet watching anything.
func on_spectator_side(key: String) -> bool:
	return teams != null and teams.team_of(key) == rules.spectator_team


## Everybody currently watching.
func viewers() -> PackedStringArray:
	return spectators.call("viewers") if spectators != null else PackedStringArray()


## Everybody watching a given person. What a "3 spectators" badge reads.
func watchers_of(target: String) -> PackedStringArray:
	var out := PackedStringArray()

	for key in viewers():
		if target_of(key) == target:
			out.append(key)

	out.sort()
	return out


## Who this viewer is allowed to watch, in the order a cycle visits them.
func watchable(key: String) -> PackedStringArray:
	return spectators.call("targets_for", key) if spectators != null else PackedStringArray()


## Whether one person may watch another, with the reason if not.
func may_watch(key: String, target: String) -> DotResult:
	if spectators == null:
		return DotResult.fail(DotError.CODE_STATE, "Not set up.")

	return spectators.call("may_watch", key, target) as DotResult


# --- Doing ------------------------------------------------------------------

## Starts somebody watching, choosing a target for them.
##
## Chooses rather than requiring one, because every caller would otherwise write the
## same "find somebody sensible" loop — and the version that gets written in a hurry
## picks the first participant, which is usually the person who just killed them.
func begin(key: String, prefer: String = "") -> DotResult:
	if spectators == null:
		return DotResult.fail(DotError.CODE_STATE, "Not set up.")

	var allowed := spectators.call("may_spectate", key) as DotResult

	if not allowed.ok:
		return allowed

	var target := prefer

	if target == "" or not spectators.may_watch(key, target).ok:
		var options := watchable(key)

		if options.is_empty():
			return DotResult.fail(
				DotError.CODE_STATE,
				"There is nobody %s is allowed to watch." % key,
				"Every playing side may be empty, or the rules may be stricter than "
				+ "the session. See DotTeamSpectateRules."
			)

		target = options[0]

	var res := spectators.call("watch", key, target) as DotResult

	if res.ok:
		began.emit(key, target)

	return res


## Stops.
func end(key: String) -> void:
	if spectators == null:
		return

	spectators.call("stop", key)
	ended.emit(key)


func next(key: String) -> DotResult:
	if spectators == null:
		return DotResult.fail(DotError.CODE_STATE, "Not set up.")

	return spectators.call("next_target", key) as DotResult


func previous(key: String) -> DotResult:
	if spectators == null:
		return DotResult.fail(DotError.CODE_STATE, "Not set up.")

	return spectators.call("previous_target", key) as DotResult


## Points a viewer at the first watchable member of a side.
##
## What a "watch the other team" button does, and it is a [DotResult] rather than a
## boolean because the refusal — you may not watch that side — is the answer a player
## needs to see.
func watch_team(key: String, team_id: StringName) -> DotResult:
	if spectators == null:
		return DotResult.fail(DotError.CODE_STATE, "Not set up.")

	if teams == null or not teams.teams.has_team(team_id):
		return DotResult.fail(
			DotError.CODE_INVALID, "There is no side called '%s'." % String(team_id)
		)

	for candidate in teams.members(team_id):
		if (spectators.call("may_watch", key, candidate) as DotResult).ok:
			return spectators.call("watch", key, candidate) as DotResult

	return DotResult.fail(
		DotError.CODE_FORBIDDEN,
		"There is nobody on %s you may watch." % teams.teams.display_of(team_id)
	)


## Moves somebody to the spectator side and starts them watching.
##
## The two together on purpose: a spectator staring at a black screen is
## indistinguishable from a crash, and every game that separates the two calls forgets
## the second one in at least one code path.
func join_spectators(key: String) -> DotResult:
	if teams == null:
		return DotResult.fail(DotError.CODE_STATE, "No team roster.")

	if not rules.allow_join_while_alive and _alive(key):
		return DotResult.fail(
			DotError.CODE_STATE,
			"You cannot become a spectator while you are alive.",
			"Killing the player first is the game's decision, not this addon's — a "
			+ "living player who became a spectator would have a way out of a fight."
		)

	var moved := teams.force_team(key, rules.spectator_team, &"spectate")

	if not moved.ok:
		return moved

	side_changed.emit(key, rules.spectator_team)

	if not rules.watch_on_join:
		return DotResult.success(null)

	var begun := begin(key)

	# A move that succeeded and a camera that did not is still a success: the player is
	# a spectator, which is what they asked for, and the empty view is reported rather
	# than undoing the move they can see happened.
	if not begun.ok:
		DotLog.debug(CHANNEL, "joined spectators with nobody to watch", {"key": key})

	return DotResult.success(null)


## Puts somebody back into the game and stops their camera.
func leave_spectators(key: String, team_id: StringName = &"") -> DotResult:
	if teams == null:
		return DotResult.fail(DotError.CODE_STATE, "No team roster.")

	var wanted := team_id

	if wanted == &"":
		wanted = rules.rejoin_team

	if wanted == &"":
		wanted = teams.best_team_for(key)

	var moved := teams.force_team(key, wanted, &"unspectate")

	if not moved.ok:
		return moved

	end(key)
	side_changed.emit(key, wanted)
	return DotResult.success(wanted)


## One tick. Advances the camera history and the death-cam chain.
func advance(tick: int) -> void:
	if spectators != null:
		spectators.call("advance", tick)


## The camera transform for a viewer.
func camera_of(key: String) -> Transform3D:
	if spectators == null:
		return Transform3D.IDENTITY

	var t: Variant = spectators.call("camera_of", key)
	return t as Transform3D if t is Transform3D else Transform3D.IDENTITY


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("team spectate: %d viewers, %d playing sides" % [
		viewers().size(), _playing_ids.size()
	])

	for key in viewers():
		out.append("  %-16s -> %-16s (%s)" % [
			key, target_of(key), String(teams.team_of(key)) if teams != null else "?"
		])

	if spectators != null and spectators.has_method("describe_lines"):
		out.append_array(spectators.call("describe_lines") as PackedStringArray)

	return out


func describe() -> String:
	return "DotTeamSpectate(%d viewers)" % viewers().size()


# --- The callables dot-spectate is given ------------------------------------

func _participants() -> PackedStringArray:
	if teams == null:
		return PackedStringArray()

	var out := PackedStringArray()

	for key in teams.keys():
		if rules.watch_non_playing or teams.teams.is_playing(teams.team_of(key)):
			out.append(key)

	out.sort()
	return out


func _team_index(key: String) -> int:
	return team_index(teams.team_of(key)) if teams != null else 0


func _alive(key: String) -> bool:
	return bool(alive_fn.call(key)) if alive_fn.is_valid() else false


func _pose(key: String) -> Transform3D:
	if not pose_fn.is_valid():
		return Transform3D.IDENTITY

	var t: Variant = pose_fn.call(key)
	return t as Transform3D if t is Transform3D else Transform3D.IDENTITY


## The side policy, handed to dot-spectate as its extra filter.
##
## [b]An extra filter and not a replacement.[/b] dot-spectate applies its own
## force-camera rule first and this runs afterwards, so a server that has set
## [code]mp_forcecamera 2[/code] still forbids everything regardless of what is written
## here — which is the correct precedence: the operator's setting is not something an
## addon on top gets to relax.
func _may_watch(viewer: String, target: String) -> bool:
	if teams == null:
		return true

	var mine := teams.team_of(viewer)
	var theirs := teams.team_of(target)

	if not rules.watch_non_playing and not teams.teams.is_playing(theirs):
		return false

	if mine == theirs:
		return true

	# From here on, the viewer is looking at a side that is not their own.
	if rules.open_after_round and not _round_live():
		return true

	if mine == rules.spectator_team:
		return rules.spectators_see_everybody

	if mine == &"" or not teams.teams.is_playing(mine):
		return rules.unassigned_may_watch

	if _alive(viewer):
		# A living player watching anybody is a replay or a demo, and dot-spectate's
		# own allow_while_alive already decided whether that is permitted at all.
		return true

	if rules.dead_see_enemies:
		return true

	if rules.fall_back_when_team_gone and _own_side_empty(mine):
		# Nobody left on your side to watch. The alternative is a camera with nothing
		# to point at, which the player reads as the game having frozen.
		return true

	return false


func _own_side_empty(team_id: StringName) -> bool:
	for key in teams.members(team_id):
		if _alive(key):
			return false

	return true


func _round_live() -> bool:
	return bool(round_live_fn.call()) if round_live_fn.is_valid() else true
