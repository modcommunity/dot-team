class_name DotTeamBalance
extends RefCounted

## Which side somebody should join, and who should be moved. Pure, and explainable.
##
## [b]Every function here is static and takes counts rather than a roster.[/b] That is
## not purity for its own sake: autobalance is the single most complained-about thing a
## server does, and "the server moved me" is only acceptable if the server can say why.
## A decision computed from a dictionary of counts can be printed, logged, replayed and
## argued with; one computed from live objects cannot.

## The side with the fewest members. Ties broken by the order in [param order].
##
## Deterministic ties matter here for the same reason they matter in dot-spawn: a client
## previewing which side it will land on and a server deciding must agree, or the
## preview is a lie.
static func smallest(counts: Dictionary, order: Array[StringName]) -> StringName:
	var best := &""
	var best_n := 0x7FFFFFFF

	for team_id in order:
		var n := int(counts.get(team_id, 0))

		if n < best_n:
			best = team_id
			best_n = n

	return best


## The side with the most members.
static func largest(counts: Dictionary, order: Array[StringName]) -> StringName:
	var best := &""
	var best_n := -1

	for team_id in order:
		var n := int(counts.get(team_id, 0))

		if n > best_n:
			best = team_id
			best_n = n

	return best


## The difference between the biggest and smallest playing side.
static func spread(counts: Dictionary, order: Array[StringName]) -> int:
	if order.is_empty():
		return 0

	var lo := 0x7FFFFFFF
	var hi := -1

	for team_id in order:
		var n := int(counts.get(team_id, 0))
		lo = mini(lo, n)
		hi = maxi(hi, n)

	return maxi(0, hi - lo)


## Whether the sides are within [param max_difference] of each other.
static func balanced(
	counts: Dictionary,
	order: Array[StringName],
	max_difference: int
) -> bool:
	return spread(counts, order) <= maxi(0, max_difference)


## Whether one more person on [param team_id] would break the balance.
##
## Asked before a join and before a switch, which is why it takes the prospective side
## rather than answering about the current state: refusing after the fact means telling
## somebody they have been moved back.
static func would_unbalance(
	counts: Dictionary,
	order: Array[StringName],
	team_id: StringName,
	max_difference: int
) -> bool:
	var after := counts.duplicate()
	after[team_id] = int(after.get(team_id, 0)) + 1
	return not balanced(after, order, max_difference)


## How many people must move, and from where to where, to restore the balance.
##
## Returns an array of [code]{"from": id, "to": id}[/code] moves, shortest first. Empty
## when nothing needs doing, which is the common case and is why this is cheap.
static func moves_to_balance(
	counts: Dictionary,
	order: Array[StringName],
	max_difference: int
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var working := counts.duplicate()
	var guard := 0

	while not balanced(working, order, max_difference):
		var from := largest(working, order)
		var to := smallest(working, order)

		if from == to or from == &"" or to == &"":
			break

		# A side with nobody on it cannot give anybody up, and a loop that did not
		# check would run until the guard tripped and then report a pile of impossible
		# moves as if they were a plan.
		if int(working.get(from, 0)) <= 0:
			break

		working[from] = int(working[from]) - 1
		working[to] = int(working.get(to, 0)) + 1
		out.append({"from": from, "to": to})

		guard += 1

		# The guard is a real safety net rather than a formality: `counts` comes from a
		# caller, and a caller that passes a side not in `order` produces a spread that
		# never closes.
		if guard > 256:
			break

	return out


## Which member of a side to move, given the rule and what is known about each.
##
## [param candidates] is an array of [code]{"key", "joined_tick", "score", "alive"}[/code]
## dictionaries. Returns "" when nobody is eligible, which is the correct answer for a
## round where everybody on the oversized side is alive and the policy forbids moving
## the living.
static func choose_victim(
	candidates: Array[Dictionary],
	rule: int,
	allow_alive: bool,
	rng: RandomNumberGenerator = null
) -> String:
	var eligible: Array[Dictionary] = []

	for c in candidates:
		if allow_alive or not bool(c.get("alive", false)):
			eligible.append(c)

	if eligible.is_empty():
		return ""

	match rule:
		DotTeamPolicy.Victim.RANDOM:
			if rng == null:
				# Not an error, and not a silent fallback either: without a generator
				# the answer would depend on nothing reproducible, and two machines
				# would move different people.
				return _by(eligible, "joined_tick", false)
			return str(eligible[rng.randi_range(0, eligible.size() - 1)].get("key", ""))

		DotTeamPolicy.Victim.LOWEST_SCORE:
			return _by(eligible, "score", true)

		DotTeamPolicy.Victim.OLDEST:
			return _by(eligible, "joined_tick", true)

		_:
			# NEWEST. The fairest and least surprising: whoever joined most recently has
			# the least invested in the side they are on.
			return _by(eligible, "joined_tick", false)


## The candidate with the lowest (or highest) value of a field, ties broken by key.
static func _by(candidates: Array[Dictionary], field: String, lowest: bool) -> String:
	var best := ""
	var best_v := 0.0

	for c in candidates:
		var v := float(c.get(field, 0))
		var key := str(c.get("key", ""))

		if key == "":
			continue

		if best == "" or (v < best_v if lowest else v > best_v):
			best = key
			best_v = v
		elif is_equal_approx(v, best_v) and key < best:
			best = key

	return best


## A line a server can print when it moves somebody.
static func explain(from: StringName, to: StringName, key: String, spread_before: int) -> String:
	return (
		"%s moved from %s to %s: the sides were %d apart"
		% [key, String(from), String(to), spread_before]
	)
