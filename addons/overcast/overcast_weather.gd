class_name OvercastWeather
extends Node3D
## Rain and lightning: drops around the camera, haze and far rain where rain is falling, wet ground,
## rain sound that muffles under a roof, and a storm that closes the sky over. Set `rain`, give it a
## `sky`, and it does the rest.
##
## Roofs are a rain floor (OvercastRainFloor): without one, rain falls everywhere.
##
## Networked games: let one peer time the strikes (times_strikes), send the seed `struck` hands
## you, and call strike(seed) with it on the others. Everything about a strike comes from its
## seed, so every peer sees the same bolt.

## Lightning, every frame of a strike: `k` is its light, 0 to 1, ending on 0. Add it to the light
## the sky puts on your scene (FLASH * k) to light the open ground and not a torch-lit room.
signal flash_changed(k: float)
## A strike timed here (times_strikes); strike(seed) has already been called.
signal struck(strike_seed: int)

const SkyScript = preload("res://addons/overcast/overcast_sky.gd")

## Lightning's light at the peak of a strike, as linear light added to the sky's.
const FLASH := Vector3(2.0, 2.1, 2.6)
## What it lights the sky itself with, brightest toward the bolt. A day sky is already bright, and
## the full flash would white it out and hide the bolt, so it takes SKY_FLASH_DAY of it, rising to
## all of it at full `night`.
const SKY_FLASH := Color(1.0, 1.05, 1.3)
const SKY_FLASH_DAY := 0.3
## The light of a strike over time: a stroke, a fainter return stroke, each dying away fast.
const STROKES := [[0.0, 1.0], [0.11, 0.75]]
const STROKE_DECAY := 0.07
const FLASH_LENGTH := 0.6
## Seconds between strikes at the lightest rain and at a downpour.
const STRIKE_GAP_LIGHT := Vector2(25.0, 45.0)
const STRIKE_GAP_HEAVY := Vector2(4.0, 10.0)
## How overcast the sky goes at the lightest rain (it reaches 1 at a downpour), and how fast it
## closes over or clears, per second.
const STORM_LIGHT := 0.55
const STORM_RATE := 0.2
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
## Rain haze: density per metre of rain-filled air at a full storm, scaled by storm² so light rain
## barely hazes; 0.04 loses ~70% of the view in 30 m of downpour. Its colour is the sky's at the
## horizon, so distance fades into the sky behind it, but never darker than HAZE_FLOOR of
## HAZE_COLOR in sky_light: a night sky is near black, and the scene's moonlight usually is not.
const HAZE_DENSITY := 0.04
const HAZE_COLOR := Color(0.4, 0.43, 0.48)
const HAZE_FLOOR := 0.25
const HAZE_FLASH := 0.35
## Gusts: how far the haze density swings either way, and how fast the curtains drift (m/s).
const GUST_AMOUNT := 0.6
const GUST_DRIFT := Vector3(2.5, -1.0, 0.9)
const GUST_CELL := 80.0  # metres to the noise texture's width, as the shader's
## Drops fill a box this size (m) around the camera: this many at the lightest rain and at a
## downpour. DROP_LIGHT is how bright they read by day; lightning adds DROP_FLASH of its light and
## DROP_FLASH_OPACITY times their opacity.
const DROP_BOX := Vector3(36.0, 24.0, 36.0)
const DROPS_LIGHT := 3000.0
const DROPS_HEAVY := 40000.0
const DROP_LIGHT := 0.85
const DROP_FLASH := 1.5
const DROP_FLASH_OPACITY := 2.5
const DROP_COLOR := Color(0.75, 0.8, 0.9)
## Opacity of the far rain's streaks at a downpour.
const FAR_OPACITY := 0.6
## Wet ground (shaders/wet.gdshaderinc): per second, how fast it soaks at a downpour (slower in
## light rain) and dries once it stops, and the same for puddles, which only a downpour fills.
const WET_RISE := 1.0 / 20.0
const WET_DRY := 1.0 / 120.0
const PUDDLE_RISE := 1.0 / 90.0
const PUDDLE_DRY := 1.0 / 240.0
## Bolts: segments, height over the top of `area` (m), and the speed thunder travels at.
const BOLT_SEGMENTS := 16
const BOLT_HEIGHT := Vector2(110.0, 170.0)
const SOUND_SPEED := 340.0

