class_name DotTeamBlockRules
extends RefCounted

## Whether two players stop at each other, per pair; handed to `DotPlayerBodyRules.pair_fn` as
## `rules.blocks`. Teammates (same [member side_fn] side) pass, enemies and sideless keys block
## by `mp_enemyblock`; `!noblock`/`!block` requests ([method request]) replicate as [constant CVAR_STATE].

signal changed

enum Relation { TEAM, ENEMY }

const CVAR_TEAM := "mp_teamblock"
const CVAR_ENEMY := "mp_enemyblock"
const CVAR_CMD := "mp_blockcmd"
const CVAR_RELATIONS := "mp_blockcmd_relations"
const CVAR_SCOPE := "mp_blockscope"
const CVAR_STATE := "mp_blockstate"

var config: DotTeamBlockConfig = DotTeamBlockConfig.new()

## `(key) -> side id` (StringName or String; empty or null for none).
var side_fn: Callable = Callable()

## Optional: a side counts as a team only if the set says it is playing, and only when two are.
var team_set: DotTeamSet = null

## Holder -> `[team_override, enemy_override]`, each -1 unset, 0 pass, 1 block.
var _overrides: Dictionary = {}
var _cvars: Dictionary = {}
var _writing: bool = false


## Whether [param a] and [param b] are teammates or enemies.
func relation(a: Variant, b: Variant) -> int:
	var side_a := _side(a)
	var side_b := _side(b)
	if side_a == "" or side_b == "" or side_a != side_b:
		return Relation.ENEMY
	if team_set != null:
		if team_set.playing_teams().size() < 2 or not team_set.is_playing(StringName(side_a)):
			return Relation.ENEMY
	return Relation.TEAM


## Whether [param a] and [param b] stop at each other.
func blocks(a: Variant, b: Variant) -> bool:
	var rel := relation(a, b)
	var base := config.team_block if rel == Relation.TEAM else config.enemy_block
	var from_a := _override(a, rel)
	var from_b := _override(b, rel)
	if base:
		return from_a != 0 and from_b != 0
	return from_a == 1 and from_b == 1


## Whether [param key] may use the commands, and why not.
func may_request(is_admin: bool) -> DotResult:
	match config.command_mode:
		0:
			return DotResult.fail(DotError.CODE_FORBIDDEN, "Block commands are disabled on this server.")
		1:
			if not is_admin:
				return DotResult.fail(DotError.CODE_FORBIDDEN, "Only admins may change collision here.")
	return DotResult.success(true)


## Records [param key]'s wish for [param relations] (a Relation list); [param block] -1 clears.
## Refuses by the command mode and the allowed relations.
func request(key: Variant, relations: Array, block: int, is_admin: bool = false) -> DotResult:
	var allowed := may_request(is_admin)
	if not allowed.ok:
		return allowed
	for rel: Variant in relations:
		if (config.command_relations & (1 << int(rel))) == 0 and not is_admin:
			return DotResult.fail(DotError.CODE_FORBIDDEN, "The server does not let players change that.")
	var holder := _holder(key)
	var held: Array = _overrides.get(holder, [-1, -1])
	for rel: Variant in relations:
		held[int(rel)] = block
	if held == [-1, -1]:
		_overrides.erase(holder)
	else:
		_overrides[holder] = held
	_publish()
	return DotResult.success(true)


## What [param key] asked for [param rel]: -1 nothing, 0 pass, 1 block.
func requested(key: Variant, rel: int) -> int:
	return _override(key, rel)


## Drops a leaver's requests (a team's stay: they belong to the side).
func forget(key: Variant) -> void:
	if config.scope == 0 and _overrides.erase(_holder(key)):
		_publish()


func clear() -> void:
	if _overrides.is_empty():
		return
	_overrides.clear()
	_publish()


## The requests as one line, `holder=TE;holder=TE` with `-`, `0` or `1` per relation.
func state_string() -> String:
	var parts := PackedStringArray()
	var holders: Array = _overrides.keys()
	holders.sort()
	for holder: Variant in holders:
		var held: Array = _overrides[holder]
		parts.append("%s=%s%s" % [holder, _digit(held[0]), _digit(held[1])])
	return ";".join(parts)


func apply_state_string(text: String) -> void:
	var next := {}
	for part in text.split(";", false):
		var pair := part.rsplit("=", true, 1)
		if pair.size() != 2 or pair[1].length() != 2:
			continue
		next[pair[0]] = [_undigit(pair[1][0]), _undigit(pair[1][1])]
	if next == _overrides:
		return
	_overrides = next
	changed.emit()


