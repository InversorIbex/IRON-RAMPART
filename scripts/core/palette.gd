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

## Materials (desaturated, derived from Olive Black / Military Green).
const METAL_DARK := Color(0.13, 0.15, 0.13)
const METAL := Color(0.36, 0.39, 0.33)
const TRACK := Color(0.12, 0.12, 0.10)
const SHADOW := Color(0, 0, 0, 0.32)
## Enemy faction: dark hulls + light outline so units read on sand (Hito 3 contrast fix).
const ENEMY_HULL := Color(0.17, 0.18, 0.16)
const ENEMY_OUTLINE := Color(0.90, 0.88, 0.80)

## Combat effects (warm tones derived from Tactical Gold / Alert Red).
const FX_FLASH := Color(1.0, 0.95, 0.75)
const FX_FIRE := Color(1.0, 0.55, 0.15)
const FX_SPARK := Color(1.0, 0.85, 0.40)
const FX_SMOKE := Color(0.55, 0.55, 0.50)
const FX_DUST := Color(0.75, 0.72, 0.60)
const FX_SCORCH := Color(0.08, 0.08, 0.06)
const FX_DEBRIS := Color(0.15, 0.14, 0.12)
const FX_MISSILE := Color(0.85, 0.85, 0.80)
