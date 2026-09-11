extends Node

## Exercises dot-team against a real team roster and a real spectator manager.
##
## The bridge is the part worth checking hardest: dot-spectate numbers its sides and
## dot-team names them, and an off-by-one in the mapping silently inverts who may watch
## whom — which is a competitive-integrity bug that nothing would report as one.
##
## [codeblock]
## godot --headless --path . res://examples/team_spectate_selftest.tscn
## [/codeblock]

const SECTIONS := 7
const CHECKS := 86

var _passed := 0
var _failed := 0
var _section_count := 0

var _alive: Dictionary = {}
var _live := true


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-team self-test")
	_line("")

	_test_rules()
	_test_setup()
	_test_bridge()
	_test_policy()
	_test_joining()
	_test_api()
	_test_duck_typing()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


func _teams_roster() -> DotTeamRoster:
	var r := DotTeamRoster.new()
	r.teams = DotTeamSet.standard_pair()
	r.policy = DotTeamPolicy.new()
	r.policy.enforce_balance_on_switch = false
	r.register_service = false
	r.alive_fn = func(key: String) -> bool: return bool(_alive.get(key, false))
	add_child(r)
	var _res := r.setup()
	return r


func _spectate(
	teams: DotTeamRoster,
	rules: DotTeamSpectateRules = null
) -> DotTeamSpectate:
	var s := DotTeamSpectate.new()
	s.teams = teams
	s.rules = rules if rules != null else DotTeamSpectateRules.new()
	s.register_service = false

	# Free camera and no delay: this suite is about who may watch whom, and a
	# broadcast delay would put every camera check a hundred ticks in the past.
	#
	# dot-spectate is linked into THIS project so the suite runs against the real
	# manager rather than a stand-in — the addon itself never names it, which is the
	# thing the "no manager at all" section below checks.
	var sr := DotSpectatorRules.new()
	sr.force_camera = 0
	sr.delay_ticks = 0
	sr.allow_while_alive = true
	s.spectator_rules = sr

	s.alive_fn = func(key: String) -> bool: return bool(_alive.get(key, false))
	s.round_live_fn = func() -> bool: return _live
	add_child(s)
	var _res := s.setup()
	return s


func _populate(teams: DotTeamRoster) -> void:
	_alive.clear()

	for key in ["blue1", "blue2"]:
		var _a := teams.add(key)
		var _f := teams.force_team(key, &"blue")
		_alive[key] = true

	for key in ["red1", "red2"]:
		var _a := teams.add(key)
		var _f := teams.force_team(key, &"red")
		_alive[key] = true


# --- Rules ------------------------------------------------------------------

func _test_rules() -> void:
	_section("rules")

	var r := DotTeamSpectateRules.new()
	_check(r.validate().ok, "the defaults validate")
	_check(
		r.spectators_see_everybody,
		"a spectator sees everybody — somebody who has deliberately left the game to "
		+ "watch is not coming back this round, so they are not the risk a dead player is"
	)
	_check(
		not r.dead_see_enemies,
		"and a dead player does not, which is the oldest problem in competitive "
		+ "multiplayer"
	)
	_check(r.open_after_round, "and everything opens up once the round is decided")

	var nameless := DotTeamSpectateRules.new()
	nameless.spectator_team = &""
	_check(
		not nameless.validate().ok,
		"a rules set with no spectator side is refused: nobody could be moved to one"
	)

	_check(DotTeamSpectateRules.open().dead_see_enemies, "the open preset lets the dead look")
	_check(
		not DotTeamSpectateRules.locked().spectators_see_everybody,
		"and the locked one does not, even for spectators"
	)
	_check(DotTeamSpectateRules.presets().size() == 3, "three presets")
	_check(DotTeamSpectateRules.preset(&"open") != null, "resolving by name")
	_check(r.env_prefix() == "DOT_TEAM_SPECTATE_", "with the family's config layering")


