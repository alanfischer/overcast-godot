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

```gdscript
var sky := OvercastSky.new({"cloud_amount": 0.4, "sun_dir": OvercastSky.sun_dir_of($Sun)})
$WorldEnvironment.environment = sky.make_environment()

$OvercastWeather.sky = sky   # an OvercastWeather node in the scene
$OvercastWeather.rain = 0.6  # 0 dry … 1 a downpour
```

Run `demo/demo.tscn` to see all of it. It has a field and a few open huts, with sliders for
rain and night, a lightning button, a volumetric-clouds switch, and a mode where showers come
and go on their own.

## What's in it

- **`OvercastSky`** draws a gradient, a sun, stars, cirrus and a cumulus layer that closes over
  into a storm deck as `storm` rises. The sky shader is `shaders/sky.gdshader`, built on
  `sky.gdshaderinc`. To draw the sky on your own geometry instead of a Godot `Sky`, include that
  file in a spatial shader.
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
  - lightning: a bolt, a flash, and thunder delayed by the distance
- **`OvercastRainFloor.bake`** raycasts down through your level once to find where rain stops:
  roofs, overhangs, the ground. Without a rain floor, rain falls everywhere.
- **`OvercastCycle`** produces showers that build, wander and die away. The same seed gives the
  same weather.

## Networked games

Overcast has no networking of its own; you sync two things.

1. **Rain:** sync `rain`, or share an `OvercastCycle` seed.
2. **Lightning:** let one peer time the strikes (`times_strikes = true`) and send the seed from
   `struck` to the others, which call `strike(seed)`. The bolt, flash direction and thunder all
   derive from the seed, so every peer sees the same strike.

## Lighting the scene

Overcast lights its own sky, rain and haze. For your scene, it gives you hooks:

- `flash_changed(k)` fires every frame of a strike. Add `OvercastWeather.FLASH * k` to the sky's
  light on your scene.
- `sky_light` and `night` tell the weather how dark your scene is, so the rain dims with it.
- `sun`, if set, is a `DirectionalLight3D` that dims under the storm and lights up with each
  flash.

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