## How hard it is raining: 0 dry, from a drizzle just above 0 to a downpour at 1. Past 1 only the
## number of drops keeps rising.
@export_range(0.0, 4.0, 0.01, "or_greater") var rain := 0.0:
	set(value):
		rain = maxf(value, 0.0)
		if is_node_ready():
			_refresh()
@export var lightning := true
## Whether this peer decides when lightning strikes. Off on all but one peer of a networked game.
@export var times_strikes := true
## Where lightning lands: the strike falls within this box, over its top.
@export var area := AABB(Vector3(-100, -20, -100), Vector3(200, 60, 200))
## A sun to dim under the storm and light with the flash. Optional.
@export var sun: DirectionalLight3D
## Who hears the rain and is lit by the flash's direction: the current camera when unset.
@export var listener: Node3D
## Where the listener's ears are, above its origin.
@export var listener_height := 0.0
## Overcast's own rain and thunder (sounds/, CC0) when unset.
@export var rain_stream: AudioStream
@export var thunder_stream: AudioStream
@export var rain_bus := &"Master"
@export var thunder_bus := &"Master"

## The sky the storm closes over and the lightning lights: an OvercastSky, or anything with a
## `storm` property, set_storm(float), set_flash(Color, Vector3) and horizon_color() -> Color.
var sky: Object
## The light the sky puts on the scene, as a multiplier: white by day, dimmer at night. Lights the
## drops and the haze.
var sky_light := Color.WHITE
## 0 day to 1 night: how much of the full flash the sky takes (SKY_FLASH_DAY).
var night := 0.0
## Set while the camera is underwater: no rain is drawn, the sound carries on.
var underwater := false
## A low-pass on the rain's bus, closed down as the rain goes out of reach. Optional.
var rain_filter: AudioEffectLowPassFilter
## Draws a bolt instead of the built-in one: (points: PackedVector3Array, width: float,
## brightness: float, fade: float) -> void. Called for each stroke.
var bolt_drawer: Callable

var storm := 0.0
var _flash_t := -1.0
var _flash_k := 0.0
var _flash_dir := Vector3.UP
var _next_strike := 0.0
var _shown := 0.0
var _drops: MultiMeshInstance3D
var _drop_material: ShaderMaterial
var _haze: MeshInstance3D
var _haze_material: ShaderMaterial
var _rain_audio: AudioStreamPlayer
var _linear_output := true
var _floor: Image
var _floor_tex: ImageTexture
var _floor_origin := Vector3.ZERO
var _floor_size := Vector2.ONE
var _floor_top := 1e6
var _rain_db := 0.0
var _exposure := 1.0
var _exposure_target := 1.0
var _sample_in := 0.0
var _gust_offset := Vector3.ZERO
var _wet_mats: Array[ShaderMaterial] = []
var _wetness := 0.0
var _puddles := 0.0
var _wet_pushed := Vector4(-1, -1, -1, -1)  # wetness, puddles, sky luma, flash, as last pushed
var _sun_energy := -1.0


func _ready() -> void:
	_linear_output = SkyScript.renderer_is_linear()
	# The shader places every drop itself; the instances carry no transforms.
	_drop_material = ShaderMaterial.new()
	_drop_material.shader = preload("res://addons/overcast/shaders/rain.gdshader")
	_drop_material.set_shader_parameter("box", DROP_BOX)
	_drop_material.render_priority = Material.RENDER_PRIORITY_MAX
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _drop_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	_drops = MultiMeshInstance3D.new()
	_drops.name = "RainDrops"
	_drops.multimesh = multimesh
	_drops.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drops.visible = false
	add_child(_drops)

	if rain_stream == null:
		rain_stream = _sound("rain")
	if thunder_stream == null:
		thunder_stream = _sound("thunder")
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.name = "RainAudio"
	_rain_audio.bus = rain_bus
	_rain_audio.stream = rain_stream
	_rain_audio.finished.connect(_on_rain_finished)
	add_child(_rain_audio)
	if sun:
		_sun_energy = sun.light_energy
	if _floor_tex:
		_hand_floor(_drop_material)
	_refresh()