func _test_setup() -> void:
	_section("setup")

	var bare := DotTeamSpectate.new()
	bare.register_service = false
	add_child(bare)
	_check(
		not bare.setup().ok,
		"a bridge with no team roster refuses to set up, because the whole addon is "
		+ "the bridge"
	)

	var ffa := DotTeamRoster.new()
	ffa.teams = DotTeamSet.free_for_all()
	ffa.policy = DotTeamPolicy.free_for_all()
	ffa.register_service = false
	add_child(ffa)
	var _fr := ffa.setup()

	var no_side := DotTeamSpectate.new()
	no_side.teams = ffa
	no_side.rules = DotTeamSpectateRules.new()
	no_side.rules.spectator_team = &"nonexistent"
	no_side.register_service = false
	add_child(no_side)
	_check(
		not no_side.setup().ok,
		"and one whose spectator side is not in the team set is refused — "
		+ "join_spectators would fail for everybody, one player at a time"
	)

	var teams := _teams_roster()
	var s := _spectate(teams)
	_check(s.spectators != null, "a working one builds a spectator manager")
	_check(s.spectators.participants_fn.is_valid(), "and wires the participant list")
	_check(s.spectators.team_fn.is_valid(), "and the side lookup")
	_check(s.spectators.target_filter.is_valid(), "and the policy filter")

	bare.queue_free()
	ffa.queue_free()
	no_side.queue_free()
	teams.queue_free()
	s.queue_free()


# --- The bridge -------------------------------------------------------------

func _test_bridge() -> void:
	_section("the bridge")

	var teams := _teams_roster()
	var s := _spectate(teams)
	_populate(teams)

	_check(
		s.team_index(&"blue") == 1 and s.team_index(&"red") == 2,
		"the playing sides map to one and two"
	)
	_check(
		s.team_index(DotTeamSet.SPECTATOR) == 0,
		"and the spectator side maps to zero — which is exactly what dot-spectate's "
		+ "force-camera rule means by 'no team', so that rule does the right thing "
		+ "without being told anything about dot-team"
	)
	_check(s.team_index(DotTeamSet.UNASSIGNED) == 0, "and so does the holding pen")
	_check(s.team_index(&"nonsense") == 0, "and an unknown side")

	_check(s.team_of_index(1) == &"blue", "and the mapping reverses")
	_check(s.team_of_index(0) == &"", "with zero meaning nothing")
	_check(s.team_of_index(99) == &"", "and an index past the end too")

	_check(
		s.spectators.team_fn.call("blue1") == 1,
		"and dot-spectate asks through the bridge and gets the number"
	)

	var participants := s.spectators.participants_fn.call() as PackedStringArray
	_check(participants.size() == 4, "the participant list is everybody playing")

	var _spec := teams.force_team("red2", DotTeamSet.SPECTATOR)
	var fewer := s.spectators.participants_fn.call() as PackedStringArray
	_check(
		fewer.size() == 3,
		"and drops somebody who moves to a non-playing side, because a cycle that "
		+ "included them would stop on a black screen"
	)

	teams.queue_free()
	s.queue_free()


func _test_policy() -> void:
	_section("who may watch whom")

	var teams := _teams_roster()
	var s := _spectate(teams)
	_populate(teams)
	_live = true

	_alive["blue1"] = false

	_check(
		s.may_watch("blue1", "blue2").ok,
		"a dead player may watch their own side"
	)
	_check(
		not s.may_watch("blue1", "red1").ok,
		"and not the other one, which is what stops a dead player calling out positions"
	)

	_live = false
	_check(
		s.may_watch("blue1", "red1").ok,
		"once the round is over, everything opens up — the round is decided, so there "
		+ "is nothing left to give away"
	)
	_live = true

	# A spectator.
	var _sp := teams.force_team("blue1", DotTeamSet.SPECTATOR)
	_check(s.may_watch("blue1", "red1").ok, "a spectator may watch anybody")

	s.rules.spectators_see_everybody = false
	_check(
		not s.may_watch("blue1", "red1").ok,
		"unless the server says otherwise, which is what a tournament seat is"
	)
	s.rules.spectators_see_everybody = true

	# The fallback when a side is wiped.
	var _back := teams.force_team("blue1", &"blue")
	_alive["blue1"] = false
	_alive["blue2"] = false
	_check(
		s.may_watch("blue1", "red1").ok,
		"a player whose whole side is dead may watch the other one — the alternative "
		+ "is a camera with nothing to point at, which reads as the game freezing"
	)

	s.rules.fall_back_when_team_gone = false
	_check(
		not s.may_watch("blue1", "red1").ok,
		"and a server that would rather show nothing can say so"
	)
	s.rules.fall_back_when_team_gone = true

	_alive["blue2"] = true
	_check(
		not s.may_watch("blue1", "red1").ok,
		"with one team-mate alive, the restriction is back"
	)

	# Non-playing targets.
	var _spec2 := teams.force_team("red2", DotTeamSet.SPECTATOR)
	_check(
		not s.may_watch("blue1", "red2").ok,
		"nobody watches a spectator, because there is nothing to see"
	)

	# The operator's own setting wins.
	s.spectators.rules.force_camera = 2
	_check(
		not s.may_watch("blue1", "blue2").ok,
		"and dot-spectate's own force-camera setting is applied first — an addon on "
		+ "top does not get to relax the operator's setting"
	)
	s.spectators.rules.force_camera = 0

	teams.queue_free()
	s.queue_free()


