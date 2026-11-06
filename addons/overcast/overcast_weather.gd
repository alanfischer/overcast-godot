@tool
class_name OvercastWeather
extends Node3D
## Rain, snow and lightning: drops or flakes around the camera, haze and far rain where they are
## falling, wet ground, lying snow, rain sound that muffles under a roof, and a storm that closes the
## sky over. Set `rain` (and `snow`) and it does the rest, over the scene's OvercastSky (or `sky`).
## It all shows in the editor.
##
## Roofs are a rain floor: press Bake Rain Floor in the inspector, or bake one at runtime
## (bake_rain_floor). Without one, rain falls everywhere.
##
## Any material whose shader includes shaders/wet.gdshaderinc gets wet, and one that includes
## shaders/snow.gdshaderinc gets snowed on: the weather reaches it through global uniforms
## (OvercastGlobals), so one weather drives a scene at a time.
##
## Networked games: let one peer time the strikes (times_strikes), send the seed `struck` hands
## you, and call strike(seed) with it on the others. Everything about a strike comes from its
## seed, so every peer sees the same bolt.

## Lightning, every frame of a strike: `k` is its light, 0 to 1, ending on 0. Add it to the light
## the sky puts on your scene (FLASH * k) to light the open ground and not a torch-lit room.
signal flash_changed(k: float)
## A strike timed here (times_strikes); strike(seed) has already been called.
signal struck(strike_seed: int)

const Cycle = preload("res://addons/overcast/overcast_cycle.gd")
const Globals = preload("res://addons/overcast/overcast_globals.gd")
const Live = preload("res://addons/overcast/rain_floor_live.gd")
const Drift = preload("res://addons/overcast/overcast_snow_drift.gd")

## Lightning's light at the peak of a strike, as linear light added to the sky's.
const FLASH := Vector3(2.0, 2.1, 2.6)
## What it lights the sky itself with, brightest toward the bolt. A day sky is already bright, and
## the full flash would white it out and hide the bolt, so it takes SKY_FLASH_DAY of it, rising to
## all of it at the sky's full night.
const SKY_FLASH := Color(1.0, 1.05, 1.3)
const SKY_FLASH_DAY := 0.3
## The light of a strike over time: a stroke, a fainter return stroke, each dying away fast.
const STROKES := [[0.0, 1.0], [0.11, 0.75]]
const STROKE_DECAY := 0.07
const FLASH_LENGTH := 0.6
## How overcast the sky goes at the lightest rain (it reaches 1 at a downpour), and how fast it
## closes over or clears, per second.
const STORM_LIGHT := 0.55
## Snow falls from a sky already closed over: even light snow takes it this far.
const SNOW_STORM_LIGHT := 0.85
const STORM_RATE := 0.2
## Snow drifts: the even layer (m) a calm leaves, which the ground's own snow draws, and how far the
## steady wind (m/s) moves, held for DRIFT_WAIT seconds, before they are baked again.
const DRIFT_LAYER := 0.3
const DRIFT_REBAKE := 1.0
const DRIFT_WAIT := 1.0
## Rain sound by how much of the rain around the listener is reachable: sampled off the rain floor
## in rings (metres) a few times a second. Deep indoors it is RAIN_INDOOR_GAIN of the open-air
## volume and low-passed to RAIN_INDOOR_CUTOFF.
const RAIN_RINGS := [2.0, 6.0, 12.0]
const RAIN_RING_POINTS := 8
const RAIN_INDOOR_GAIN := 0.25
const RAIN_INDOOR_CUTOFF := 600.0
const RAIN_OPEN_CUTOFF := 20000.0
const RAIN_SAMPLE_EVERY := 0.25
const RAIN_EASE := 1.5  # exposure per second
## Wind sound by the wind's speed as it gusts (m/s): none below WIND_QUIET, a breeze can be heard
## but not this, rising to WIND_DB at WIND_LOUD and past it, and a little higher in pitch as it
## rises. Under a roof it is WIND_INDOOR_GAIN as loud.
const WIND_QUIET := 5.0
const WIND_LOUD := 18.0
const WIND_DB := -4.0
const WIND_PITCH := Vector2(0.85, 1.15)
const WIND_INDOOR_GAIN := 0.4
## Rain haze's colour is the sky's at the horizon, so distance fades into the sky behind it, but
## never darker than HAZE_FLOOR of HAZE_COLOR in the scene's light: a night sky is near black, and the
## scene's moonlight usually is not.
const HAZE_COLOR := Color(0.4, 0.43, 0.48)
const HAZE_FLOOR := 0.25
const HAZE_FLASH := 0.35
## Gusts: how far the haze density swings either way, and how fast the curtains drift (m/s).
const GUST_AMOUNT := 0.6
const GUST_DRIFT := Vector3(2.5, -1.0, 0.9)
const GUST_CELL := 80.0  # metres to the noise texture's width, as the shader's
## Drops fill a box this size (m) around the camera. DROP_LIGHT is how bright they read by day;
## lightning adds DROP_FLASH of its light and DROP_FLASH_OPACITY times their opacity.
const DROP_BOX := Vector3(36.0, 24.0, 36.0)
const DROP_LIGHT := 0.85
const DROP_FLASH := 1.5
const DROP_FLASH_OPACITY := 2.5
const DROP_COLOR := Color(0.75, 0.8, 0.9)
## Splashes land on the rain floor within SPLASH_BOX (m, square) around the camera.
const SPLASH_BOX := 28.0
## Flakes fill a smaller box: they are slow, and far off too small to see. FLAKE_COLOR is theirs in
## full daylight.
const FLAKE_BOX := Vector3(24.0, 16.0, 24.0)
const FLAKE_COLOR := Color(0.95, 0.96, 1.0)
## Snow hazes the distance less than rain, into the pale sky a snow storm draws; with no sky, into
## SNOW_HAZE_COLOR in the scene's light. Flakes range from FLAKE_DIM of their light to all of it,
## so some show dark against that haze and some light against the ground.
const SNOW_HAZE := 0.6
const SNOW_HAZE_COLOR := Color(0.72, 0.74, 0.78)
const FLAKE_DIM := 0.7
## Opacity of the far rain's streaks at a downpour, and of the far snow's flakes at a blizzard.
const FAR_OPACITY := 0.6
const FAR_SNOW_OPACITY := 0.8
## Gusts: how fast they come and go (noise per second), how far the speed swings either way at
## full gustiness (the noise mostly stays within ±0.5 of it), and how far the direction veers (rad).
const GUST_RATE := 25.0
const GUST_SWING := 2.0
const GUST_VEER := 0.6
## Bolts: segments, height over the top of `area` in cloud heights, and the speed thunder travels at.
const BOLT_SEGMENTS := 16
const BOLT_HEIGHT := Vector2(1.1, 1.7)
const SOUND_SPEED := 340.0
## How far a full storm dims `sun` when there is no sky to say (OvercastSky.storm_shadow).
const SUN_STORM_SHADOW := 0.88

