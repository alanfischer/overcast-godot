class_name OvercastForecast
extends Node
## Real weather for an OvercastWeather, from Open-Meteo (open-meteo.com): the forecast, or further
## back the record, for its sky's place at its sky's moment, as OvercastConditions blended between
## the hours. The sky must be placed (OvercastSky.placed); set its unix_time to the clock for the
## weather now.
##
## Off until `enabled`: turning it on sends the sky's latitude and longitude to Open-Meteo, so ask
## the player first. Open-Meteo is free without a key for non-commercial use only, and its data is
## CC BY 4.0: credit it ("Weather data by Open-Meteo.com").

## New hours came in.
signal updated
## A fetch failed; it tries again after _RETRY seconds.
signal failed(message: String)

const _HOURLY := "temperature_2m,dew_point_2m,precipitation,snowfall,visibility,weather_code,cloud_cover_low," \
	+ "cloud_cover_mid,cloud_cover_high,wind_speed_10m,wind_direction_10m,wind_gusts_10m,cape," \
	+ "wind_speed_850hPa,wind_direction_850hPa"
## Further back than this the forecast service has no hours; the record (archive) takes over.
const _FORECAST_PAST_DAYS := 80
## Seconds before a failed fetch is tried again, and how far a moment moves before the
## conditions are blended again.
const _RETRY := 60.0
const _STEP := 10.0
## An hour's cloud is what stands at that hour, not a share of the hour before: the next hour's
## comes in over the last of this one, from this far through it.
const _CLOUD_TURN := 0.75
const _CLOUD := [&"low_cover", &"low_base", &"low_sheet", &"towering", &"mid_cover", &"mid_base",
	&"mid_sheet", &"high_cover", &"high_base", &"high_sheet"]
## Degrees the place moves before it is fetched again.
const _MOVED := 0.05
## Precipitation (mm an hour) that is a downpour: OvercastWeather.rain 1.
const _DOWNPOUR := 10.0
## Millimetres of water in a centimetre of fresh snow, as Open-Meteo counts it.
const _SNOW_WATER := 10.0 / 7.0
## Visibility in fog, when the record gives none.
const _FOG := 300.0
## Metres the cloud base rises per degree between the air and its dew point.
const _BASE_PER_DEGREE := 125.0

## Fetch and follow the real weather. Sends the sky's place to Open-Meteo.
@export var enabled := false
## The weather to drive: this node's parent when unset.
@export var weather: OvercastWeather
## Open-Meteo's key, for commercial use: fetches then go to its customer servers.
@export var api_key := ""
## Seconds before the hours about the present are fetched again, as the forecast is remade.
@export_range(60.0, 86400.0, 1.0, "or_greater", "suffix:s") var refresh := 1800.0

## The hours fetched: Unix seconds (UTC), and the conditions at each.
var times := PackedFloat64Array()
var hours: Array[OvercastConditions] = []

var _http: HTTPRequest
var _place := Vector2.INF
var _fetched_at := -INF
var _retry_at := -INF
var _shown := Vector2(NAN, NAN)  # the moment and north the weather was last handed


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	_http.request_completed.connect(_on_response)
	add_child(_http)


func _process(_delta: float) -> void:
	var w := _target()
	var sky := w.current_sky() if w else null
	if not enabled or sky == null or not sky.placed:
		return
	var t := sky.unix_time
	var place := Vector2(sky.latitude, sky.longitude)
	var now := Time.get_unix_time_from_system()
	if not _covers(t) or place.distance_to(_place) > _MOVED \
			or (t > now - 2 * 86400.0 and now - _fetched_at > refresh):
		_fetch(t, place, now)
	if _covers(t) and (not absf(t - _shown.x) < _STEP or sky.north != _shown.y):
		_shown = Vector2(t, sky.north)
		w.conditions = turned(conditions_at(t), sky.north)


## The conditions at `t` (Unix seconds), between the two hours either side (the cloud late in the
## hour, _CLOUD_TURN); null outside them.
## Their winds blow in a world whose north is -Z (turned).
func conditions_at(t: float) -> OvercastConditions:
	if not _covers(t):
		return null
	var i := times.bsearch(t, false) - 1
	if i < 0:
		return hours[0]
	if i >= times.size() - 1:
		return hours[-1]
	var f := (t - times[i]) / (times[i + 1] - times[i])
	var c := OvercastConditions.blend(hours[i], hours[i + 1], f)
	var late := OvercastConditions.blend(hours[i], hours[i + 1], smoothstep(_CLOUD_TURN, 1.0, f))
	for p in _CLOUD:
		c.set(p, late.get(p))
	return c


func _target() -> OvercastWeather:
	return weather if weather else get_parent() as OvercastWeather


func _covers(t: float) -> bool:
	return not times.is_empty() and t >= times[0] and t <= times[-1]