func _test_joining() -> void:
	_section("joining and leaving")

	var teams := _teams_roster()
	var s := _spectate(teams)
	_populate(teams)
	_live = true

	var sides: Array = []
	s.side_changed.connect(func(key: String, to: StringName) -> void:
		sides.append([key, String(to)])
	)
	var begins: Array = []
	s.began.connect(func(key: String, target: String) -> void: begins.append([key, target]))

	_check(s.join_spectators("blue1").ok, "somebody joins the spectators")
	_check(s.on_spectator_side("blue1"), "and is on that side")
	_check(sides.size() == 1, "with a signal")
	_check(
		s.is_spectating("blue1"),
		"and is watching immediately — a spectator staring at a black screen is "
		+ "indistinguishable from a crash, and every game that separates the two calls "
		+ "forgets the second one somewhere"
	)
	_check(begins.size() == 1, "with a signal for that too")
	_check(s.target_of("blue1") != "", "and an actual target")
	_check(s.target_of("blue1") != "blue1", "which is not themselves")

	_check(s.leave_spectators("blue1", &"red").ok, "and they can come back")
	_check(teams.team_of("blue1") == &"red", "onto the side they asked for")
	_check(not s.is_spectating("blue1"), "with the camera stopped")

	var _rejoin := s.leave_spectators("blue1")
	_check(
		teams.teams.is_playing(teams.team_of("blue1")),
		"and naming no side puts them on a playing one rather than nowhere"
	)

	s.rules.allow_join_while_alive = false
	_alive["blue2"] = true
	_check(
		not s.join_spectators("blue2").ok,
		"a server can forbid becoming a spectator while alive, which would otherwise "
		+ "be a way out of a fight"
	)
	_alive["blue2"] = false
	_check(s.join_spectators("blue2").ok, "and allow it once they are dead")

	s.rules.watch_on_join = false
	_alive["red1"] = false
	var _quiet := s.join_spectators("red1")
	_check(
		not s.is_spectating("red1"),
		"a game that would rather show its own screen first can turn the camera off"
	)

	teams.queue_free()
	s.queue_free()


func _test_api() -> void:
	_section("the API a game asks for")

	var teams := _teams_roster()
	var s := _spectate(teams)
	_populate(teams)
	_live = true
	_alive["blue1"] = false

	_check(not s.is_spectating("blue1"), "nobody is watching to begin with")
	_check(s.target_of("blue1") == "", "and nobody has a target")
	_check(s.viewers().is_empty(), "and there are no viewers")

	_check(s.begin("blue1").ok, "beginning picks a target rather than demanding one")
	_check(
		s.target_of("blue1") == "blue2",
		"and picks somebody sensible — every caller would otherwise write the same "
		+ "loop, and the version written in a hurry picks whoever just killed them"
	)
	_check(s.viewers().size() == 1, "and they are a viewer")
	_check(s.watchers_of("blue2").size() == 1, "and their target has a watcher")
	_check(s.watchers_of("red1").is_empty(), "while nobody else does")

	_check(s.mode_of("blue1") != 0, "they are in a camera mode")
	_check(s.watchable("blue1").size() >= 1, "and have somebody to cycle to")

	var forbidden := s.begin("blue1", "red1")
	_check(forbidden.ok, "beginning with a forbidden preference still succeeds")
	_check(
		s.target_of("blue1") != "red1",
		"but does not honour it — a preference is a preference, and silently granting "
		+ "one the rules forbid is the whole competitive-integrity problem arriving "
		+ "through a convenience parameter"
	)

	_check(s.next("blue1").ok, "cycling forward works")
	_check(s.previous("blue1").ok, "and backward")

	_check(not s.watch_team("blue1", &"red").ok, "watching a forbidden side is refused")
	_check(
		s.watch_team("blue1", &"red").error.message.contains("Red"),
		"by its display name, which is what a player needs to read"
	)
	_check(not s.watch_team("blue1", &"nonexistent").ok, "and an unknown side too")

	_live = false
	_check(s.watch_team("blue1", &"red").ok, "and allowed once the round is over")
	_check(s.target_of("blue1").begins_with("red"), "landing on that side")
	_live = true

	s.end("blue1")
	_check(not s.is_spectating("blue1"), "and it can be stopped")

	s.advance(10)
	_check(s.camera_of("blue1") is Transform3D, "a camera transform is always available")
	_check(s.describe_lines().size() >= 1, "and it describes itself")
	_check(s.describe().contains("viewers"), "briefly too")

	teams.queue_free()
	s.queue_free()


