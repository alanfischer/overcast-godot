@tool
class_name OvercastWeather
extends Node3D
## Rain, snow and lightning: drops or flakes around the camera, haze and far rain where they are
## falling, wet ground, lying snow, rain sound that muffles under a roof, and a storm that closes the
## sky over. Set `rain` (and `temperature`) and it does the rest, over the scene's OvercastSky (or `sky`).
## It all shows in the editor.
##
## Roofs are a rain floor: press Bake Rain Floor in the inspector, or bake one at runtime
## (bake_rain_floor). Without one, rain falls everywhere.
##
## What lies on the ground, wet, ice and snow, is its `ground` (OvercastGround).
##
## Any material whose shader includes shaders/wet.gdshaderinc gets wet, and one that includes
## shaders/snow.gdshaderinc gets snowed on: the weather reaches it through global uniforms
## (overcast_globals.gd), so one weather drives a scene at a time.
##
## Networked games: let one peer time the strikes (times_strikes), send the seed `struck` hands
## you, and call strike(seed) with it on the others. Everything about a strike comes from its
## seed, so every peer sees the same bolt.

## Lightning, every frame of a strike: the linear light it adds to what the sky puts on your scene,
## ending on black. Add it there to light the open ground and not a torch-lit room.
signal flash_changed(light: Color)
## A strike timed here (times_strikes); strike(seed) has already been called.
signal struck(strike_seed: int)

const _Cycle = preload("res://addons/overcast/overcast_cycle.gd")
const _Globals = preload("res://addons/overcast/overcast_globals.gd")
const _Live = preload("res://addons/overcast/rain_floor_live.gd")
const _Drift = preload("res://addons/overcast/overcast_snow_drift.gd")

## Lightning's light at the peak of a strike, as linear light added to the sky's.
const _FLASH := Color(2.0, 2.1, 2.6)
## What it lights the sky itself with, brightest toward the bolt. A day sky is already bright, and
## the full flash would white it out and hide the bolt, so it takes _SKY_FLASH_DAY of it, rising to
## all of it at the sky's full night.
const _SKY_FLASH := Color(1.0, 1.05, 1.3)
const _SKY_FLASH_DAY := 0.3
## The light of a strike over time: a stroke, a fainter return stroke, each dying away fast.
const _STROKES := [[0.0, 1.0], [0.11, 0.75]]
const _STROKE_DECAY := 0.07
const _FLASH_LENGTH := 0.6
## How overcast the sky goes at the lightest rain (it reaches 1 at a downpour), and how fast it
## closes over or clears, per second.
const _STORM_LIGHT := 0.55
## Snow falls from a sky already closed over: even light snow takes it this far.
const _SNOW_STORM_LIGHT := 0.85
## Degrees C over which what falls turns from all snow to all rain.
const SLEET := Vector2(-1.0, 3.0)
## Snow lies at this and below, and melts above it; wet ground freezes, and ice thaws.
const FREEZING := 0.0
const _STORM_RATE := 0.2
## Snow drifts: the even layer (m) a calm leaves, which the ground's own snow draws, and how far the
## steady wind (m/s) moves, held for _DRIFT_WAIT seconds, before they are baked again.
const DRIFT_LAYER := 0.3
const _DRIFT_REBAKE := 1.0
const _DRIFT_WAIT := 1.0
## A wind that turns again before what lies on the ground is this far round to it is followed
## straight away; later, once the ground has come all the way round.
const _GROUND_RETARGET := 0.05
## Rain sound by how much of the rain around the listener is reachable: sampled off the rain floor
## in rings (metres) a few times a second. Deep indoors it is _RAIN_INDOOR_GAIN of the open-air
## volume and low-passed to _RAIN_INDOOR_CUTOFF.
const _RAIN_RINGS := [2.0, 6.0, 12.0]
const _RAIN_RING_POINTS := 8
const _RAIN_INDOOR_GAIN := 0.25
const _RAIN_INDOOR_CUTOFF := 600.0
const _RAIN_OPEN_CUTOFF := 20000.0
const _RAIN_SAMPLE_EVERY := 0.25
const _RAIN_EASE := 1.5  # exposure per second
## Wind sound by the wind's speed as it gusts (m/s): none below _WIND_QUIET, a breeze can be heard
## but not this, rising to _WIND_DB at _WIND_LOUD and past it, and a little higher in pitch as it
## rises. Under a roof it is _WIND_INDOOR_GAIN as loud.
const _WIND_QUIET := 5.0
const _WIND_LOUD := 18.0
const _WIND_DB := -4.0
const _WIND_PITCH := Vector2(0.85, 1.15)
const _WIND_INDOOR_GAIN := 0.4
## Rain haze's colour is the sky's at the horizon, so distance fades into the sky behind it, but
## never darker than _HAZE_FLOOR of _HAZE_COLOR in the scene's light: a night sky is near black, and the
## scene's moonlight usually is not.
const _HAZE_COLOR := Color(0.4, 0.43, 0.48)
const _HAZE_FLOOR := 0.25
const _HAZE_FLASH := 0.35
## Gusts: how far the haze density swings either way, and how fast the curtains drift (m/s).
const _GUST_AMOUNT := 0.6
const _GUST_DRIFT := Vector3(2.5, -1.0, 0.9)
const _GUST_CELL := 80.0  # metres to the noise texture's width, as the shader's
## Drops fill a box this size (m) around the camera. _DROP_LIGHT is how bright they read by day;
## lightning adds _DROP_FLASH of its light and _DROP_FLASH_OPACITY times their opacity.
const _DROP_BOX := Vector3(36.0, 24.0, 36.0)
const _DROP_LIGHT := 0.85
const _DROP_FLASH := 1.5
const _DROP_FLASH_OPACITY := 2.5
const _DROP_COLOR := Color(0.75, 0.8, 0.9)
## Splashes land on the rain floor within _SPLASH_BOX (m, square) around the camera.
const _SPLASH_BOX := 28.0
## Flakes fill a smaller box: they are slow, and far off too small to see. _FLAKE_COLOR is theirs in
## full daylight.
const _FLAKE_BOX := Vector3(24.0, 16.0, 24.0)
## Metres fallen are wrapped at this; the far rain's carry at _FAR_WRAP, where its grid repeats
## (rain_haze.gdshader's CELL * WRAP_CELLS).
const _FALL_WRAP := 16384.0
const _FAR_WRAP := 0.9 * 1024.0
const _FLAKE_COLOR := Color(0.95, 0.96, 1.0)
## Snow hazes the distance less than rain, into the pale sky a snow storm draws; with no sky, into
## _SNOW_HAZE_COLOR in the scene's light. Flakes range from _FLAKE_DIM of their light to all of it,
## so some show dark against that haze and some light against the ground.
const _SNOW_HAZE := 0.6
const _SNOW_HAZE_COLOR := Color(0.72, 0.74, 0.78)
const _FLAKE_DIM := 0.7
## Opacity of the far rain's streaks at a downpour, and of the far snow's flakes at a blizzard.
const _FAR_OPACITY := 0.6
const _FAR_SNOW_OPACITY := 0.8
## Gusts: how fast they come and go (noise per second), how far the speed swings either way at
## full gustiness (the noise mostly stays within ±0.5 of it), and how far the direction veers (rad).
const _GUST_RATE := 25.0
const _GUST_SWING := 2.0
const _GUST_VEER := 0.6
## Bolts: segments, height over the top of `area` in cloud heights, and the speed thunder travels at.
const _BOLT_SEGMENTS := 16
const _BOLT_HEIGHT := Vector2(1.1, 1.7)
const _SOUND_SPEED := 340.0
## How far a full storm dims `sun` when there is no sky to say (OvercastSky.storm_shadow).
const _SUN_STORM_SHADOW := 0.88
## How far under where rain stops ground still takes it (rains_on).
const _GROUND_REACH := 1.0

