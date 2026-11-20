extends RefCounted

## GameSpice Team's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises for anything new a game could call; OLDEST rises to LEVEL when a callable
## is removed or changes meaning.

# 1 is everything before this file existed; 2 DotTeamRotation; 3 DotTeamRotation.pick
# rest_first; 4 DotTeamBlockRules, DotTeamBlockConfig and DotTeamBlockCommands; 5 DotTeamMenuServer;
# 6 DotTeamSet.palette_colour, palette_name and the PALETTE_* tables.
const LEVEL := 6
const OLDEST := 1
