@tool
class_name OvercastWeather
extends Node3D
## Rain and lightning: drops around the camera, haze and far rain where rain is falling, wet ground,
## rain sound that muffles under a roof, and a storm that closes the sky over. Set `rain` and it
## does the rest, over the scene's OvercastSky (or `sky`). Rain and lightning show in the editor.
##
## Roofs are a rain floor: press Bake Rain Floor in the inspector, or bake one at runtime
## (bake_rain_floor). Without one, rain falls everywhere.
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
## Rain haze's colour is the sky's at the horizon, so distance fades into the sky behind it, but
## never darker than HAZE_FLOOR of HAZE_COLOR in sky_light: a night sky is near black, and the
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
## Opacity of the far rain's streaks at a downpour.
const FAR_OPACITY := 0.6
## Bolts: segments, height over the top of `area` (m), and the speed thunder travels at.
const BOLT_SEGMENTS := 16
const BOLT_HEIGHT := Vector2(110.0, 170.0)
const SOUND_SPEED := 340.0
## How far a full storm dims `sun` when there is no sky to say (OvercastSky.storm_shadow).
const SUN_STORM_SHADOW := 0.88
## Covers re-stamp the rain floor at most this often (s), and only for a step that shows: half a
## cell sideways or COVER_STEP (m) up or down. The floor is re-uploaded whole each time.
const COVER_EVERY := 0.1
const COVER_STEP := 0.05

## How hard it is raining: 0 dry, from a drizzle just above 0 to a downpour at 1. Past 1 only the
## number of drops keeps rising.
@export_range(0.0, 4.0, 0.01, "or_greater") var rain := 0.0:
	set(value):
		var was := rain
		rain = maxf(value, 0.0)
		if is_node_ready():
			_refresh(was)
## The sky the storm closes over and the lightning lights: the scene's own OvercastSky (its
## WorldEnvironment's) when unset.
@export var sky: OvercastSky
## The weather's extent: the rain floor is baked over this box, and lightning lands within it,
## over its top.
@export var area := AABB(Vector3(-100, -20, -100), Vector3(200, 60, 200))

@export_group("Rain floor")
## Where rain stops, so it stays out from under roofs. Bake it below, or at runtime.
@export var rain_floor: OvercastRainFloor:
	set(value):
		rain_floor = value
		_take_floor()
## Metres per cell the bake traces.
@export_range(0.1, 4.0, 0.05, "or_greater") var rain_floor_cell := 0.5
## Physics layers that catch rain.
@export_flags_3d_physics var rain_floor_mask := 0xFFFFFFFF
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
## The light the sky puts on the scene, as a multiplier: white by day, dimmer at night
## (OvercastSky.scene_light). Lights the drops and the haze.
@export var sky_light := Color.WHITE

@export_group("Look")
## Rain haze: density per metre of rain-filled air at a full storm, scaled by storm² so light rain
## barely hazes; 0.04 loses ~70% of the view in 30 m of downpour.
@export_range(0.0, 0.2, 0.001) var haze_density := 0.04
## Drops around the camera at the lightest rain and at a downpour.
@export_range(0, 100000, 100) var drops_light := 3000
@export_range(0, 100000, 100) var drops_heavy := 40000
## Wet ground (shaders/wet.gdshaderinc): seconds to soak at a downpour (longer in light rain) and
## to dry once it stops, and the same for puddles, which only a downpour fills.
@export_range(0.1, 600.0, 0.1, "or_greater", "suffix:s") var soak_time := 20.0
@export_range(0.1, 600.0, 0.1, "or_greater", "suffix:s") var dry_time := 120.0
@export_range(0.1, 600.0, 0.1, "or_greater", "suffix:s") var puddle_time := 90.0
@export_range(0.1, 600.0, 0.1, "or_greater", "suffix:s") var puddle_dry_time := 240.0

@export_group("Sound")
## Who hears the rain and is lit by the flash's direction: the current camera when unset.
@export var listener: Node3D
## Where the listener's ears are, above its origin.
@export var listener_height := 0.0
## Overcast's own rain and thunder (sounds/, CC0) when unset.
@export var rain_stream: AudioStream
@export var thunder_stream: AudioStream
@export var rain_bus := &"Master"
@export var thunder_bus := &"Master"

