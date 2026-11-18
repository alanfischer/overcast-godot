# Roadmap: the sky over a real place

The aim: name a latitude, longitude and time, and get the sky that stands there — the sun, moon
and stars where they are, and in the end the clouds and weather that are there now.

## 1. Sun, moon and stars from a place and a time (done)

Pure arithmetic, no network.

- `OvercastEphemeris`: the sun's and moon's positions (Schlyter's method: about an arcminute for
  the sun, a few for the moon, the moon's parallax included), the moon's phase, and local
  sidereal time, from a Unix time, latitude and longitude.
- `OvercastSky.placed`: the sky takes its sun, moon, phase and stars from `latitude`,
  `longitude`, `date` and `time_of_day` (local, `utc_offset` hours from UTC), with `north` saying
  which way the world's north lies. The stars turn about the real pole, and the Milky Way lies
  where it does.
- Night, dusk and moonlight go by how high the sun and moon really stand, so polar summer has no
  night and polar winter no day. The hour-keyed arc (`time_of_day` round `sun_dir`) stays the
  simple mode.
- Real stars (done): the Yale Bright Star Catalogue, about 9,000 to magnitude 6.5, baked by
  `tools/bake_stars.gd` into `stars.res`, an octahedral map in the sky's star frame, precessed
  from J2000 to the date (IAU 1976). Not yet: proper motion (Barnard's star aside, under an
  arcminute since 2000).

## 2. One weather state, in layers (done)

Today the weather is spread over `cloud_amount`, `storm`, `snowy`, `rain`, `temperature` and
`wind`. One conditions resource instead: cover, type and base for a low, a middle and a high
layer; rain or snow and how hard; temperature; wind at the ground and aloft; visibility. Set by
hand, by OvercastCycle or by a feed, and read by the sky and the weather. The layers are how
forecasts and observations describe cloud, so real data and new cloud types share one model.

Heights are real metres; the sky's `world_scale` shrinks them into the world (1/15 by default,
for small levels; 1 for a world at real size).

## 3. Cloud types (done)

Each layer runs from heaped to a sheet, so a forecast blends between kinds rather than switching:

- Low (`cloud_sheet`): cumulus, stratocumulus, stratus. Ground shadows follow.
- Middle (`mid_cloud_sheet`): altocumulus, altostratus, the sun behind it as through frosted glass.
- High (`cirrus_sheet`): cirrus, cirrostratus with the 22° halo.
- `cloud_towering`: thunderheads painted round the horizon, towering cumulus then cumulonimbus
  with anvils and rain curtains. Overhead, a thunderstorm stays the storm deck.

Not done: cirrocumulus (the middle layer's puffs, smaller and higher), and thunderheads in the
ray-marched layer. Only the low layer ray-marches.

## 4. Real weather

Optional, off by default, and the game hands it the place (the place is the player's; it goes
to a third party only when they agree).

- Open-Meteo (done): `OvercastForecast` fetches the hours about the placed sky's moment, the
  forecast or the record, and hands the weather conditions blended between them. The clouds now
  drift with the wind (summed on the CPU into `overcast_cloud_drift`), the 850 hPa wind when the
  forecast gives it. Visibility becomes fog and haze (OvercastWeather.visibility), and how much
  of the rain is snow is the model's (snowfall against precipitation) rather than the ground
  temperature's alone, which covers what the freezing level would.
- METAR, near airports: observed cloud bases, and towering cumulus and cumulonimbus by name.
- Satellite (done): `OvercastSatellite` lays NASA GIBS' geostationary infrared round the place as
  the sky's cover map, a rank of how cold each pixel is, pressed toward no say when the frame's
  temperatures barely differ. The shell meets the horizon a few heights out where the real layer
  runs on for a hundred km, so the map is looked up by elevation and bearing. Not yet: Europe,
  Africa and India (no Meteosat in GIBS); telling the layers apart by temperature (every layer
  takes the same map); the daytime visible band. A new frame fades in over the last for a minute.
