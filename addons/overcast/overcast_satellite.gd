class_name OvercastSatellite
extends Node
## Where the clouds really are round a placed sky (OvercastSky.placed): geostationary infrared
## from NASA GIBS (gibs.earthdata.nasa.gov), every ten minutes, laid as the sky's cover map. How
## much cloud there is stays the sky's to say (an OvercastForecast's, say); this says where it
## lies: the coldest tops are cloud first. 2 km pixels: overhead that is one or two, so mostly it
## places the banks and gaps toward the horizon. GOES-East, GOES-West and Himawari see the
## Americas, the Pacific and East Asia; Europe, Africa and India are out of their sight.
##
## Off until `enabled`: turning it on sends the sky's latitude and longitude to NASA, so ask the
## player first. Imagery goes back a few months.

## A new frame was laid.
signal updated
## A fetch failed, or there is no satellite over the place; it tries again after _RETRY seconds.
signal failed(message: String)

const _WMS := "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi"
const _COLORMAP := "https://gibs.earthdata.nasa.gov/colormaps/v1.3/Clean_Longwave_Infrared_Window_Band.xml"
## Layer, and the longitude the satellite stands over.
const SATELLITES := [["GOES-East_ABI_Band13_Clean_Infrared", -75.2],
	["GOES-West_ABI_Band13_Clean_Infrared", -137.2], ["Himawari_AHI_Band13_Clean_Infrared", 140.7]]
## Degrees of longitude off a satellite past which it sees too slant to use.
const _REACH := 70.0
## Seconds between frames, how long one takes to be published, and how many to step back past a
## missing one.
const _FRAME := 600
const _LATENCY := 1800
const _STEPS_BACK := 6
## Real metres across the map, and its pixels: a little finer than the imagery's 2 km.
const SPAN := 200000.0
const _SIZE := 160
const _RETRY := 60.0
const _METRES_PER_DEGREE := 111320.0
## °C between a frame's warm and cold tenths over which its map goes from no say to full say.
const _SPREAD := Vector2(3.0, 20.0)

## Fetch and lay the satellite's clouds. Sends the sky's place to NASA.
@export var enabled := false:
	set(on):
		enabled = on
		if not on:
			_clear()
## The weather whose sky to lay it on: this node's parent when unset.
@export var weather: OvercastWeather

## Unix seconds (UTC) of the frame laid; 0 for none.
var frame := 0

var _http: HTTPRequest
var _colormap := []
var _colors := {}
var _busy := false
var _place := Vector2.INF
var _want := 0
var _retry_at := -INF
var _laid_on: OvercastSky


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)


func _exit_tree() -> void:
	_clear()


func _process(_delta: float) -> void:
	var w := weather if weather else get_parent() as OvercastWeather
	var sky := w.current_sky() if w else null
	if not enabled or sky == null or not sky.placed or _busy:
		return
	var now := Time.get_unix_time_from_system()
	var want := frame_time(sky.unix_time, now)
	var place := Vector2(sky.latitude, sky.longitude)
	if (want != _want or place != _place or sky != _laid_on) and now >= _retry_at:
		_fetch(sky, place, want)


## The frame to show at `t`: the last at or before it, and none newer than is published by `now`.
static func frame_time(t: float, now: float) -> int:
	return int(floorf(minf(t, now - _LATENCY) / _FRAME)) * _FRAME


## The layer of the satellite that sees `longitude` best, or "" for none.
static func layer_for(longitude: float) -> String:
	var best := ""
	var off := _REACH
	for s in SATELLITES:
		var d := absf(wrapf(longitude - s[1], -180.0, 180.0))
		if d < off:
			off = d
			best = s[0]
	return best


func _fetch(sky: OvercastSky, place: Vector2, want: int) -> void:
	_busy = true
	_want = want
	_place = place
	var layer := layer_for(place.y)
	var error := ""
	if layer.is_empty():
		error = "no geostationary satellite over longitude %.1f" % place.y
	elif _colormap.is_empty():
		var got := await _download(_COLORMAP)
		_colormap = parse_colormap(got.get_string_from_utf8()) if not got.is_empty() else {}
		if _colormap.is_empty():
			error = "no colour map"
	var map: Image
	var t := want
	if error.is_empty():
		for i in _STEPS_BACK:
			var got := await _download(_url(layer, place, t))
			if got.is_empty():
				error = "imagery request failed"
				break
			var img := Image.new()
			if img.load_png_from_buffer(got) == OK:
				# Off the main thread: a frame's colours take a good part of a frame to read.
				var out := [null]
				var task := WorkerThreadPool.add_task(func() -> void: out[0] = cover_from(img, _colormap, _colors))
				while not WorkerThreadPool.is_task_completed(task):
					await get_tree().process_frame
				WorkerThreadPool.wait_for_task_completion(task)
				map = out[0]
				if map:
					break
			t -= _FRAME  # a frame missing from the record comes back empty
		if map == null and error.is_empty():
			error = "no frame near %s" % Time.get_datetime_string_from_unix_time(want)
	_busy = false
	if not is_inside_tree() or not enabled:
		return
	if map == null:
		_retry_at = Time.get_unix_time_from_system() + _RETRY
		failed.emit(error)
		return
	frame = t
	if _laid_on and _laid_on != sky:
		_laid_on.set_cover_map(null, SPAN)
	_laid_on = sky
	sky.set_cover_map(ImageTexture.create_from_image(map), SPAN)
	updated.emit()