## Set while the camera is underwater: no rain is drawn, the sound carries on.
var underwater := false
## A low-pass on the rain's bus, closed down as the rain goes out of reach. Optional.
var rain_filter: AudioEffectLowPassFilter
## Microseconds a tick may spend rasterizing covers that turned (at least one is, whatever the
## budget). Past it the rest keep their old stamp and go first next tick, so a walking golem
## spreads its turning limbs over a few ticks rather than hitching one frame.
var cover_budget_usec := 1000
## Draws a bolt instead of the built-in one: (points: PackedVector3Array, width: float,
## brightness: float, fade: float) -> void. Called for each stroke.
var bolt_drawer: Callable

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
var _sky_storm := NAN
## A dedicated server keeps the weather's timing and draws and plays none of it.
var _presenting := DisplayServer.get_name() != "headless"
## In the editor it draws, for a preview, but makes no sound, times no strikes and leaves the
## scene's own nodes (the sun) as they are saved.
var _editor := Engine.is_editor_hint()
var _flash_t := -1.0
var _flash_k := 0.0
var _flash_dir := Vector3.UP
var _next_strike := 0.0
var _drops: MultiMeshInstance3D
var _drop_material: ShaderMaterial
var _haze: MeshInstance3D
var _haze_material: ShaderMaterial
var _rain_audio: AudioStreamPlayer
var _linear_output := true
## The rain floor: heights row by row, as baked and with the covers stamped on, and the image
## and texture the shaders read. _cell is metres per cell.
var _baked := PackedFloat32Array()
var _heights := PackedFloat32Array()
var _floor_dims := Vector2i.ZERO
var _floor: Image
var _floor_tex: ImageTexture
var _floor_origin := Vector3.ZERO
var _floor_size := Vector2.ONE
var _cell := Vector2.ONE
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
var _sun_energy := -1.0  # the sun's own light while taken; -1 when not
var _sun_color := Color.WHITE
var _sun_basis := Basis()
## Node3D -> Cover.
var _covers := {}
var _cover_in := 0.0


func _ready() -> void:
	if not bolt_drawer.is_valid():
		bolt_drawer = _draw_bolt
	if not _presenting:
		return
	_linear_output = OvercastSky.renderer_is_linear()
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

	if not _editor:
		_rain_audio = AudioStreamPlayer.new()
		_rain_audio.name = "RainAudio"
		_rain_audio.bus = rain_bus
		_rain_audio.stream = rain_stream if rain_stream else _sound("rain")
		_rain_audio.finished.connect(_on_rain_finished)
		add_child(_rain_audio)
	if _floor_tex:
		_hand_floor(_drop_material)
	_refresh(0.0)


func _enter_tree() -> void:
	_take_sun()


func _exit_tree() -> void:
	_let_sun_go()


func _take_sun() -> void:
	if sun and _sun_energy < 0.0 and _presenting and not _editor and is_inside_tree():
		_sun_energy = sun.light_energy
		_sun_color = sun.light_color
		_sun_basis = sun.basis


func _let_sun_go() -> void:
	if _sun_energy >= 0.0 and is_instance_valid(sun):
		sun.light_energy = _sun_energy
		sun.light_color = _sun_color
		sun.basis = _sun_basis
	_sun_energy = -1.0


## One of sounds/.
static func _sound(sound_name: String) -> AudioStream:
	return load("res://addons/overcast/sounds/%s.ogg" % sound_name) as AudioStream


## Bakes the rain floor over `area` from the colliders in the world now (at runtime, after a
## physics frame), and uses it.
func bake_rain_floor() -> void:
	rain_floor = OvercastRainFloor.bake(get_world_3d(), area, rain_floor_cell, rain_floor_mask)


## The inspector's Bake Rain Floor: saved beside the scene as <scene>_rain_floor.res, so the scene
## file keeps a reference rather than the heights.
func _bake_in_editor() -> void:
	var baked := OvercastRainFloor.bake(get_world_3d(), area, rain_floor_cell, rain_floor_mask)
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
	if rain_floor == null or rain_floor.image == null:
		_floor = null
		_floor_tex = null
		_baked = PackedFloat32Array()
		_heights = PackedFloat32Array()
		_floor_dims = Vector2i.ZERO
		_floor_top = 1e6
	else:
		var img := rain_floor.image
		if img.get_format() != Image.FORMAT_RF:
			img = img.duplicate()
			img.convert(Image.FORMAT_RF)
		_floor_dims = img.get_size()
		_baked = img.get_data().to_float32_array()
		_heights = _baked.duplicate()
		_floor = img.duplicate()
		_floor_origin = rain_floor.origin
		_floor_size = rain_floor.size
		_cell = _floor_size / Vector2(_floor_dims)
		_floor_top = rain_floor.top
		_floor_tex = ImageTexture.create_from_image(_floor)
	if _drop_material:
		_hand_floor(_drop_material)
	if _haze_material:
		_hand_floor(_haze_material)
		_haze_material.set_shader_parameter("rain_top", _floor_top)
	for mat in _wet_mats:
		_hand_floor(mat)
	if rain > 0.0 and _floor:
		_soak()
	for node in _covers:  # stamped afresh on this floor
		_covers[node].xform = Transform3D(Basis(), Vector3.INF)
		_covers[node].raster_xform = Transform3D(Basis(), Vector3.INF)
		_covers[node].rect = Rect2i()


