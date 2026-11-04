# Overcast

[![tests](https://github.com/alanfischer/overcast-godot/actions/workflows/tests.yml/badge.svg)](https://github.com/alanfischer/overcast-godot/actions/workflows/tests.yml)

Sky, clouds and weather for Godot 4. The weather shows up in the world under the sky too: cloud
shadows drift across the ground, rain stays out from under roofs, the ground gets wet, rain sounds
muffled indoors, and lightning lights the open ground but not a torch-lit room. It works on every
renderer, including Compatibility and Mobile.

![Fair weather, with cloud shadows on the ground](docs/clear.png)
![A downpour: haze, far rain, puddles](docs/rain.png)

## Quick start

Copy `addons/overcast/` into your project and enable the plugin. The plugin declares the cloud
layer's global shader uniforms, which every Overcast shader needs to compile.

1. In your WorldEnvironment's Environment, set Background to Sky, and pick **New OvercastSky**
   as the Sky's material. Set its `sun_dir` to match your sun.
2. Add an **OvercastWeather** node. Set its `area` to cover your level and press
   **Bake Rain Floor**. Then drag `rain` up. The rain, the storm closing over and the lightning
   (**Strike**) all show in the editor.

The same from code:

```gdscript
var sky := OvercastSky.new({"cloud_amount": 0.4, "sun_dir": OvercastSky.sun_dir_of($Sun)})
$WorldEnvironment.environment = sky.make_environment()

$OvercastWeather.rain = 0.6  # 0 dry … 1 a downpour; it finds the scene's sky by itself
```

Run `demo/demo.tscn` to see all of it. It has a field and a few open huts, with sliders for
rain and the time of day, a lightning button, a volumetric-clouds switch, and a mode where showers come
and go on their own.

## What's in it

- **`OvercastSky`** is a sky material, with a `time_of_day` in hours: its day colours warm into a
  sunset at 18:00, go to moonlight and stars at night, and come back through dawn at 6:00. The
  sun crosses the sky with it (`sun_dir` is where it is at noon), and the weather's `sun` light
  turns to match. For a sun baked into your lighting, turn off `sun_follows_time`: the sun and
  moon then stay at `sun_dir`.
  `scene_light()` is the light it puts on your scene at that hour, for a sun's colour or a
  lightmap. It draws a gradient, a sun, stars, cirrus and a cumulus
  layer that closes over into a storm deck as `storm` rises. Its look is its shader parameters;
  the cloud layer's scale, speed and shadows are its own properties. Save it as a `.tres` to
  share one sky between scenes. The sky shader is `shaders/sky.gdshader`, built on
  `sky.gdshaderinc`. To draw the sky on your own geometry instead of a Godot `Sky`, include that
  file in a spatial shader and pass it as `OvercastSky.new({}, shader)`.
- **Volumetric clouds**: `OvercastClouds.set_volumetric(true)` ray-marches the clouds through 3D
  noise. That costs about a millisecond at 720p on an M1 on Compatibility. The radiance cubemap
  pass skips the clouds, so ambient light stays cheap.
- **Cloud shadows.** Include `shaders/clouds.gdshaderinc` and multiply your sun light by
  `cloud_sunlight(world_pos)`. The shadow comes from the same cloud the sky draws in front of
  the sun, so what's on the ground matches what's overhead. `demo/ground.gdshader` shows how in
  `light()`. For a game with baked lighting, scale the sun's share of each lightmap texel
  instead.
- **`OvercastWeather`** handles the rain:
  - drops in a box around the camera
  - haze and far rain only through air that rain is actually falling in
  - wet ground and puddles on every material that includes `shaders/wet.gdshaderinc`
  - rain sound that fades and low-passes under cover
  - lightning: a glowing bolt, a flash, and thunder delayed by the distance
  - its own rain loop and thunder, CC0 (`sounds/CREDITS.md`). Set `rain_stream` and
    `thunder_stream` to use your own, and `bolt_drawer` to draw bolts your way.
- **`OvercastRainFloor`** is where rain stops: roofs, overhangs, the ground. The weather's
  **Bake Rain Floor** raycasts down through your level's colliders once and saves it beside the
  scene as `<scene>_rain_floor.res`. A level built at runtime calls `bake_rain_floor()` after a
  physics frame instead. Without a rain floor, rain falls everywhere.
- **Covers** are things that move and keep the rain off: lifts, trains, drawbridges, a wall that
  can be knocked down. `add_cover(node)` rasterizes the node's own meshes onto the rain floor
  wherever it goes, so each cell takes the highest of it over that cell: something rotated,
  L-shaped or pitched keeps rain off exactly what is under it. A box or triangles of your own
  work too. A cover that only slides reuses its raster, and turning ones share out a per-tick
  budget. A hidden cover keeps nothing off. Drops, haze, wet ground and rain sound all follow it.
- **Showers:** turn on the weather's `cycle` and rain comes and goes on its own, building,
  wandering and dying away (`OvercastCycle`). The same `cycle_seed` gives the same weather.
- **Tuning** that a game would want to change is in the inspector: haze, drop counts, how fast
  ground soaks and dries, the gaps between strikes, how dark cloud shadows are.

## Networked games

Overcast has no networking of its own; you sync two things.

1. **Rain:** sync `rain`, or share `cycle_seed` and `cycle_time`.
2. **Lightning:** let one peer time the strikes (`times_strikes = true`) and send the seed from
   `struck` to the others, which call `strike(seed)`. The bolt, flash direction and thunder all
   derive from the seed, so every peer sees the same strike.

## Lighting the scene

Overcast lights its own sky, rain and haze. For your scene, it gives you hooks:

- `flash_changed(k)` fires every frame of a strike. Add `OvercastWeather.FLASH * k` to the sky's
  light on your scene.
- `sky_light` tells the weather how your scene is lit (`OvercastSky.scene_light()`), so the rain
  dims with it. The sky's time of day sets how bright lightning lights it.
- `sun`, if set, is a `DirectionalLight3D` that dims under the storm and lights up with each
  flash.

## Limits

- One sky draws the cloud layer at a time, because the clouds' shadows are global shader
  uniforms. The sky that last started drawing owns it.
- The sky's sun is its `sun_dir`; it does not follow a DirectionalLight3D by itself.
- The sun's path is an equinox's: up at 6:00, at `sun_dir` at noon, down at 18:00, with the moon
  on the same arc at night. There are no seasons or latitude.
- The cloud layer is tuned for levels a few dozen metres across (see below).

## Origin

Overcast comes from [Wizard Wars](https://github.com/alanfischer/wizardwars), a GoldSrc mod
ported to Godot. Its maps are lit by baked lightmaps, which is why cloud shadows and lightning
work through a light multiplier rather than through Godot's dynamic lights. The game plays on
Quest as well as desktop, which is why everything works on Compatibility.

The cloud layer sits 100 m up. That is tuned to maps a few dozen metres across; a much larger
world will want `CLOUD_HEIGHT` and the related constants in `clouds.gdshaderinc` scaled up.

## Tests

`./run_tests.sh` runs the suites headless. CI runs them on Godot 4.4 and 4.7.

## License

MIT
