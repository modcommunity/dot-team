extends Node

## Exercises dot-team with no match, no players and no transport.
##
## The balance half is checked hardest, for the reason the code gives: autobalance is
## the most complained-about thing a server does, and a decision that cannot be
## explained cannot be defended. Every balance function is static and takes counts, so
## the whole of it is checkable as arithmetic.
##
## [codeblock]
## godot --headless --path . res://examples/team_selftest.tscn
## [/codeblock]

const SECTIONS := 8
const CHECKS := 153

const RATE := 64

var _passed := 0
var _failed := 0
var _section_count := 0

var _alive: Dictionary = {}
var _live := false


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-team self-test")
	_line("")

	_test_defs()
	_test_sets()
	_test_policy()
	_test_balance_maths()
	_test_membership()
	_test_switching()
	_test_rebalancing()
	_test_mirror_and_match()

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


func _roster(set: DotTeamSet = null, policy: DotTeamPolicy = null) -> DotTeamRoster:
	var r := DotTeamRoster.new()
	r.teams = set if set != null else DotTeamSet.standard_pair()
	r.policy = policy if policy != null else DotTeamPolicy.new()
	r.policy.tick_rate = RATE
	r.register_service = false
	r.alive_fn = func(key: String) -> bool: return bool(_alive.get(key, false))
	r.live_fn = func() -> bool: return _live
	add_child(r)
	var _res := r.setup()
	return r


# --- Definitions ------------------------------------------------------------

func _test_defs() -> void:
	_section("a team definition")

	var t := DotTeamDef.make(&"blue", "Blue", Color.BLUE)
	_check(t.id == &"blue", "has an id")
	_check(t.display_name == "Blue", "and a name")
	_check(t.playing, "and plays by default")
	_check(not t.friendly_fire, "with friendly fire off")
	_check(t.max_players == 0, "and no size limit")
	_check(t.spawn_id() == &"blue", "its spawn group defaults to its own id")

	t.spawn_group = &"blue_starts"
	_check(t.spawn_id() == &"blue_starts", "and can be pointed elsewhere")

	t.attributes = {"attacks": true, "announcer": "blue_wins"}
	_check(bool(t.attribute("attacks", false)), "an attribute reads back")
	_check(t.attribute("nope", "fallback") == "fallback", "and an unknown one defaults")
	_check(t.attribute_is("attacks", true), "and compares")
	_check(
		not t.attribute_is("attacks", "true"),
		"a string against a bool answers false rather than erroring, because "
		+ "DotValue.same is total where == is not"
	)

	var auto := DotTeamDef.make(&"green")
	_check(auto.display_name == "Green", "a name is derived when none is given")
	_check(auto.short_name == "GRE", "and a short one too")
	_check(t.describe().contains("blue"), "and it describes itself")