## How hard it is raining: 0 dry, from a drizzle just above 0 to a downpour at 1. Past 1 only the
## number of drops keeps rising.
@export_range(0.0, 4.0, 0.01, "or_greater") var rain := 0.0:
	set(value):
		var was := rain
		rain = maxf(value, 0.0)
		if is_node_ready():
			_refresh(was)
## How much of what falls is snow: 0 all rain, 1 all snow, sleet between. `rain` is how much
## falls either way.
@export_range(0.0, 1.0, 0.01) var snow := 0.0:
	set(value):
		snow = clampf(value, 0.0, 1.0)
		if is_node_ready():
			_refresh(rain)
## Wind across the ground, m/s (y is ignored): rain slants with it, snow is carried off on it, and
## the haze's curtains blow along it.
@export var wind := Vector3.ZERO
## How far the wind swings in gusts, in speed and a little in direction: 0 steady, 1 from still to
## twice its speed.
@export_range(0.0, 1.0, 0.01) var gustiness := 0.4
## The sky the storm closes over and the lightning lights: the scene's own OvercastSky (its
## WorldEnvironment's) when unset.
@export var sky: OvercastSky:
	set(v):
		if v != sky:
			_let_sky_go()
		sky = v
		update_configuration_warnings()
## The weather's extent, in this node's space: the rain floor is baked over this box, and lightning
## lands within it, over its top.
@export var area := AABB(Vector3(-100, -20, -100), Vector3(200, 60, 200)):
	set(v):
		area = v
		update_gizmos()

@export_group("Rain floor")
## Where rain stops, so it stays out from under roofs. Bake it below, or at runtime.
@export var rain_floor: OvercastRainFloor:
	set(value):
		rain_floor = value
		_take_floor()
		update_configuration_warnings()
## Metres per cell the bake traces.
@export_range(0.1, 4.0, 0.05, "or_greater") var rain_floor_cell := 0.5
## Physics layers that catch rain.
@export_flags_3d_physics var rain_floor_mask := 0xFFFFFFFF
## Whether rain falls past the floor's edges: on for an open world (an island in the sea), off for
## a map with nothing past them.
@export var rain_beyond_floor := false:
	set(on):
		rain_beyond_floor = on
		_live.beyond = on
		if is_node_ready():
			_push_floor()
## Traces the scene's colliders down through `area`, and saves the floor beside the scene.
@export_tool_button("Bake Rain Floor", "Bake") var _bake_button := _bake_in_editor

@export_group("Showers")
## Rain that comes and goes on its own (OvercastCycle), overriding `rain`.
@export var cycle := false:
	set(on):
		cycle = on
		_cycle = null
		cycle_time = 0.0
## The same seed gives the same weather; 0 picks one at random.
@export var cycle_seed := 0:
	set(v):
		cycle_seed = v
		_cycle = null
## How much faster than real time the showers pass.
@export_range(0.0, 100.0, 0.1, "or_greater") var cycle_speed := 1.0

@export_group("Lightning")
@export var lightning := true
## Whether this peer decides when lightning strikes. Off on all but one peer of a networked game.
@export var times_strikes := true
## Seconds between strikes, least and most, at the lightest rain and at a downpour.
@export var strike_gap_light := Vector2(25.0, 45.0)
@export var strike_gap_heavy := Vector2(4.0, 10.0)
## A strike here and now, to see one in the editor.
@export_tool_button("Strike", "Play") var _strike_button := func() -> void: strike(randi())

@export_group("Scene light")
## A sun to dim under the storm and light with the flash, and, while the sky's sun follows the
## time of day, to turn with it and take its light (OvercastSky.scene_light). Optional. Let go
## of, as it was, when replaced or when the weather leaves the tree.
@export var sun: DirectionalLight3D:
	set(light):
		if light == sun:
			return
		_let_sun_go()
		sun = light
		_take_sun()
## Light the drops and the haze with the sky's scene_light(). Off, or with no sky, sky_light does.
@export var light_from_sky := true
## The light on the scene, as a multiplier: white by day, dimmer at night. Lights the drops and the
## haze when light_from_sky is off.
@export var sky_light := Color.WHITE

@export_group("Look")
## Rain wets every material that includes shaders/wet.gdshaderinc.
@export var wet_ground := true
## Rain haze: density per metre of rain-filled air at a full storm, scaled by storm² so light rain
## barely hazes; 0.04 loses ~70% of the view in 30 m of downpour.
@export_range(0.0, 0.2, 0.001) var haze_density := 0.04
## Drops around the camera at the lightest rain and at a downpour.
@export_range(0, 100000, 100) var drops_light := 3000
@export_range(0, 100000, 100) var drops_heavy := 40000
## Splashes on the ground around the camera at the lightest rain and at a downpour (each lands about
## twice a second). They need a rain floor: it is what they land on.
@export_range(0, 20000, 50) var splashes_light := 150
@export_range(0, 20000, 50) var splashes_heavy := 2500
## Snow covers every material that includes shaders/snow.gdshaderinc.
@export var lying_snow := true
## In a wind, lying snow heaps up in the lee of walls and banks against them, drawn as a surface of
## its own over the ground's snow (OvercastSnowDrift). Baked off the main thread from the rain
## floor, and again when the steady wind turns.
@export var snow_drifts := true
## Flakes around the camera at the lightest snow and at a blizzard.
@export_range(0, 100000, 100) var flakes_light := 8000
@export_range(0, 100000, 100) var flakes_heavy := 50000
## Wet ground (shaders/wet.gdshaderinc): seconds to soak at a downpour (longer in light rain) and
## to dry once it stops, and the same for puddles, which only a downpour fills.
@export_range(0.1, 600.0, 0.1, "or_greater", "suffix:s") var soak_time := 20.0
@export_range(0.1, 600.0, 0.1, "or_greater", "suffix:s") var dry_time := 120.0
@export_range(0.1, 600.0, 0.1, "or_greater", "suffix:s") var puddle_time := 90.0
@export_range(0.1, 600.0, 0.1, "or_greater", "suffix:s") var puddle_dry_time := 240.0
## Lying snow: seconds to cover the ground in a blizzard (longer in light snow), and to melt once
## it stops (rain melts it four times as fast).
@export_range(0.1, 3600.0, 0.1, "or_greater", "suffix:s") var snow_time := 90.0
@export_range(0.1, 3600.0, 0.1, "or_greater", "suffix:s") var melt_time := 600.0

@export_group("Sound")
## Who hears the rain and is lit by the flash's direction: the current camera when unset.
@export var listener: Node3D
## Where the listener's ears are, above its origin.
@export var listener_height := 0.0
## Overcast's own rain and thunder (sounds/, CC0) when unset.
@export var rain_stream: AudioStream:
	set(v):
		rain_stream = v
		if _rain_audio:
			_rain_audio.stream = v if v else _sound("rain")
@export var thunder_stream: AudioStream
@export var rain_bus := &"Master":
	set(v):
		rain_bus = v
		if _rain_audio:
			_rain_audio.bus = v
