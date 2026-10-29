extends RefCounted

## dot-team's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises for anything new a game could call; OLDEST rises to LEVEL when a callable
## is removed or changes meaning.

# 1 is everything before this file existed; 2 DotTeamRotation; 3 DotTeamRotation.pick
# rest_first; 4 DotTeamBlockRules, DotTeamBlockConfig and DotTeamBlockCommands.
const LEVEL := 4
const OLDEST := 1
