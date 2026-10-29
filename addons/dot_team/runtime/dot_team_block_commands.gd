class_name DotTeamBlockCommands
extends RefCounted

## `!block`/`!noblock [team|enemy|all]` and `!block reset` over [DotTeamBlockRules]; the host
## has `add_command` or `command` (duck-typed like `DotVoteCommands`). Who may: `mp_blockcmd`.

const CHANNEL := "team.block.commands"
const DEFAULTS := {"block": "block", "noblock": "noblock"}

var rules: DotTeamBlockRules
var prefix: String = ""
var names: Dictionary = {}

## `(ctx) -> key` of the caller in the rules; the default is the session's userid, which is
## the player id in the family's games. Null refuses the line ("players only").
var key_fn: Callable = Callable()

## Called after a request, for a game that needs to reapply collision exceptions at once.
var applied_fn: Callable = Callable()

var registered: PackedStringArray = PackedStringArray()


func _init(p_rules: DotTeamBlockRules = null) -> void:
	rules = p_rules


func install(host: Object) -> DotResult:
	if host == null or rules == null:
		return DotResult.fail(DotError.CODE_INVALID, "A host and rules are both needed.")
	var adder := "add_command" if host.has_method("add_command") else ("command" if host.has_method("command") else "")
	if adder == "":
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "That host has no way to register a command.")
	var table := {
		"block": [func(ctx: Object) -> void: _run(ctx, 1), "Block teammates (or enemies) again: [team|enemy|all|reset]"],
		"noblock": [func(ctx: Object) -> void: _run(ctx, 0), "Walk through teammates (or enemies): [team|enemy|all]"],
	}
	for role: String in table:
		for full in DotCommandNames.all_of(prefix, names, DEFAULTS, role):
			if not DotCommandNames.available(host, full, registered, role, "team"):
				continue
			var entry: Array = table[role]
			var command: Variant = host.call(adder, full, entry[0], entry[1], "")
			if command is Object and (command as Object).has_method("with_chat"):
				(command as Object).call("with_chat")
			registered.append(full)
	DotLog.info(CHANNEL, "commands registered", {"count": registered.size()})
	return DotResult.success(registered)


func _run(ctx: Object, want: int) -> void:
	var key: Variant = _key(ctx)
	if key == null:
		ctx.call("reply", "Only players can change their collision.")
		return
	var word := ""
	var args: Variant = ctx.get("args")
	if args is PackedStringArray and not (args as PackedStringArray).is_empty():
		word = (args as PackedStringArray)[0].to_lower()
	var relations: Array = []
	var block := want
	match word:
		"", "all":
			relations = [DotTeamBlockRules.Relation.TEAM, DotTeamBlockRules.Relation.ENEMY]
		"team", "teammates", "friends":
			relations = [DotTeamBlockRules.Relation.TEAM]
		"enemy", "enemies":
			relations = [DotTeamBlockRules.Relation.ENEMY]
		"reset", "default":
			relations = [DotTeamBlockRules.Relation.TEAM, DotTeamBlockRules.Relation.ENEMY]
			block = -1
		_:
			ctx.call("reply", "Usage: [team|enemy|all|reset]")
			return
	# A plain "all" from a player the server limits to teammates means the teammates.
	var admin := _is_admin(ctx)
	if word in ["", "all"] and not admin:
		var allowed: Array = []
		for rel: Variant in relations:
			if (rules.config.command_relations & (1 << int(rel))) != 0:
				allowed.append(rel)
		if not allowed.is_empty():
			relations = allowed
	var res := rules.request(key, relations, block, admin)
	if not res.ok:
		ctx.call("reply", res.error.message if res.error != null else "Refused.")
		return
	if applied_fn.is_valid():
		applied_fn.call(key)
	var what := "teammates and enemies" if relations.size() > 1 else ("teammates" if relations[0] == DotTeamBlockRules.Relation.TEAM else "enemies")
	var scope := " (your whole team)" if rules.config.scope == 1 else ""
	var line := "The server's rule applies to %s again." % what
	if block == 1:
		line = "You block %s. Where the server lets them pass, they must ask too." % what
	elif block == 0:
		line = "You pass through %s." % what
	ctx.call("reply", line + (" (your whole team)" if rules.config.scope == 1 else ""))


func _key(ctx: Object) -> Variant:
	if key_fn.is_valid():
		return key_fn.call(ctx)
	var session: Variant = ctx.get("session")
	if session is Object:
		var userid: Variant = (session as Object).get("userid")
		if userid != null:
			return int(userid)
	return null


func _is_admin(ctx: Object) -> bool:
	return ctx.has_method("has_permission") and bool(ctx.call("has_permission", rules.config.admin_permission))