## How hard it is raining: 0 dry, from a drizzle just above 0 to a downpour at 1. Past 1 only the
## number of drops keeps rising.
@export_range(0.0, 4.0, 0.01, "or_greater") var rain := 0.0:
	set(value):
		var was := rain
		rain = maxf(value, 0.0)
		if is_node_ready():
			_refresh(was)
## Degrees C at the ground. What falls is snow below SLEET.x, rain above SLEET.y, sleet between;
## snow lies while it is freezing (FREEZING and below), and melts once it is not.
@export_range(-30.0, 40.0, 0.5, "or_less", "or_greater", "suffix:°C") var temperature := 10.0:
	set(value):
		temperature = value
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
## Whether the showers bring their own wind too, overriding `wind`.
@export var cycle_wind := true
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
## time of day, to turn with it and take its light (OvercastSky.scene_light). Optional. Its own
## energy, colour and direction, as set, are the noon sun's: a change made to them from outside
## (the inspector, code) is its own from then on. Let go of, as it was, when replaced or when the
## weather leaves the tree. In the editor it is driven too, for the preview, and saved as it was.
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
## its own over the ground's snow (overcast_snow_drift.gd). Baked off the main thread from the rain
## floor, and again when the steady wind turns.
@export var snow_drifts := true
## The deepest a drift starts against a wall or a cliff (m); it slopes away downwind from there.
@export_range(0.3, 5.0, 0.05, "or_greater", "suffix:m") var drift_deepest := _Drift.DEEPEST
## Drifts lie on the faces of the meshes under this (the level's standing geometry), where they
## face up and rain reaches them, and so end where those faces do. None: this weather's parent.
@export var drift_ground: Node3D:
	set(node):
		drift_ground = node
		_faces_taken = false
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
## it is above freezing (rain melts it four times as fast).
@export_range(0.1, 3600.0, 0.1, "or_greater", "suffix:s") var snow_time := 90.0
@export_range(0.1, 3600.0, 0.1, "or_greater", "suffix:s") var melt_time := 600.0
## Ice: seconds for wet ground to freeze over 5 degrees below freezing, and for its ice to thaw
## as far above it (rain thaws it four times as fast).
@export_range(0.1, 3600.0, 0.1, "or_greater", "suffix:s") var freeze_time := 60.0
@export_range(0.1, 3600.0, 0.1, "or_greater", "suffix:s") var thaw_time := 30.0

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
## Whether this draws and plays the weather. Off on a headless server, which still times the
## strikes, keeps the ground (`ground`) and answers the *_at queries, but draws and plays
## nothing. Set before it enters the tree. (Not OvercastSky.drawing, which is which sky holds the
## cloud layer.)
var presenting := DisplayServer.get_name() != "headless"
## Draws a bolt instead of the built-in one: (points: PackedVector3Array, width: float,
## brightness: float, fade: float) -> void. Called for each stroke.
var bolt_drawer: Callable

## What lies on the ground: wet, ice and snow, kept on a headless server too. Its own object, for a
## networked game to keep one peer's and have the others take it up.
var ground := OvercastGround.new(self)
## How much of what falls is snow at `temperature`: 0 all rain, 1 all snow, sleet between.
var snow_share: float:
	get:
		return 1.0 - smoothstep(SLEET.x, SLEET.y, temperature)
## How much of `rain` falls as rain, and how much as snow.
var rainfall: float:
	get:
		return rain * (1.0 - snow_share)
var snowfall: float:
	get:
		return rain * snow_share
## The wind this frame, gusts and all.
var wind_now: Vector3:
	get:
		return _wind_now
## How far the sky has closed over, 0 to 1: follows the rain at _STORM_RATE.
var storm: float:
	get:
		return _storm
## Seconds into the showers (cycle). Peers that share cycle_seed and this agree on the rain; set
## back, the showers are planned afresh from the start.
var cycle_time := 0.0:
	set(t):
		if t < cycle_time:
			_cycle = null
		cycle_time = t