@export var thunder_bus := &"Master"
## Overcast's own wind (sounds/, CC0) when unset. Heard only in a strong wind.
@export var wind_stream: AudioStream:
	set(v):
		wind_stream = v
		if _wind_audio:
			_wind_audio.stream = v if v else _sound("wind")
@export var wind_bus := &"Master":
	set(v):
		wind_bus = v
		if _wind_audio:
			_wind_audio.bus = v

## Set while the camera is underwater: no rain is drawn, the sound carries on.
var underwater := false
## A low-pass on the rain's bus, closed down as the rain goes out of reach. Optional.
var rain_filter: AudioEffectLowPassFilter
## Microseconds a tick may spend rasterizing covers that turned (at least one is, whatever the
## budget). Past it the rest keep their old stamp and go first next tick, so a walking golem
## spreads its turning limbs over a few ticks rather than hitching one frame.
var cover_budget_usec: int:
	get:
		return _live.budget_usec
	set(v):
		_live.budget_usec = v
## Whether this draws and plays the weather. Off on a headless server, which only times the
## strikes and answers floor_at. Set before it enters the tree.
var presenting := DisplayServer.get_name() != "headless"
## Draws a bolt instead of the built-in one: (points: PackedVector3Array, width: float,
## brightness: float, fade: float) -> void. Called for each stroke.
var bolt_drawer: Callable

## How much snow lies on the ground, 0 to 1 (overcast_snow_cover): for a game's exposure, or its
## footsteps.
var snow_lying: float:
	get:
		return _snow_lying
## How far the sky has closed over, 0 to 1: follows the rain at STORM_RATE.
var storm := 0.0
## Seconds into the showers (cycle). Peers that share cycle_seed and this agree on the rain; set
## back, the showers are planned afresh from the start.
var cycle_time := 0.0:
	set(t):
		if t < cycle_time:
			_cycle = null
		cycle_time = t
var _cycle: Cycle
var _sky_told := 0  # the instance id of the sky last told the storm, and what it was told
var _sky_storm := Vector2(NAN, NAN)
## How much of the storm is snow: follows `snow` at STORM_RATE, as the sky turns pale.
var snowy := 0.0
## In the editor it draws, for a preview, but makes no sound, times no strikes and leaves the
## scene's own nodes (the sun) as they are saved.
var _editor := Engine.is_editor_hint()
var _flash_t := -1.0
var _flash_k := 0.0
var _flash_dir := Vector3.UP
var _next_strike := 0.0
var _drops: MultiMeshInstance3D
var _drop_material: ShaderMaterial
var _flakes: MultiMeshInstance3D
var _splashes: MultiMeshInstance3D
var _splash_material: ShaderMaterial
var _flake_material: ShaderMaterial
var _haze: MeshInstance3D
var _haze_material: ShaderMaterial
var _rain_audio: AudioStreamPlayer
var _wind_audio: AudioStreamPlayer
var _linear_output := true
var _live := Live.new()
## The drifts' material (shaders/drift.gdshader): its `contours` show how deep they are.
var drift_material: ShaderMaterial
var _drifts: MeshInstance3D
var _drift_floor: OvercastRainFloor  # what the drifts were baked for, and in what wind
var _drift_wind := Vector3.INF
var _drift_wait := DRIFT_WAIT
var _drift_task := -1
var _drift_arrays := []
var _rain_db := 0.0
var _exposure := 1.0
var _exposure_target := 1.0
var _sample_in := 0.0
var _gust_offset := Vector3.ZERO
var _gusts := FastNoiseLite.new()
var _gust_t := 0.0
## The wind as it blows this frame, gusts and all.
var _wind_now := Vector3.ZERO
## How far it has carried the drops and the flakes, wrapped into their boxes.
var _drop_drift := Vector3.ZERO
var _flake_drift := Vector3.ZERO
var _drop_fall := 9.0
var _flake_fall := 1.0
var _wetness := 0.0
var _puddles := 0.0
var _snow_lying := 0.0
var _wet_pushed := Vector4(-1, -1, -1, -1)  # wetness, puddles, sky luma, flash, as last pushed
var _snow_pushed := -1.0
var _rainfall_pushed := -1.0
var _slant_pushed := Vector2.INF
var _sun_energy := -1.0  # the sun's own light while taken; -1 when not
var _sun_color := Color.WHITE
var _sun_basis := Basis()
## The instance id of the weather whose rain the globals carry.
static var _globals_owner := 0


func _ready() -> void:
	if not bolt_drawer.is_valid():
		bolt_drawer = _draw_bolt
	if _editor:
		update_configuration_warnings.call_deferred()  # once the environment is in
	if not presenting:
		return
	_linear_output = OvercastSky.renderer_is_linear()
	_drop_material = _falling_material(preload("res://addons/overcast/shaders/rain.gdshader"), DROP_BOX)
	_drops = _falling("RainDrops", _drop_material)
	_flake_material = _falling_material(preload("res://addons/overcast/shaders/snow.gdshader"), FLAKE_BOX)
	_flakes = _falling("SnowFlakes", _flake_material)
	drift_material = ShaderMaterial.new()
	drift_material.shader = preload("res://addons/overcast/shaders/drift.gdshader")
	_splash_material = _falling_material(preload("res://addons/overcast/shaders/splash.gdshader"),
		Vector3(SPLASH_BOX, 1.0, SPLASH_BOX))
	_splashes = _falling("RainSplashes", _splash_material, _splash_mesh())

	if not _editor:
		_rain_audio = AudioStreamPlayer.new()
		_rain_audio.name = "RainAudio"
		_rain_audio.bus = rain_bus
		_rain_audio.stream = rain_stream if rain_stream else _sound("rain")
		_rain_audio.finished.connect(_on_rain_finished)
		add_child(_rain_audio)
		_wind_audio = AudioStreamPlayer.new()
		_wind_audio.name = "WindAudio"
		_wind_audio.bus = wind_bus
		_wind_audio.stream = wind_stream if wind_stream else _sound("wind")
		_wind_audio.finished.connect(func() -> void: _wind_audio.play())
		add_child(_wind_audio)
	_push_floor()
	_refresh(0.0)


func _falling_material(shader: Shader, box: Vector3) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("box", box)
	mat.render_priority = Material.RENDER_PRIORITY_MAX
	return mat