func _test_sets() -> void:
	_section("a team set")

	var pair := DotTeamSet.standard_pair()
	_check(pair.build().ok, "the standard pair builds")
	_check(
		pair.teams.size() == 4,
		"with four entries, not two — a player who has connected and not chosen is "
		+ "neither on a team nor spectating, and a set with no id for that represents "
		+ "it as the empty string"
	)
	_check(pair.playing_teams().size() == 2, "of which two play")
	_check(pair.is_playing(&"blue"), "blue plays")
	_check(not pair.is_playing(DotTeamSet.SPECTATOR), "spectators do not")
	_check(not pair.is_playing(DotTeamSet.UNASSIGNED), "and neither does the holding pen")

	_check(pair.are_enemies(&"blue", &"red"), "the two sides are enemies")
	_check(not pair.are_enemies(&"blue", &"blue"), "a side is not its own enemy")
	_check(
		not pair.are_enemies(&"blue", DotTeamSet.SPECTATOR),
		"and a spectator is nobody's enemy — the spelling 'is their team not my team' "
		+ "makes them everybody's"
	)
	_check(not pair.are_enemies(&"blue", &"nonsense"), "nor is an unknown side")

	_check(pair.colour_of(&"red").r > 0.5, "a set answers colours")
	_check(pair.colour_of(&"nope") == Color.WHITE, "and white for a side it has no idea about")
	_check(pair.display_of(&"blue") == "Blue", "and display names")

	var sorted := pair.sorted_teams()
	_check(
		sorted[0].playing and not sorted[3].playing,
		"sorted order puts the playing sides first, so a scoreboard does not open with "
		+ "the spectators"
	)

	var ffa := DotTeamSet.free_for_all()
	_check(ffa.playing_teams().size() == 1, "free-for-all is one playing side")
	_check(
		ffa.get_team(&"players").friendly_fire,
		"with friendly fire on, because 'no teams' modelled as no teams makes every "
		+ "consumer branch on whether teams exist"
	)

	var ad := DotTeamSet.attack_defend()
	_check(bool(ad.get_team(&"attackers").attribute("attacks", false)), "attackers attack")
	_check(not bool(ad.get_team(&"defenders").attribute("attacks", false)), "defenders do not")

	_check(DotTeamSet.four_way().playing_teams().size() == 4, "four-way has four")
	_check(DotTeamSet.presets().size() == 4, "there are four presets")
	_check(DotTeamSet.preset(&"ffa") != null, "resolving by name")
	_check(DotTeamSet.preset(&"nope") == null, "and nothing for a name that is not one")

	var dup := DotTeamSet.new()
	dup.teams = [DotTeamDef.make(&"a"), DotTeamDef.make(&"a")]
	_check(not dup.build().ok, "two teams with one name are refused")

	var nobody := DotTeamSet.new()
	nobody.teams = [DotTeamDef.make(&"spec", "Spectators", Color.GRAY, false)]
	_check(
		not nobody.build().ok,
		"a set where nothing plays is refused: a round whose only sides are spectators "
		+ "cannot end"
	)

	_check(not DotTeamSet.new().build().ok, "and so is an empty one")
	_check(pair.describe_lines().size() == 5, "a set describes itself")


func _test_policy() -> void:
	_section("policy")

	var p := DotTeamPolicy.new()
	_check(p.validate().ok, "the defaults validate")
	_check(p.max_difference == 1, "allowing one player of difference")
	_check(p.switch_cooldown_ticks() == 30 * 60, "with a thirty-second cooldown")

	var zero := DotTeamPolicy.new()
	zero.max_difference = 0
	_check(
		not zero.validate().ok,
		"exactly equal sides are refused: an odd number of players cannot satisfy it, "
		+ "so every join past the first odd one bounces and the server looks full"
	)

	var stuck := DotTeamPolicy.new()
	stuck.allow_choice = false
	stuck.auto_assign = false
	_check(not stuck.validate().ok, "and so is a policy where nobody ever gets a side")

	_check(DotTeamPolicy.casual().autobalance == false, "casual does not rebalance")
	_check(DotTeamPolicy.competitive().lock_when_live, "competitive locks during a round")
	_check(
		not DotTeamPolicy.competitive().allow_switch_while_alive,
		"and does not let a living player move, which is a teleport or an escape"
	)
	_check(DotTeamPolicy.free_for_all().allow_switch == false, "free-for-all has nowhere to go")
	_check(DotTeamPolicy.presets().size() == 3, "three presets")
	_check(DotTeamPolicy.preset(&"casual") != null, "resolving by name")
	_check(p.env_prefix() == "DOT_TEAM_", "and the config layers the family's way")


# --- Balance arithmetic -----------------------------------------------------

