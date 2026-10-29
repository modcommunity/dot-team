extends Node
## Harness, fakes and the block-rule checks of team_selftest.gd, split out for file size.

var _passed := 0
var _failed := 0
var _section_count := 0


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


func _test_block() -> void:
	_section("Block rules: teammates pass, enemies stop")
	var sides := {1: &"blue", 2: &"blue", 3: &"red", 4: &"", 5: &"spectators"}
	var rules := DotTeamBlockRules.new()
	rules.side_fn = func(key: Variant) -> Variant: return sides.get(int(key), &"")
	rules.team_set = DotTeamSet.standard_pair()
	_check(not rules.blocks(1, 2), "two teammates pass through each other by default")
	_check(rules.blocks(1, 3), "enemies stop at each other by default")
	_check(rules.blocks(1, 4) and rules.blocks(4, 4), "a player with no team is an enemy of everyone, so stays solid")
	_check(rules.blocks(1, 5) and rules.blocks(5, 5), "spectators are nobody's teammates")

	var ffa := DotTeamBlockRules.new()
	ffa.side_fn = func(_key: Variant) -> Variant: return &"players"
	ffa.team_set = DotTeamSet.free_for_all()
	_check(ffa.blocks(1, 2), "a free-for-all (one playing side) stays solid")
	var solo := DotTeamBlockRules.new()
	_check(solo.blocks(1, 2), "a solo game with no side function stays solid")

	var made := _block_cvars(rules)
	var host := FakeHost.new()
	var session_one := _block_commands(rules, host, made)
	_block_client_and_modes(rules, host, session_one)


func _block_cvars(rules: DotTeamBlockRules) -> Dictionary:
	var made := {}
	var add := func(n: String, v: String, _d: String, _f: int) -> Object:
		var c := FakeCvar.new()
		c.value = v
		made[n] = c
		return c
	var _bound := rules.bind_cvars(add, 4, 4)
	_check(made.size() == 6 and (made[DotTeamBlockRules.CVAR_TEAM] as FakeCvar).value == "0"
		and (made[DotTeamBlockRules.CVAR_ENEMY] as FakeCvar).value == "1", "six cvars bound with the defaults 0 and 1")
	(made[DotTeamBlockRules.CVAR_TEAM] as FakeCvar).set_value("1")
	_check(rules.blocks(1, 2), "mp_teamblock 1 makes teammates stop")
	(made[DotTeamBlockRules.CVAR_TEAM] as FakeCvar).set_value("0")
	(made[DotTeamBlockRules.CVAR_ENEMY] as FakeCvar).set_value("0")
	_check(not rules.blocks(1, 3), "mp_enemyblock 0 lets enemies through")
	(made[DotTeamBlockRules.CVAR_ENEMY] as FakeCvar).set_value("1")
	var layered := DotTeamBlockConfig.new()
	var _env := layered.apply_dictionary({"team_block": true, "command_mode": 1})
	_check(layered.team_block and layered.command_mode == 1, "the layered config takes overrides")
	return made


func _block_commands(rules: DotTeamBlockRules, host: FakeHost, made: Dictionary) -> FakeSession:
	var commands := DotTeamBlockCommands.new(rules)
	_check(commands.install(host).ok and host.handlers.has("block") and host.handlers.has("noblock"),
		"!block and !noblock register on a duck-typed host")
	var session_one := FakeSession.new()
	session_one.userid = 1
	var ctx := FakeCtx.new()
	ctx.session = session_one
	host.handlers["block"].call(ctx)
	_check(not rules.blocks(1, 2), "!block from one player is not enough to make teammates stop")
	var session_two := FakeSession.new()
	session_two.userid = 2
	var ctx2 := FakeCtx.new()
	ctx2.session = session_two
	host.handlers["block"].call(ctx2)
	_check(rules.blocks(1, 2), "both asking makes the teammates stop")
	host.handlers["noblock"].call(ctx)
	_check(not rules.blocks(1, 2), "!noblock flips it back: passing wins")
	var ctx3 := FakeCtx.new()
	ctx3.session = session_one
	ctx3.args = PackedStringArray(["enemy"])
	host.handlers["noblock"].call(ctx3)
	_check(rules.blocks(1, 3) and not ctx3.replies.is_empty(), "players may not pass through enemies by default")
	ctx3.admin = true
	host.handlers["noblock"].call(ctx3)
	_check(not rules.blocks(1, 3) and rules.blocks(2, 3), "an admin may, and only for their own pairs")
	host.handlers["block"].call(FakeCtx.new())
	_check(rules.blocks(2, 3), "a console without a session is refused harmlessly")
	_check((made[DotTeamBlockRules.CVAR_STATE] as FakeCvar).value == rules.state_string(), "the state rides the replicated cvar")
	return session_one


func _block_client_and_modes(rules: DotTeamBlockRules, host: FakeHost, session_one: FakeSession) -> void:
	var client := DotTeamBlockRules.new()
	client.side_fn = rules.side_fn
	client.team_set = rules.team_set
	client.set_cvar(DotTeamBlockRules.CVAR_STATE, rules.state_string())
	_check(client.blocks(1, 2) == rules.blocks(1, 2) and client.blocks(1, 3) == rules.blocks(1, 3),
		"a client decodes the same pairs")

	rules.clear()
	rules.config.command_mode = 0
	var ctx4 := FakeCtx.new()
	ctx4.session = session_one
	host.handlers["noblock"].call(ctx4)
	_check(not rules.request(1, [0], 0).ok and rules.requested(1, 0) == -1, "mp_blockcmd 0 disables the commands")
	rules.config.command_mode = 1
	_check(not rules.request(1, [0], 0).ok and rules.request(1, [0], 0, true).ok, "mode 1 is admins only")
	rules.clear()
	rules.config.command_mode = 2
	rules.config.team_block = true
	rules.config.scope = 1
	_check(rules.request(1, [0], 0).ok and not rules.blocks(1, 2) and not rules.blocks(2, 1), "team scope: one member's request covers the team")
	_check(rules.blocks(1, 3) == rules.blocks(3, 1), "and the answer is symmetric")


class FakeCvar extends RefCounted:
	signal changed(old_value: String, new_value: String)
	var value := ""

	func get_string() -> String:
		return value

	func set_value(v: String, _context: Dictionary = {}) -> void:
		var old := value
		value = v
		changed.emit(old, v)

	func with_range(_lo: float, _hi: float) -> FakeCvar:
		return self


class FakeCtx extends RefCounted:
	var session: Object = null
	var args := PackedStringArray()
	var admin := false
	var replies: Array[String] = []

	func reply(text: String) -> void:
		replies.append(text)

	func has_permission(_flag: String) -> bool:
		return admin


class FakeSession extends RefCounted:
	var userid := 0


class FakeHost extends RefCounted:
	var handlers: Dictionary = {}

	func add_command(command_name: String, handler: Callable, _desc: String = "", _perm: String = "") -> Object:
		handlers[command_name] = handler
		return null
