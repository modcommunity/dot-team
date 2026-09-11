@tool
class_name DotTeamSpectateRules
extends DotConfig

## Who may watch whom, in terms of sides rather than of numbers.
##
## [b]This sits on top of dot-spectate's rules rather than replacing them.[/b] That
## addon already has the force-camera policy and the broadcast delay, and both are
## right; what it does not have is a notion of what a side [i]is[/i] — its
## [code]team_fn[/code] answers an integer and zero means "none". So the policy here is
## expressed in dot-team's terms and compiled down, and the two are applied together.

@export_group("Who may watch")

## Whether a player on the spectator side may watch anybody.
##
## [b]On, and it is the setting that makes a spectator side worth having.[/b] Somebody
## who has deliberately left the game to watch is not a competitive risk in the way a
## dead player is: they are not coming back this round.
@export var spectators_see_everybody: bool = true

## Whether a dead player may watch the other side before the round ends.
##
## Off. A dead player calling out positions is the oldest problem in competitive
## multiplayer, and it is the reason dot-spectate's force-camera setting exists at all.
@export var dead_see_enemies: bool = false

## Whether everybody may watch everybody once the round is over.
##
## On: the round is decided, so there is nothing left to give away, and being locked to
## your own dead team during the end-of-round camera is just annoying.
@export var open_after_round: bool = true

## Whether an unassigned player — connected, not yet on a side — may watch.
@export var unassigned_may_watch: bool = true

## Whether a player may watch somebody on a side that is not playing.
##
## Off. There is nothing to see, and a cycle that includes them stops on a black screen.
@export var watch_non_playing: bool = false

@export_group("Joining and leaving")

## Which side [method DotTeamSpectate.join_spectators] moves people to.
@export var spectator_team: StringName = &"spectator"

## Which side [method DotTeamSpectate.leave_spectators] puts them back on when they
## name none. Empty asks dot-team for the smallest.
@export var rejoin_team: StringName = &""

## Whether joining the spectator side is allowed while alive.
##
## On, and the player is killed by the game first — which is the game's job, not this
## addon's. A living player who became a spectator without dying would be a way to
## escape a fight.
@export var allow_join_while_alive: bool = true

## Whether somebody who joins the spectator side starts watching immediately.
##
## On: a spectator staring at a black screen is indistinguishable from a crash.
@export var watch_on_join: bool = true

@export_group("Cycling")

# There was a `cycle_within_team` here and it is gone rather than implemented, because
# the behaviour it described is already what happens: dot-spectate builds a cycle out of
# `targets_for`, which filters by `may_watch`, which is this policy. A second setting
# that could only ever agree with the first is a setting somebody will one day set to
# the other value and then spend an afternoon on.

## Whether a viewer whose side is entirely dead falls back to watching everybody.
##
## [b]On.[/b] The alternative is a camera with nothing to point at, which dot-spectate
## reports honestly and which the player reads as the game having frozen.
@export var fall_back_when_team_gone: bool = true


func env_prefix() -> String:
	return "DOT_TEAM_SPECTATE_"


func cli_prefix() -> String:
	return "team-spectate-"


func validate() -> DotResult:
	if spectator_team == &"":
		return DotResult.fail(
			DotError.CODE_INVALID,
			"There is no spectator side named, so nobody can be moved to one."
		)

	if not spectators_see_everybody and not dead_see_enemies and not open_after_round:
		# Legal, and worth naming: this is a server where a spectator can only ever
		# watch their own side, which is a defensible competitive choice and a
		# surprising default to arrive at by accident.
		DotLog.debug(
			"team.spectate",
			"nobody may ever watch the other side, in any state",
			{}
		)

	return DotResult.success(null)


# --- Presets ----------------------------------------------------------------

## Dead players see their own side; spectators see everybody; open after the round.
static func competitive() -> DotTeamSpectateRules:
	return DotTeamSpectateRules.new()


## Everybody sees everybody. A casual server, a practice range, a demo.
static func open() -> DotTeamSpectateRules:
	var r := DotTeamSpectateRules.new()
	r.dead_see_enemies = true
	r.spectators_see_everybody = true
	r.watch_non_playing = false
	return r


## Nobody sees the other side, ever, including spectators.
##
## For a tournament server where a spectator seat is a seat in the room.
static func locked() -> DotTeamSpectateRules:
	var r := DotTeamSpectateRules.new()
	r.spectators_see_everybody = false
	r.dead_see_enemies = false
	r.open_after_round = false
	return r


static func presets() -> Dictionary:
	return {
		&"competitive": Callable(DotTeamSpectateRules, "competitive"),
		&"open": Callable(DotTeamSpectateRules, "open"),
		&"locked": Callable(DotTeamSpectateRules, "locked"),
	}


static func preset(p_id: StringName) -> DotTeamSpectateRules:
	var table := presets()

	if not table.has(p_id):
		return null

	var fn: Callable = table[p_id]
	return fn.call() as DotTeamSpectateRules
