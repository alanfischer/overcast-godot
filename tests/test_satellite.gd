extends "res://tests/suite.gd"

const Satellite = preload("res://addons/overcast/overcast_satellite.gd")
const SkyScript = preload("res://addons/overcast/overcast_sky.gd")
const Clouds = preload("res://addons/overcast/overcast_clouds.gd")
const Globals = preload("res://addons/overcast/overcast_globals.gd")

## A colour map as GIBS writes one: white for the coldest, a colour, then a grey ramp.
const XML := """<ColorMaps><ColorMap><Entries>
<ColorMapEntry rgb="255,255,255" transparent="false" sourceValue="(-92.1,-91.1]" value="(-92.1,-91.1]" ref="0"/>
<ColorMapEntry rgb="0,200,0" transparent="false" sourceValue="(-41.1,-40.1]" value="(-41.1,-40.1]" ref="1"/>
<ColorMapEntry rgb="200,200,200" transparent="false" sourceValue="(-20.25,-19.75]" value="(-20.25,-19.75]" ref="2"/>
<ColorMapEntry rgb="100,100,100" transparent="false" sourceValue="(19.75,20.25]" value="(19.75,20.25]" ref="3"/>
<ColorMapEntry rgb="0,0,0" transparent="true" nodata="true" ref="4"/>
</Entries></ColorMap></ColorMaps>"""


func test_the_colour_map_reads_back_to_temperatures() -> void:
	var map := Satellite.parse_colormap(XML)
	assert_eq(map.size(), 4, "every coloured entry, not the no-data one")
	var cache := {}
	assert_almost_eq(Satellite.temperature_of(0x646464, map, cache), 20.0, 1e-3, "an entry's colour, its middle")
	assert_almost_eq(Satellite.temperature_of(0x969696, map, cache), 0.0, 1e-3, "a grey between two, between them")
	assert_almost_eq(Satellite.temperature_of(0x64C864, map, cache), -30.0, 1.0,
		"a colour off the map, by the nearest step")
	assert_true(cache.has(0x969696), "kept for the next frame")


func test_tops_colder_than_clear_ground_are_cloud_and_say_how_high() -> void:
	var map := Satellite.parse_colormap(XML)
	var frame := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	frame.fill(Color8(100, 100, 100))
	for y in 8:
		frame.set_pixel(0, y, Color8(200, 200, 200))
	var cover := Satellite.cover_from(frame, map, 20.0)
	assert_eq(cover.get_format(), Image.FORMAT_RGBA8, "cloud, top and say")
	assert_eq(cover.get_pixel(0, 1).r, 1.0, "a -20 C top over 20 C ground is cloud")
	assert_almost_eq(cover.get_pixel(0, 1).g * Satellite.COVER_TOP_KM, 40.0 / 6.5, 0.1,
		"its top by the lapse rate")
	assert_eq(cover.get_pixel(5, 1).r, 0.0, "the ground clear")
	assert_eq(cover.get_pixel(5, 1).a, 1.0, "and sure of it")
	frame.fill(Color8(100, 100, 100))
	frame.set_pixel(0, 0, Color8(110, 110, 110))
	var flat := Satellite.cover_from(frame, map, 26.0)
	assert_eq(flat.get_pixel(3, 3).r, 0.0, "a clear night: ground under the air is still clear")
	assert_eq(flat.get_pixel(3, 3).a, 1.0, "and says so")
	frame.fill(Color8(200, 200, 200))
	assert_eq(Satellite.cover_from(frame, map, 20.0).get_pixel(3, 3).r, 1.0,
		"a frame cloudy all over is cloud, by the air")
	frame.fill(Color(0, 0, 0, 0))
	assert_eq(Satellite.cover_from(frame, map, 20.0), null, "an empty frame is none")


func test_frames_and_satellites() -> void:
	var now := 1794960000.0
	assert_eq(Satellite.frame_time(now - 7200.0 + 450.0, now), int(now - 7200.0), "the last frame at or before")
	assert_lt(Satellite.frame_time(now, now), int(now - 1700.0), "none newer than is out yet")
	assert_eq(Satellite.layer_for(-103.9), "GOES-East_ABI_Band13_Clean_Infrared", "the Black Hills: GOES-East")
	assert_eq(Satellite.layer_for(-150.0), "GOES-West_ABI_Band13_Clean_Infrared", "Hawaii: GOES-West")
	assert_eq(Satellite.layer_for(151.2), "Himawari_AHI_Band13_Clean_Infrared", "Sydney: Himawari")
	assert_eq(Satellite.layer_for(2.35), "", "Paris: out of their sight")


func test_a_cover_map_is_laid_and_taken_up() -> void:
	var sky := SkyScript.new({"north": 90.0})
	sky.drawing = true
	sky._start()
	var white := Image.create(4, 4, false, Image.FORMAT_L8)
	white.fill(Color.WHITE)
	var map := ImageTexture.create_from_image(white)
	sky.set_cover_map(map, 200000.0)
	var laid: Image = Globals.value("overcast_cover_map").get_image()
	assert_eq(laid.get_size(), Vector2i(8, 4), "laid, beside room for the one before")
	assert_eq(laid.get_pixel(1, 1), Color.WHITE, "on the left")
	var frame: Vector4 = Globals.value("overcast_cover_map_frame")
	assert_vec2_almost_eq(Vector2(frame.x, frame.y), Vector2(0.0, 1.0), 1e-5,
		"east turned with the world's north: north at +X puts east at +Z")
	assert_eq(frame.z, 200000.0, "its span")
	assert_almost_eq(frame.w, sky.world_scale, 1e-6, "and the world's scale")
	assert_eq(Globals.value("overcast_cover_map_place").z, 1.0, "with full say")
	var next := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_L8))
	sky.set_cover_map(next, 200000.0)
	laid = Globals.value("overcast_cover_map").get_image()
	assert_eq(laid.get_pixel(1, 1), Color.BLACK, "the next frame laid")
	assert_eq(laid.get_pixel(5, 1), Color.WHITE, "beside the one before, in the one texture")
	assert_eq(Globals.value("overcast_cover_map_place").z, 0.0, "fading in from nothing")
	assert_eq(Globals.value("overcast_cover_map_was_place").z, 1.0, "the old one whole")
	Clouds._fade_cover_maps(Clouds.COVER_FADE * 0.5)
	assert_almost_eq(Globals.value("overcast_cover_map_place").z, 0.5, 1e-6, "halfway")
	assert_almost_eq(Globals.value("overcast_cover_map_was_place").z, 0.5, 1e-6, "both")
	Clouds._fade_cover_maps(Clouds.COVER_FADE)
	assert_eq(Globals.value("overcast_cover_map_place").z, 1.0, "then the new one alone")
	assert_eq(Globals.value("overcast_cover_map_was_place").z, 0.0, "the old one gone")
	sky.set_cover_map(null, 200000.0)
	assert_eq(Globals.value("overcast_cover_map_place").z, 0.0, "taken up")
	sky.set_cover_map(map, 200000.0)
	sky.drawing = false
	assert_eq(Globals.value("overcast_cover_map_place").z, 0.0, "gone with the sky that laid it")
