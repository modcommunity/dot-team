The side a player is on, held for the whole session, in one place every other addon reads it from. It also holds the spectating policy that sits on top: who may watch which side.

## Install

1. Get [Godot 4.7](https://godotengine.org/download).
2. Either use [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap), which clones every project and links the addons, or copy `addons/dot_team/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable both in *Project > Project Settings > Plugins*.

dot-core is the only dependency.

## Use

```gdscript
var teams := DotTeamRoster.new()
teams.teams  = DotTeamSet.standard_pair()        # blue, red, unassigned, spectator
teams.policy = DotTeamPolicy.competitive()
teams.alive_fn = func(key): return roster.get_record(key).alive
add_child(teams)
teams.setup()

teams.add("ada")                                  # onto the smaller side
teams.request_switch("ada", &"red", tick)         # enforces the whole policy
teams.rebalance(tick)                             # between rounds

if teams.are_enemies(shooter, victim):
    apply_damage()
```

- `standard_pair()` has four entries: blue, red, unassigned and spectator. "Connected but not chosen yet" needs a real id, or it ends up as an empty string that matches nothing or everything.
- Free-for-all is one team with friendly fire on, not "no teams".
- `are_enemies` is the one answer other addons ask. A spectator is nobody's enemy.

Every refused switch carries a sentence and fires `switch_refused`:

```gdscript
var res := teams.request_switch("ada", &"red", tick)
if not res.ok:
    hud.say(res.error.message)   # "You switched recently. 22 seconds to go."
```

## Autobalance

Every function in `DotTeamBalance` is static and takes counts, not a roster, so a decision can be printed, logged and replayed:

```gdscript
DotTeamBalance.moves_to_balance({&"blue": 6, &"red": 2}, order, 1)
DotTeamBalance.explain(&"blue", &"red", "ada", 6)
# "ada moved from blue to red: the sides were 6 apart"
```

Who gets moved is a policy: `newest` (default, since the newest player has least invested in a side), `lowest_score`, `random` or `oldest`. Nobody alive is moved unless the server says so.

## With dot-match

```gdscript
teams.bind_match(match_node.teams)
```

dot-team is the authority and dot-match is told, through duck typing (`assign(key, index)` if present). Everybody already assigned is pushed when you bind. dot-match has its own smaller `DotTeam` class, which is why this addon's names differ.

## Spectating by side

`DotTeamSpectate` maps dot-team's named sides to [dot-spectate](https://github.com/modcommunity/dot-spectate)'s numbered ones and holds the watch policy. dot-spectate is not a dependency: the manager is duck-typed and built automatically if the class exists.

```gdscript
var spectate := DotTeamSpectate.new()
spectate.teams = team_roster
spectate.alive_fn = func(key): return roster.get_record(key).alive
spectate.pose_fn  = func(key): return eye_transform_of(key)
add_child(spectate)
spectate.setup()

spectate.join_spectators("ada")   # moves them and starts the camera
spectate.watchers_of("bob")       # ["ada"]
```

`team_index(&"blue")` is 1; the spectator and unassigned sides are 0, which is what "no team" means in dot-spectate.

| Policy | Default | Meaning |
| --- | --- | --- |
| `spectators_see_everybody` | on | Someone who left the game to watch is not coming back this round. |
| `dead_see_enemies` | off | Stops a dead player calling out positions. |
| `open_after_round` | on | The round is decided, so nothing is left to give away. |
| `fall_back_when_team_gone` | on | A viewer whose whole side is dead gets the other one. |

dot-spectate's own `force_camera` is applied first and this policy cannot relax it.

## Picking who takes a role

For games with one special side (hunters, drivers), `DotTeamRotation` picks who takes it each round and says why.

| Mode | Picks |
| --- | --- |
| `RANDOM` | A seeded draw that skips last round's picks while anybody else is left. |
| `QUEUE` | Everybody gets an equal share of turns. |
| `SWAP` | Last round's other side. |

Players who asked for the role go first, players who asked to stay out go last.

```gdscript
var history := {}   # keep this for the session
var want := DotTeamRotation.count_for(players.size(), 4.0, 1, 6)   # one per 4 players, min 1, max 6
var result := DotTeamRotation.pick(players, want, DotTeamRotation.Mode.QUEUE, history, round_seed, wishes)
DotTeamRotation.note(history, players, result["picked"], round_number)
print(result["why"])   # {"ada": "the fewest turns: 2 of 9 rounds", ...}
```

The minimum and maximum in `count_for` are arguments you choose.

## Testing

Import the project once, then run the self-test scene in `examples/` headless with Godot.

## Status and licence

Part of the TMC **dot-\*** family of Godot addons. Written with Claude Code and maintained by `gamemann`. Every addon has headless tests, but little of this has been played by real users yet, so expect rough edges and please [open an issue](https://github.com/modcommunity/dot-team/issues) when you hit one.

MIT licence, see [LICENSE](LICENSE). The only closed part of the TMC platform is the web back end; you can use your own instead of TMC's.
