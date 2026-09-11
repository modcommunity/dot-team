# dot-team

Sides that outlive the match.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first — no autoloads, `DotNodeRef` instead of scene paths, `DotResult` for anything fallible, `Dot`-prefixed class names, layered configuration, `describe()` on anything stateful. This file is only what is specific to teams.

## The one idea

**Autobalance is only defensible if the server can say why.**

Everything in `DotTeamBalance` is static and takes a dictionary of counts rather than a roster. That is not purity for its own sake: being moved to the losing side between rounds is, from the player's point of view, being punished for the server's arithmetic, and a decision computed from counts can be printed, logged, replayed and argued with, while one computed from live objects cannot. The suite checks that two rosters given the same session make the same moves, which is only a meaningful check because the function is pure.

The second idea is about scope. dot-match's team manager is scoped to a match and resets with it — right for a deathmatch, wrong for a server where somebody joins blue, plays four maps and expects to still be blue. This one holds the assignment for the session and **drives** dot-match's rather than competing with it.

## It absorbed dot-team-spectate

`DotTeamSpectate` and `DotTeamSpectateRules` were their own addon and are now two files here. The merge is recorded in the top-level `tmp.md`.

**The interesting part is what it cost: nothing.** dot-team still installs with dot-core alone, because the spectator manager is duck-typed — no `DotSpectator*` identifier appears anywhere in this addon. Naming one would be worse than a dependency: a script that mentions a `class_name` the project does not have fails to parse and takes every script referencing it down with it, which is the failure mode `DotWeaponLoadoutBridge`'s documentation already describes.

`_make_spectator_manager` finds the class through `ProjectSettings.get_global_class_list()` and instantiates it, which is the same trick `DotTransportENet` uses to reach ENet without mentioning `ENetMultiplayerPeer` on a web export where the class is absent. A game without dot-spectate gets a bridge whose watching half is inert and whose assignment half works, which is exactly what a lobby wants.

`examples/team_spectate_selftest.tscn` runs against the **real** dot-spectate — linked into this project for the test — and has a section that runs against a stub with the same shape, so the duck typing is tested rather than asserted in a comment.

## Layout

```
addons/dot_team/
  core/
    dot_team_def.gd            one side: colour, friendly fire, cap, attributes
    dot_team_set.gd            the sides a session has, and four presets
    dot_team_policy.gd         joining, switching, locking, balancing — a DotConfig
    dot_team_balance.gd        all the arithmetic, static and pure
    dot_team_spectate_rules.gd who may watch whom, in rounds and sides
  runtime/
    dot_team_roster.gd         who is on which side, authoritative or mirrored
    dot_team_spectate.gd       the bridge to dot-spectate, duck-typed
```

Two self-test scenes, one project: `team_selftest` (the main scene) and `team_spectate_selftest`. **Run both.**

## Why the names are what they are

`DotTeamDef`, not `DotTeam`. dot-match already has `DotTeam` and `DotTeamManager`, `class_name` is global in Godot, and the two addons install side by side. Renaming dot-match's would have been a breaking change for every consumer of a published addon, to gain nothing but a shorter name here.

## Four entries in a two-sided set

`standard_pair()` returns **unassigned, blue, red, spectator**. The two non-playing entries are the ones a project inventing this forgets, and the failure is specific: a player who has connected and not chosen is neither on a team nor watching, so a set without an id for that state represents it as `&""` — which matches nothing in one comparison and everything in another, depending on which ran.

`playing` is the most-read field in `DotTeamDef`. Balance ignores non-playing sides, win conditions ignore them, the scoreboard sorts them last. A game that treats spectators as another team gets a round that cannot end, because the spectators are still alive.

Free-for-all is **one playing team with friendly fire on**, not zero teams. Zero makes every consumer branch on whether teams exist at all, and the branch nobody wrote is the one that matters.

## `are_enemies` lives here so it is written once

dot-combat, dot-chat and dot-spectate all ask it. The natural spelling — "is their team not my team" — makes a spectator everybody's enemy, and three addons each writing it means at least one gets it wrong. `DotTeamSet.are_enemies` requires *both* sides to be playing and different; `DotTeamRoster.are_enemies` resolves the keys and asks it.

## `attributes` is open on purpose

dot-objective wants to know which side attacks, dot-spawn wants a site group, a game wants an announcer line and an icon. A fixed field list means this file gains a property every time another addon needs one, and then every game re-exports it. `attribute_is` uses `DotValue.same`, because both sides come from content rather than from code.

## `validate()` refuses two configurations, and both have a symptom

`max_difference = 0` demands exactly equal sides, which an odd number of players cannot satisfy — so every join past the first odd one is refused and the server looks full to everybody trying to get in.

`allow_choice = false` with `auto_assign = false` means nobody ever gets a side, and the symptom is a lobby where the Ready button does nothing.

## The dot-match bridge is duck-typed and one-directional

`bind_match(manager)` calls `assign(key, index)` if the object has one. Duck-typed because dot-team must not depend on dot-match: a lobby, a timer server and a sandbox all want sides and none of them wants a match loop. One-directional because two systems both deciding which side somebody is on is precisely the bug this addon removes.

The index is the position among the *playing* ids, which is stable because the set is ordered and built once. A move to a non-playing side is not pushed at all — dot-match's sides are the playing ones, and there is no index for "watching".

## The spectate bridge: an index, not a cast

`team_index` is one-based over the **playing** ids, so spectators and the unassigned holding pen are both zero — which is what dot-spectate already means by "no team". `_playing_ids` is cached in `setup()` deliberately: recomputing it per call is a linear search per viewer per tick, and re-reading the set per call would let a mid-round change renumber the sides underneath dot-spectate, silently inverting the policy.

The policy is installed as dot-spectate's `target_filter`, which runs **after** its own rules. `mp_forcecamera 2` therefore still forbids everything regardless of what is written here, and the suite checks that ordering — the opposite arrangement would look identical in every test that did not specifically try it.

`_push_to_match` translates a side to dot-match's own team **id**, by position in the manager's list. dot-match's `standard_pair()` is `1` and `2` and a spectator team is `31`; passing dot-team's index straight through would assign everybody to teams `0` and `1`, of which only one exists, and half the server would be on a side dot-match refuses to spawn.

## What this does not do

It does not score, spawn, damage or draw. It does not know what a round is: `live_fn` is supplied by the game, because a lobby has no rounds and a timer server's "live" means something else.

It does not hold player records either. Given dot-player it reads liveness, score and join tick through callables; given nothing it falls back to join order, and everything else is the same.