## Straight to the weather the current rain is heading for: the storm closed over as far as it
## goes, the ground soaked. For a scene that starts mid-shower, and for screenshots.
func settle() -> void:
	storm = _storm_target()
	_soak()


func _soak() -> void:
	_wetness = 1.0 if rain > 0.0 else 0.0
	_puddles = heaviness(rain)


func _storm_target() -> float:
	return 0.0 if rain <= 0.0 else lerpf(STORM_LIGHT, 1.0, heaviness(rain))


## Something that moves and keeps rain off what is under it: a lift, a train, a drawbridge, a
## wall that can be knocked down. `shape` is what of it rain lands on, in its own frame: an AABB,
## a PackedVector3Array of triangles, or nothing for the meshes under the node (not those under a
## physics body of their own). Each floor cell takes the highest of it over that cell, so a
## rotated, L-shaped or pitched thing keeps rain off exactly what is under it. Re-stamped as it
## moves (COVER_EVERY, COVER_STEP); it covers nothing while hidden, and a freed node is let go of
## by itself.
func add_cover(node: Node3D, shape: Variant = null) -> void:
	remove_cover(node)
	var tris: PackedVector3Array
	if shape is AABB:
		tris = _box_triangles(shape)
	elif shape is PackedVector3Array:
		tris = shape
	else:
		tris = mesh_triangles(node)
	if tris.is_empty():
		return
	var cover := Cover.new()
	cover.triangles = tris
	var bounds := AABB(tris[0], Vector3.ZERO)
	for v in tris:
		bounds = bounds.expand(v)
	for i in 8:
		cover.corners.append(bounds.get_endpoint(i))
	_covers[node] = cover
	_cover_in = 0.0


func has_cover(node: Node3D) -> bool:
	return _covers.has(node)


func remove_cover(node: Node3D) -> void:
	if _covers.has(node):
		var rect: Rect2i = _covers[node].rect
		_covers.erase(node)
		if _floor:
			_restamp([rect])


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


## One cover: its triangles and bounds in its own frame, and what it last stamped.
class Cover:
	var triangles: PackedVector3Array
	var corners := PackedVector3Array()
	var xform := Transform3D(Basis(), Vector3.INF)
	var shown := false
	## Where it stamps now: its raster moved `shift` cells and raised `rise`, clipped to the floor.
	var rect := Rect2i()
	var shift := Vector2i.ZERO
	var rise := 0.0
	## Its last rasterization: per cell of raster_rect, row by row, -INF where it is not over. Kept
	## while it only translates; turning it rasterizes it afresh.
	var raster_rect := Rect2i()
	var raster := PackedFloat32Array()
	var raster_xform := Transform3D(Basis(), Vector3.INF)


## Re-stamps the cells covers have left or moved onto, and uploads the floor if any changed.
func _update_covers(delta := COVER_EVERY) -> void:
	if _floor == null or _covers.is_empty() or not _presenting:
		return
	_cover_in -= delta
	if _cover_in > 0.0:
		return
	_cover_in = COVER_EVERY
	var dirty: Array[Rect2i] = []
	var start := Time.get_ticks_usec()
	var rasterized := 0
	var done: Array[Node3D] = []
	for node in _covers.keys():
		var cover: Cover = _covers[node]
		if not is_instance_valid(node):
			dirty.append(cover.rect)
			_covers.erase(node)
			continue
		var shown: bool = node.is_visible_in_tree()
		var xform: Transform3D = node.global_transform
		if shown == cover.shown and not _moved(cover, xform):
			continue
		var turned := shown and _turned(cover, xform)
		if turned:
			if rasterized > 0 and Time.get_ticks_usec() - start > cover_budget_usec:
				continue  # next tick, and first in line then
			rasterized += 1
		dirty.append(cover.rect)
		cover.xform = xform
		cover.shown = shown
		if shown:
			_place(cover, turned)
		else:
			cover.rect = Rect2i()
		dirty.append(cover.rect)
		done.append(node)
	# To the back of the line: whoever was put off goes first next tick.
	for node in done:
		var cover: Cover = _covers[node]
		_covers.erase(node)
		_covers[node] = cover
	_restamp(dirty)