## A splash's two quads (splash.gdshader): one upright for its droplets, one flat (UV2.x 1) for its
## ring.
static func _splash_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var corners := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	for flat in [0.0, 1.0]:
		for c: Vector2 in corners:
			verts.append(Vector3(c.x, 0.0, c.y) if flat else Vector3(c.x, c.y, 0.0))
			uvs.append(Vector2(c.x + 0.5, 0.5 - c.y))
			uv2s.append(Vector2(flat, 0.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The drops or the flakes. The shader places every one itself; the instances carry no transforms.
func _falling(node_name: String, mat: ShaderMaterial, mesh: Mesh = null) -> MultiMeshInstance3D:
	if mesh == null:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		mesh = quad
	mesh.surface_set_material(0, mat)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = multimesh
	mmi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	add_child(mmi)
	return mmi


func _enter_tree() -> void:
	_take_sun()
	if is_node_ready():
		_push_floor()


func _exit_tree() -> void:
	if _drift_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_drift_task)
		_drift_task = -1
	_let_sun_go()
	_let_sky_go()
	if _flash_t >= 0.0:  # a flash ends on 0, whatever cuts it short
		_flash_t = -1.0
		_flash_k = 0.0
		flash_changed.emit(0.0)
	if _globals_owner == get_instance_id():
		_globals_owner = 0
		for key in ["overcast_has_rain_floor", "overcast_rain_beyond_floor", "overcast_rain_floor",
				"overcast_rain_under", "overcast_rain_floor_origin",
				"overcast_rain_floor_size", "overcast_rain_top", "overcast_wetness", "overcast_puddles",
				"overcast_rain_sky", "overcast_snow_cover", "overcast_rainfall", "overcast_rain_slant"]:
			Globals.reset(key)


func _take_sun() -> void:
	if sun and _sun_energy < 0.0 and presenting and not _editor and is_inside_tree():
		_sun_energy = sun.light_energy
		_sun_color = sun.light_color
		_sun_basis = sun.basis


func _let_sun_go() -> void:
	if _sun_energy >= 0.0 and is_instance_valid(sun):
		sun.light_energy = _sun_energy
		sun.light_color = _sun_color
		sun.basis = _sun_basis
	_sun_energy = -1.0


## The sky this has been closing over, back to clear: no storm, no snow, no flash.
func _let_sky_go() -> void:
	var told := instance_from_id(_sky_told) as OvercastSky
	if told:
		told.storm = 0.0
		told.snowy = 0.0
		told.set_flash(Color.BLACK, Vector3.UP)
	_sky_told = 0


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not Globals.declared():
		warnings.append("Overcast's global shader uniforms are not declared: enable the Overcast plugin in Project Settings > Plugins.")
	if current_sky() == null:
		warnings.append("No OvercastSky to close over: set `sky`, or give the WorldEnvironment's Sky an OvercastSky material. Rain still falls.")
	if rain_floor == null:
		warnings.append("No rain floor, so rain falls everywhere, under roofs too: press Bake Rain Floor.")
	return warnings


## One of sounds/.
static func _sound(sound_name: String) -> AudioStream:
	return load("res://addons/overcast/sounds/%s.ogg" % sound_name) as AudioStream


## `area` in world space: the box around it, if the node is turned.
func world_area() -> AABB:
	return global_transform * area if is_inside_tree() else area


## Bakes the rain floor over `area` from the colliders in the world now (at runtime, after a
## physics frame), and uses it.
func bake_rain_floor() -> void:
	rain_floor = OvercastRainFloor.bake(get_world_3d(), world_area(), rain_floor_cell, rain_floor_mask)


## The inspector's Bake Rain Floor: saved beside the scene as <scene>_rain_floor.res, so the scene
## file keeps a reference rather than the heights.
func _bake_in_editor() -> void:
	var baked := OvercastRainFloor.bake(get_world_3d(), world_area(), rain_floor_cell, rain_floor_mask)
	var root := get_tree().edited_scene_root if get_tree() else null
	if root and not root.scene_file_path.is_empty():
		var path := root.scene_file_path.get_basename() + "_rain_floor.res"
		if ResourceSaver.save(baked, path) == OK:
			baked.take_over_path(path)
		else:
			push_warning("Could not save %s: the rain floor stays in the scene" % path)
	else:
		push_warning("Save the scene first to keep the rain floor beside it: until then it is in the scene")
	rain_floor = baked
	var editor := Engine.get_singleton("EditorInterface")
	if editor:
		editor.mark_scene_as_unsaved()


## A scene loaded into rain already falling starts soaked.
func _take_floor() -> void:
	_live.set_floor(rain_floor, presenting)
	if is_node_ready():
		_push_floor()
	if rain > 0.0 and _live.image:
		_soak()


## The rain floor to the shaders, and so this weather's rain to the globals.
func _push_floor() -> void:
	if not presenting or not is_inside_tree():
		return
	_globals_owner = get_instance_id()
	_wet_pushed = Vector4(-1, -1, -1, -1)
	_snow_pushed = -1.0
	_rainfall_pushed = -1.0
	_slant_pushed = Vector2.INF
	Globals.set_value("overcast_has_rain_floor", _live.texture != null)
	Globals.set_value("overcast_rain_beyond_floor", rain_beyond_floor)
	Globals.set_value("overcast_rain_floor", _live.texture)
	Globals.set_value("overcast_rain_under", _live.under_texture)
	Globals.set_value("overcast_rain_floor_origin", _live.origin)
	Globals.set_value("overcast_rain_floor_size", _live.size)
	Globals.set_value("overcast_rain_top", _live.top)


## Straight to the weather the current rain is heading for: the storm closed over as far as it
## goes, the ground soaked or snowed over. For a scene that starts mid-shower, and for screenshots.
func settle() -> void:
	storm = _storm_target()
	snowy = snow
	_soak()


## Bakes the drifts for the rain floor and wind now, on this thread, rather than waiting for the
## wind to hold and baking them off it. For screenshots and tests.
func bake_drifts() -> void:
	if _drift_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_drift_task)
		_drift_task = -1
	if not presenting or not _drifting():
		return
	_drift_floor = rain_floor
	_drift_wind = Vector3(wind.x, 0.0, wind.z)
	_show_drifts(Drift.surface_arrays(rain_floor, Drift.bake(rain_floor, _drift_wind, DRIFT_LAYER), DRIFT_LAYER))


func _drifting() -> bool:
	return snow_drifts and lying_snow and rain_floor != null and rain_floor.image != null


## Shows the drifts while snow lies, and bakes them again for a new floor, or a wind that has
## turned and held.
func _update_drifts(delta: float) -> void:
	if _drift_task >= 0:
		if not WorkerThreadPool.is_task_completed(_drift_task):
			return
		WorkerThreadPool.wait_for_task_completion(_drift_task)
		_drift_task = -1
		_show_drifts(_drift_arrays)
	var on := _drifting()
	if _drifts:
		_drifts.visible = on and _snow_lying > 0.0
	if not on or (_snow_lying <= 0.0 and not _settling()):
		return
	var steady := Vector3(wind.x, 0.0, wind.z)
	if rain_floor == _drift_floor:
		if steady.distance_to(_drift_wind) < DRIFT_REBAKE:
			_drift_wait = DRIFT_WAIT
			return
		_drift_wait -= delta
		if _drift_wait > 0.0:
			return
	_drift_wait = DRIFT_WAIT
	_drift_floor = rain_floor
	_drift_wind = steady
	var source := rain_floor
	_drift_task = WorkerThreadPool.add_task(func() -> void:
		_drift_arrays = Drift.surface_arrays(source, Drift.bake(source, steady, DRIFT_LAYER), DRIFT_LAYER))


