# dot-team

Sides that outlive the match: team definitions and presets, a session-long roster that drives dot-match's, pure balance arithmetic, role rotation for asymmetric games, and team-aware spectating through dot-spectate.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to teams.

**The distributable is `addons/dot_team/`.** It requires [dot-core](../dot-core) and nothing else. dot-match, dot-spectate and dot-player are optional and duck-typed; dot-spectate is linked only for the spectate suite (`addons/dot_spectate`, gitignored).

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: why balance is pure, session scope, the four-entry set, `are_enemies`, attributes, `validate()`, the dot-match and dot-spectate bridges, rotation, what this does not do |
| [docs/history.md](docs/history.md) | the absorbed dot-team-spectate, the alphabetical draw |

## Layout

| Path | What |
| --- | --- |
| `core/dot_team_def.gd` | `DotTeamDef`: one side; colour, friendly fire, cap, `playing`, `attributes` |
| `core/dot_team_set.gd` | `DotTeamSet`: the sides a session has, presets (`standard_pair()`), `are_enemies` |
| `core/dot_team_policy.gd` | `DotTeamPolicy`: joining, switching, locking, balancing; a `DotConfig` with `validate()` |
| `core/dot_team_balance.gd` | `DotTeamBalance`: all the arithmetic, static and pure |
| `core/dot_team_rotation.gd` | `DotTeamRotation`: who takes a role this round (`RANDOM`, `QUEUE`, `SWAP`), and why |
| `core/dot_team_spectate_rules.gd` | `DotTeamSpectateRules`: who may watch whom |
| `runtime/dot_team_roster.gd` | `DotTeamRoster`: who is on which side, authoritative or mirrored; `bind_match`, `live_fn` |
| `runtime/dot_team_spectate.gd` | `DotTeamSpectate`: the duck-typed bridge to dot-spectate |
| `dot_team_api.gd` | the API level; bump `LEVEL` for anything new a game can call (rule on dot-core's `DotAddonApi`) |
| `examples/team_selftest.tscn`, `team_spectate_selftest.tscn` | the two suites |

Paths except `examples/` are in `addons/dot_team/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then **both** `godot --headless --path . res://examples/team_selftest.tscn` and `res://examples/team_spectate_selftest.tscn`. The second needs dot-spectate linked at `addons/dot_spectate`.

## Rules that bite

- Balance takes counts, not a roster, and stays static and pure. [design](docs/design.md#autobalance-is-only-defensible-if-the-server-can-say-why)
- The roster drives dot-match's team manager, one way; never let both decide. [design](docs/design.md#the-dot-match-bridge-is-duck-typed-and-one-directional)
- Push to dot-match by its team **id** at the playing position, never dot-team's index; never push a non-playing side. [design](docs/design.md#the-dot-match-bridge-is-duck-typed-and-one-directional)
- Every set has an unassigned and a spectator entry; check `playing` before treating a side as a team. Free-for-all is one playing team with friendly fire on. [design](docs/design.md#four-entries-in-a-two-sided-set)
- Ask `are_enemies` here; never write "their team is not mine" elsewhere. [design](docs/design.md#are_enemies-is-written-once)
- Add an `attributes` key, not a field, for another addon's need. [design](docs/design.md#attributes-is-open-on-purpose)
- `validate()` refuses `max_difference = 0` and no-choice-no-auto-assign; keep both. [design](docs/design.md#validate-refuses-two-configurations-and-both-have-a-symptom)
- Never write a `DotSpectator*` or dot-match identifier in a statement; find classes by `get_global_class_list()` and call by name. [design](docs/design.md#the-spectate-bridge-an-index-not-a-cast)
- `team_index` is one-based over playing ids, cached at `setup()`; the filter runs after dot-spectate's own rules. [design](docs/design.md#the-spectate-bridge-an-index-not-a-cast)
- A random draw is mixed, never a raw string hash. [design](docs/design.md#who-takes-a-role-dotteamrotation)

Not here: scoring, spawning, damage, drawing, rounds (`live_fn`), player records. [design](docs/design.md#what-this-does-not-do)

## Open

- mg-deathrun still draws its activators with its own `DrGame._draw_sides` rather than `DotTeamRotation`, which was extracted from it; mg-prop-hunt and game-hide-n-seek use `DotTeamRotation`. Not yet converted; reason unknown (mg-deathrun's design doc argues for a draw that excludes last round's activators, which `RANDOM` already does).