## One of sounds/.
static func _sound(sound_name: String) -> AudioStream:
	return load("res://addons/overcast/sounds/%s.ogg" % sound_name) as AudioStream


## Where rain stops (OvercastRainFloor.bake). A scene loaded into rain already falling starts soaked.
func set_rain_floor(rain_floor: Dictionary) -> void:
	_floor = rain_floor["image"]
	_floor_origin = rain_floor["origin"]
	_floor_size = rain_floor["size"]
	_floor_top = rain_floor.get("top", 1e6)
	_floor_tex = ImageTexture.create_from_image(_floor)
	if _drop_material:
		_hand_floor(_drop_material)
	if _haze_material:
		_hand_floor(_haze_material)
	for mat in _wet_mats:
		_hand_floor(mat)
	if _shown > 0.0:
		_wetness = 1.0
		_puddles = heaviness(_shown)


func _hand_floor(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("has_floor", _floor_tex != null)
	mat.set_shader_parameter("rain_floor", _floor_tex)
	mat.set_shader_parameter("rain_floor_origin", _floor_origin)
	mat.set_shader_parameter("rain_floor_size", _floor_size)


## Every material under `root` whose shader takes rain (includes shaders/wet.gdshaderinc). Each
## pools by `puddle_scale(mesh_instance)` (0 drains, 1 pools freely) when given, else 1.
func add_wet_materials(root: Node, puddle_scale := Callable()) -> void:
	var seen := {}
	for mat in _wet_mats:
		seen[mat] = true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var pools: float = puddle_scale.call(mi) if puddle_scale.is_valid() else 1.0
		for i in mi.mesh.get_surface_count():
			for mat in [mi.mesh.surface_get_material(i), mi.get_surface_override_material(i)]:
				if mat is ShaderMaterial and not seen.has(mat) and takes_rain(mat.shader):
					seen[mat] = true
					_hand_floor(mat)
					mat.set_shader_parameter("puddle_scale", pools)
					_wet_mats.append(mat)
	_wet_pushed = Vector4(-1, -1, -1, -1)


static var _rain_shaders := {}


## Whether `shader` declares wet.gdshaderinc's uniforms.
static func takes_rain(shader: Shader) -> bool:
	if shader == null:
		return false
	if not _rain_shaders.has(shader):
		_rain_shaders[shader] = shader.get_shader_uniform_list().any(
			func(u: Dictionary) -> bool: return u["name"] == "wetness")
	return _rain_shaders[shader]


## 0 at the lightest rain to 1 at a downpour, and 0 when dry: what looks and sounds heavier
## stops at a downpour.
static func heaviness(amount: float) -> float:
	return clampf(amount, 0.0, 1.0) if amount > 0.0 else 0.0


## Seconds to the next strike after one, at rain `amount`.
static func strike_gap(amount: float) -> float:
	var t := heaviness(amount)
	return randf_range(lerpf(STRIKE_GAP_LIGHT.x, STRIKE_GAP_HEAVY.x, t),
		lerpf(STRIKE_GAP_LIGHT.y, STRIKE_GAP_HEAVY.y, t))


func _refresh() -> void:
	# The countdown restarts only when rain starts (rain that wanders would never let it run out);
	# heavier rain only ever pulls the next strike in.
	if rain > 0.0 and _shown <= 0.0:
		_next_strike = strike_gap(rain) * 0.5
	elif rain > _shown:
		_next_strike = minf(_next_strike, lerpf(STRIKE_GAP_LIGHT.y, STRIKE_GAP_HEAVY.y, heaviness(rain)))
	_shown = rain
	if rain <= 0.0:
		if _haze_material:
			_haze_material.set_shader_parameter("streak_opacity", 0.0)
		if _rain_audio.playing:
			_rain_audio.stop()
		return
	if _haze == null and DisplayServer.get_name() != "headless":
		_build_haze()

	var heavy := heaviness(rain)
	var count := int(lerpf(DROPS_LIGHT, DROPS_HEAVY, rain))
	var multimesh := _drops.multimesh
	if multimesh.instance_count < count:
		multimesh.instance_count = maxi(count, int(DROPS_HEAVY))
	multimesh.visible_instance_count = count
	# Rain falls at its terminal speed, a few m/s for drizzle and ~9 for a downpour's big drops.
	var fall_speed := lerpf(6.0, 9.5, heavy)
	var streak_length := lerpf(0.3, 0.55, heavy)
	var streak_width := lerpf(0.004, 0.007, heavy)
	_drop_material.set_shader_parameter("velocity", Vector3(0.0, -fall_speed, 0.0))
	_drop_material.set_shader_parameter("streak_length", streak_length)
	_drop_material.set_shader_parameter("width", streak_width)
	_drop_material.set_shader_parameter("opacity", lerpf(0.3, 0.45, heavy))
	if _haze_material:
		# The far rain thins out with the rain, and past a downpour fills in as the box does.
		_haze_material.set_shader_parameter("presence", clampf(count / DROPS_HEAVY, 0.15, 1.0))
		_haze_material.set_shader_parameter("streak_opacity", FAR_OPACITY * maxf(count / DROPS_HEAVY, 1.0))
		_haze_material.set_shader_parameter("fall_speed", fall_speed)
		_haze_material.set_shader_parameter("streak_length", streak_length)
		_haze_material.set_shader_parameter("streak_width", streak_width)

	# -20 dB for light rain to -5 dB for a downpour, and by how much of it is in reach.
	_rain_db = lerpf(-20.0, -5.0, heavy)
	_apply_rain_volume()
	if not _rain_audio.playing and _rain_audio.stream:
		_rain_audio.play()


func _build_haze() -> void:
	_haze_material = ShaderMaterial.new()
	_haze_material.shader = preload("res://addons/overcast/shaders/rain_haze.gdshader")
	_haze_material.render_priority = Material.RENDER_PRIORITY_MAX - 1  # over all it hazes, under the drops
	# OpenGL's NDC z is -1..1, Vulkan/Metal's 0..1.
	var gl := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_haze_material.set_shader_parameter("depth_remap", Vector2(2.0, -1.0) if gl else Vector2(1.0, 0.0))
	_haze_material.set_shader_parameter("linear_output", _linear_output)
	_haze_material.set_shader_parameter("rain_top", _floor_top)
	_hand_floor(_haze_material)
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
	if _shown > 0.0:
		_rain_audio.play()


func _ears() -> Vector3:
	var node := listener if listener else get_viewport().get_camera_3d() as Node3D
	return node.global_position + Vector3.UP * listener_height if node else Vector3.ZERO


## How much of the rain around `ears` reaches them, 0 under a roof with no open sky in reach to 1
## in the open. Each sample point counts where rain lands below the ears there; the near ring
## counts most. Walls between are not seen: rain past one reads as rain through it.
func rain_exposure(ears: Vector3) -> float:
	if _floor == null:
		return 1.0
	var hit := 0.0
	var total := 0.0
	for i in RAIN_RINGS.size() + 1:
		var r: float = 0.0 if i == 0 else RAIN_RINGS[i - 1]
		var weight := 1.0 / (1.0 + r * 0.25)
		for k in (1 if i == 0 else RAIN_RING_POINTS):
			var a := TAU * k / RAIN_RING_POINTS
			total += weight
			if floor_at(ears + Vector3(cos(a), 0.0, sin(a)) * r) < ears.y:
				hit += weight
	return hit / total


## Where rain stops at world XZ `q`: INF off the floor, where no rain falls; -INF with no floor.
func floor_at(q: Vector3) -> float:
	if _floor == null:
		return -INF
	var u := (q.x - _floor_origin.x) / _floor_size.x
	var v := (q.z - _floor_origin.z) / _floor_size.y
	if u < 0.0 or v < 0.0 or u >= 1.0 or v >= 1.0:
		return INF
	return _floor.get_pixel(int(u * _floor.get_width()), int(v * _floor.get_height())).r


func _update_rain_sound(delta: float) -> void:
	_sample_in -= delta
	if _sample_in <= 0.0:
		_sample_in = RAIN_SAMPLE_EVERY
		_exposure_target = rain_exposure(_ears())
	if _exposure != _exposure_target:
		_exposure = move_toward(_exposure, _exposure_target, RAIN_EASE * delta)
		_apply_rain_volume()


func _apply_rain_volume() -> void:
	_rain_audio.volume_db = _rain_db + linear_to_db(lerpf(RAIN_INDOOR_GAIN, 1.0, _exposure))
	if rain_filter:
		rain_filter.cutoff_hz = RAIN_INDOOR_CUTOFF * pow(RAIN_OPEN_CUTOFF / RAIN_INDOOR_CUTOFF, _exposure)


## What the haze fades to before lightning: the sky at the horizon, or lit haze where there is none.
func _haze_base() -> Color:
	var horizon: Color = sky.horizon_color() if sky else Color.BLACK
	var lit := HAZE_COLOR * sky_light
	var least := lit * HAZE_FLOOR
	return lit if horizon == Color.BLACK else \
		Color(maxf(horizon.r, least.r), maxf(horizon.g, least.g), maxf(horizon.b, least.b))


func _update_haze(delta: float, haze_color: Color, drop_light: Color) -> void:
	var density := HAZE_DENSITY * storm * storm
	_haze.visible = (density > 0.0005 or _shown > 0.0) and not underwater
	if not _haze.visible:
		return
	# Kept in [0, 1) rather than driven off TIME, which loses precision as it grows.
	_gust_offset = (_gust_offset + GUST_DRIFT * delta / GUST_CELL).posmod(1.0)
	_haze_material.set_shader_parameter("gust_offset", _gust_offset)
	_haze_material.set_shader_parameter("density", density)
	_drop_material.set_shader_parameter("haze_density", density)
	_haze_material.set_shader_parameter("haze_color", Vector3(haze_color.r, haze_color.g, haze_color.b))
	var streak := DROP_COLOR * drop_light
	_haze_material.set_shader_parameter("streak_color", Vector3(streak.r, streak.g, streak.b))
	_haze_material.set_shader_parameter("flash", _flash_k * DROP_FLASH_OPACITY)


## Soaks and dries the wet materials, and hands them the sky they reflect, lightning included.
## Pushed only when the state moves by a step the screen can show.
func _update_wet(delta: float, reflected: Color) -> void:
	if _wet_mats.is_empty():
		return
	var wet_target := 1.0 if _shown > 0.0 else 0.0
	var puddle_target := heaviness(_shown)
	_wetness = move_toward(_wetness, wet_target,
		(WET_RISE * lerpf(0.35, 1.0, puddle_target) if wet_target > _wetness else WET_DRY) * delta)
	_puddles = move_toward(_puddles, puddle_target,
		(PUDDLE_RISE if puddle_target > _puddles else PUDDLE_DRY) * delta)
	var state := Vector4(_wetness, _puddles, reflected.get_luminance(), _flash_k).snapped(Vector4.ONE / 255.0)
	if state == _wet_pushed:
		return
	_wet_pushed = state
	var srgb := reflected.linear_to_srgb()
	for mat in _wet_mats:
		mat.set_shader_parameter("wetness", _wetness)
		mat.set_shader_parameter("puddles", _puddles)
		mat.set_shader_parameter("rain_sky", Vector3(srgb.r, srgb.g, srgb.b))


## Drops are only seen by the light on them: dim under a storm sky, dimmer at night, and lit up
## all at once by lightning. Their colour goes to the shader in its output space.
func _update_drops(light: Color) -> void:
	if not _drops.visible:
		return
	var color := DROP_COLOR * light
	if not _linear_output:
		color = color.linear_to_srgb()
	_drop_material.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	_drop_material.set_shader_parameter("flash", _flash_k * DROP_FLASH_OPACITY)


func _process(delta: float) -> void:
	_drops.visible = _shown > 0.0 and not underwater
	if _rain_audio.playing:
		_update_rain_sound(delta)

	var storm_target := 0.0 if _shown <= 0.0 else lerpf(STORM_LIGHT, 1.0, heaviness(_shown))
	storm = move_toward(storm, storm_target, STORM_RATE * delta)
	# Compared every frame rather than pushed on change: a game may swap the sky for a new one,
	# which starts clear.
	if sky and sky.storm != storm:
		sky.set_storm(storm)
	if _shown > 0.0 and lightning and times_strikes:
		_next_strike -= delta
		if _next_strike <= 0.0:
			_next_strike = strike_gap(_shown)
			var strike_seed := randi()
			strike(strike_seed)
			struck.emit(strike_seed)

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
		if sky:
			sky.set_flash(SKY_FLASH * k * lerpf(SKY_FLASH_DAY, 1.0, clampf(night, 0.0, 1.0)), _flash_dir)
	if sun and _sun_energy >= 0.0:
		sun.light_energy = _sun_energy * (1.0 - SkyScript.STORM_SHADOW * storm) + _flash_k * FLASH.x
	var drop_light := sky_light * DROP_LIGHT + SKY_FLASH * _flash_k * DROP_FLASH
	_update_drops(drop_light)
	if _haze:
		var haze_color := _haze_base() + SKY_FLASH * _flash_k * HAZE_FLASH
		_update_haze(delta, haze_color, drop_light)
		_update_wet(delta, haze_color)


## One lightning strike, somewhere over `area`, drawn up into the sky. Everything about it comes
## from the seed, so the bolt, its flash and its thunder agree on every peer that is handed it.
func strike(strike_seed: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = strike_seed
	var centre := area.get_center()
	var radius := maxf(area.size.x, area.size.z) * 0.5
	var angle := rng.randf() * TAU
	var out := Vector3(cos(angle), 0.0, sin(angle))
	var ground := centre + out * radius * rng.randf_range(0.2, 1.1)
	ground.y = area.end.y + 2.0
	var top := Vector3(ground.x, ground.y + rng.randf_range(BOLT_HEIGHT.x, BOLT_HEIGHT.y), ground.z) \
		+ out * rng.randf_range(-25.0, 25.0)

	_bolt(ground, top, 1.0, rng)
	for i in rng.randi_range(1, 2):
		var from := ground.lerp(top, rng.randf_range(0.35, 0.75))
		var side := out.cross(Vector3.UP) * rng.randf_range(-1.0, 1.0)
		var to := from + (side + out * 0.4 + Vector3.DOWN).normalized() * rng.randf_range(15.0, 35.0)
		_bolt(to, from, 0.5, rng)

	var eye := _ears() if (listener or get_viewport().get_camera_3d()) else centre
	_flash_dir = (ground.lerp(top, 0.6) - eye).normalized()
	_flash_t = 0.0

	if thunder_stream:
		var dist := eye.distance_to(ground)
		var thunder := AudioStreamPlayer.new()
		thunder.stream = thunder_stream
		thunder.bus = thunder_bus
		thunder.volume_db = lerpf(-2.0, -12.0, clampf(dist / 250.0, 0.0, 1.0))
		thunder.pitch_scale = rng.randf_range(0.85, 1.1)
		add_child(thunder)
		thunder.finished.connect(thunder.queue_free)
		get_tree().create_timer(dist / SOUND_SPEED).timeout.connect(func() -> void:
			if is_instance_valid(thunder):
				thunder.play())


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
		get_tree().create_timer(stroke[0]).timeout.connect(func() -> void:
			if not is_inside_tree():
				return
			if bolt_drawer.is_valid():
				bolt_drawer.call(points, 2.2 * width_scale, stroke[1], 0.25)
			else:
				_draw_bolt(points, 2.2 * width_scale, stroke[1], 0.25))


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