var _cycle: _Cycle
var _sky_told := 0  # the instance id of the sky last told the storm, and what it was told
var _sky_storm := Vector2(NAN, NAN)
## How much of the storm is snow: follows snow_share at _STORM_RATE, as the sky turns pale.
var snowy: float:
	get:
		return _snowy
var _storm := 0.0
var _snowy := 0.0
## In the editor it draws, for a preview, but makes no sound and times no strikes.
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
var _live := _Live.new()
## The drifts' material (shaders/drift.gdshader): its `contours` show how deep they are.
var drift_material: ShaderMaterial
var _drifts: MeshInstance3D
var _field_drifted := false  # its target is a wind's drifts, not the even layer
var _drift_target := PackedFloat32Array()
var _drift_floor: OvercastRainFloor  # what the drifts were baked for, and in what wind
var _drift_wind := Vector3.INF
var _drift_wait := _DRIFT_WAIT
var _drift_task := -1
var _drift_arrays := []
var _faces := PackedVector3Array()  # drift_ground's faces, in the world
var _faces_taken := false
var _ground: _Drift.Ground  # what the drifts lie on, laid for _ground_floor
var _ground_floor: OvercastRainFloor
var _ground_laid: _Drift.Ground  # what the bake under way laid them on
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
var _far_fall := 9.0
## How far they have fallen, and the far rain been carried: integrated, so a change of speed moves
## them on from where they are.
var _drop_fallen := 0.0
var _flake_fallen := 0.0
var _far_fallen := 0.0
var _far_carried := Vector2.ZERO
var _wet_pushed := Vector4(-1, -1, -1, -1)  # wetness, puddles, sky luma, flash, as last pushed
var _snow_pushed := -1.0
var _ice_pushed := -1.0
var _rainfall_pushed := -1.0
var _slant_pushed := Vector2.INF
## The slant the ground was wet or snowed on for, and the one it is coming round to, by _ground_shift.
var _ground_slant := Vector4.INF
var _ground_shift := 1.0
var _ground_pushed := -1.0
var _sun_taken := false
var _sun_energy := 1.0  # the sun's own light, colour and direction, while taken
var _sun_color := Color.WHITE
var _sun_basis := Basis()
var _sun_set_energy := 0.0  # what this last left the sun at, to tell a change from outside
var _sun_set_color := Color.WHITE
var _sun_set_basis := Basis()
## The instance id of the weather whose rain the globals carry.
static var _globals_owner := 0


func _ready() -> void:
	if not bolt_drawer.is_valid():
		bolt_drawer = _draw_bolt
	if _editor:
		update_configuration_warnings.call_deferred()  # once the environment is in
	if not presenting:
		return
	_linear_output = OvercastSky._renderer_is_linear()
	_drop_material = _falling_material(preload("res://addons/overcast/shaders/rain.gdshader"), _DROP_BOX)
	_drops = _falling("RainDrops", _drop_material)
	_flake_material = _falling_material(preload("res://addons/overcast/shaders/snow.gdshader"), _FLAKE_BOX)
	_flakes = _falling("SnowFlakes", _flake_material)
	drift_material = ShaderMaterial.new()
	drift_material.shader = preload("res://addons/overcast/shaders/drift.gdshader")
	_splash_material = _falling_material(preload("res://addons/overcast/shaders/splash.gdshader"),
		Vector3(_SPLASH_BOX, 1.0, _SPLASH_BOX))
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
		flash_changed.emit(Color.BLACK)
	if _globals_owner == get_instance_id():
		_globals_owner = 0
		for key in ["overcast_has_rain_floor", "overcast_rain_beyond_floor", "overcast_rain_floor",
				"overcast_rain_under", "overcast_rain_floor_origin",
				"overcast_rain_floor_size", "overcast_rain_top", "overcast_wetness", "overcast_puddles",
				"overcast_rain_sky", "overcast_snow_cover", "overcast_has_snow_field",
				"overcast_snow_field", "overcast_rainfall", "overcast_rain_slant",
				"overcast_ground_slant", "overcast_ground_shift", "overcast_ice",
				"overcast_has_ice_field", "overcast_ice_field"]:
			_Globals.reset(key)


func _take_sun() -> void:
	if sun and not _sun_taken and presenting and is_inside_tree():
		_sun_taken = true
		_sun_energy = sun.light_energy
		_sun_color = sun.light_color
		_sun_basis = sun.basis
		_note_sun()


func _let_sun_go() -> void:
	if _sun_taken and is_instance_valid(sun):
		_restore_sun()
	_sun_taken = false


func _restore_sun() -> void:
	sun.light_energy = _sun_energy
	sun.light_color = _sun_color
	sun.basis = _sun_basis
	_note_sun()


func _note_sun() -> void:
	_sun_set_energy = sun.light_energy
	_sun_set_color = sun.light_color
	_sun_set_basis = sun.basis


## The editor saves the sun as it was, not as the preview drives it: what is saved is what the
## next run takes for the noon sun.
func _notification(what: int) -> void:
	if not _sun_taken or not is_instance_valid(sun):
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_restore_sun()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_drive_sun(current_sky())


## The sky this has been closing over, back to clear: no storm, no snow, no flash.
func _let_sky_go() -> void:
	var told := instance_from_id(_sky_told) as OvercastSky
	if told:
		told.set_weather(0.0, 0.0)
		told.set_flash(Color.BLACK, Vector3.UP)
	_sky_told = 0


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not _Globals.declared():
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
	ground._take_floor(rain_floor, _live.image != null, presenting)
	_field_drifted = false
	_drift_floor = null
	_faces_taken = false  # a new floor: the level may have changed under it
	if is_node_ready():
		_push_floor()
	if rain > 0.0 and _live.image:
		ground._soak()