func _url(layer: String, place: Vector2, t: int) -> String:
	var half_lat := SPAN * 0.5 / _METRES_PER_DEGREE
	var half_lon := half_lat / maxf(cos(deg_to_rad(place.x)), 0.05)
	return "%s?SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0&LAYERS=%s&CRS=EPSG:4326&BBOX=%.4f,%.4f,%.4f,%.4f&WIDTH=%d&HEIGHT=%d&FORMAT=image/png&TIME=%s" % [
		_WMS, layer, place.x - half_lat, place.y - half_lon, place.x + half_lat, place.y + half_lon,
		_SIZE, _SIZE, Time.get_datetime_string_from_unix_time(t) + "Z"]


## The body of a GET, empty if it failed.
func _download(url: String) -> PackedByteArray:
	if _http.request(url, ["User-Agent: overcast-godot"]) != OK:
		return PackedByteArray()
	var res: Array = await _http.request_completed
	return res[3] if res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200 else PackedByteArray()


func _clear() -> void:
	if _laid_on:
		_laid_on.set_cover_map(null, SPAN)
	_laid_on = null
	frame = 0
	_want = 0


## GIBS' colour map: its colours in order of temperature, as [Vector3 rgb, °C] (each colour's
## middle).
static func parse_colormap(xml: String) -> Array:
	var out := []
	var entry := RegEx.create_from_string(
		"<ColorMapEntry rgb=\"(\\d+),(\\d+),(\\d+)\"[^>]*?value=\"[\\[(]([-\\d.]+),([-\\d.]+)[\\])]\"")
	for m in entry.search_all(xml):
		out.append([Vector3(int(m.get_string(1)), int(m.get_string(2)), int(m.get_string(3))),
			(float(m.get_string(4)) + float(m.get_string(5))) * 0.5])
	out.sort_custom(func(a, b) -> bool: return a[1] < b[1])
	return out


## The temperature a frame's colour stands for. The frames are drawn smooth, so most colours lie
## between two of the map's: each is placed on the nearest step from one to the next. Where the
## coldest tops' greys meet the ground's, the warmer reading wins. `cache` keeps what was found.
static func temperature_of(rgb: int, colormap: Array, cache: Dictionary) -> float:
	if cache.has(rgb):
		return cache[rgb]
	var c := Vector3(rgb >> 16, (rgb >> 8) & 255, rgb & 255)
	var best := INF
	var t := NAN
	for i in colormap.size() - 1:
		var p0: Vector3 = colormap[i][0]
		var d: Vector3 = colormap[i + 1][0] - p0
		var u := clampf((c - p0).dot(d) / maxf(d.length_squared(), 1e-6), 0.0, 1.0)
		var miss := (c - (p0 + d * u)).length_squared()
		if miss <= best:
			best = miss
			t = lerpf(colormap[i][1], colormap[i + 1][1], u)
	cache[rgb] = t
	return t


## The cover map from an infrared frame: each pixel by how cold it is among the frame's, white the
## coldest, pressed toward mid grey (no say) as far as the frame's temperatures barely differ.
## Null if the frame holds nothing.
static func cover_from(frame_image: Image, colormap: Array, cache := {}) -> Image:
	frame_image.convert(Image.FORMAT_RGBA8)
	var data := frame_image.get_data()
	var n := frame_image.get_width() * frame_image.get_height()
	var temps := PackedFloat32Array()
	temps.resize(n)
	var known := PackedFloat32Array()
	for i in n:
		var o := i * 4
		if data[o + 3] == 0:
			temps[i] = NAN
			continue
		var c := temperature_of((data[o] << 16) | (data[o + 1] << 8) | data[o + 2], colormap, cache)
		temps[i] = c
		known.append(c)
	if known.size() < n / 4:
		return null
	known.sort()
	var spread := known[int(known.size() * 0.9)] - known[int(known.size() * 0.1)]
	var contrast := smoothstep(_SPREAD.x, _SPREAD.y, spread)
	var cover := PackedByteArray()
	cover.resize(n)
	var count := float(known.size())
	for i in n:
		var c := temps[i]
		if is_nan(c):
			cover[i] = 128
			continue
		# Ties take their middle rank, so a field of one temperature is one grey.
		var rank := (known.bsearch(c, true) + known.bsearch(c, false)) * 0.5 / count
		cover[i] = clampi(int((0.5 + (0.5 - rank) * contrast) * 255.0), 0, 255)
	return Image.create_from_data(frame_image.get_width(), frame_image.get_height(), false,
		Image.FORMAT_L8, cover)
