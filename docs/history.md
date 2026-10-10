# History

Decisions and bugs worth keeping. The rules they left are in [design.md](design.md).

## dot-team-spectate was absorbed

`DotTeamSpectate` and `DotTeamSpectateRules` were their own addon, never pushed, and are now two files here. It cost nothing: dot-team still installs with dot-core alone, because the spectator manager is duck-typed. `team_spectate_selftest` runs against the real dot-spectate (linked for the test) and has a section against a stub of the same shape, so the duck typing is tested rather than asserted in a comment.

## The random draw was alphabetical

The first `DotTeamRotation` sorted on `hash("%d:%s" % [seed, key])`, and Godot's string hash moves by one when the last character does, so over short keys the order was the keys' own. The suite's two-round check passed anyway ([a, b] then [c, d] skips last round's holders perfectly). `_roll` now mixes the hash, and the suite asserts every key is drawn first a fair share of 200 seeds, which fails on the old roll.

`DotTeamRotation` was extracted from mg-deathrun's `DrGame._draw_sides`, the first game to need it.