## The rain floor to the shaders, and so this weather's rain to the globals.
func _push_floor() -> void:
	if not presenting or not is_inside_tree():
		return
	_globals_owner = get_instance_id()
	_wet_pushed = Vector4(-1, -1, -1, -1)
	_snow_pushed = -1.0
	_ice_pushed = -1.0
	_rainfall_pushed = -1.0
	_slant_pushed = Vector2.INF
	_ground_pushed = -1.0
	_Globals.set_value("overcast_has_rain_floor", _live.texture != null)
	_Globals.set_value("overcast_rain_beyond_floor", rain_beyond_floor)
	_Globals.set_value("overcast_rain_floor", _live.texture)
	_Globals.set_value("overcast_rain_under", _live.under_texture)
	_Globals.set_value("overcast_rain_floor_origin", _live.origin)
	_Globals.set_value("overcast_rain_floor_size", _live.size)
	_Globals.set_value("overcast_rain_top", _live.top)
	var snow := ground._snow
	var frozen := ground._ice_field
	_Globals.set_value("overcast_has_snow_field", snow != null)
	_Globals.set_value("overcast_snow_field", snow.texture if snow else null)
	_Globals.set_value("overcast_has_ice_field", frozen != null)
	_Globals.set_value("overcast_ice_field", frozen.texture if frozen else null)


## Straight to the weather the current rain is heading for: the storm closed over as far as it
## goes, the ground soaked or snowed over. For a scene that starts mid-shower, and for screenshots.
func settle() -> void:
	_storm = _storm_target()
	_snowy = snow_share
	ground._soak()
	_ground_shift = 1.0
	_ground_slant = Vector4.INF


## Bakes the drifts for the rain floor and wind now, on this thread, rather than waiting for the
## wind to hold and baking them off it, and lays the snow as deep in them as it lies anywhere. For
## screenshots and tests.
func bake_drifts() -> void:
	if _drift_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_drift_task)
		_drift_task = -1
	var field := ground._snow
	if field == null or not _drifting():
		return
	_drift_floor = rain_floor
	_drift_wind = Vector3(wind.x, 0.0, wind.z)
	_drift_target = _drifted(rain_floor, _drift_wind, drift_deepest)
	field.set_target(_drift_target)
	_field_drifted = true
	field.fill(ground.snow_cover)
	if presenting:
		_show_drifts(_Drift.surface_arrays(_laid(rain_floor, _ground_faces()), field.target, DRIFT_LAYER))


func _drifting() -> bool:
	return snow_drifts and lying_snow and rain_floor != null and rain_floor.image != null


## The faces of drift_ground's meshes, in the world, taken once for each floor (main thread only:
## it reads the meshes). Leaves out this weather's own.
func _ground_faces() -> PackedVector3Array:
	if _faces_taken:
		return _faces
	_faces_taken = true
	_faces = PackedVector3Array()
	_ground = null
	var root := drift_ground if drift_ground else get_parent() as Node3D
	if root == null or not root.is_inside_tree():
		return _faces
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.push_front(root)
	for mi: MeshInstance3D in meshes:
		if mi.mesh and mi != self and not is_ancestor_of(mi) and _drifts_on(mi):
			_faces.append_array(mi.global_transform * mi.mesh.get_faces())
	return _faces


## Whether drifts lie on `mesh`, one of drift_ground's: a game leaves out what is not ground to it
## (a liquid's surface, the sky).
func _drifts_on(_mesh: MeshInstance3D) -> bool:
	return true


## What the drifts lie on for `source`, laid from `faces` the first time.
func _laid(source: OvercastRainFloor, faces: PackedVector3Array) -> _Drift.Ground:
	if _ground_floor != source or _ground == null:
		_ground = _Drift.lay(source, faces)
		_ground_floor = source
	return _ground


## The snow `rain_floor` holds once it has all settled in `wind`, rounded off.
static func _drifted(source: OvercastRainFloor, steady: Vector3, deepest: float) -> PackedFloat32Array:
	return _Drift.rounded(source, _Drift.bake(source, steady, DRIFT_LAYER, deepest).get_data().to_float32_array())


## Shows the drifts while snow lies, and bakes them again for a new floor, or a wind that has
## turned and held: the field comes round to them, and the mesh reaches over both the snow lying
## now and the drifts it heads for. Undrawn, only the depths are baked.
func _update_drifts(delta: float) -> void:
	if _drift_task >= 0:
		if not WorkerThreadPool.is_task_completed(_drift_task):
			return
		WorkerThreadPool.wait_for_task_completion(_drift_task)
		_drift_task = -1
		if presenting:
			_ground = _ground_laid
			_ground_floor = _drift_floor
		if ground._snow and rain_floor == _drift_floor:
			ground._snow.set_target(_drift_target)
			_field_drifted = true
			if presenting:
				_show_drifts(_drift_arrays)
	var field := ground._snow
	var on := field != null and _drifting()
	if _drifts:
		_drifts.visible = on and ground.snow_cover > 0.0
	if field and not on and _field_drifted:
		_forget_drifts()
	if not on or (ground.snow_cover <= 0.0 and not ground._settling()):
		return
	var steady := Vector3(wind.x, 0.0, wind.z)
	if rain_floor == _drift_floor:
		if steady.distance_to(_drift_wind) < _DRIFT_REBAKE:
			_drift_wait = _DRIFT_WAIT
			return
		_drift_wait -= delta
		if _drift_wait > 0.0:
			return
	_drift_wait = _DRIFT_WAIT
	_drift_floor = rain_floor
	_drift_wind = steady
	var source := rain_floor
	var lying := field.depth.duplicate()
	var bare := field.bare_cells().duplicate()
	var deepest := drift_deepest
	var drawn := presenting
	var faces := _ground_faces() if drawn else PackedVector3Array()
	var laid := _ground if _ground_floor == source else null
	_drift_task = WorkerThreadPool.add_task(func() -> void:
		var drifted := _drifted(source, steady, deepest)
		_drift_target = drifted
		if not drawn:
			return
		var heap := drifted.duplicate()
		for i in heap.size():
			heap[i] = maxf(heap[i], lying[i])
		for c in bare:
			heap[c] = 0.0
		var bed := laid if laid else _Drift.lay(source, faces)
		_ground_laid = bed
		_drift_arrays = _Drift.surface_arrays(bed, heap, DRIFT_LAYER))


