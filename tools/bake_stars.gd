extends SceneTree
## Bakes the Yale Bright Star Catalogue (5th ed.; bsc5.dat, unzipped, fixed-width, as CDS V/50
## and SAO give it) into addons/overcast/stars.res: an octahedral map of the sky, in the frame the sky
## shader turns its stars in, one star a texel, the brightest where two share one.
##   CATALOGUE=/path/bsc5.dat godot --headless --path . -s res://tools/bake_stars.gd

const SkyScript = preload("res://addons/overcast/overcast_sky.gd")
const _Ephemeris = preload("res://addons/overcast/overcast_ephemeris.gd")
const SIZE := 1024
const OUT := "res://addons/overcast/stars.res"
## Steps of the blue channel a magnitude, from magnitude -2 at 255 (0 is no star).
const _PER_MAGNITUDE := 25.0


func _initialize() -> void:
	var path := OS.get_environment("CATALOGUE")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("CATALOGUE= the path to bsc5.dat")
		quit(1)
		return
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 4)
	var stars := 0
	var dropped := 0
	while not file.eof_reached():
		var line := file.get_line()
		if line.length() < 107 or line.substr(75, 8).strip_edges().is_empty() \
				or line.substr(102, 5).strip_edges().is_empty():
			continue
		var ra := (float(line.substr(75, 2)) + float(line.substr(77, 2)) / 60.0
			+ float(line.substr(79, 4)) / 3600.0) * 15.0
		var dec := float(line.substr(84, 2)) + float(line.substr(86, 2)) / 60.0 + float(line.substr(88, 2)) / 3600.0
		if line[83] == "-":
			dec = -dec
		var mag := float(line.substr(102, 5))
		var bv_text := line.substr(109, 5).strip_edges() if line.length() >= 114 else ""
		var bv := float(bv_text) if not bv_text.is_empty() else 0.6
		var dir: Vector3 = SkyScript._galaxy_turn * _Ephemeris.radec(ra, dec)
		var uv := octahedral(dir) * SIZE
		var texel := Vector2i(mini(int(uv.x), SIZE - 1), mini(int(uv.y), SIZE - 1))
		var o := (texel.y * SIZE + texel.x) * 4
		var b := clampi(roundi(255.0 - (mag + 2.0) * _PER_MAGNITUDE), 1, 255)
		if data[o + 2] >= b:
			dropped += 1  # a brighter one is there already
			continue
		if data[o + 2] > 0:
			dropped += 1
		data[o] = clampi(int((uv.x - texel.x) * 256.0), 0, 255)
		data[o + 1] = clampi(int((uv.y - texel.y) * 256.0), 0, 255)
		data[o + 2] = b
		data[o + 3] = clampi(roundi((bv + 0.5) * 100.0), 0, 255)
		stars += 1
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	var err := ResourceSaver.save(img, OUT, ResourceSaver.FLAG_COMPRESS)
	print("%d stars, %d sharing a texel with a brighter one; %s: %s" % [stars - dropped, dropped, OUT,
		error_string(err)])
	quit(0 if err == OK else 1)


## The magnitude a texel holds (as sky.gdshaderinc reads it).
static func magnitude(texel: Color) -> float:
	return (1.0 - texel.b) * 255.0 / _PER_MAGNITUDE - 2.0


## Where unit `n` lands on the octahedral map, 0 to 1 (as star_octahedral in sky.gdshaderinc).
static func octahedral(n: Vector3) -> Vector2:
	n /= absf(n.x) + absf(n.y) + absf(n.z)
	var p := Vector2(n.x, n.y)
	if n.z < 0.0:
		p = Vector2((1.0 - absf(n.y)) * (1.0 if n.x >= 0.0 else -1.0),
			(1.0 - absf(n.x)) * (1.0 if n.y >= 0.0 else -1.0))
	return p * 0.5 + Vector2(0.5, 0.5)