## Whether any corner of the cover has moved a step that shows since it was stamped: half a cell
## sideways or COVER_STEP up or down.
func _moved(cover: Cover, xform: Transform3D) -> bool:
	if not cover.xform.origin.is_finite():
		return true
	var half := minf(_cell.x, _cell.y) * 0.5
	for c in cover.corners:
		var d := xform * c - cover.xform * c
		if Vector2(d.x, d.z).length() > half or absf(d.y) > COVER_STEP:
			return true
	return false


## Whether placing the cover at `xform` needs a fresh raster rather than its last one moved.
static func _turned(cover: Cover, xform: Transform3D) -> bool:
	return not cover.raster_xform.origin.is_finite() \
		or not xform.basis.is_equal_approx(cover.raster_xform.basis)


## Where the cover stamps at cover.xform: a fresh raster if it `turned`, else its last one shifted.
func _place(cover: Cover, turned: bool) -> void:
	if turned:
		cover.raster_xform = cover.xform
		_rasterize(cover)
	var d := cover.xform.origin - cover.raster_xform.origin
	cover.shift = Vector2i(roundi(d.x / _cell.x), roundi(d.z / _cell.y))
	cover.rect = Rect2i(cover.raster_rect.position + cover.shift, cover.raster_rect.size) \
		.intersection(Rect2i(Vector2i.ZERO, _floor_dims))
	cover.rise = d.y