## The snow heads for the even layer until the drifts are baked again.
func _forget_drifts() -> void:
	if ground._snow:
		ground._snow.set_target(_even_target())
	_field_drifted = false
	_drift_floor = null


func _even_target() -> PackedFloat32Array:
	var even := PackedFloat32Array()
	even.resize(ground._snow.depth.size())
	even.fill(DRIFT_LAYER)
	return even


func _show_drifts(baked: Array) -> void:
	if _drifts == null:
		_drifts = MeshInstance3D.new()
		_drifts.name = "SnowDrifts"
		_drifts.top_level = true
		add_child(_drifts)
	_drifts.mesh = _Drift.surface_mesh(baked, drift_material)
	_drifts.visible = ground.snow_cover > 0.0


## How fast lying wet or snow comes round to a new wind, per second: as snow settles where it lies,
## else as the ground soaks.
func _ground_rate() -> float:
	return 1.0 / (snow_time if ground.snow_cover > 0.0 or ground._settling() else soak_time)


func _storm_target() -> float:
	return 0.0 if rain <= 0.0 else lerpf(lerpf(_STORM_LIGHT, _SNOW_STORM_LIGHT, snow_share), 1.0, _heaviness(rain))


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
		tris = _mesh_triangles(node)
	_live.add_cover(node, tris)


func has_cover(node: Node3D) -> bool:
	return _live.covers.has(node)


func remove_cover(node: Node3D) -> void:
	_live.remove_cover(node)


## The triangles of every mesh under `node`, in its frame, skipping meshes under a physics body
## of their own (another mover's).
static func _mesh_triangles(node: Node, xform := Transform3D()) -> PackedVector3Array:
	var tris := PackedVector3Array()
	for child in node.get_children():
		if child is PhysicsBody3D or not child is Node3D:
			continue
		var at: Transform3D = xform * (child as Node3D).transform
		var mi := child as MeshInstance3D
		if mi and mi.mesh:
			for v in mi.mesh.get_faces():
				tris.append(at * v)
		tris.append_array(_mesh_triangles(child, at))
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
static func _heaviness(amount: float) -> float:
	return clampf(amount, 0.0, 1.0) if amount > 0.0 else 0.0


## Seconds to the next strike after one, at rain `amount`.
func _strike_gap(amount: float) -> float:
	var t := _heaviness(amount)
	return randf_range(lerpf(strike_gap_light.x, strike_gap_heavy.x, t),
		lerpf(strike_gap_light.y, strike_gap_heavy.y, t))


## `was` is the rain before.
func _refresh(was: float) -> void:
	# The countdown restarts only when rain starts (rain that wanders would never let it run out);
	# heavier rain only ever pulls the next strike in.
	if rain > 0.0 and was <= 0.0:
		_next_strike = _strike_gap(rain) * 0.5
	elif rain > was:
		_next_strike = minf(_next_strike, lerpf(strike_gap_light.y, strike_gap_heavy.y, _heaviness(rain)))
	if not presenting:
		return
	if rain > 0.0 and _haze == null:
		_build_haze()
	_refresh_flakes()
	var wet := rainfall
	var count := _fill(_drops, drops_light, drops_heavy, wet)
	_fill(_splashes, splashes_light, splashes_heavy, wet)
	if wet <= 0.0:
		if _rain_audio and _rain_audio.playing:
			_rain_audio.stop()
		return

	var heavy := _heaviness(wet)
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
		_set_far(full, _FAR_OPACITY, fall_speed, streak_length, streak_width, streak_length * 5.0)

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
	return snow_share >= 0.5


## The far rain or snow, past the box (rain_haze.gdshader): `full` is how full its slots are.
func _set_far(full: float, opacity: float, fall_speed: float, length: float, width: float,
		gap: float) -> void:
	_haze_material.set_shader_parameter("presence", clampf(full, 0.15, 1.0))
	_haze_material.set_shader_parameter("streak_opacity", opacity * maxf(full, 1.0) if full > 0.0 else 0.0)
	_far_fall = fall_speed
	_haze_material.set_shader_parameter("streak_length", length)
	_haze_material.set_shader_parameter("streak_width", width)
	_haze_material.set_shader_parameter("streak_gap", gap)


func _refresh_flakes() -> void:
	var amount := snowfall
	var count := _fill(_flakes, flakes_light, flakes_heavy, amount)
	if _haze_material and (_far_snow() or rain <= 0.0):
		var full := float(count) / maxi(flakes_heavy, 1) if _far_snow() else 0.0
		var heavy_far := _heaviness(amount)
		var size := lerpf(0.018, 0.03, heavy_far)
		# Far off, a flake is a dot: a streak no longer than it is wide.
		_set_far(full, _FAR_SNOW_OPACITY, lerpf(0.8, 1.5, heavy_far), size * 1.5, size, 3.0)
	if amount <= 0.0:
		return
	var heavy := _heaviness(amount)
	# Flakes drift down at about a metre a second; a blizzard's are bigger and wetter, and faster.
	_flake_fall = lerpf(0.8, 1.5, heavy)
	_flake_material.set_shader_parameter("flake_size", lerpf(0.018, 0.03, heavy))
	_flake_material.set_shader_parameter("opacity", lerpf(0.8, 0.95, heavy))
	_flake_material.set_shader_parameter("dim", _FLAKE_DIM)


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
	_haze_material.set_shader_parameter("gust_amount", _GUST_AMOUNT)
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
	if rainfall > 0.0:
		_rain_audio.play()


func _ears(fallback := Vector3.ZERO) -> Vector3:
	var node := listener if listener else get_viewport().get_camera_3d() as Node3D
	return node.global_position + Vector3.UP * listener_height if node else fallback