func _show_drifts(arrays: Array) -> void:
	if _drifts == null:
		_drifts = MeshInstance3D.new()
		_drifts.name = "SnowDrifts"
		_drifts.top_level = true
		add_child(_drifts)
	_drifts.mesh = Drift.surface_mesh(arrays, drift_material)
	_drifts.visible = _snow_lying > 0.0


func _soak() -> void:
	_wetness = 1.0 if rainfall() > 0.0 else 0.0
	_puddles = heaviness(rainfall())
	_snow_lying = 1.0 if _settling() else 0.0


## How much of `rain` falls as rain, and how much as snow.
func rainfall() -> float:
	return rain * (1.0 - snow)


func snowfall() -> float:
	return rain * snow


## Snow lies while more of it falls than rain.
func _settling() -> bool:
	return snow > 0.5 and rain > 0.0


func _storm_target() -> float:
	return 0.0 if rain <= 0.0 else lerpf(lerpf(STORM_LIGHT, SNOW_STORM_LIGHT, snow), 1.0, heaviness(rain))


## Something that moves and keeps rain off what is under it: a lift, a train, a drawbridge, a
## wall that can be knocked down. `shape` is what of it rain lands on, in its own frame: an AABB,
## a PackedVector3Array of triangles, or nothing for the meshes under the node (not those under a
## physics body of their own). Each floor cell takes the highest of it over that cell, so a
## rotated, L-shaped or pitched thing keeps rain off exactly what is under it. Re-stamped as it
## moves; it covers nothing while hidden, and a freed node is let go of by itself.
func add_cover(node: Node3D, shape: Variant = null) -> void:
	var tris: PackedVector3Array
	if shape is AABB:
		tris = _box_triangles(shape)
	elif shape is PackedVector3Array:
		tris = shape
	else:
		tris = mesh_triangles(node)
	_live.add_cover(node, tris)


func has_cover(node: Node3D) -> bool:
	return _live.covers.has(node)


func remove_cover(node: Node3D) -> void:
	_live.remove_cover(node)


## The triangles of every mesh under `node`, in its frame, skipping meshes under a physics body
## of their own (another mover's).
static func mesh_triangles(node: Node, xform := Transform3D()) -> PackedVector3Array:
	var tris := PackedVector3Array()
	for child in node.get_children():
		if child is PhysicsBody3D or not child is Node3D:
			continue
		var at: Transform3D = xform * (child as Node3D).transform
		var mi := child as MeshInstance3D
		if mi and mi.mesh:
			for v in mi.mesh.get_faces():
				tris.append(at * v)
		tris.append_array(mesh_triangles(child, at))
	return tris


static func _box_triangles(box: AABB) -> PackedVector3Array:
	var mesh := BoxMesh.new()
	mesh.size = box.size
	var tris := PackedVector3Array()
	for v in mesh.get_faces():
		tris.append(v + box.get_center())
	return tris


## 0 at the lightest rain to 1 at a downpour, and 0 when dry: what looks and sounds heavier
## stops at a downpour.
static func heaviness(amount: float) -> float:
	return clampf(amount, 0.0, 1.0) if amount > 0.0 else 0.0


## Seconds to the next strike after one, at rain `amount`.
func strike_gap(amount: float) -> float:
	var t := heaviness(amount)
	return randf_range(lerpf(strike_gap_light.x, strike_gap_heavy.x, t),
		lerpf(strike_gap_light.y, strike_gap_heavy.y, t))


## `was` is the rain before.
func _refresh(was: float) -> void:
	# The countdown restarts only when rain starts (rain that wanders would never let it run out);
	# heavier rain only ever pulls the next strike in.
	if rain > 0.0 and was <= 0.0:
		_next_strike = strike_gap(rain) * 0.5
	elif rain > was:
		_next_strike = minf(_next_strike, lerpf(strike_gap_light.y, strike_gap_heavy.y, heaviness(rain)))
	if not presenting:
		return
	if rain > 0.0 and _haze == null:
		_build_haze()
	_refresh_flakes()
	var wet := rainfall()
	var count := _fill(_drops, drops_light, drops_heavy, wet)
	_fill(_splashes, splashes_light, splashes_heavy, wet)
	if wet <= 0.0:
		if _rain_audio and _rain_audio.playing:
			_rain_audio.stop()
		return

	var heavy := heaviness(wet)
	# Rain falls at its terminal speed, a few m/s for drizzle and ~9 for a downpour's big drops.
	var fall_speed := lerpf(6.0, 9.5, heavy)
	var streak_length := lerpf(0.3, 0.55, heavy)
	var streak_width := lerpf(0.004, 0.007, heavy)
	_drop_fall = fall_speed
	_drop_material.set_shader_parameter("fall_speed", fall_speed)
	_drop_material.set_shader_parameter("streak_length", streak_length)
	_drop_material.set_shader_parameter("width", streak_width)
	_drop_material.set_shader_parameter("opacity", lerpf(0.3, 0.45, heavy))
	if _haze_material and not _far_snow():
		# The far rain thins out with the rain, and past a downpour fills in as the box does.
		var full := float(count) / maxi(drops_heavy, 1)
		_set_far(full, FAR_OPACITY, fall_speed, streak_length, streak_width, streak_length * 5.0)

	# -20 dB for light rain to -5 dB for a downpour, and by how much of it is in reach.
	_rain_db = lerpf(-20.0, -5.0, heavy)
	if _rain_audio:
		_apply_rain_volume()
		if not _rain_audio.playing and _rain_audio.stream:
			_rain_audio.play()


## Shows `amount` worth of drops or flakes: `light` at the least, `heavy` at a downpour, and more
## past it. Returns how many.
static func _fill(mmi: MultiMeshInstance3D, light: int, heavy: int, amount: float) -> int:
	var count := int(lerpf(light, heavy, amount)) if amount > 0.0 else 0
	var multimesh := mmi.multimesh
	if multimesh.instance_count < count:
		multimesh.instance_count = maxi(count, heavy)
	multimesh.visible_instance_count = count
	return count


## Whether the far streaks are snow's flakes rather than rain's: when more of it is snow.
func _far_snow() -> bool:
	return snow >= 0.5


## The far rain or snow, past the box (rain_haze.gdshader): `full` is how full its slots are.
func _set_far(full: float, opacity: float, fall_speed: float, length: float, width: float,
		gap: float) -> void:
	_haze_material.set_shader_parameter("presence", clampf(full, 0.15, 1.0))
	_haze_material.set_shader_parameter("streak_opacity", opacity * maxf(full, 1.0) if full > 0.0 else 0.0)
	_haze_material.set_shader_parameter("fall_speed", fall_speed)
	_haze_material.set_shader_parameter("streak_length", length)
	_haze_material.set_shader_parameter("streak_width", width)
	_haze_material.set_shader_parameter("streak_gap", gap)