func cvar_specs() -> Array[Dictionary]:
	return [
		{"name": CVAR_TEAM, "value": "1" if config.team_block else "0", "min": 0.0, "max": 1.0,
			"description": "Teammates: 1 stop at each other, 0 pass through (default)"},
		{"name": CVAR_ENEMY, "value": "1" if config.enemy_block else "0", "min": 0.0, "max": 1.0,
			"description": "Enemies and players with no team: 1 stop at each other (default), 0 pass through"},
		{"name": CVAR_CMD, "value": str(config.command_mode), "min": 0.0, "max": 2.0,
			"description": "!block and !noblock: 0 disabled, 1 admins only, 2 everyone"},
		{"name": CVAR_RELATIONS, "value": str(config.command_relations), "min": 1.0, "max": 3.0,
			"description": "What the commands may change: 1 teammates, 2 enemies, 3 both"},
		{"name": CVAR_SCOPE, "value": str(config.scope), "min": 0.0, "max": 1.0,
			"description": "Whose collision a command changes: 0 the caller's, 1 the caller's team"},
	]


## Registers the cvars (see `DotPlayerBodyRules.bind_cvars` for [param add]) and
## [constant CVAR_STATE]. Pass dot-server's FLAG_REPLICATED: a client predicts against them.
## [param state_flags] for the state is the replicated flag with hidden and not archived.
func bind_cvars(add: Callable, flags: int = 0, state_flags: int = 0) -> Array:
	var made: Array = []
	var specs := cvar_specs()
	specs.append({"name": CVAR_STATE, "value": "", "min": NAN,
		"description": "Who asked to pass through or block (managed by the server)"})
	for spec in specs:
		var cvar_name: String = spec["name"]
		var is_state := cvar_name == CVAR_STATE
		var made_cvar: Variant = add.call(cvar_name, String(spec["value"]), String(spec["description"]),
			state_flags if is_state else flags)
		if not (made_cvar is Object) or made_cvar == null:
			continue
		var cv := made_cvar as Object
		_cvars[cvar_name] = cv
		if not is_state and cv.has_method(&"with_range"):
			cv.call(&"with_range", float(spec["min"]), float(spec["max"]))
		if cv.has_signal(&"changed"):
			cv.connect(&"changed", _on_cvar_changed.bind(cvar_name))
		if cv.has_method(&"get_string"):
			var _applied := set_cvar(cvar_name, String(cv.call(&"get_string")))
		made.append(cv)
	return made


## Follows a server's values through its link; false for an older shell's link.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for cvar_name: String in [CVAR_TEAM, CVAR_ENEMY, CVAR_CMD, CVAR_RELATIONS, CVAR_SCOPE, CVAR_STATE]:
		var held := String(source.call(&"replicated_cvar", cvar_name, "\u0001"))
		if held != "\u0001":
			var _applied := set_cvar(cvar_name, held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated_cvar):
		source.connect(&"replicated_cvar_changed", _on_replicated_cvar)
	return true


func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()
	if cvar_name == CVAR_STATE:
		apply_state_string(text)
		return true
	if not text.is_valid_int():
		return false
	var number := text.to_int()
	match cvar_name:
		CVAR_TEAM:
			config.team_block = number != 0
		CVAR_ENEMY:
			config.enemy_block = number != 0
		CVAR_CMD:
			config.command_mode = clampi(number, 0, 2)
		CVAR_RELATIONS:
			config.command_relations = clampi(number, 1, 3)
		CVAR_SCOPE:
			var scope := clampi(number, 0, 1)
			if scope != config.scope:
				config.scope = scope
				_overrides.clear()
				_publish()
		_:
			return false
	changed.emit()
	return true


func describe() -> Dictionary:
	return {"team_block": config.team_block, "enemy_block": config.enemy_block,
		"command_mode": config.command_mode, "scope": config.scope, "requests": state_string()}


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"teammates: %s, enemies: %s" % [
			"stop" if config.team_block else "pass through", "stop" if config.enemy_block else "pass through"],
		"commands: %s, scope %s, requests [%s]" % [
			["off", "admins", "everyone"][config.command_mode],
			["player", "team"][config.scope], state_string()],
	])


func _side(key: Variant) -> String:
	if not side_fn.is_valid():
		return ""
	var side: Variant = side_fn.call(key)
	return "" if side == null else str(side)


func _holder(key: Variant) -> String:
	if config.scope == 1:
		var side := _side(key)
		if side != "":
			return "t:" + side
	return str(key)


func _override(key: Variant, rel: int) -> int:
	var held: Variant = _overrides.get(_holder(key))
	return int((held as Array)[rel]) if held != null else -1


func _publish() -> void:
	changed.emit()
	var cv: Variant = _cvars.get(CVAR_STATE)
	if cv is Object and cv != null and (cv as Object).has_method(&"set_value"):
		_writing = true
		(cv as Object).call(&"set_value", state_string())
		_writing = false


func _on_cvar_changed(_old: Variant, new_value: Variant, cvar_name: String) -> void:
	if cvar_name == CVAR_STATE and _writing:
		return
	var _applied := set_cvar(cvar_name, str(new_value))


func _on_replicated_cvar(cvar_name: String, value: String) -> void:
	var _applied := set_cvar(cvar_name, value)


static func _digit(value: int) -> String:
	return "-" if value < 0 else str(value)


static func _undigit(ch: String) -> int:
	return -1 if ch == "-" else clampi(int(ch), 0, 1)