## How much of the rain around `ears` reaches them, 0 under a roof with no open sky in reach to 1
## in the open. Each sample point counts where rain lands below the ears there; the near ring
## counts most. Walls between are not seen: rain past one reads as rain through it.
func _rain_exposure(ears: Vector3) -> float:
	if _live.image == null:
		return 1.0
	if not presenting:
		_live.sync()
	var hit := 0.0
	var total := 0.0
	for i in _RAIN_RINGS.size() + 1:
		var r: float = 0.0 if i == 0 else _RAIN_RINGS[i - 1]
		var weight := 1.0 / (1.0 + r * 0.25)
		for k in (1 if i == 0 else _RAIN_RING_POINTS):
			var a := TAU * k / _RAIN_RING_POINTS
			total += weight
			if _live.floor_at(ears + Vector3(cos(a), 0.0, sin(a)) * r) < ears.y:
				hit += weight
	return hit / total


## Whether rain falls on the ground at world point `p`, straight down (the wind's slant aside). A
## cell stops rain at the highest of its corners, so ground up to _GROUND_REACH under that still
## counts: a slope, a stair. The ground's *_at queries (OvercastGround) go by it.
func rains_on(p: Vector3) -> bool:
	return floor_at(p) < p.y + _GROUND_REACH


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
		_sample_in = _RAIN_SAMPLE_EVERY
		_exposure_target = _rain_exposure(_ears())
	if _exposure != _exposure_target:
		_exposure = move_toward(_exposure, _exposure_target, _RAIN_EASE * delta)
		if _rain_audio.playing:
			_apply_rain_volume()


## How loud the wind is now, 0 to 1 (of _WIND_DB), in the open: none in a breeze.
func _wind_loudness() -> float:
	var k := smoothstep(_WIND_QUIET, _WIND_LOUD, _wind_now.length())
	return k * k


func _update_wind_sound() -> void:
	var gain := _wind_loudness()
	if gain < 0.001:
		if _wind_audio.playing:
			_wind_audio.stop()
		return
	_wind_audio.volume_db = _WIND_DB + linear_to_db(gain * lerpf(_WIND_INDOOR_GAIN, 1.0, _exposure))
	_wind_audio.pitch_scale = lerpf(_WIND_PITCH.x, _WIND_PITCH.y, sqrt(gain))
	if not _wind_audio.playing and _wind_audio.stream:
		_wind_audio.play()


func _apply_rain_volume() -> void:
	_rain_audio.volume_db = _rain_db + linear_to_db(lerpf(_RAIN_INDOOR_GAIN, 1.0, _exposure))
	if rain_filter:
		rain_filter.cutoff_hz = _RAIN_INDOOR_CUTOFF * pow(_RAIN_OPEN_CUTOFF / _RAIN_INDOOR_CUTOFF, _exposure)


## The light on the scene: the sky's (light_from_sky), else sky_light.
func _scene_light(drawn: OvercastSky) -> Color:
	return drawn.scene_light() if drawn and light_from_sky else sky_light


## What the haze fades to before lightning: the sky at the horizon, or lit haze where there is none.
func _haze_base(drawn: OvercastSky, light: Color) -> Color:
	var horizon: Color = drawn.horizon_now() if drawn else Color.BLACK
	var lit := _HAZE_COLOR.lerp(_SNOW_HAZE_COLOR, snowy) * light
	var least := lit * _HAZE_FLOOR
	return lit if horizon == Color.BLACK else \
		Color(maxf(horizon.r, least.r), maxf(horizon.g, least.g), maxf(horizon.b, least.b))


func _blow(delta: float) -> void:
	_gust_t += delta
	var flat := Vector3(wind.x, 0.0, wind.z)
	var swing := _gusts.get_noise_2d(_gust_t * _GUST_RATE, 0.0)
	var veer := _gusts.get_noise_2d(_gust_t * _GUST_RATE, 50.0)
	_wind_now = flat.rotated(Vector3.UP, veer * gustiness * _GUST_VEER) \
		* maxf(1.0 + swing * gustiness * _GUST_SWING, 0.0)
	_drop_drift = (_drop_drift + _wind_now * delta).posmodv(_DROP_BOX)
	_flake_drift = (_flake_drift + _wind_now * delta).posmodv(_FLAKE_BOX)
	_drop_fallen = fposmod(_drop_fallen + _drop_fall * delta, _FALL_WRAP)
	_flake_fallen = fposmod(_flake_fallen + _flake_fall * delta, _FALL_WRAP)
	_drop_material.set_shader_parameter("drift", _drop_drift)
	_drop_material.set_shader_parameter("fallen", _drop_fallen)
	_drop_material.set_shader_parameter("wind", _wind_now)
	_flake_material.set_shader_parameter("drift", _flake_drift)
	_flake_material.set_shader_parameter("fallen", _flake_fallen)
	# Roofs keep rain off by the steady wind, not each gust: wet ground does not flicker with it.
	var fall := _flake_fall if snowfall > rainfall else _drop_fall
	var slant := (Vector2(wind.x, wind.z) / fall).snapped(Vector2.ONE / 64.0)
	if slant != _slant_pushed:
		_slant_pushed = slant
		_globals_owner = get_instance_id()
		_Globals.set_value("overcast_rain_slant", slant)
	_turn_ground(delta, slant)


