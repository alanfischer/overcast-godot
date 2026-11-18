extends "res://tests/suite.gd"

const Forecast = preload("res://addons/overcast/overcast_forecast.gd")


## Two hours as Open-Meteo sends them: a dry, breezy one under broken cloud, then a thunderstorm.
func _hourly() -> Dictionary:
	return {
		"time": [1794916800, 1794920400, 1794924000],
		"temperature_2m": [13.0, 9.0, null],
		"dew_point_2m": [7.0, 8.6, null],
		"precipitation": [0.0, 10.0, null],
		"snowfall": [0.0, 0.0, null],
		"visibility": [24000.0, 4000.0, null],
		"weather_code": [3, 95, null],
		"cloud_cover_low": [60, 100, null],
		"cloud_cover_mid": [0, 100, null],
		"cloud_cover_high": [100, 40, null],
		"wind_speed_10m": [6.0, 4.0, null],
		"wind_direction_10m": [270, 180, null],
		"wind_gusts_10m": [12.0, 4.0, null],
		"cape": [10.0, 3000.0, null],
		"wind_speed_850hPa": [20.0, null, null],
		"wind_direction_850hPa": [0, null, null],
	}


func test_an_hour_becomes_conditions() -> void:
	var parsed := Forecast.parse(_hourly())
	var times: PackedFloat64Array = parsed[0]
	var hours: Array = parsed[1]
	assert_eq(times.size(), 2, "the hour not yet in the record is left out")
	var dry: OvercastConditions = hours[0]
	assert_almost_eq(dry.low_cover, 0.6, 1e-6, "low cloud as a share")
	assert_almost_eq(dry.high_cover, 1.0, 1e-6, "and the cirrus")
	assert_almost_eq(dry.low_base, 750.0, 1e-3, "its base where the air cools to its dew point")
	assert_eq(dry.rain, 0.0, "dry")
	assert_vec3_almost_eq(dry.wind, Vector3(6.0, 0.0, 0.0), 1e-4, "a west wind blows east, +X")
	assert_almost_eq(dry.gustiness, 1.0, 1e-6, "gusting to twice its speed")
	assert_vec3_almost_eq(dry.wind_aloft, Vector3(0.0, 0.0, 20.0), 1e-4, "a north wind aloft blows south, +Z")
	assert_lt(dry.towering, 0.01, "no thunderheads in still air")
	assert_eq(dry.visibility, 20000.0, "clear air past 20 km is clear")
	var storm: OvercastConditions = hours[1]
	assert_almost_eq(storm.rain, 1.0, 1e-6, "10 mm an hour is a downpour")
	assert_gt(storm.towering, 0.89, "a thunderstorm towers")
	assert_lt(storm.low_base, 300.0, "under a low base in the damp air")
	assert_vec3_almost_eq(storm.wind, Vector3(0.0, 0.0, -4.0), 1e-4, "a south wind blows north, -Z")
	assert_eq(storm.gustiness, 0.0, "steady")
	assert_eq(storm.wind_aloft, Vector3.ZERO, "none aloft given: the weather's guess")
	assert_eq(storm.visibility, 4000.0, "hazed by the rain")
	assert_eq(storm.snow_share, 0.0, "and all of it rain")


func test_the_worlds_north_turns_the_wind() -> void:
	var c := Forecast.conditions_of({"wind_speed_10m": 5.0, "wind_direction_10m": 180.0}, 90.0)
	assert_vec3_almost_eq(c.wind, Vector3(5.0, 0.0, 0.0), 1e-4, "north turned to +X: a south wind blows there")


func test_rain_from_steady_cloud_and_from_showers() -> void:
	var steady := Forecast.conditions_of({"weather_code": 63, "cloud_cover_low": 100, "precipitation": 2.5})
	assert_almost_eq(steady.rain, 0.5, 1e-6, "moderate rain")
	assert_gt(steady.low_sheet, 0.74, "out of a spread sheet")
	assert_gt(steady.mid_sheet, 0.89, "under altostratus")
	var showers := Forecast.conditions_of({"weather_code": 81, "cloud_cover_low": 100, "precipitation": 2.5, "cape": 0.0})
	assert_lt(showers.low_sheet, 0.5, "showers fall from heaped cloud")
	assert_gt(showers.towering, 0.3, "built up")
	var drizzle := Forecast.conditions_of({"weather_code": 53, "cloud_cover_low": 40})
	assert_eq(drizzle.low_sheet, 1.0, "drizzle from stratus")
	var sleet := Forecast.conditions_of({"temperature_2m": 2.0, "precipitation": 2.0, "snowfall": 0.7})
	assert_almost_eq(sleet.snow_share, 0.5, 1e-6, "half of it snow, as the model has it, warm or not")
	assert_almost_eq(Forecast.conditions_of({"temperature_2m": -5.0}).snow_share, 1.0, 1e-6,
		"dry, by the temperature")
	var fog := Forecast.conditions_of({"weather_code": 45})
	assert_eq(fog.visibility, 300.0, "fog with no visibility given: a few hundred metres")
	var empty := Forecast.conditions_of({})
	assert_eq(empty.rain, 0.0, "nothing given: dry")
	assert_eq(empty.low_cover, 0.0, "and clear")


func test_the_hours_between_blend() -> void:
	var f := Forecast.new()
	_keep(f)
	var parsed := Forecast.parse(_hourly())
	f.times = parsed[0]
	f.hours.assign(parsed[1])
	assert_eq(f.conditions_at(1794916800.0 - 1.0), null, "nothing before the first hour")
	assert_eq(f.conditions_at(1794920400.0 + 1.0), null, "or after the last")
	var half := f.conditions_at(1794918600.0)
	assert_almost_eq(half.low_cover, 0.8, 1e-6, "halfway, cover halfway")
	assert_almost_eq(half.temperature, 11.0, 1e-6, "and the temperature")
	assert_almost_eq(f.conditions_at(1794920400.0).rain, 1.0, 1e-6, "on the hour, that hour")