func _refresh_flakes() -> void:
	var amount := snowfall()
	var count := _fill(_flakes, flakes_light, flakes_heavy, amount)
	if _haze_material and (_far_snow() or rain <= 0.0):
		var full := float(count) / maxi(flakes_heavy, 1) if _far_snow() else 0.0
		var heavy_far := heaviness(amount)
		var size := lerpf(0.018, 0.03, heavy_far)
		# Far off, a flake is a dot: a streak no longer than it is wide.
		_set_far(full, FAR_SNOW_OPACITY, lerpf(0.8, 1.5, heavy_far), size * 1.5, size, 3.0)
	if amount <= 0.0:
		return
	var heavy := heaviness(amount)
	# Flakes drift down at about a metre a second; a blizzard's are bigger and wetter, and faster.
	_flake_fall = lerpf(0.8, 1.5, heavy)
	_flake_material.set_shader_parameter("fall_speed", _flake_fall)
	_flake_material.set_shader_parameter("flake_size", lerpf(0.018, 0.03, heavy))
	_flake_material.set_shader_parameter("opacity", lerpf(0.8, 0.95, heavy))
	_flake_material.set_shader_parameter("dim", FLAKE_DIM)


func _build_haze() -> void:
	_haze_material = ShaderMaterial.new()
	_haze_material.shader = preload("res://addons/overcast/shaders/rain_haze.gdshader")
	_haze_material.render_priority = Material.RENDER_PRIORITY_MAX - 1  # over all it hazes, under the drops
	# OpenGL's NDC z is -1..1, Vulkan/Metal's 0..1.
	_haze_material.set_shader_parameter("depth_remap", Vector2(1.0, 0.0) if _linear_output else Vector2(2.0, -1.0))
	_haze_material.set_shader_parameter("linear_output", _linear_output)
	var noise := FastNoiseLite.new()
	noise.frequency = 1.0 / 16.0
	noise.fractal_octaves = 3
	var gusts := NoiseTexture3D.new()
	gusts.width = 64
	gusts.height = 64
	gusts.depth = 64
	gusts.seamless = true
	gusts.noise = noise
	_haze_material.set_shader_parameter("gust_noise", gusts)
	_haze_material.set_shader_parameter("gust_amount", GUST_AMOUNT)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)  # clip space, see the shader's vertex()
	quad.material = _haze_material
	_haze = MeshInstance3D.new()
	_haze.name = "RainHaze"
	_haze.mesh = quad
	# Drawn over the whole screen whatever the camera sees, so never culled.
	_haze.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_haze.visible = false
	add_child(_haze)


func _on_rain_finished() -> void:
	if rainfall() > 0.0:
		_rain_audio.play()


func _ears(fallback := Vector3.ZERO) -> Vector3:
	var node := listener if listener else get_viewport().get_camera_3d() as Node3D
	return node.global_position + Vector3.UP * listener_height if node else fallback


## How much of the rain around `ears` reaches them, 0 under a roof with no open sky in reach to 1
## in the open. Each sample point counts where rain lands below the ears there; the near ring
## counts most. Walls between are not seen: rain past one reads as rain through it.
func rain_exposure(ears: Vector3) -> float:
	if _live.image == null:
		return 1.0
	if not presenting:
		_live.sync()
	var hit := 0.0
	var total := 0.0
	for i in RAIN_RINGS.size() + 1:
		var r: float = 0.0 if i == 0 else RAIN_RINGS[i - 1]
		var weight := 1.0 / (1.0 + r * 0.25)
		for k in (1 if i == 0 else RAIN_RING_POINTS):
			var a := TAU * k / RAIN_RING_POINTS
			total += weight
			if _live.floor_at(ears + Vector3(cos(a), 0.0, sin(a)) * r) < ears.y:
				hit += weight
	return hit / total


## Where rain stops at world XZ `q`, covers included: off the floor INF, where no rain falls, or
## -INF with rain_beyond_floor; -INF with no floor.
func floor_at(q: Vector3) -> float:
	if not presenting:
		_live.sync()
	return _live.floor_at(q)


## How open the sky around the listener is, for the rain and the wind, eased as they move.
func _update_exposure(delta: float) -> void:
	_sample_in -= delta
	if _sample_in <= 0.0:
		_sample_in = RAIN_SAMPLE_EVERY
		_exposure_target = rain_exposure(_ears())
	if _exposure != _exposure_target:
		_exposure = move_toward(_exposure, _exposure_target, RAIN_EASE * delta)
		if _rain_audio.playing:
			_apply_rain_volume()


## How loud the wind is now, 0 to 1 (of WIND_DB), in the open: none in a breeze.
func wind_loudness() -> float:
	var k := smoothstep(WIND_QUIET, WIND_LOUD, _wind_now.length())
	return k * k


func _update_wind_sound() -> void:
	var gain := wind_loudness()
	if gain < 0.001:
		if _wind_audio.playing:
			_wind_audio.stop()
		return
	_wind_audio.volume_db = WIND_DB + linear_to_db(gain * lerpf(WIND_INDOOR_GAIN, 1.0, _exposure))
	_wind_audio.pitch_scale = lerpf(WIND_PITCH.x, WIND_PITCH.y, sqrt(gain))
	if not _wind_audio.playing and _wind_audio.stream:
		_wind_audio.play()


func _apply_rain_volume() -> void:
	_rain_audio.volume_db = _rain_db + linear_to_db(lerpf(RAIN_INDOOR_GAIN, 1.0, _exposure))
	if rain_filter:
		rain_filter.cutoff_hz = RAIN_INDOOR_CUTOFF * pow(RAIN_OPEN_CUTOFF / RAIN_INDOOR_CUTOFF, _exposure)


## The light on the scene: the sky's (light_from_sky), else sky_light.
func scene_light(drawn: OvercastSky) -> Color:
	return drawn.scene_light() if drawn and light_from_sky else sky_light


## What the haze fades to before lightning: the sky at the horizon, or lit haze where there is none.
func _haze_base(drawn: OvercastSky, light: Color) -> Color:
	var horizon: Color = drawn.horizon_now() if drawn else Color.BLACK
	var lit := HAZE_COLOR.lerp(SNOW_HAZE_COLOR, snowy) * light
	var least := lit * HAZE_FLOOR
	return lit if horizon == Color.BLACK else \
		Color(maxf(horizon.r, least.r), maxf(horizon.g, least.g), maxf(horizon.b, least.b))


## The wind this frame, gusts and all.
func wind_now() -> Vector3:
	return _wind_now