## Anything with the right methods is a spectator manager, including this.
##
## dot-team names no `DotSpectator*` identifier anywhere, so a game with its own camera
## system — or with dot-spectate absent entirely — still gets the side policy. This is
## that promise, tested rather than asserted in a comment.
class StubManager extends Node:
	var participants_fn: Callable = Callable()
	var team_fn: Callable = Callable()
	var alive_fn: Callable = Callable()
	var pose_fn: Callable = Callable()
	var target_filter: Callable = Callable()
	var rules: Object = null

	var watching: Dictionary = {}
	var advanced: int = -1

	func setup() -> DotResult:
		return DotResult.success(null)

	func is_spectating(key: String) -> bool:
		return watching.has(key)

	func may_spectate(_key: String) -> DotResult:
		return DotResult.success(null)

	func may_watch(key: String, target: String) -> DotResult:
		if target_filter.is_valid() and not bool(target_filter.call(key, target)):
			return DotResult.fail(DotError.CODE_FORBIDDEN, "The side policy says no.")

		return DotResult.success(null)

	func watch(key: String, target: String) -> DotResult:
		watching[key] = target
		return DotResult.success(null)

	func stop(key: String) -> void:
		watching.erase(key)

	func targets_for(_key: String) -> PackedStringArray:
		return participants_fn.call() if participants_fn.is_valid() else PackedStringArray()

	func viewers() -> PackedStringArray:
		var out := PackedStringArray()
		for key: Variant in watching.keys():
			out.append(String(key))
		return out

	func advance(tick: int) -> void:
		advanced = tick

	func camera_of(_key: String) -> Transform3D:
		return Transform3D.IDENTITY


func _test_duck_typing() -> void:
	_section("a manager that is not dot-spectate's")

	_alive.clear()
	_live = true

	var teams := _teams_roster()
	_populate(teams)

	var stub := StubManager.new()
	var s := DotTeamSpectate.new()
	s.teams = teams
	s.register_service = false
	s.rules = DotTeamSpectateRules.new()
	s.alive_fn = func(key: String) -> bool: return bool(_alive.get(key, false))
	s.round_live_fn = func() -> bool: return _live
	s.spectators = stub
	add_child(s)

	_check(s.setup().ok, "a stub manager sets up")
	_check(
		stub.participants_fn.is_valid(),
		"and gets the participant list wired into it — dot-team names no "
		+ "DotSpectator* identifier anywhere, so a game with its own camera system gets "
		+ "the side policy for free"
	)
	_check(stub.team_fn.is_valid(), "and the side lookup")
	_check(stub.target_filter.is_valid(), "and the policy filter")
	_check(int(stub.team_fn.call("blue1")) == 1, "which answers in dot-spectate's numbers")

	_alive["blue1"] = false
	_check(not s.may_watch("blue1", "red1").ok, "and the policy is enforced through it")
	_check(s.may_watch("blue1", "blue2").ok, "in both directions")

	_check(s.begin("blue1").ok, "watching works")
	_check(s.is_spectating("blue1"), "and is reported")
	_check(s.viewers().size() == 1, "and listed")
	s.advance(77)
	_check(stub.advanced == 77, "and a tick reaches the manager")
	s.end("blue1")
	_check(not s.is_spectating("blue1"), "and stopping stops")

	# No manager at all, which is what a lobby with no dot-spectate looks like.
	var bare := DotTeamSpectate.new()
	bare.teams = teams
	bare.register_service = false
	bare.rules = DotTeamSpectateRules.new()
	add_child(bare)
	bare.spectators = null

	_check(bare.setup().ok, "and a bridge with no manager sets up rather than failing")

	teams.queue_free()
	s.queue_free()
	bare.queue_free()


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
