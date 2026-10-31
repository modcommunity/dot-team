class_name DotTeamMenuServer
extends RefCounted

## The server half of the team menu (period key): `teams` answers with a `team_menu` notice, and `teams <id>`, `teams auto`, `teams spectate` and `teams play` switch. The game supplies the callables below, so this never depends on how it keeps teams.
## Every rule is a cvar read per request: mp_teamswitch_enabled, _cooldown (seconds), _imbalance (how many more than the smallest team a join may leave, -1 none), _maxplayers (cap per team when the team has none of its own, 0 none), _anytime (0: only when window_fn says so), _kill (1: a switch kills), _spectate. Spectating is always on offer unless _spectate is 0.

const CHANNEL := "team.menu"
const TOPIC := &"team_menu"
const NOTICE_SCRIPT := "res://addons/dot_server/net/dot_notice.gd"
const DEFAULTS := {"teams": "teams"}

## Menu choice meaning "watch, do not play".
const SPECTATE := "spectate"
const PLAY := "play"

const SPECS := [
	{"name": "mp_teamswitch_enabled", "value": "1", "description": "1: players may pick their team from the menu (period)."},
	{"name": "mp_teamswitch_cooldown", "value": "5", "description": "Seconds a player waits between team switches."},
	{"name": "mp_teamswitch_imbalance", "value": "1", "description": "A join may leave the new team at most this many players above the smallest other team. -1: no limit."},
	{"name": "mp_teamswitch_maxplayers", "value": "0", "description": "Most players on one team when the team has no limit of its own. 0: none."},
	{"name": "mp_teamswitch_anytime", "value": "1", "description": "1: switch at any time. 0: only where the mode allows (between rounds, or while dead)."},
	{"name": "mp_teamswitch_kill", "value": "0", "description": "1: switching teams while alive kills the player."},
	{"name": "mp_teamswitch_spectate", "value": "1", "description": "1: the menu offers Spectate."},
]

var prefix: String = ""
var names: Dictionary = {}
var registered: PackedStringArray = PackedStringArray()

## `func() -> Array` of `{id:int, name:String, colour:String, count:int, max:int}`; empty is a free-for-all.
var teams_fn: Callable = Callable()
## `func(key) -> Dictionary` `{team:int (-1 none), spectating:bool}`.
var state_fn: Callable = Callable()
## `func(key, team_id:int, kill:bool) -> DotResult`: move the player.
var join_fn: Callable = Callable()
## `func(key) -> DotResult`: start watching.
var spectate_fn: Callable = Callable()
## `func(key) -> DotResult`: free-for-all: start playing.
var play_fn: Callable = Callable()
## `func(key) -> bool`: whether a switch is allowed right now when mp_teamswitch_anytime is 0.
var window_fn: Callable = Callable()
## `func(ctx) -> key`; null refuses. The default is the session's userid.
var key_fn: Callable = Callable()
## `func(ctx, data) -> bool`: unset sends a notice through the `dot_server` service.
var notice_fn: Callable = Callable()
## `func() -> float`: seconds, for a suite.
var clock_fn: Callable = Callable()

var last_menu: Dictionary = {}
var last_result: Dictionary = {}

var _cvars: Dictionary = {}
var _last_switch: Dictionary = {}


## Registers the cvars; [param add] is `(name, value, help, flags) -> cvar`.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec: Dictionary in SPECS:
		var cv: Variant = add.call(spec["name"], spec["value"], spec["description"], flags)
		if cv is Object:
			_cvars[spec["name"]] = cv
			made.append(cv)
	return made


func install(host: Object) -> DotResult:
	if host == null:
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "No host to register commands on.")
	var adder := "add_command" if host.has_method("add_command") else ("command" if host.has_method("command") else "")
	if adder == "":
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "That host has no way to register a command.")
	for full in DotCommandNames.all_of(prefix, names, DEFAULTS, "teams"):
		if not DotCommandNames.available(host, full, registered, "teams", "team"):
			continue
		var command: Variant = host.call(adder, full, _cmd, "The team menu: list the teams, or switch: [team id|auto|spectate|play]", "")
		if command is Object and (command as Object).has_method("with_chat"):
			(command as Object).call("with_chat")
		registered.append(full)
	DotLog.info(CHANNEL, "commands registered", {"count": registered.size()})
	return DotResult.success(registered)


