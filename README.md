This is the **team** asset for TMC's **Dot** collection. It is the side a player is on, held for the whole session rather than for one match, the one place every other asset reads it from — and the spectating policy that sits on top of it.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Install

Copy `addons/dot_team/` and `addons/dot_core/` into your project and enable both in *Project → Project Settings → Plugins*.

Requires Godot 4.7 or newer.

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

## Four entries, not two

`DotTeamSet.standard_pair()` has **blue, red, unassigned and spectator**, and the last two are the ones that get forgotten. A player who has connected and not chosen is neither on a team nor watching, and a set with no id for that state ends up representing it as the empty string — which then matches nothing, or matches everything, depending on which comparison happens to run.

Free-for-all is **one team with friendly fire on**, not "no teams". Modelling it as no teams makes every consumer branch on whether teams exist, and the branch nobody wrote is the one that matters.

`are_enemies` is the question dot-combat, dot-chat and dot-spectate all ask. Answered once, here: a spectator is nobody's enemy, which the natural spelling — "is their team not my team" — gets backwards.

## Autobalance is deterministic and explainable, or it is indefensible

Being moved is, from the player's side, being punished for the server's arithmetic. So every function in `DotTeamBalance` is **static and takes counts**, not a roster:

```gdscript
DotTeamBalance.moves_to_balance({&"blue": 6, &"red": 2}, order, 1)
# [ {from: blue, to: red}, {from: blue, to: red}, {from: blue, to: red} ]
DotTeamBalance.explain(&"blue", &"red", "ada", 6)
# "ada moved from blue to red: the sides were 6 apart"
```

A decision computed from a dictionary can be printed, logged, replayed and argued with. One computed from live objects cannot. The suite checks two rosters given the same session make the same moves.

Who gets moved is a policy choice — `newest`, `lowest_score`, `random`, `oldest` — and **newest** is the default because whoever joined most recently has the least invested in the side they are on. Nobody alive is moved unless the server says so; that is the single most complained-about thing a server does.

## Refusals say why

```gdscript
var res := teams.request_switch("ada", &"red", tick)
if not res.ok:
    hud.say(res.error.message)   # "You switched recently. 22 seconds to go."
```

"Nothing happened when I clicked" is the worst possible answer. Every refusal carries a sentence and fires the `switch_refused` signal.

## It drives dot-match rather than competing with it

```gdscript
teams.bind_match(match_node.teams)
```

Duck-typed: it calls `assign(key, index)` if the object has one and does nothing otherwise, so dot-team does not depend on dot-match and dot-match keeps working with nobody driving it. **The direction matters** — this is the authority and the match is told. Two systems both deciding which side somebody is on is the bug this addon was written to remove.

Binding late is not a silent half-configuration: everybody already assigned is pushed on the way in.

## Spectating, by side

`DotTeamSpectate` is the second half of this addon and it does two things: it bridges dot-team's **named** sides to dot-spectate's **numbered** ones, and it holds the watch policy in terms of rounds and teams.

```gdscript
var spectate := DotTeamSpectate.new()
spectate.teams = team_roster
spectate.alive_fn = func(key): return roster.get_record(key).alive
spectate.pose_fn  = func(key): return eye_transform_of(key)
add_child(spectate)
spectate.setup()

spectate.join_spectators("ada")   # moves them AND starts the camera
spectate.watchers_of("bob")       # ["ada"] — a "2 spectators" badge
```

**dot-spectate is not a dependency and no `DotSpectator*` identifier appears in this addon.** dot-team's whole install cost is dot-core, and a lobby that wants sides and no cameras should not have to fetch a spectator addon to get them — so the manager is duck-typed, the way dot-weapon's bridges duck-type dot-loadout and dot-inventory. Naming the class would be *worse* than a dependency: a script that mentions a `class_name` the project does not have fails to parse and takes every script referencing it down with it.

A game with dot-spectate installed gets one built automatically, through the global class list — the same trick dot-core's `DotTransportENet` uses to reach ENet on a web export. A game without it assigns its own object with the same shape, or leaves it null and uses the rest of the addon.

### The index is zero-based over the *playing* sides

```gdscript
spectate.team_index(&"blue")            # 1
spectate.team_index(&"spectator")       # 0 — which is what "no team" means over there
```

So the spectator side and the unassigned holding pen both come out as zero, and dot-spectate's force-camera rule does the right thing without being told anything about dot-team. An off-by-one here does not crash: it **inverts who may watch whom**, which is a competitive-integrity bug that nothing would report as one.

### The policy

| | |
| --- | --- |
| `spectators_see_everybody` | On. Somebody who deliberately left the game to watch is not coming back this round; they are not the risk a dead player is. |
| `dead_see_enemies` | Off. A dead player calling out positions is the oldest problem in competitive multiplayer. |
| `open_after_round` | On. The round is decided, so there is nothing left to give away. |
| `fall_back_when_team_gone` | On. A viewer whose whole side is dead gets the other one — the alternative is a camera with nothing to point at, which reads as the game having frozen. |

**dot-spectate's own `force_camera` is applied first and this cannot relax it.** The policy here is installed as an *extra* filter, so a server that set `mp_forcecamera 2` still forbids everything — an addon layered on top does not get to overrule the operator.

`join_spectators` moves the player **and** starts them watching, because a spectator staring at a black screen is indistinguishable from a crash, and every game that separates the two calls forgets the second one in at least one code path.

## Why not `DotTeam`

dot-match already has a class by that name, and `class_name` is global in Godot. The names here are the price of the two addons being independently installable, which they are on purpose: a deathmatch needs dot-match's smaller match-scoped notion and nothing else.

## Licence

MIT. See [LICENSE](LICENSE).