func _test_balance_maths() -> void:
	_section("balance arithmetic")

	var order: Array[StringName] = [&"blue", &"red"]

	_check(DotTeamBalance.smallest({"blue": 3, "red": 1}, order) == &"red", "smallest is smallest")
	_check(DotTeamBalance.largest({"blue": 3, "red": 1}, order) == &"blue", "largest is largest")
	_check(
		DotTeamBalance.smallest({"blue": 2, "red": 2}, order) == &"blue",
		"a tie resolves to the first in the declared order, deterministically — a "
		+ "client previewing which side it will land on and a server deciding must agree"
	)
	_check(DotTeamBalance.spread({"blue": 5, "red": 1}, order) == 4, "spread is the difference")
	_check(DotTeamBalance.spread({}, order) == 0, "an empty session has no spread")
	_check(DotTeamBalance.balanced({"blue": 3, "red": 2}, order, 1), "one apart is balanced")
	_check(not DotTeamBalance.balanced({"blue": 4, "red": 2}, order, 1), "two apart is not")

	_check(
		DotTeamBalance.would_unbalance({"blue": 3, "red": 3}, order, &"blue", 1) == false,
		"joining an even pair is fine"
	)
	_check(
		DotTeamBalance.would_unbalance({"blue": 4, "red": 3}, order, &"blue", 1),
		"joining the bigger side of an uneven one is not"
	)

	var plan := DotTeamBalance.moves_to_balance({"blue": 6, "red": 2}, order, 1)
	_check(plan.size() == 2, "six against two needs two moves")
	_check(
		plan[0]["from"] == &"blue" and plan[0]["to"] == &"red",
		"from the big side to the small one"
	)
	_check(
		DotTeamBalance.moves_to_balance({"blue": 3, "red": 3}, order, 1).is_empty(),
		"and an even session needs none, which is the common case"
	)
	_check(
		DotTeamBalance.moves_to_balance({"blue": 0, "red": 0}, order, 1).is_empty(),
		"an empty one too"
	)
	_check(
		DotTeamBalance.moves_to_balance({"blue": 4}, order, 1).size() <= 256,
		"a count missing a side terminates rather than spinning until the guard trips"
	)

	# Victim selection.
	var candidates: Array[Dictionary] = [
		{"key": "old", "joined_tick": 10, "score": 90.0, "alive": false},
		{"key": "mid", "joined_tick": 50, "score": 10.0, "alive": true},
		{"key": "new", "joined_tick": 99, "score": 50.0, "alive": false},
	]

	_check(
		DotTeamBalance.choose_victim(candidates, DotTeamPolicy.Victim.NEWEST, true) == "new",
		"the newest is the fairest: whoever joined most recently has the least "
		+ "invested in the side they are on"
	)
	_check(
		DotTeamBalance.choose_victim(candidates, DotTeamPolicy.Victim.OLDEST, true) == "old",
		"the oldest rule picks the other end"
	)
	_check(
		DotTeamBalance.choose_victim(candidates, DotTeamPolicy.Victim.LOWEST_SCORE, true) == "mid",
		"the lowest score picks by score"
	)
	_check(
		DotTeamBalance.choose_victim(candidates, DotTeamPolicy.Victim.NEWEST, false) == "new",
		"and the living are skipped when the policy says so"
	)
	_check(
		DotTeamBalance.choose_victim(candidates, DotTeamPolicy.Victim.LOWEST_SCORE, false) == "new",
		"which changes the answer: 'mid' has the lowest score and is alive"
	)

	var all_alive: Array[Dictionary] = [{"key": "a", "alive": true}]
	_check(
		DotTeamBalance.choose_victim(all_alive, DotTeamPolicy.Victim.NEWEST, false) == "",
		"nobody eligible answers nothing, which is the right answer for a round where "
		+ "everybody on the big side is alive"
	)
	_check(
		DotTeamBalance.choose_victim([], DotTeamPolicy.Victim.NEWEST, true) == "",
		"and an empty side has nobody to give up"
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	_check(
		DotTeamBalance.choose_victim(candidates, DotTeamPolicy.Victim.RANDOM, true, rng) != "",
		"the random rule picks somebody when given a generator"
	)
	_check(
		DotTeamBalance.choose_victim(candidates, DotTeamPolicy.Victim.RANDOM, true) == "new",
		"and falls back to the newest without one, rather than to something two "
		+ "machines would disagree about"
	)

	_check(
		DotTeamBalance.explain(&"blue", &"red", "ada", 3).contains("ada"),
		"and a move can be explained in one line"
	)


# --- The roster -------------------------------------------------------------

func _test_membership() -> void:
	_section("membership")

	_alive.clear()
	var r := _roster()

	var changes: Array = []
	r.team_changed.connect(func(key: String, from: StringName, to: StringName, why: StringName) -> void:
		changes.append([key, String(from), String(to), String(why)])
	)

	_check(r.setup().ok, "a roster sets up")
	_check(r.add("a").ok, "somebody is added")
	_check(r.team_of("a") == &"blue", "onto the first playing side")
	_check(r.add("b").ok, "and a second")
	_check(r.team_of("b") == &"red", "onto the other, because it was smaller")
	_check(r.add("c").ok, "a third")
	_check(r.team_of("c") == &"blue", "back onto the first")
	_check(changes.size() == 3, "with a signal each")
	_check(changes[0][3] == "joined", "saying why")

	_check(r.counts() == {&"blue": 2, &"red": 1}, "the counts are right")
	_check(r.count_on(&"blue") == 2, "and read one at a time")
	_check(r.spread() == 1, "the spread is one")
	_check(r.is_balanced(), "which is balanced")
	_check(r.members(&"blue") == PackedStringArray(["a", "c"]), "a side lists its members")
	_check(r.keys().size() == 3, "and the roster lists everybody, in join order")

	_check(r.are_enemies("a", "b"), "opposing players are enemies")
	_check(not r.are_enemies("a", "c"), "team-mates are not")
	_check(not r.are_enemies("a", "a"), "and nobody is their own")
	_check(r.are_allies("a", "c"), "team-mates are allies")
	_check(r.are_allies("a", "a"), "and so is everybody with themselves")
	_check(not r.are_allies("a", "b"), "opponents are not")

	var _spec := r.force_team("c", DotTeamSet.SPECTATOR)
	_check(r.team_of("c") == DotTeamSet.SPECTATOR, "somebody can be forced to spectate")
	_check(
		not r.are_enemies("a", "c") and not r.are_allies("a", "c"),
		"and is then neither an enemy nor an ally, which is the whole point of the "
		+ "playing flag"
	)
	_check(r.counts()[&"blue"] == 1, "and is out of the playing counts")

	_check(not r.force_team("a", &"nonexistent").ok, "an unknown side is refused")
	_check(r.add("a").ok, "adding somebody twice is not an error")
	_check(r.keys().size() == 3, "and does not duplicate them")

	_check(r.remove("c").ok, "somebody leaves")
	_check(not r.has_player("c"), "and is gone")
	_check(not r.remove("c").ok, "removing them again is refused")

	_check(r.describe_lines().size() == 5, "and the roster describes itself")

	# A team with a size limit.
	var capped := DotTeamSet.standard_pair()
	capped.get_team(&"blue").max_players = 1
	var cr := _roster(capped)
	var _ca := cr.add("x")
	var _cb := cr.add("y")
	var _cc := cr.add("z")
	_check(
		cr.count_on(&"blue") == 1,
		"a capped side stops taking people"
	)

	capped.get_team(&"red").max_players = 1
	var _cd := cr.add("w")
	_check(
		cr.team_of("w") == DotTeamSet.UNASSIGNED,
		"and when every playing side is full, the holding pen is the honest answer — "
		+ "putting somebody on a full team to avoid an awkward return value is how a "
		+ "five-slot mode ends up with nine players"
	)

	r.queue_free()
	cr.queue_free()


func _test_switching() -> void:
	_section("switching")

	_alive.clear()
	_live = false

	var policy := DotTeamPolicy.new()
	policy.switch_cooldown_sec = 10.0
	# Balance enforcement is checked on its own roster below. Left on here, an even
	# four-player session refuses every switch and the cooldown checks could not fail.
	policy.enforce_balance_on_switch = false
	var r := _roster(null, policy)

	for key in ["a", "b", "c", "d"]:
		var _res := r.add(key)

	var refusals: Array = []
	r.switch_refused.connect(func(key: String, to: StringName, why: String) -> void:
		refusals.append([key, String(to), why])
	)

	_check(r.team_of("a") == &"blue", "a starts blue")
	_check(r.request_switch("a", &"blue", 0).ok, "switching to your own side is a no-op")

	var moved := r.request_switch("a", &"red", 0)
	_check(moved.ok, "and a real switch is allowed")
	_check(r.team_of("a") == &"red", "and lands")

	var too_soon := r.request_switch("a", &"blue", 100)
	_check(not too_soon.ok, "a second switch inside the cooldown is refused")
	_check(
		too_soon.error.message.contains("seconds"),
		"with the wait in seconds, because 'nothing happened when I clicked' is the "
		+ "worst possible answer"
	)
	_check(refusals.size() == 1, "and a signal so a client can say so")

	_check(r.request_switch("a", &"blue", 100 + policy.switch_cooldown_ticks()).ok,
		"and allowed once the cooldown is up")

	_alive["b"] = true
	var alive_switch := r.request_switch("b", &"blue", 10000)
	_check(
		not alive_switch.ok,
		"a living player cannot switch: a body moved to the other side's spawn is "
		+ "either a teleport into their base or a free escape from a fight"
	)
	_alive["b"] = false

	policy.lock_when_live = true
	_live = true
	_check(not r.request_switch("b", &"blue", 20000).ok, "sides lock while a round is live")
	_live = false

	policy.allow_switch = false
	_check(not r.request_switch("b", &"blue", 30000).ok, "and a server can turn it off")
	policy.allow_switch = true

	_check(not r.request_switch("nobody", &"blue", 0).ok, "an unknown player is refused")

	# Balance enforcement on a switch.
	var even := _roster()
	for key in ["p", "q", "r", "s"]:
		var _res := even.add(key)
	_check(even.counts() == {&"blue": 2, &"red": 2}, "four players are even")
	var unbalancing := even.request_switch("p", &"red", 0)
	_check(
		not unbalancing.ok,
		"and a switch that would make them uneven is refused, which is what stops the "
		+ "whole server moving to whichever side is winning"
	)

	even.policy.enforce_balance_on_switch = false
	_check(
		even.request_switch("p", &"red", 0).ok,
		"unless the server would rather let people play where they like"
	)

	r.queue_free()
	even.queue_free()


func _test_rebalancing() -> void:
	_section("rebalancing")

	_alive.clear()
	var policy := DotTeamPolicy.competitive()
	policy.tick_rate = RATE
	var r := _roster(null, policy)

	# Force a lopsided session, which is what a round of people quitting produces.
	for key in ["a", "b", "c", "d", "e", "f"]:
		var _add := r.add(key)
		var _force := r.force_team(key, &"blue")

	_check(r.counts() == {&"blue": 6, &"red": 0}, "six against nobody")
	_check(not r.is_balanced(), "which is not balanced")

	var reported: Array = []
	r.balanced.connect(func(moves: Array) -> void: reported.append(moves.size()))

	var moves := r.rebalance(0)
	_check(moves.size() == 3, "three moves put it right")
	_check(r.is_balanced(), "and it is balanced afterwards")
	_check(r.counts() == {&"blue": 3, &"red": 3}, "three against three")
	_check(reported.size() == 1 and int(reported[0]) == 3, "with one signal carrying them")
	_check(
		String(moves[0]["from"]) == "blue",
		"and every move says where from and where to, so a chat line can name it"
	)

	_check(r.rebalance(1).is_empty(), "a second pass does nothing")

	# Determinism: the same session rebalances the same way.
	var again := _roster(null, policy)
	for key in ["a", "b", "c", "d", "e", "f"]:
		var _add2 := again.add(key)
		var _force2 := again.force_team(key, &"blue")
	var moves2 := again.rebalance(0)
	var same := moves2.size() == moves.size()
	for i in range(mini(moves.size(), moves2.size())):
		if str(moves[i]["key"]) != str(moves2[i]["key"]):
			same = false
	_check(
		same,
		"two servers running the same session make the same moves — being moved is "
		+ "being punished for the server's arithmetic, and arbitrary is indefensible"
	)

	# Everybody alive, and the policy forbidding moving them.
	var stuck := _roster(null, policy)
	for key in ["g", "h", "i", "j"]:
		var _add3 := stuck.add(key)
		var _force3 := stuck.force_team(key, &"blue")
		_alive[key] = true
	_check(
		stuck.rebalance(0).is_empty(),
		"with everybody on the big side alive and the policy forbidding it, nobody "
		+ "moves — which is correct, and is a stop rather than a loop"
	)
	_check(not stuck.is_balanced(), "so the session stays uneven, visibly")

	policy.autobalance = false
	_check(r.rebalance(2).is_empty(), "a server that does not rebalance does not")

	_alive.clear()
	r.queue_free()
	again.queue_free()
	stuck.queue_free()


func _test_mirror_and_match() -> void:
	_section("mirroring and dot-match")

	var server := _roster()
	var _a := server.add("a")
	var _b := server.add("b")

	var client := DotTeamRoster.new()
	client.authoritative = false
	client.register_service = false
	client.teams = DotTeamSet.standard_pair()
	client.policy = DotTeamPolicy.new()
	add_child(client)

	_check(client.apply_wire(server.to_wire()).ok, "assignments travel")
	_check(client.team_of("a") == server.team_of("a"), "and land")
	_check(client.keys() == server.keys(), "in the same order")

	_check(not client.add("c").ok, "a mirror adds nobody")
	_check(not client.force_team("a", &"red").ok, "and moves nobody")
	_check(not client.request_switch("a", &"red").ok, "and grants no switches")
	_check(client.rebalance(0).is_empty(), "and rebalances nothing")
	_check(
		not server.apply_wire({}).ok,
		"and the authoritative one is not told who is on which side"
	)

	# The dot-match bridge, duck-typed.
	var fake := FakeMatch.new()
	add_child(fake)
	_check(server.bind_match(fake).ok, "a team manager can be bound")
	_check(
		fake.assignments.size() == 2,
		"and everybody already assigned is pushed to it, so binding late is not a "
		+ "silent half-configuration"
	)
	var _c := server.add("c")
	_check(fake.assignments.size() == 3, "with new assignments following"	)
	_check(
		int(fake.assignments["a"]) != int(fake.assignments["b"]),
		"and the two sides map to different ids"
	)
	_check(
		int(fake.assignments["a"]) >= 1,
		"which are the MANAGER's ids, not dot-team's positions — dot-match's pair is 1 "
		+ "and 2, and passing a position straight through would put half the server on "
		+ "a side that does not exist"
	)
	server.match_tick_fn = func() -> int: return 99
	var _late := server.force_team("a", &"red", &"test")
	_check(int(fake.ticks["a"]) == 99, "and a supplied tick reaches it")

	var _spec := server.force_team("c", DotTeamSet.SPECTATOR)
	_check(
		fake.assignments.size() == 3,
		"a move to a non-playing side is not pushed, because dot-match's sides are the "
		+ "playing ones and there is no index for 'watching'"
	)

	var wrong := Node.new()
	add_child(wrong)
	_check(
		not server.bind_match(wrong).ok,
		"an object with no assign() is refused rather than silently doing nothing"
	)
	_check(server.bind_match(null).ok, "and it can be unbound")

	server.queue_free()
	client.queue_free()
	fake.queue_free()
	wrong.queue_free()


## Stands in for dot-match's DotTeamManager, which this project does not depend on.
##
## [b]The signature and the id numbering are copied from the real one deliberately.[/b]
## dot-match's is `assign(key, tick, team)` and its `standard_pair()` uses ids 1 and 2 —
## not 0 and 1, and not positions. A stand-in that took two arguments and stored the
## index would pass while the real manager errored on every call, which is the exact
## shape of a bridge that is only ever tested against its own mock.
class FakeMatch extends Node:
	var assignments: Dictionary = {}
	var ticks: Dictionary = {}

	var teams: Array = [FakeTeam.new(1), FakeTeam.new(2)]

	func assign(key: String, tick: int, team: int) -> DotResult:
		assignments[key] = team
		ticks[key] = tick
		return DotResult.success(null)


class FakeTeam extends RefCounted:
	var id: int = 0

	func _init(p_id: int) -> void:
		id = p_id


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