## Clears the callables the owner gave, which usually point back at the owner.
func release() -> void:
	teams_fn = Callable()
	state_fn = Callable()
	join_fn = Callable()
	spectate_fn = Callable()
	play_fn = Callable()
	window_fn = Callable()
	key_fn = Callable()
	notice_fn = Callable()
	clock_fn = Callable()


func value(cvar_name: String) -> float:
	var cv: Variant = _cvars.get(cvar_name)
	if cv is Object and is_instance_valid(cv) and (cv as Object).has_method("get_string"):
		var text := str((cv as Object).call("get_string")).strip_edges()
		if text.is_valid_float():
			return text.to_float()
	for spec: Dictionary in SPECS:
		if spec["name"] == cvar_name:
			return str(spec["value"]).to_float()
	return 0.0


func _now() -> float:
	return float(clock_fn.call()) if clock_fn.is_valid() else Time.get_ticks_msec() / 1000.0


## What the menu shows [param key]: every team with its live count and why it is closed to them, if it is.
func menu_for(key: Variant) -> Dictionary:
	var rows: Array = teams_fn.call() if teams_fn.is_valid() else []
	var state: Dictionary = state_fn.call(key) if state_fn.is_valid() else {}
	var mine := int(state.get("team", -1))
	var out: Array = []
	for row: Variant in rows:
		var t := (row as Dictionary).duplicate()
		var why := _team_refusal(key, int(t["id"]), rows, state)
		t["closed"] = why
		t["current"] = mine == int(t["id"]) and not bool(state.get("spectating", false))
		out.append(t)
	var data := {
		"teams": out, "ffa": rows.is_empty(), "spectating": bool(state.get("spectating", false)),
		"enabled": value("mp_teamswitch_enabled") != 0.0, "spectate_ok": value("mp_teamswitch_spectate") != 0.0,
		"wait": maxf(0.0, _last_switch.get(key, -1e9) + value("mp_teamswitch_cooldown") - _now()),
	}
	last_menu = data
	return data


## Why [param key] cannot take [param team_id] right now, or "".
func _team_refusal(key: Variant, team_id: int, rows: Array, state: Dictionary) -> String:
	var target: Dictionary = {}
	for row: Variant in rows:
		if int((row as Dictionary)["id"]) == team_id:
			target = row
	if target.is_empty():
		return "No such team."
	var mine := int(state.get("team", -1))
	var playing := not bool(state.get("spectating", false))
	if playing and mine == team_id:
		return "You are already on this team."
	var cap := int(target.get("max", 0))
	if cap <= 0:
		cap = int(value("mp_teamswitch_maxplayers"))
	var count := int(target.get("count", 0))
	if cap > 0 and count >= cap:
		return "That team is full."
	var limit := int(value("mp_teamswitch_imbalance"))
	if limit >= 0:
		var smallest := 1 << 30
		for row: Variant in rows:
			var r := row as Dictionary
			if int(r["id"]) == team_id:
				continue
			var n := int(r.get("count", 0)) - (1 if playing and int(r["id"]) == mine else 0)
			smallest = mini(smallest, n)
		if smallest != 1 << 30 and count + 1 - smallest > limit:
			return "That team has enough players."
	return ""


## The checks every switch passes, in order; ok carries nothing.
func check(key: Variant, choice: String) -> DotResult:
	if value("mp_teamswitch_enabled") == 0.0:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Team switching is off on this server.")
	if choice == SPECTATE and value("mp_teamswitch_spectate") == 0.0:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Spectating is off on this server.")
	if value("mp_teamswitch_anytime") == 0.0 and window_fn.is_valid() and not bool(window_fn.call(key)):
		return DotResult.fail(DotError.CODE_STATE, "You can only switch between rounds or while dead.")
	var wait: float = _last_switch.get(key, -1e9) + value("mp_teamswitch_cooldown") - _now()
	if wait > 0.0:
		return DotResult.fail(DotError.CODE_RATE_LIMITED, "Wait %d s before switching again." % ceili(wait))
	return DotResult.success()


