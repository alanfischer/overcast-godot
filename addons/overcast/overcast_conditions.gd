@tool
class_name OvercastConditions
extends Resource
## The weather at one moment, as forecasts and observations give it: cloud in three layers, what
## falls, how cold, and the wind. Give one to an OvercastWeather (`conditions`) and it and its sky
## follow it; blend two for the hours between a forecast's. Heights are real metres: the sky's
## world_scale shrinks them into the world.

@export_group("Low cloud")
## Cumulus, closing into a storm's deck as the rain comes. Bases under 2 km.
@export_range(0.0, 1.0, 0.01) var low_cover := 0.45
@export_range(100.0, 3000.0, 10.0, "or_greater", "suffix:m") var low_base := 1500.0
## Heaped cumulus at 0, stratocumulus at 0.5, a stratus sheet at 1.
@export_range(0.0, 1.0, 0.01) var low_sheet := 0.0
## Thunderheads round the horizon: towering cumulus as it rises, cumulonimbus with anvils toward 1.
@export_range(0.0, 1.0, 0.01) var towering := 0.0
@export_group("Middle cloud")
## Altocumulus, or spread into altostratus, 2 to 6 km up.
@export_range(0.0, 1.0, 0.01) var mid_cover := 0.0
@export_range(2000.0, 8000.0, 10.0, "or_greater", "suffix:m") var mid_base := 4000.0
## Altocumulus at 0, altostratus at 1.
@export_range(0.0, 1.0, 0.01) var mid_sheet := 0.0
@export_group("High cloud")
## Cirrus, or spread into cirrostratus, over 6 km.
@export_range(0.0, 1.0, 0.01) var high_cover := 0.5
@export_range(5000.0, 15000.0, 10.0, "or_greater", "suffix:m") var high_base := 9000.0
## Cirrus at 0, cirrostratus and its halo at 1.
@export_range(0.0, 1.0, 0.01) var high_sheet := 0.0
@export_group("")
## As OvercastWeather.rain: 0 dry, 1 a downpour.
@export_range(0.0, 4.0, 0.01, "or_greater") var rain := 0.0
@export_range(-30.0, 40.0, 0.5, "or_less", "or_greater", "suffix:°C") var temperature := 10.0
## At the ground, m/s (y is ignored).
@export var wind := Vector3.ZERO

## `t` of the way from `from` to `to`, as a new one.
static func blend(from: OvercastConditions, to: OvercastConditions, t: float) -> OvercastConditions:
	var c: OvercastConditions = from.duplicate()
	for p in from.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			c.set(p["name"], lerp(from.get(p["name"]), to.get(p["name"]), t))
	return c
