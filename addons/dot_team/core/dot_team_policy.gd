@tool
class_name DotTeamPolicy
extends DotConfig

## Every rule about joining, leaving and being moved between sides.

@export_group("Joining")

## Whether a player with no side is put on one automatically.
##
## Off for a game with a team-select screen; on for a server that wants people playing
## rather than reading a menu.
@export var auto_assign: bool = true

## Which side a new player lands on before anything else happens.
@export var initial_team: StringName = &"unassigned"

## Whether a player may pick their own side at all.
@export var allow_choice: bool = true

@export_group("Switching")

## Whether a player may change sides once assigned.
@export var allow_switch: bool = true

## Seconds a player must wait between switches.
##
## [b]The anti-abuse setting, and the reason is specific.[/b] Without it, a player on
## the losing side switches to the winning one every round, and in an elimination mode
## a player switches sides mid-round to see where the other team is.
@export_range(0.0, 3600.0, 1.0) var switch_cooldown_sec: float = 30.0

## Whether switching is allowed while the switcher is alive.
##
## Off: switching alive moves a living body to the other side's spawn, which is either
## a teleport into the enemy base or a free escape from a fight.
@export var allow_switch_while_alive: bool = false

## Whether a switch that would unbalance the sides is refused.
@export var enforce_balance_on_switch: bool = true

@export_group("Balance")

## Largest allowed difference between the biggest and smallest playing side.
##
## One is the usual answer. Zero means "exactly equal", which cannot be satisfied with
## an odd number of players and is therefore refused by [method validate].
@export_range(0, 64, 1) var max_difference: int = 1

## Whether the roster moves people to keep the sides even.
##
## [b]The setting everybody turns off eventually.[/b] Being moved to the losing side
## between rounds is, from the player's point of view, being punished for the server's
## arithmetic — so the default is on and the selection is deterministic and explainable,
## rather than on and arbitrary.
@export var autobalance: bool = true

## Whether autobalance may move somebody who is alive.
##
## Off. Moving a living player to the other side mid-fight is the single most
## complained-about thing a server does.
@export var autobalance_while_alive: bool = false

## How a victim is chosen when somebody must be moved.
##
## [code]newest[/code] is the fairest and the least surprising: the player who joined
## most recently has the least invested in the side they are on.
@export_enum("newest", "lowest_score", "random", "oldest") var balance_victim: int = 0

@export_group("Locking")

## Whether sides are locked once a round is live.
@export var lock_when_live: bool = false

## Ticks per second, for turning seconds into ticks.
@export_range(1, 1000, 1) var tick_rate: int = 60


func env_prefix() -> String:
	return "DOT_TEAM_"


func cli_prefix() -> String:
	return "team-"


func validate() -> DotResult:
	if max_difference == 0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A maximum difference of zero demands exactly equal sides, which an odd "
			+ "number of players cannot satisfy.",
			"Every join past the first odd one would be refused, and the server would "
			+ "look full to everybody trying to get in."
		)

	if not allow_choice and not auto_assign:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"Players may not choose a side and are not assigned one, so nobody ever "
			+ "gets on a team."
		)

	if autobalance and not allow_switch and enforce_balance_on_switch:
		# Legal, and worth a line: the server will move people who are not allowed to
		# move themselves, which is a defensible design and a surprising one.
		DotLog.debug(
			"team",
			"autobalance is on while switching is off — the server moves people who "
			+ "cannot move themselves"
		)

	return DotResult.success(null)


func switch_cooldown_ticks() -> int:
	return int(round(switch_cooldown_sec * float(maxi(1, tick_rate))))


enum Victim {
	NEWEST = 0,
	LOWEST_SCORE = 1,
	RANDOM = 2,
	OLDEST = 3,
}


# --- Presets ----------------------------------------------------------------

## Pick your side, switch freely, no balancing. A casual server.
static func casual() -> DotTeamPolicy:
	var p := DotTeamPolicy.new()
	p.auto_assign = true
	p.allow_switch = true
	p.switch_cooldown_sec = 5.0
	p.autobalance = false
	p.max_difference = 2
	return p


## Balanced, cooled down, locked during a round. A competitive server.
static func competitive() -> DotTeamPolicy:
	var p := DotTeamPolicy.new()
	p.auto_assign = true
	p.allow_switch = true
	p.switch_cooldown_sec = 60.0
	p.allow_switch_while_alive = false
	p.autobalance = true
	p.autobalance_while_alive = false
	p.max_difference = 1
	p.lock_when_live = true
	return p


## One side, nothing to balance, nothing to switch to.
static func free_for_all() -> DotTeamPolicy:
	var p := DotTeamPolicy.new()
	p.auto_assign = true
	p.initial_team = &"players"
	p.allow_choice = false
	p.allow_switch = false
	p.autobalance = false
	p.max_difference = 64
	return p


static func presets() -> Dictionary:
	return {
		&"casual": Callable(DotTeamPolicy, "casual"),
		&"competitive": Callable(DotTeamPolicy, "competitive"),
		&"free_for_all": Callable(DotTeamPolicy, "free_for_all"),
	}


static func preset(p_id: StringName) -> DotTeamPolicy:
	var table := presets()

	if not table.has(p_id):
		return null

	var fn: Callable = table[p_id]
	return fn.call() as DotTeamPolicy