## Applies [param choice] (a team id, "auto", [constant SPECTATE] or [constant PLAY]) for [param key].
func request(key: Variant, choice: String) -> DotResult:
	var rows: Array = teams_fn.call() if teams_fn.is_valid() else []
	var state: Dictionary = state_fn.call(key) if state_fn.is_valid() else {}
	var res := check(key, choice)
	if not res.ok:
		return res
	var spectating := bool(state.get("spectating", false))
	if choice == SPECTATE:
		if spectating:
			return DotResult.fail(DotError.CODE_STATE, "You are already spectating.")
		res = spectate_fn.call(key) if spectate_fn.is_valid() else DotResult.fail(DotError.CODE_UNSUPPORTED, "This mode cannot spectate.")
	elif rows.is_empty():
		if not spectating:
			return DotResult.fail(DotError.CODE_STATE, "You are already playing.")
		res = play_fn.call(key) if play_fn.is_valid() else DotResult.fail(DotError.CODE_UNSUPPORTED, "This mode cannot join.")
	else:
		var team_id := -1
		if choice == "auto" or choice == PLAY:
			team_id = _smallest_open(key, rows, state)
			if team_id < 0:
				return DotResult.fail(DotError.CODE_STATE, "Every team is closed to you right now.")
		elif choice.is_valid_int():
			team_id = int(choice)
		else:
			return DotResult.fail(DotError.CODE_INVALID, "Usage: [team id|auto|spectate|play]")
		var why := _team_refusal(key, team_id, rows, state)
		if why != "":
			return DotResult.fail(DotError.CODE_STATE, why)
		res = join_fn.call(key, team_id, value("mp_teamswitch_kill") != 0.0) if join_fn.is_valid() else DotResult.fail(DotError.CODE_UNSUPPORTED, "This mode cannot switch.")
	if res.ok:
		_last_switch[key] = _now()
	return res


func _smallest_open(key: Variant, rows: Array, state: Dictionary) -> int:
	var best := -1
	var best_count := 1 << 30
	for row: Variant in rows:
		var r := row as Dictionary
		if _team_refusal(key, int(r["id"]), rows, state) != "":
			continue
		if int(r.get("count", 0)) < best_count:
			best_count = int(r.get("count", 0))
			best = int(r["id"])
	return best


func _cmd(ctx: Object) -> void:
	var key: Variant = _key(ctx)
	if key == null:
		ctx.call("reply", "Only players can pick a team.")
		return
	var args: Variant = ctx.get("args")
	var word := ""
	if args is PackedStringArray and not (args as PackedStringArray).is_empty():
		word = (args as PackedStringArray)[0].to_lower()
	var data := {}
	if word != "":
		var res := request(key, word)
		last_result = {"ok": res.ok, "message": "" if res.ok else (res.error.message if res.error != null else "Refused.")}
		if not res.ok:
			ctx.call("reply", last_result["message"])
	data = menu_for(key)
	if word != "":
		data["result"] = last_result
	var _sent := _send(ctx, data)


func _key(ctx: Object) -> Variant:
	if key_fn.is_valid():
		return key_fn.call(ctx)
	var session: Variant = ctx.get("session")
	if session is Object:
		var userid: Variant = (session as Object).get("userid")
		if userid != null:
			return int(userid)
	return null


func _send(ctx: Object, data: Dictionary) -> bool:
	if notice_fn.is_valid():
		return bool(notice_fn.call(ctx, data))
	var session: Variant = ctx.get("session")
	if not (session is Object) or not ResourceLoader.exists(NOTICE_SCRIPT):
		return false
	var server: Object = DotRegistry.get_service(&"dot_server")
	if server == null or not server.has_method("send_notice"):
		return false
	var notice: Object = (load(NOTICE_SCRIPT) as GDScript).call("make", &"", "", -1.0, TOPIC, data)
	return bool(server.call("send_notice", session, notice))


func describe() -> Dictionary:
	return {"commands": registered, "cvars": _cvars.size(), "teams_fn": teams_fn.is_valid(),
		"last_menu_teams": (last_menu.get("teams", []) as Array).size(), "last_result": last_result}