func _blow(delta: float) -> void:
	_gust_t += delta
	var flat := Vector3(wind.x, 0.0, wind.z)
	var swing := _gusts.get_noise_2d(_gust_t * GUST_RATE, 0.0)
	var veer := _gusts.get_noise_2d(_gust_t * GUST_RATE, 50.0)
	_wind_now = flat.rotated(Vector3.UP, veer * gustiness * GUST_VEER) \
		* maxf(1.0 + swing * gustiness * GUST_SWING, 0.0)
	_drop_drift = (_drop_drift + _wind_now * delta).posmodv(DROP_BOX)
	_flake_drift = (_flake_drift + _wind_now * delta).posmodv(FLAKE_BOX)
	_drop_material.set_shader_parameter("drift", _drop_drift)
	_drop_material.set_shader_parameter("wind", _wind_now)
	_flake_material.set_shader_parameter("drift", _flake_drift)
	# Roofs keep rain off by the steady wind, not each gust: wet ground does not flicker with it.
	var fall := _flake_fall if snowfall() > rainfall() else _drop_fall
	var slant := (Vector2(wind.x, wind.z) / fall).snapped(Vector2.ONE / 64.0)
	if slant != _slant_pushed:
		_slant_pushed = slant
		_globals_owner = get_instance_id()
		Globals.set_value("overcast_rain_slant", slant)


func _update_haze(delta: float, haze_color: Color, drop_light: Color) -> void:
	var density := haze_density * storm * storm * lerpf(1.0, SNOW_HAZE, snowy)
	_haze.visible = (density > 0.0005 or rain > 0.0) and not underwater
	if not _haze.visible:
		return
	# Kept in [0, 1) rather than driven off TIME, which loses precision as it grows.
	_gust_offset = (_gust_offset + (GUST_DRIFT + _wind_now) * delta / GUST_CELL).posmod(1.0)
	var fall := _flake_fall if _far_snow() else _drop_fall
	_haze_material.set_shader_parameter("slant", Vector2(_wind_now.x, _wind_now.z) / fall)
	_haze_material.set_shader_parameter("gust_offset", _gust_offset)
	_haze_material.set_shader_parameter("density", density)
	_drop_material.set_shader_parameter("haze_density", density)
	_splash_material.set_shader_parameter("haze_density", density)
	_flake_material.set_shader_parameter("haze_density", density)
	_haze_material.set_shader_parameter("haze_color", Vector3(haze_color.r, haze_color.g, haze_color.b))
	var streak := DROP_COLOR * drop_light
	if _far_snow():
		streak = FLAKE_COLOR * drop_light * lerpf(FLAKE_DIM, 1.0, 0.5)
	_haze_material.set_shader_parameter("streak_color", Vector3(streak.r, streak.g, streak.b))
	_haze_material.set_shader_parameter("flash", _flash_k * DROP_FLASH_OPACITY)


## Soaks and dries the ground, settles and melts the snow, and hands wet surfaces the sky they
## reflect, lightning included. Pushed only when the state moves by a step the screen can show.
func _update_wet(delta: float, reflected: Color) -> void:
	_update_snow(delta)
	var falling := snappedf(heaviness(rainfall()), 1.0 / 255.0)
	if falling != _rainfall_pushed:
		_rainfall_pushed = falling
		_globals_owner = get_instance_id()
		Globals.set_value("overcast_rainfall", falling)
	# Melting snow keeps the ground under it wet.
	var melting := _snow_lying > 0.0 and not _settling()
	var wet_target := 1.0 if (rainfall() > 0.0 or melting) and wet_ground else 0.0
	var puddle_target := heaviness(rainfall()) if wet_ground else 0.0
	_wetness = move_toward(_wetness, wet_target,
		(lerpf(0.35, 1.0, puddle_target) / soak_time if wet_target > _wetness else 1.0 / dry_time) * delta)
	_puddles = move_toward(_puddles, puddle_target,
		(1.0 / puddle_time if puddle_target > _puddles else 1.0 / puddle_dry_time) * delta)
	var state := Vector4(_wetness, _puddles, reflected.get_luminance(), _flash_k).snapped(Vector4.ONE / 255.0)
	if state == _wet_pushed:
		return
	_wet_pushed = state
	var srgb := reflected.linear_to_srgb()
	_globals_owner = get_instance_id()
	Globals.set_value("overcast_wetness", state.x)
	Globals.set_value("overcast_puddles", state.y)
	Globals.set_value("overcast_rain_sky", Vector3(srgb.r, srgb.g, srgb.b))


func _update_snow(delta: float) -> void:
	if _settling() and lying_snow:
		_snow_lying = move_toward(_snow_lying, 1.0, lerpf(0.35, 1.0, heaviness(snowfall())) / snow_time * delta)
	else:
		_snow_lying = move_toward(_snow_lying, 0.0, (1.0 + 3.0 * heaviness(rainfall())) / melt_time * delta)
	var lying := snappedf(_snow_lying, 1.0 / 255.0)
	if lying == _snow_pushed:
		return
	_snow_pushed = lying
	_globals_owner = get_instance_id()
	Globals.set_value("overcast_snow_cover", lying)


## Drops are only seen by the light on them: dim under a storm sky, dimmer at night, and lit up
## all at once by lightning. Their colour goes to the shader in its output space.
func _update_drops(light: Color) -> void:
	if not _drops.visible:
		return
	var color := DROP_COLOR * light
	if not _linear_output:
		color = color.linear_to_srgb()
	for mat in [_drop_material, _splash_material]:
		mat.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
		mat.set_shader_parameter("flash", _flash_k * DROP_FLASH_OPACITY)


func _update_flakes(light: Color) -> void:
	if not _flakes.visible:
		return
	var color := light if _linear_output else light.linear_to_srgb()
	_flake_material.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	_flake_material.set_shader_parameter("flash", _flash_k)


## The sky in use: `sky`, else the one the scene's environment draws.
func current_sky() -> OvercastSky:
	if sky:
		return sky
	var world := get_world_3d() if is_inside_tree() else null
	var env := world.environment if world else null
	if env == null and world:
		env = world.fallback_environment
	if env and env.sky and env.sky.sky_material is OvercastSky:
		return env.sky.sky_material
	return null