func _fetch(t: float, place: Vector2, now: float) -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED or now < _retry_at:
		return
	var archive := t < now - _FORECAST_PAST_DAYS * 86400.0
	var host := "archive-api.open-meteo.com/v1/archive" if archive else "api.open-meteo.com/v1/forecast"
	if not api_key.is_empty():
		host = "customer-" + host
	var url := "https://%s?latitude=%.4f&longitude=%.4f&hourly=%s&wind_speed_unit=ms&timeformat=unixtime&timezone=GMT&start_date=%s&end_date=%s" % [
		host, place.x, place.y, _HOURLY,
		Time.get_date_string_from_unix_time(int(t - 86400.0)),
		Time.get_date_string_from_unix_time(int(t + 86400.0))]
	if not api_key.is_empty():
		url += "&apikey=" + api_key.uri_encode()
	if _http.request(url, ["User-Agent: overcast-godot"]) == OK:
		_place = place
		_fetched_at = now
		# Not again soon, answered or not: hours that still miss the moment would ask at once.
		_retry_at = now + _RETRY
	else:
		_failed("could not start the request")


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var json = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
	if code != 200 or not json is Dictionary or not json.get("hourly") is Dictionary:
		var reason: String = json.get("reason", "") if json is Dictionary else ""
		_failed("HTTP %d %s" % [code, reason] if result == HTTPRequest.RESULT_SUCCESS else "request failed (%d)" % result)
		return
	var parsed := parse(json["hourly"])
	times = parsed[0]
	hours = parsed[1]
	_shown = Vector2(NAN, NAN)
	updated.emit()


func _failed(message: String) -> void:
	_retry_at = Time.get_unix_time_from_system() + _RETRY
	_place = Vector2.INF
	failed.emit(message)


## `c` in a world whose north is turned `north` degrees from -Z, clockwise seen from above
## (OvercastSky.north), as a new one.
static func turned(c: OvercastConditions, north: float) -> OvercastConditions:
	var out: OvercastConditions = c.duplicate()
	out.wind = c.wind.rotated(Vector3.UP, -deg_to_rad(north))
	out.wind_aloft = c.wind_aloft.rotated(Vector3.UP, -deg_to_rad(north))
	return out


## Open-Meteo's `hourly` block as [times, conditions].
static func parse(hourly: Dictionary) -> Array:
	var ts := PackedFloat64Array()
	var cs: Array[OvercastConditions] = []
	var at: Array = hourly.get("time", [])
	for i in at.size():
		var v := {}
		for key in hourly:
			var column = hourly[key]
			v[key] = column[i] if column is Array and i < column.size() else null
		if v["temperature_2m"] == null or v["cloud_cover_low"] == null:
			continue  # an hour not yet in the record
		ts.append(at[i])
		cs.append(conditions_of(v))
	return [ts, cs]


## One hour of Open-Meteo's values (by its names; any may be null) as conditions, north -Z.
static func conditions_of(v: Dictionary) -> OvercastConditions:
	var c := OvercastConditions.new()
	var temperature := _num(v, "temperature_2m", 10.0)
	var code := int(_num(v, "weather_code", 0.0))
	var showery := code in [80, 81, 82, 85, 86, 95, 96, 99]
	var steady := (code >= 51 and code <= 67) or (code >= 71 and code <= 77)
	var foggy := code == 45 or code == 48
	var dull := (code >= 51 and code <= 57) or foggy  # drizzle or fog: stratus
	var cape := _num(v, "cape", 0.0)
	var convective := maxf(smoothstep(50.0, 800.0, cape), 0.6 if showery else 0.0)
	c.temperature = temperature
	c.low_cover = _num(v, "cloud_cover_low", 0.0) / 100.0
	c.mid_cover = _num(v, "cloud_cover_mid", 0.0) / 100.0
	c.high_cover = _num(v, "cloud_cover_high", 0.0) / 100.0
	var spread := temperature - _num(v, "dew_point_2m", temperature - 8.0)
	c.low_base = clampf(spread * _BASE_PER_DEGREE, 150.0, 3000.0)
	c.low_sheet = smoothstep(0.5, 1.0, c.low_cover) * (1.0 - convective)
	if steady:
		c.low_sheet = maxf(c.low_sheet, 0.75)
	if dull:
		c.low_sheet = 1.0
	c.towering = smoothstep(300.0, 2500.0, cape)
	if showery:
		c.towering = maxf(c.towering, 0.35)
	if code >= 95:
		c.towering = maxf(c.towering, 0.9)
	c.mid_sheet = maxf(smoothstep(0.5, 1.0, c.mid_cover), 0.9 if steady else 0.0)
	c.high_sheet = smoothstep(0.7, 1.0, c.high_cover)
	var mm := _num(v, "precipitation", 0.0)
	c.rain = sqrt(mm / _DOWNPOUR) if mm >= 0.05 else 0.0
	# Which falls as snow is the model's, which knows the air aloft; dry, it is the temperature's.
	c.snow_share = clampf(_num(v, "snowfall", 0.0) * _SNOW_WATER / mm, 0.0, 1.0) if c.rain > 0.0 \
		else OvercastWeather.snow_share_at(temperature)
	c.visibility = clampf(_num(v, "visibility", _FOG if foggy else OvercastWeather.CLEAR_VISIBILITY),
		10.0, OvercastWeather.CLEAR_VISIBILITY)
	var speed := _num(v, "wind_speed_10m", 0.0)
	# A wind from a bearing blows toward the opposite one.
	c.wind = OvercastEphemeris.bearing(_num(v, "wind_direction_10m", 0.0) + 180.0) * speed
	c.gustiness = clampf(_num(v, "wind_gusts_10m", speed) / maxf(speed, 1.0) - 1.0, 0.0, 1.0)
	# Without the 850 hPa wind, the weather's own guess, filled in so hours blend evenly.
	c.wind_aloft = OvercastEphemeris.bearing(float(v["wind_direction_850hPa"]) + 180.0) \
		* float(v["wind_speed_850hPa"]) if v.get("wind_speed_850hPa") != null \
		and v.get("wind_direction_850hPa") != null else c.wind * OvercastWeather.ALOFT
	return c


static func _num(v: Dictionary, key: String, fallback: float) -> float:
	var x = v.get(key)
	return float(x) if x != null else fallback
