# Design

Why dot-team is shaped the way it is. The one-line rules are in [CLAUDE.md](../CLAUDE.md).

## Autobalance is only defensible if the server can say why

Everything in `DotTeamBalance` is static and takes a dictionary of counts rather than a roster. Being moved to the losing side between rounds is, from the player's view, being punished for the server's arithmetic; a decision computed from counts can be printed, logged, replayed and argued with, and one computed from live objects cannot. The suite checks that two rosters given the same session make the same moves, which is only meaningful because the function is pure.

## Sides outlive the match

dot-match's team manager is scoped to a match and resets with it: right for a deathmatch, wrong for a server where somebody joins blue, plays four maps and expects to still be blue. `DotTeamRoster` holds the assignment for the session and **drives** dot-match's rather than competing with it.

`DotTeamDef`, not `DotTeam`: dot-match already has `DotTeam` and `DotTeamManager`, `class_name` is global, and the two addons install side by side. Renaming dot-match's would break every consumer of a published addon to gain a shorter name here.

## Four entries in a two-sided set

`DotTeamSet.standard_pair()` returns **unassigned, blue, red, spectator**. The two non-playing entries are the ones a project inventing this forgets: a player who has connected and not chosen is neither on a team nor watching, and a set without an id for that state represents it as `&""`, which matches nothing in one comparison and everything in another.

`playing` is the most-read field in `DotTeamDef`. Balance ignores non-playing sides, win conditions ignore them, the scoreboard sorts them last. A game that treats spectators as another team gets a round that cannot end, because the spectators are still alive.

Free-for-all is **one playing team with friendly fire on**, not zero teams. Zero makes every consumer branch on whether teams exist, and the branch nobody wrote is the one that matters.

## `are_enemies` is written once

dot-combat, dot-chat and dot-spectate all ask it. The natural spelling ("their team is not my team") makes a spectator everybody's enemy, and three addons each writing it means at least one gets it wrong. `DotTeamSet.are_enemies` requires *both* sides to be playing and different; `DotTeamRoster.are_enemies` resolves the keys and asks it.

## `attributes` is open on purpose

dot-objective wants to know which side attacks, dot-spawn wants a site group, a game wants an announcer line and an icon. A fixed field list means this file gains a property every time another addon needs one. `attribute_is` uses `DotValue.same`, because both sides come from content rather than code.

## `validate()` refuses two configurations, and both have a symptom

`max_difference = 0` demands exactly equal sides, which an odd number of players cannot satisfy: every join past the first odd one is refused and the server looks full to everybody. `allow_choice = false` with `auto_assign = false` means nobody ever gets a side, and the symptom is a lobby where the Ready button does nothing.

## The dot-match bridge is duck-typed and one-directional

`bind_match(manager)` requires an `assign(key, index)` method. Duck-typed because dot-team must not depend on dot-match (a lobby, a timer server and a sandbox all want sides and none wants a match loop); one-directional because two systems both deciding somebody's side is the bug this addon removes.

`_push_to_match` translates a side to dot-match's own team **id** by position among the *playing* ids (stable, because the set is ordered and built once), read off the manager's `teams` list. dot-match's `DotTeam.standard_pair()` is ids `1` and `2` and its spectator team is `31`; passing dot-team's index straight through would assign everybody to `0` and `1`, of which only one exists, and half the server would be on a side dot-match refuses to spawn. A move to a non-playing side is not pushed: dot-match has no index for "watching".

## The spectate bridge: an index, not a cast

`DotTeamSpectate` reaches dot-spectate without naming it: no `DotSpectator*` identifier appears in a statement anywhere in this addon. A script that mentions a `class_name` the project does not have fails to parse and takes every script referencing it down with it (dot-weapon's `DotWeaponLoadoutBridge` documents the same failure). `_make_spectator_manager` finds the class through `ProjectSettings.get_global_class_list()` and instantiates it, the trick `DotTransportENet` uses for ENet on web. Without dot-spectate the bridge's watching half is inert and its assignment half works, which is what a lobby wants.

`team_index` is one-based over the **playing** ids, so spectators and the unassigned pen are both zero, which is what dot-spectate means by "no team". `_playing_ids` is cached in `setup()`: recomputing per call is a linear search per viewer per tick, and re-reading the set would let a mid-round change renumber the sides underneath dot-spectate, silently inverting the policy.

The policy is installed as dot-spectate's `target_filter`, which runs **after** its own rules, so `mp_forcecamera 2` still forbids everything regardless of what is written here. The suite checks that ordering; the opposite arrangement would look identical in every test that did not specifically try it.

## Who takes a role: `DotTeamRotation`

The other half of asymmetric games: not which side somebody joins, but who is the hunter, the activator or the driver this round. It is static like the balance arithmetic and returns who was picked **and why**, so "why am I hunter again" has an answer.

- `RANDOM` is a seeded draw that skips last round's holders while anybody else is left (`may_repeat` turns that off).
- `QUEUE` gives everybody an equal share: smallest share of rounds played first, then whoever had it longest ago.
- `SWAP` puts last round's other side in the role.
- A wish of +1 is first and -1 last in every mode, so a player who asked to stay out is only picked to fill a round.
- `count_for` is one per N players, clamped, never everybody. `note` keeps the history a caller holds.

The random roll is **mixed**, not just hashed: Godot's string hash moves by one when the last character does, so a sort on `hash(seed:key)` over short keys comes out alphabetical ([history](history.md#the-random-draw-was-alphabetical)).

## What this does not do

It does not score, spawn, damage or draw. It does not know what a round is: `live_fn` comes from the game, because a lobby has no rounds and a timer server's "live" means something else. It holds no player records: given dot-player it reads liveness, score and join tick through `alive_fn`, `score_fn` and the like; given nothing it falls back to join order.