## Brings what lies on the ground round to the wind's `slant`: the wet and the snow blown in under
## one eave fade as they gather under another. With nothing lying it is there at once.
func _turn_ground(delta: float, slant: Vector2) -> void:
	var to := Vector2(_ground_slant.z, _ground_slant.w)
	if slant != to and (_ground_shift >= 1.0 or _ground_shift <= _GROUND_RETARGET):
		var lying := ground.wetness > 0.0 or ground.snow_cover > 0.0
		var from := Vector2(_ground_slant.x, _ground_slant.y) if _ground_shift < 1.0 else to
		if not lying or _ground_slant == Vector4.INF:
			from = slant
		_ground_slant = Vector4(from.x, from.y, slant.x, slant.y)
		if from == slant:
			_ground_shift = 1.0
		elif _ground_shift >= 1.0:
			_ground_shift = 0.0
		_ground_pushed = -1.0
		_globals_owner = get_instance_id()
		_Globals.set_value("overcast_ground_slant", _ground_slant)
	if _ground_shift < 1.0:
		_ground_shift = move_toward(_ground_shift, 1.0, _ground_rate() * delta)
	var shift := snappedf(_ground_shift, 1.0 / 255.0) if _ground_shift < 1.0 else 1.0
	if shift != _ground_pushed:
		_ground_pushed = shift
		_globals_owner = get_instance_id()
		_Globals.set_value("overcast_ground_shift", shift)


func _update_haze(delta: float, haze_color: Color, drop_light: Color) -> void:
	var density := haze_density * storm * storm * lerpf(1.0, _SNOW_HAZE, snowy)
	_haze.visible = (density > 0.0005 or rain > 0.0) and not underwater
	if not _haze.visible:
		return
	# Kept in [0, 1) rather than driven off TIME, which loses precision as it grows.
	_gust_offset = (_gust_offset + (_GUST_DRIFT + _wind_now) * delta / _GUST_CELL).posmod(1.0)
	var blow := Vector2(_wind_now.x, _wind_now.z)
	_far_fallen = fposmod(_far_fallen + _far_fall * delta, _FALL_WRAP)
	_far_carried = (_far_carried + blow * delta).posmod(_FAR_WRAP)
	_haze_material.set_shader_parameter("fallen", _far_fallen)
	_haze_material.set_shader_parameter("carried", _far_carried)
	_haze_material.set_shader_parameter("slant", blow / _far_fall)
	_haze_material.set_shader_parameter("gust_offset", _gust_offset)
	_haze_material.set_shader_parameter("density", density)
	_drop_material.set_shader_parameter("haze_density", density)
	_splash_material.set_shader_parameter("haze_density", density)
	_flake_material.set_shader_parameter("haze_density", density)
	_haze_material.set_shader_parameter("haze_color", Vector3(haze_color.r, haze_color.g, haze_color.b))
	var streak := _DROP_COLOR * drop_light
	if _far_snow():
		streak = _FLAKE_COLOR * drop_light * lerpf(_FLAKE_DIM, 1.0, 0.5)
	_haze_material.set_shader_parameter("streak_color", Vector3(streak.r, streak.g, streak.b))
	_haze_material.set_shader_parameter("flash", _flash_k * _DROP_FLASH_OPACITY)


## Hands the shaders the ground's wet, ice and snow, and wet surfaces the sky they reflect,
## lightning included. Pushed only when the state moves by a step the screen can show.
func _update_wet(reflected: Color) -> void:
	_update_snow()
	var glaze := snappedf(ground.ice, 1.0 / 255.0)
	if glaze != _ice_pushed:
		_ice_pushed = glaze
		_globals_owner = get_instance_id()
		_Globals.set_value("overcast_ice", glaze)
	var falling := snappedf(_heaviness(rainfall), 1.0 / 255.0)
	if falling != _rainfall_pushed:
		_rainfall_pushed = falling
		_globals_owner = get_instance_id()
		_Globals.set_value("overcast_rainfall", falling)
	var state := Vector4(ground.wetness, ground.puddles, reflected.get_luminance(), _flash_k).snapped(Vector4.ONE / 255.0)
	if state == _wet_pushed:
		return
	_wet_pushed = state
	var srgb := reflected.linear_to_srgb()
	_globals_owner = get_instance_id()
	_Globals.set_value("overcast_wetness", state.x)
	_Globals.set_value("overcast_puddles", state.y)
	_Globals.set_value("overcast_rain_sky", Vector3(srgb.r, srgb.g, srgb.b))


func _update_snow() -> void:
	var lying := snappedf(ground.snow_cover, 1.0 / 255.0)
	if lying == _snow_pushed:
		return
	_snow_pushed = lying
	_globals_owner = get_instance_id()
	_Globals.set_value("overcast_snow_cover", lying)


## Drops are only seen by the light on them: dim under a storm sky, dimmer at night, and lit up
## all at once by lightning. Their colour goes to the shader in its output space.
func _update_drops(light: Color) -> void:
	if not _drops.visible:
		return
	var color := _DROP_COLOR * light
	if not _linear_output:
		color = color.linear_to_srgb()
	for mat in [_drop_material, _splash_material]:
		mat.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
		mat.set_shader_parameter("flash", _flash_k * _DROP_FLASH_OPACITY)


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
			_cycle = _Cycle.new(cycle_seed)
		cycle_time += delta * cycle_speed
		rain = _cycle.rain_at(cycle_time)
		if cycle_wind:
			wind = _cycle.wind_at(cycle_time)
	_storm = move_toward(_storm, _storm_target(), _STORM_RATE * delta)
	# Snow hardly ever thunders: strikes come with the rain in it.
	if rainfall > 0.0 and lightning and times_strikes and not _editor:
		_next_strike -= delta
		if _next_strike <= 0.0:
			_next_strike = _strike_gap(rainfall)
			var strike_seed := randi()
			strike(strike_seed)
			struck.emit(strike_seed)
	# Or still showing some: wetness set to none from outside is drawn as none.
	var on_ground := rain > 0.0 or ground.wetness > 0.0 or ground.snow_cover > 0.0 \
		or ground.ice > 0.0 or _wet_pushed.x > 0.0
	ground._step(delta, on_ground)
	_update_drifts(delta)
	if not presenting:
		return
	var drawn := current_sky()
	_snowy = move_toward(_snowy, snow_share, _STORM_RATE * delta)
	if drawn and (drawn.get_instance_id() != _sky_told or Vector2(storm, snowy) != _sky_storm):
		drawn.set_weather(_storm, _snowy)
		_sky_told = drawn.get_instance_id()
		_sky_storm = Vector2(storm, snowy)
	_live.update(delta)
	_blow(delta)
	_drops.visible = rainfall > 0.0 and not underwater
	_flakes.visible = snowfall > 0.0 and not underwater
	_splashes.visible = _drops.visible and _live.texture != null
	if _rain_audio and (_rain_audio.playing or _wind_audio.playing or _wind_loudness() > 0.0):
		_update_exposure(delta)
	if _wind_audio:
		_update_wind_sound()

	if _flash_t >= 0.0:
		_flash_t += delta
		var k := 0.0
		for s in _STROKES:
			if _flash_t >= s[0]:
				k = maxf(k, s[1] * exp(-(_flash_t - s[0]) / _STROKE_DECAY))
		if _flash_t >= _FLASH_LENGTH:
			k = 0.0
			_flash_t = -1.0
		_flash_k = k
		flash_changed.emit(_FLASH * k)
		if drawn:
			drawn.set_flash(_SKY_FLASH * k * lerpf(_SKY_FLASH_DAY, 1.0, drawn.night), _flash_dir)
	if _sun_taken and is_instance_valid(sun):
		_drive_sun(drawn)
	var light := _scene_light(drawn)
	var drop_light := light * _DROP_LIGHT + _SKY_FLASH * _flash_k * _DROP_FLASH
	_update_drops(drop_light)
	_update_flakes(light * _FLAKE_COLOR + _SKY_FLASH * _flash_k * _DROP_FLASH)
	if _haze or on_ground:
		var haze_color := _haze_base(drawn, light) + _SKY_FLASH * _flash_k * _HAZE_FLASH
		if _haze:
			_update_haze(delta, haze_color, drop_light)
		_update_wet(haze_color)


