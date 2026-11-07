class_name Palette
extends RefCounted
## Official IRON RAMPART palette. Source of truth: docs/ART_DIRECTION.md.
## Every gameplay/UI colour should derive from these constants.

const OLIVE_BLACK := Color(0.1333, 0.1686, 0.1451) # #222B25 backgrounds, UI
const MILITARY_GREEN := Color(0.3451, 0.4, 0.2941) # #58664B identity, military elements
const SANDSTONE := Color(0.6471, 0.6471, 0.5451) # #A5A58B terrain, secondary
const TACTICAL_GOLD := Color(0.8275, 0.6431, 0.2314) # #D3A43B resources, selection, progress
const ALERT_RED := Color(0.7255, 0.2627, 0.2118) # #B94336 damage, danger, alerts

## Neutral tones derived from the palette (not new hues).
const TERRAIN_GROUND := Color(0.5294, 0.5098, 0.4078) # warm desert ground
const TERRAIN_ROAD := Color(0.4392, 0.4196, 0.3412)
const TERRAIN_ROCK := Color(0.2549, 0.2588, 0.2275)
const GRID_LINE := Color(0.1333, 0.1686, 0.1451, 0.18)
const VALID := Color(0.4706, 0.6, 0.3412) # lighter military green for "valid placement"