func _process(delta: float) -> void:
	if cycle and not _editor:
		if _cycle == null:
			_cycle = Cycle.new(cycle_seed)
		cycle_time += delta * cycle_speed
		rain = _cycle.rain_at(cycle_time)
	storm = move_toward(storm, _storm_target(), STORM_RATE * delta)
	# Snow hardly ever thunders: strikes come with the rain in it.
	if rainfall() > 0.0 and lightning and times_strikes and not _editor:
		_next_strike -= delta
		if _next_strike <= 0.0:
			_next_strike = strike_gap(rainfall())
			var strike_seed := randi()
			strike(strike_seed)
			struck.emit(strike_seed)
	if not presenting:
		return
	var drawn := current_sky()
	snowy = move_toward(snowy, snow, STORM_RATE * delta)
	if drawn and (drawn.get_instance_id() != _sky_told or Vector2(storm, snowy) != _sky_storm):
		drawn.storm = storm
		drawn.snowy = snowy
		_sky_told = drawn.get_instance_id()
		_sky_storm = Vector2(storm, snowy)
	_live.update(delta)
	_blow(delta)
	_drops.visible = rainfall() > 0.0 and not underwater
	_flakes.visible = snowfall() > 0.0 and not underwater
	_splashes.visible = _drops.visible and _live.texture != null
	if _rain_audio and (_rain_audio.playing or _wind_audio.playing or wind_loudness() > 0.0):
		_update_exposure(delta)
	if _wind_audio:
		_update_wind_sound()

	if _flash_t >= 0.0:
		_flash_t += delta
		var k := 0.0
		for s in STROKES:
			if _flash_t >= s[0]:
				k = maxf(k, s[1] * exp(-(_flash_t - s[0]) / STROKE_DECAY))
		if _flash_t >= FLASH_LENGTH:
			k = 0.0
			_flash_t = -1.0
		_flash_k = k
		flash_changed.emit(k)
		if drawn:
			drawn.set_flash(SKY_FLASH * k * lerpf(SKY_FLASH_DAY, 1.0, drawn.night), _flash_dir)
	if sun and _sun_energy >= 0.0 and drawn and drawn.sun_follows_time:
		var toward := drawn.light_dir()
		if not toward.is_equal_approx(sun.global_basis.z):
			var up := Vector3.UP if absf(toward.y) < 0.999 else Vector3.FORWARD
			sun.global_basis = Basis.looking_at(-toward, up)
		# Below the horizon it lights nothing: the ground is in the way.
		sun.light_color = _sun_color * drawn.scene_light() * smoothstep(-0.05, 0.05, toward.y) \
			* drawn.light_strength()
	if sun and _sun_energy >= 0.0:
		var shade := drawn.storm_shadow if drawn else SUN_STORM_SHADOW
		sun.light_energy = _sun_energy * (1.0 - shade * storm) + _flash_k * FLASH.x
	var light := scene_light(drawn)
	var drop_light := light * DROP_LIGHT + SKY_FLASH * _flash_k * DROP_FLASH
	_update_drops(drop_light)
	_update_flakes(light * FLAKE_COLOR + SKY_FLASH * _flash_k * DROP_FLASH)
	if _haze or rain > 0.0 or _wetness > 0.0 or _snow_lying > 0.0:
		var haze_color := _haze_base(drawn, light) + SKY_FLASH * _flash_k * HAZE_FLASH
		if _haze:
			_update_haze(delta, haze_color, drop_light)
		_update_wet(delta, haze_color)
	_update_drifts(delta)


## One lightning strike, somewhere over `area`, drawn up into the sky. Everything about it comes
## from the seed, so the bolt, its flash and its thunder agree on every peer that is handed it.
func strike(strike_seed: int) -> void:
	if not presenting or not is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = strike_seed
	var box := world_area()
	var cloud: float = Globals.value("overcast_height")
	var centre := box.get_center()
	var radius := maxf(box.size.x, box.size.z) * 0.5
	var angle := rng.randf() * TAU
	var out := Vector3(cos(angle), 0.0, sin(angle))
	var ground := centre + out * radius * rng.randf_range(0.2, 1.1)
	ground.y = box.end.y + 2.0
	var top := Vector3(ground.x, ground.y + rng.randf_range(BOLT_HEIGHT.x, BOLT_HEIGHT.y) * cloud, ground.z) \
		+ out * rng.randf_range(-0.25, 0.25) * cloud

	_bolt(ground, top, 1.0, rng)
	for i in rng.randi_range(1, 2):
		var from := ground.lerp(top, rng.randf_range(0.35, 0.75))
		var side := out.cross(Vector3.UP) * rng.randf_range(-1.0, 1.0)
		var to := from + (side + out * 0.4 + Vector3.DOWN).normalized() * rng.randf_range(0.15, 0.35) * cloud
		_bolt(to, from, 0.5, rng)

	var eye := _ears(centre)
	_flash_dir = (ground.lerp(top, 0.6) - eye).normalized()
	_flash_t = 0.0

	var thunder_sound := thunder_stream if thunder_stream else _sound("thunder")
	if thunder_sound and not _editor:
		var dist := eye.distance_to(ground)
		var thunder := AudioStreamPlayer.new()
		thunder.stream = thunder_sound
		thunder.bus = thunder_bus
		thunder.volume_db = lerpf(-2.0, -12.0, clampf(dist / 250.0, 0.0, 1.0))
		thunder.pitch_scale = rng.randf_range(0.85, 1.1)
		add_child(thunder)
		thunder.finished.connect(thunder.queue_free)
		# Bound to the player, so a weather freed before the thunder arrives takes it along.
		thunder.create_tween().tween_callback(thunder.play).set_delay(dist / SOUND_SPEED)


## A jagged line from `from` to `to`: each point wanders off the one before, which is what makes
## it read as lightning and not a wobbly line. Drawn once per stroke.
func _bolt(from: Vector3, to: Vector3, width_scale: float, rng: RandomNumberGenerator) -> void:
	var points := PackedVector3Array()
	var walk := Vector3.ZERO
	var jitter := from.distance_to(to) / BOLT_SEGMENTS * 0.6
	for i in BOLT_SEGMENTS + 1:
		var t := float(i) / BOLT_SEGMENTS
		points.append(from.lerp(to, t) + (walk if i < BOLT_SEGMENTS else Vector3.ZERO))
		walk += Vector3(rng.randf_range(-jitter, jitter), 0.0, rng.randf_range(-jitter, jitter))
		walk *= 0.85
	for stroke in STROKES:
		create_tween().tween_callback(bolt_drawer.bind(points, 2.2 * width_scale, stroke[1], 0.25)) \
			.set_delay(stroke[0])


## The built-in bolt (shaders/bolt.gdshader): one camera-facing strip along the points, faded out
## over `fade` s.
func _draw_bolt(points: PackedVector3Array, width: float, brightness: float, fade: float) -> void:
	var mesh := ImmediateMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://addons/overcast/shaders/bolt.gdshader")
	mat.set_shader_parameter("width", width)
	mat.set_shader_parameter("brightness", brightness)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var last := points.size() - 1
	for i in last:
		# Each point's direction is shared by the segments either side of it, so they join.
		var dirs: Array[Vector3] = []
		for k in [i, i + 1]:
			dirs.append((points[mini(k + 1, last)] - points[maxi(k - 1, 0)]).normalized())
		for v in [[i, -1.0], [i, 1.0], [i + 1, 1.0], [i, -1.0], [i + 1, 1.0], [i + 1, -1.0]]:
			mesh.surface_set_normal(dirs[v[0] - i])
			mesh.surface_set_uv(Vector2(v[1], float(v[0]) / last))
			mesh.surface_add_vertex(points[v[0]])
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The strip widens in the vertex shader, past the mesh's own bounds.
	mi.extra_cull_margin = width * 4.0
	mi.top_level = true
	add_child(mi)
	var tween := mi.create_tween()
	tween.tween_method(func(k: float) -> void: mat.set_shader_parameter("brightness", k),
		brightness, 0.0, fade)
	tween.tween_callback(mi.queue_free)