func _drive_sun(drawn: OvercastSky) -> void:
	# Changed since this last set it: someone else's doing, and the sun's own from now on.
	if sun.light_energy != _sun_set_energy:
		_sun_energy = sun.light_energy
	if sun.light_color != _sun_set_color:
		_sun_color = sun.light_color
	if sun.basis != _sun_set_basis:
		_sun_basis = sun.basis
	if drawn and drawn.sun_follows_time:
		var toward := drawn.light_dir()
		if not toward.is_equal_approx(sun.global_basis.z):
			var up := Vector3.UP if absf(toward.y) < 0.999 else Vector3.FORWARD
			sun.global_basis = Basis.looking_at(-toward, up)
		# Below the horizon it lights nothing: the ground is in the way.
		sun.light_color = _sun_color * drawn.scene_light() * smoothstep(-0.05, 0.05, toward.y) \
			* drawn.light_strength()
	var shade := drawn.storm_shadow if drawn else _SUN_STORM_SHADOW
	sun.light_energy = _sun_energy * (1.0 - shade * storm) + _flash_k * _FLASH.r
	_note_sun()


## One lightning strike, somewhere over `area`, drawn up into the sky. Everything about it comes
## from the seed, so the bolt, its flash and its thunder agree on every peer that is handed it.
func strike(strike_seed: int) -> void:
	if not presenting or not is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = strike_seed
	var box := world_area()
	var cloud: float = _Globals.value("overcast_height")
	var centre := box.get_center()
	var radius := maxf(box.size.x, box.size.z) * 0.5
	var angle := rng.randf() * TAU
	var out := Vector3(cos(angle), 0.0, sin(angle))
	var landing := centre + out * radius * rng.randf_range(0.2, 1.1)
	landing.y = box.end.y + 2.0
	var top := Vector3(landing.x, landing.y + rng.randf_range(_BOLT_HEIGHT.x, _BOLT_HEIGHT.y) * cloud, landing.z) \
		+ out * rng.randf_range(-0.25, 0.25) * cloud

	_bolt(landing, top, 1.0, rng)
	for i in rng.randi_range(1, 2):
		var from := landing.lerp(top, rng.randf_range(0.35, 0.75))
		var side := out.cross(Vector3.UP) * rng.randf_range(-1.0, 1.0)
		var to := from + (side + out * 0.4 + Vector3.DOWN).normalized() * rng.randf_range(0.15, 0.35) * cloud
		_bolt(to, from, 0.5, rng)

	var eye := _ears(centre)
	_flash_dir = (landing.lerp(top, 0.6) - eye).normalized()
	_flash_t = 0.0

	var thunder_sound := thunder_stream if thunder_stream else _sound("thunder")
	if thunder_sound and not _editor:
		var dist := eye.distance_to(landing)
		var thunder := AudioStreamPlayer.new()
		thunder.stream = thunder_sound
		thunder.bus = thunder_bus
		thunder.volume_db = lerpf(-2.0, -12.0, clampf(dist / 250.0, 0.0, 1.0))
		thunder.pitch_scale = rng.randf_range(0.85, 1.1)
		add_child(thunder)
		thunder.finished.connect(thunder.queue_free)
		# Bound to the player, so a weather freed before the thunder arrives takes it along.
		thunder.create_tween().tween_callback(thunder.play).set_delay(dist / _SOUND_SPEED)


## A jagged line from `from` to `to`: each point wanders off the one before, which is what makes
## it read as lightning and not a wobbly line. Drawn once per stroke.
func _bolt(from: Vector3, to: Vector3, width_scale: float, rng: RandomNumberGenerator) -> void:
	var points := PackedVector3Array()
	var walk := Vector3.ZERO
	var jitter := from.distance_to(to) / _BOLT_SEGMENTS * 0.6
	for i in _BOLT_SEGMENTS + 1:
		var t := float(i) / _BOLT_SEGMENTS
		points.append(from.lerp(to, t) + (walk if i < _BOLT_SEGMENTS else Vector3.ZERO))
		walk += Vector3(rng.randf_range(-jitter, jitter), 0.0, rng.randf_range(-jitter, jitter))
		walk *= 0.85
	for stroke in _STROKES:
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
