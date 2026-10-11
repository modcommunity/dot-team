class_name DotTeamRotation
extends RefCounted

## Who takes a role this round: the hunters in a hide-and-seek game, the activators in a trap
## course, the drivers in a chase. Pure, static and explainable, like [DotTeamBalance].
##
## [b]Three answers, because servers disagree and each is right for somebody.[/b]
## [br]- [constant RANDOM]: a seeded draw that passes over whoever had the role last round. A
## rotation is fairer on paper and gamed in practice (leave and rejoin to move up it); a draw
## that repeats reads as favouritism, so a repeat is drawn only when there is nobody else.
## [br]- [constant QUEUE]: everybody gets an equal share. Whoever has had the role for the
## smallest fraction of the rounds they played goes first, then whoever had it longest ago. Over
## enough rounds every regular has had it the same number of times, give or take one.
## [br]- [constant SWAP]: the sides change over. Whoever was NOT in the role last round takes
## it, up to the count, which is what a server that plays "props become hunters" wants.
##
## [b]Wishes come first, in every mode.[/b] A player who asked for the role ([code]+1[/code]) is
## ahead of everybody, one who asked to stay out ([code]-1[/code]) behind everybody, so a
## refuser is only ever picked when the round would otherwise be short. That is a game's
## promise to a player, and it is kept here rather than in each game's draw.
##
## [b]Counts in, a list and the reasons out.[/b] [method pick] takes keys, a history and a seed,
## and returns who was picked and why, so "why am I hunter again" has an answer a console can
## print. The same seed gives the same answer, which is what lets a suite assert a rotation.

enum Mode {
	## A seeded draw that skips last round's holders while anybody else is left.
	RANDOM,
	## The smallest share of rounds played goes first.
	QUEUE,
	## Whoever was not in the role last round goes first.
	SWAP,
}

## How many of [param total] players take the role: one for every [param per_player], rounded
## up, at least [param at_least], at most [param at_most] (0 is no cap) — and never everybody,
## because a round with nobody on the other side is not a round. One player gets none.
static func count_for(total: int, per_player: float, at_least: int = 1, at_most: int = 0) -> int:
	if total <= 1:
		return 0

	var n := int(ceil(float(total) / maxf(per_player, 0.0001)))
	n = maxi(n, at_least)

	if at_most > 0:
		n = mini(n, at_most)

	return clampi(n, 0, total - 1)


## Picks [param want] of [param keys] for the role.
##
## [param history] is key -> `{times, rounds, last, was}` as [method note] keeps it: how many
## rounds they had the role, how many they played, the round they last had it (-1 never) and
## whether they had it last round. [param wishes] is key -> +1 (wants it), 0, -1 (wants out).
## [param may_repeat] lets [constant RANDOM] draw last round's holders as freely as anybody.
##
## Returns `{"picked": Array[StringName], "why": {key: String}}`, in the order picked.
static func pick(
	keys: Array[StringName],
	want: int,
	mode: Mode,
	history: Dictionary,
	seed_value: int,
	wishes: Dictionary = {},
	may_repeat: bool = false
) -> Dictionary:
	var ranked: Array[Dictionary] = []

	for key in keys:
		var h: Dictionary = history.get(key, {})
		var wish := int(wishes.get(key, 0))
		var was := bool(h.get("was", false))
		var rounds := int(h.get("rounds", 0))
		var times := int(h.get("times", 0))
		var last := int(h.get("last", -1))

		var row := {
			"key": key,
			# 0 volunteered, 1 no preference, 2 asked to stay out.
			"wish": 0 if wish > 0 else (2 if wish < 0 else 1),
			"roll": _roll(seed_value, key),
			"was": was,
			"share": float(times) / float(maxi(rounds, 1)),
			"last": last,
			"times": times,
			"rounds": rounds,
			"new": h.is_empty(),
		}

		match mode:
			Mode.RANDOM:
				row["order"] = [row["wish"], 1 if (was and not may_repeat) else 0, row["roll"]]
			Mode.QUEUE:
				# Never had it sorts before had it longest ago, which sorts before had it lately.
				row["order"] = [row["wish"], row["share"], last, row["roll"]]
			Mode.SWAP:
				# The other side last round first, then anybody new, then last round's holders.
				var tier := 2 if was else (1 if row["new"] else 0)
				row["order"] = [tier, row["wish"], row["roll"]]

		ranked.append(row)

	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _before(a["order"], b["order"]))

	var picked: Array[StringName] = []
	var why := {}
	var take := clampi(want, 0, ranked.size())

	for i in range(take):
		var row: Dictionary = ranked[i]
		picked.append(row["key"])
		why[row["key"]] = _reason(row, mode, may_repeat)

	return {"picked": picked, "why": why}


## Records a round: everybody in [param keys] played it, [param picked] had the role. Call it
## once per round, after [method pick], with the same keys.
static func note(history: Dictionary, keys: Array[StringName], picked: Array[StringName], round_number: int) -> void:
	for key in keys:
		var h: Dictionary = history.get(key, {"times": 0, "rounds": 0, "last": -1, "was": false})
		h["rounds"] = int(h.get("rounds", 0)) + 1
		var has := picked.has(key)
		h["was"] = has

		if has:
			h["times"] = int(h.get("times", 0)) + 1
			h["last"] = round_number

		history[key] = h


## Forgets somebody: a player who left. Their share starts again if they come back, which is
## the honest answer to a reconnect under the same key — the history is about rounds played.
static func forget(history: Dictionary, key: StringName) -> void:
	history.erase(key)


## A seeded order for one key: dot-core's [DotRandomStream], a child stream named by the
## key, drawn at index 0.
##
## [b]Not a hash of the key, twice over.[/b] Godot's string hash moves by one when the last
## character does, so "11:a" and "11:b" sorted next to each other and a "random" draw over
## short keys came out alphabetical (the first version did exactly that); and `hash()` is
## 32-bit and not promised to be stable across engine versions, so the same seed could
## draw a different side after an upgrade. The stream hashes names with FNV-1a and mixes
## with SplitMix64, which is the family's one generator.
static func _roll(seed_value: int, key: StringName) -> int:
	return DotRandomStream.new(seed_value, &"team-rotation").stream(key).at(0)


static func _before(a: Array, b: Array) -> bool:
	for i in range(mini(a.size(), b.size())):
		if a[i] == b[i]:
			continue
		return a[i] < b[i]

	return false


static func _reason(row: Dictionary, mode: Mode, may_repeat: bool) -> String:
	if int(row["wish"]) == 0:
		return "asked for it"

	var refused := int(row["wish"]) == 2

	match mode:
		Mode.RANDOM:
			if refused:
				return "drawn although they asked to stay out: nobody else was left"
			if bool(row["was"]) and not may_repeat:
				return "drawn again: nobody else was left"
			return "drawn at random"
		Mode.QUEUE:
			var times := int(row["times"])
			var rounds := int(row["rounds"])
			if rounds == 0:
				return "new, and nobody has had fewer turns"
			return "the fewest turns: %d of %d rounds" % [times, rounds]
		Mode.SWAP:
			if bool(row["was"]):
				return "kept the role: the other side was too small"
			if bool(row["new"]):
				return "new this round"
			return "was on the other side last round"

	return ""
