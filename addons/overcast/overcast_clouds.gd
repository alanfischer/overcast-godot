@tool
class_name OvercastClouds
extends Object
## The cloud layer's global shader uniforms (shaders/clouds.gdshaderinc, overcast_globals.gd). Global,
## because the sky draws the clouds and everything lit under them reads the same ones for its
## shadows: one sky at a time. Whichever last claimed it owns it, and only the owner moves it; when
## it lets go, the sky that claimed it before, if still drawing, takes it back.

const Globals = preload("res://addons/overcast/overcast_globals.gd")

## Tiling cloud noise, made once: sampling it costs a fraction of computing the octaves per pixel,
## which pays for the extra samples the cloud shading takes.
static var _noise: Texture2D
static var _volume: Texture3D
static var _volumetric := false
## The instance id of the sky drawing the layer; 0 for none.
static var _owner := 0
## Instance ids of the skies that want the layer, oldest claim first.
static var _drawing: Array[int] = []


static func _set_global(key: String, v: Variant) -> void:
	Globals.set_value(key, v)


## Ray-march the clouds through 3D noise rather than shading one flat layer; the ground's cloud
## shadows follow. About a millisecond at 720p on an M1 on gl_compatibility; the volume itself is
## built (~0.2 s) only once a sky is drawing it.
static func set_volumetric(enabled: bool) -> void:
	_volumetric = enabled
	_set_global("overcast_volumetric", 1.0 if enabled else 0.0)
	if enabled and _owner != 0:
		_set_global("overcast_volume", _volume_texture())


## OvercastSky's: the sky with instance id `owner` takes the layer. `sun_dir` toward the sun,
## `height` metres over the origin, `scale` noise units per height, `speed` noise units per
## second, `softness` of the edges.
static func _claim(owner: int, sun_dir: Vector3, height: float, scale: float, speed: float,
		softness: float) -> void:
	if _owner != owner:
		_drawing.erase(owner)
		_drawing.append(owner)
	_owner = owner
	_set_global("overcast_noise", _noise_texture())
	if _volumetric:
		_set_global("overcast_volume", _volume_texture())
	_set_global("overcast_sun_dir", sun_dir.normalized())
	_set_global("overcast_height", height)
	_set_global("overcast_scale", scale)
	_set_global("overcast_speed", speed)
	_set_global("overcast_softness", softness)


## OvercastSky's: how much of the sky is cloud, and how much of the sun's share of the light a
## cloud overhead takes off what is under it, if `owner` holds the layer. Every frame of a storm.
static func _set_weather(owner: int, cover: float, shadow: float) -> void:
	if owner == _owner:
		_set_cover(cover, shadow)


## OvercastSky's: `owner` stops drawing. If it held the layer, the previous sky still drawing
## takes it back; with none, no clouds, so no shadows.
static func _release(owner: int) -> void:
	_drawing.erase(owner)
	if owner != _owner:
		return
	_owner = 0
	_set_cover(0.0, 0.0)
	while not _drawing.is_empty():
		var sky = instance_from_id(_drawing[-1])
		if sky and sky.drawing:
			sky._sync_layer()
			return
		_drawing.pop_back()


static func _set_cover(cover: float, shadow: float) -> void:
	_set_global("overcast_cover", cover)
	_set_global("overcast_shadow", shadow)


static func _noise_texture() -> Texture2D:
	if _noise:
		return _noise
	var r := _fbm(7, false, 8.0 / 512.0, 6).get_seamless_image(512, 512)
	var g := _fbm(11, true, 24.0 / 512.0, 2).get_seamless_image(512, 512)
	var img := Image.create_from_data(512, 512, false, Image.FORMAT_RG8,
		_interleave(_bytes(r), _bytes(g)))
	img.generate_mipmaps()
	_noise = ImageTexture.create_from_image(img)
	return _noise


## Tiling 3D noise for the volumetric clouds: perlin-worley in r (shape: billows where worley
## cells are), worley distance in g (detail that erodes the edges).
static func _volume_texture() -> Texture3D:
	if _volume:
		return _volume
	const N := 64
	var perlin := _fbm(3, false, 4.0 / N, 4).get_seamless_image_3d(N, N, N)
	var cells := _fbm(5, true, 6.0 / N, 3).get_seamless_image_3d(N, N, N)
	var fine := _fbm(9, true, 8.0 / N, 3).get_seamless_image_3d(N, N, N)
	var slices: Array[Image] = []
	for z in N:
		var pd := _bytes(perlin[z])
		var cd := _bytes(cells[z])
		for i in pd.size():
			pd[i] = clampi(int((pd[i] * 0.45 + (255 - cd[i]) * 0.55 - 25.0) * 1.25), 0, 255)
		slices.append(Image.create_from_data(N, N, false, Image.FORMAT_RG8,
			_interleave(pd, _bytes(fine[z]))))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RG8, N, N, N, false, slices)
	_volume = tex
	return _volume


## Fractal noise: perlin, or worley distance (0 at a cell's centre) when `cellular`.
static func _fbm(seed: int, cellular: bool, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_CELLULAR if cellular else FastNoiseLite.TYPE_PERLIN
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	n.frequency = frequency
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n


static func _bytes(img: Image) -> PackedByteArray:
	img.convert(Image.FORMAT_L8)
	return img.get_data()


static func _interleave(r: PackedByteArray, g: PackedByteArray) -> PackedByteArray:
	var rg := PackedByteArray()
	rg.resize(r.size() * 2)
	for i in r.size():
		rg[i * 2] = r[i]
		rg[i * 2 + 1] = g[i]
	return rg