## The cover's triangles where it is now, onto the floor's cells: each cell takes the highest of
## them over it. A flat triangle is highest over a cell at one of the cell's corners or along one
## of its own edges, so those are what is sampled: the corners each row of the triangle spans, and
## every edge at half-cell steps, which also lands a beam narrower than a cell.
func _rasterize(cover: Cover) -> void:
	var xform := cover.raster_xform
	# Triangles in cell units: x, z across the floor, y the height.
	var tris := PackedVector3Array()
	tris.resize(cover.triangles.size())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in cover.triangles.size():
		var w := xform * cover.triangles[i]
		var u := Vector3((w.x - _floor_origin.x) / _cell.x, w.y, (w.z - _floor_origin.z) / _cell.y)
		tris[i] = u
		lo = lo.min(Vector2(u.x, u.z))
		hi = hi.max(Vector2(u.x, u.z))
	# Not clipped to the floor: a cover that drives onto it brings all of itself.
	var rect := Rect2i(Vector2i(floori(lo.x), floori(lo.y)),
		Vector2i(floori(hi.x) - floori(lo.x) + 1, floori(hi.y) - floori(lo.y) + 1))
	cover.raster_rect = rect
	var hs := PackedFloat32Array()
	var rx := rect.position.x
	var rz := rect.position.y
	var rw := rect.size.x
	var rh := rect.size.y
	hs.resize(rw * rh)
	hs.fill(-INF)
	# Heights at the cell corners, folded into the cells they bound at the end. Every corner a
	# triangle reaches is inside the raster; the extra row and column are padding for the fold.
	var cw := rw + 1
	var corners := PackedFloat32Array()
	corners.resize(cw * (rh + 1))
	corners.fill(-INF)
	for t in range(0, tris.size() - 2, 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var det := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
		# A wall's edges are its neighbours' too: the top face of a closed brush lands its top edge.
		var steep := absf(det) < 0.05 * (b - a).cross(c - a).length()
		for e in (0 if steep else 3):
			var p := tris[t + e]
			var q := tris[t + (e + 1) % 3]
			var steps := maxi(ceili(Vector2(q.x - p.x, q.z - p.z).length() * 2.0), 1)
			for k in steps + 1:
				var f := float(k) / steps
				var xi := floori(lerpf(p.x, q.x, f)) - rx
				var zi := floori(lerpf(p.z, q.z, f)) - rz
				if xi >= 0 and zi >= 0 and xi < rw and zi < rh:
					var y := lerpf(p.y, q.y, f)
					if y > hs[zi * rw + xi]:
						hs[zi * rw + xi] = y
		if absf(det) < 1e-6:
			continue  # edge-on from above: its edges have said all it has to say
		# The triangle's plane, y = px * x + pz * z + p0.
		var px := ((b.y - a.y) * (c.z - a.z) - (c.y - a.y) * (b.z - a.z)) / det
		var pz := ((c.y - a.y) * (b.x - a.x) - (b.y - a.y) * (c.x - a.x)) / det
		var p0 := a.y - px * a.x - pz * a.z
		for j in range(ceili(minf(a.z, minf(b.z, c.z))), floori(maxf(a.z, maxf(b.z, c.z))) + 1):
			# Where the row z = j crosses the triangle's edges.
			var x0 := INF
			var x1 := -INF
			for e in 3:
				var p := tris[t + e]
				var q := tris[t + (e + 1) % 3]
				if (p.z - j) * (q.z - j) <= 0.0 and p.z != q.z:
					var x := p.x + (q.x - p.x) * (j - p.z) / (q.z - p.z)
					x0 = minf(x0, x)
					x1 = maxf(x1, x)
			var zj := j - rz
			for i in range(maxi(ceili(x0 - 1e-4), rx), mini(floori(x1 + 1e-4), rx + rw) + 1):
				var y := px * i + pz * j + p0
				var k := zj * cw + i - rx
				if y > corners[k]:
					corners[k] = y
	# A corner is shared by the four cells around it.
	for zi in rh:
		for xi in rw:
			var k := zi * cw + xi
			var y := maxf(maxf(corners[k], corners[k + 1]), maxf(corners[k + cw], corners[k + cw + 1]))
			if y > hs[zi * rw + xi]:
				hs[zi * rw + xi] = y
	cover.raster = hs


## The dirty rects back to the baked floor, then every cover over them stamped on again, and the
## floor uploaded once. Rects are merged only where they overlap: two movers at opposite ends of
## the map restamp two patches, not everything between them.
func _restamp(rects: Array[Rect2i]) -> void:
	var merged: Array[Rect2i] = []
	for r in rects:
		if not r.has_area():
			continue
		var i := 0
		while i < merged.size():
			if merged[i].intersects(r):
				r = r.merge(merged[i])
				merged.remove_at(i)
				i = 0
			else:
				i += 1
		merged.append(r)
	if merged.is_empty():
		return
	var w := _floor_dims.x
	for region in merged:
		for z in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				_heights[z * w + x] = _baked[z * w + x]
		for node in _covers:
			var cover: Cover = _covers[node]
			var rect := cover.rect.intersection(region)
			if not rect.has_area():
				continue
			# The raster cell under floor cell (x, z) is (x, z) - shift.
			var o := cover.raster_rect.position + cover.shift
			var rw := cover.raster_rect.size.x
			for z in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var top := cover.raster[(z - o.y) * rw + x - o.x] + cover.rise
					if top > _heights[z * w + x]:
						_heights[z * w + x] = top
	_floor.set_data(w, _floor_dims.y, false, Image.FORMAT_RF, _heights.to_byte_array())
	_floor_tex.update(_floor)


func _hand_floor(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("has_floor", _floor_tex != null)
	mat.set_shader_parameter("rain_floor", _floor_tex)
	mat.set_shader_parameter("rain_floor_origin", _floor_origin)
	mat.set_shader_parameter("rain_floor_size", _floor_size)


## Every material under `root` whose shader takes rain (includes shaders/wet.gdshaderinc). Each
## pools by `puddle_scale(mesh_instance)` (0 drains, 1 pools freely) when given, else 1.
func add_wet_materials(root: Node, puddle_scale := Callable()) -> void:
	if not _presenting:
		return
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
	var rid := shader.get_rid()  # by RID, so the cache holds no shader alive
	if not _rain_shaders.has(rid):
		_rain_shaders[rid] = shader.get_shader_uniform_list().any(
			func(u: Dictionary) -> bool: return u["name"] == "wetness")
	return _rain_shaders[rid]


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
	if not _presenting:
		return
	if rain <= 0.0:
		if _haze_material:
			_haze_material.set_shader_parameter("streak_opacity", 0.0)
		if _rain_audio and _rain_audio.playing:
			_rain_audio.stop()
		return
	if _haze == null:
		_build_haze()

	var heavy := heaviness(rain)
	var count := int(lerpf(drops_light, drops_heavy, rain))
	var multimesh := _drops.multimesh
	if multimesh.instance_count < count:
		multimesh.instance_count = maxi(count, drops_heavy)
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
		var full := float(count) / maxi(drops_heavy, 1)
		_haze_material.set_shader_parameter("presence", clampf(full, 0.15, 1.0))
		_haze_material.set_shader_parameter("streak_opacity", FAR_OPACITY * maxf(full, 1.0))
		_haze_material.set_shader_parameter("fall_speed", fall_speed)
		_haze_material.set_shader_parameter("streak_length", streak_length)
		_haze_material.set_shader_parameter("streak_width", streak_width)

	# -20 dB for light rain to -5 dB for a downpour, and by how much of it is in reach.
	_rain_db = lerpf(-20.0, -5.0, heavy)
	if _rain_audio:
		_apply_rain_volume()
		if not _rain_audio.playing and _rain_audio.stream:
			_rain_audio.play()


func _build_haze() -> void:
	_haze_material = ShaderMaterial.new()
	_haze_material.shader = preload("res://addons/overcast/shaders/rain_haze.gdshader")
	_haze_material.render_priority = Material.RENDER_PRIORITY_MAX - 1  # over all it hazes, under the drops
	# OpenGL's NDC z is -1..1, Vulkan/Metal's 0..1.
	_haze_material.set_shader_parameter("depth_remap", Vector2(1.0, 0.0) if _linear_output else Vector2(2.0, -1.0))
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
	if rain > 0.0:
		_rain_audio.play()


func _ears(fallback := Vector3.ZERO) -> Vector3:
	var node := listener if listener else get_viewport().get_camera_3d() as Node3D
	return node.global_position + Vector3.UP * listener_height if node else fallback


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
	var x := floori((q.x - _floor_origin.x) / _cell.x)
	var z := floori((q.z - _floor_origin.z) / _cell.y)
	if x < 0 or z < 0 or x >= _floor_dims.x or z >= _floor_dims.y:
		return INF
	return _heights[z * _floor_dims.x + x]


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
func _haze_base(drawn: OvercastSky) -> Color:
	var horizon: Color = drawn.horizon_now() if drawn else Color.BLACK
	var lit := HAZE_COLOR * sky_light
	var least := lit * HAZE_FLOOR
	return lit if horizon == Color.BLACK else \
		Color(maxf(horizon.r, least.r), maxf(horizon.g, least.g), maxf(horizon.b, least.b))


func _update_haze(delta: float, haze_color: Color, drop_light: Color) -> void:
	var density := haze_density * storm * storm
	_haze.visible = (density > 0.0005 or rain > 0.0) and not underwater
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
	var wet_target := 1.0 if rain > 0.0 else 0.0
	var puddle_target := heaviness(rain)
	_wetness = move_toward(_wetness, wet_target,
		(lerpf(0.35, 1.0, puddle_target) / soak_time if wet_target > _wetness else 1.0 / dry_time) * delta)
	_puddles = move_toward(_puddles, puddle_target,
		(1.0 / puddle_time if puddle_target > _puddles else 1.0 / puddle_dry_time) * delta)
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
	if rain > 0.0 and lightning and times_strikes and not _editor:
		_next_strike -= delta
		if _next_strike <= 0.0:
			_next_strike = strike_gap(rain)
			var strike_seed := randi()
			strike(strike_seed)
			struck.emit(strike_seed)
	if not _presenting:
		return
	var drawn := current_sky()
	if drawn and (drawn.get_instance_id() != _sky_told or storm != _sky_storm):
		drawn.storm = storm
		_sky_told = drawn.get_instance_id()
		_sky_storm = storm
	_update_covers(delta)
	_drops.visible = rain > 0.0 and not underwater
	if _rain_audio and _rain_audio.playing:
		_update_rain_sound(delta)

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
		sun.light_color = _sun_color * drawn.scene_light() * smoothstep(-0.05, 0.05, toward.y)
	if sun and _sun_energy >= 0.0:
		var shade := drawn.storm_shadow if drawn else SUN_STORM_SHADOW
		sun.light_energy = _sun_energy * (1.0 - shade * storm) + _flash_k * FLASH.x
	var drop_light := sky_light * DROP_LIGHT + SKY_FLASH * _flash_k * DROP_FLASH
	_update_drops(drop_light)
	if _haze:
		var haze_color := _haze_base(drawn) + SKY_FLASH * _flash_k * HAZE_FLASH
		_update_haze(delta, haze_color, drop_light)
		_update_wet(delta, haze_color)


## One lightning strike, somewhere over `area`, drawn up into the sky. Everything about it comes
## from the seed, so the bolt, its flash and its thunder agree on every peer that is handed it.
func strike(strike_seed: int) -> void:
	if not _presenting:
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
			bolt_drawer.call(points, 2.2 * width_scale, stroke[1], 0.25))


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
