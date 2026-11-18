# Roadmap: the sky over a real place

The aim: name a latitude, longitude and time, and get the sky that stands there — the sun, moon
and stars where they are, and in the end the clouds and weather that are there now.

## 1. Sun, moon and stars from a place and a time

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
- Later: real stars from the Yale Bright Star Catalogue (public domain) instead of the procedural
  field.

## 2. One weather state, in layers

Today the weather is spread over `cloud_amount`, `storm`, `snowy`, `rain`, `temperature` and
`wind`. One conditions resource instead: cover, type and base for a low, a middle and a high
layer; rain or snow and how hard; temperature; wind at the ground and aloft; visibility. Set by
hand, by OvercastCycle or by a feed, and read by the sky and the weather. The layers are how
forecasts and observations describe cloud, so real data and new cloud types share one model.

Open question: in a placed sky, cloud bases at their real heights (0.5 to 12 km), with shadows
on their own scale for small levels.

## 3. Cloud types

In the layer model, by what they give for what they cost:

- Altocumulus and cirrocumulus: a cheap flat high layer of small cells, the sunset sky.
- Stratus and stratocumulus: a grey sheet with no rain (today only the storm deck closes the sky).
- Cirrostratus and altostratus: a thin veil, the sun dimmed to a disc, the 22° halo.
- Cumulonimbus: towers and anvils. The costly one: a tall volumetric slab, or painted at the
  horizon.

Only the low layer ray-marches.

## 4. Real weather

Optional, off by default, and the game hands it the place (the place is the player's; it goes
to a third party only when they agree).

- Open-Meteo first: current and hourly temperature, rain, snow, weather code, low/mid/high cloud
  cover, wind and gusts, visibility. Free without a key for non-commercial use only.
- METAR, near airports: observed cloud bases, and towering cumulus and cumulonimbus by name.
- Satellite, last: geostationary cloud imagery (NASA GIBS tiles, about every ten minutes) cropped
  round the place into a cover texture that steers the cloud noise, so the clouds overhead are
  roughly the real ones. Needs one new sky input: a world-space cover map that drifts with the
  wind.
