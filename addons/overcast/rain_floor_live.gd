extends RefCounted
## OvercastWeather's rain floor as it is now: the baked heights with every cover stamped on, the
## texture the shaders read, and the covers themselves.

const RainFloor = preload("res://addons/overcast/overcast_rain_floor.gd")

## Covers re-stamp the floor at most this often (s), and only for a step that shows: half a cell
## sideways or COVER_STEP (m) up or down. The floor is re-uploaded whole each time.
const COVER_EVERY := 0.1
const COVER_STEP := 0.05

## Heights row by row, as baked and with the covers stamped on, and the image and texture (only
## when drawn) the shaders read. `cell` is metres per cell.
var baked := PackedFloat32Array()
var heights := PackedFloat32Array()
var dims := Vector2i.ZERO
var image: Image
var texture: ImageTexture
## The air under cover (OvercastRainFloor.under), as it was baked: covers do not change it. Only
## when drawn and baked with one.
var under_texture: ImageTexture
var origin := Vector3.ZERO
var size := Vector2.ONE
var cell := Vector2.ONE
var top := 1e6
## Whether rain falls off the floor's edges (OvercastWeather.rain_beyond_floor).
var beyond := false
## Node3D -> Cover.
var covers := {}
## Microseconds a tick may spend rasterizing covers that turned (at least one is, whatever the
## budget). Past it the rest keep their old stamp and go first next tick.
var budget_usec := 1000
var _cover_in := 0.0


## Takes `source` (none for rain everywhere); `drawn` keeps a texture for the shaders. Covers
## stay, to be stamped afresh on it.
func set_floor(source: RainFloor, drawn: bool) -> void:
	texture = null
	under_texture = null
	if source == null or source.image == null:
		image = null
		baked = PackedFloat32Array()
		heights = PackedFloat32Array()
		dims = Vector2i.ZERO
		top = 1e6
	else:
		var img := source.image
		if img.get_format() != Image.FORMAT_RF:
			img = img.duplicate()
			img.convert(Image.FORMAT_RF)
		dims = img.get_size()
		baked = img.get_data().to_float32_array()
		heights = baked.duplicate()
		image = img.duplicate()
		origin = source.origin
		size = source.size
		cell = size / Vector2(dims)
		top = source.top
		if drawn:
			texture = ImageTexture.create_from_image(image)
			if source.under and source.under.get_size() == dims:
				var air := source.under
				if air.get_format() != Image.FORMAT_RGF:
					air = air.duplicate()
					air.convert(Image.FORMAT_RGF)
				under_texture = ImageTexture.create_from_image(air)
	for node in covers:
		covers[node].xform = Transform3D(Basis(), Vector3.INF)
		covers[node].raster_xform = Transform3D(Basis(), Vector3.INF)
		covers[node].rect = Rect2i()
	_cover_in = 0.0


func add_cover(node: Node3D, tris: PackedVector3Array) -> void:
	remove_cover(node)
	if tris.is_empty():
		return
	var cover := Cover.new()
	cover.triangles = tris
	var bounds := AABB(tris[0], Vector3.ZERO)
	for v in tris:
		bounds = bounds.expand(v)
	for i in 8:
		cover.corners.append(bounds.get_endpoint(i))
	covers[node] = cover
	_cover_in = 0.0


func remove_cover(node: Node3D) -> void:
	if covers.has(node):
		var rect: Rect2i = covers[node].rect
		covers.erase(node)
		if image:
			_restamp([rect])


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
func update(delta := COVER_EVERY) -> void:
	if image == null or covers.is_empty():
		return
	_cover_in -= delta
	if _cover_in > 0.0:
		return
	_cover_in = COVER_EVERY
	_stamp(budget_usec)


## Every cover where it is now, whatever the interval or budget: for a query on a peer that does
## not draw the rain, and so does not keep the floor up to date each frame.
func sync() -> void:
	if image != null and not covers.is_empty():
		_stamp(-1)


## `budget` microseconds for covers that turned; -1 for no limit.
func _stamp(budget: int) -> void:
	var dirty: Array[Rect2i] = []
	var start := Time.get_ticks_usec()
	var rasterized := 0
	var done: Array[Node3D] = []
	for node in covers.keys():
		var cover: Cover = covers[node]
		if not is_instance_valid(node):
			dirty.append(cover.rect)
			covers.erase(node)
			continue
		var shown: bool = node.is_visible_in_tree()
		var xform: Transform3D = node.global_transform
		if shown == cover.shown and not _moved(cover, xform):
			continue
		var turned := shown and _turned(cover, xform)
		if turned:
			if budget >= 0 and rasterized > 0 and Time.get_ticks_usec() - start > budget:
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
		var cover: Cover = covers[node]
		covers.erase(node)
		covers[node] = cover
	_restamp(dirty)


## Whether any corner of the cover has moved a step that shows since it was stamped: half a cell
## sideways or COVER_STEP up or down.
func _moved(cover: Cover, xform: Transform3D) -> bool:
	if not cover.xform.origin.is_finite():
		return true
	var half := minf(cell.x, cell.y) * 0.5
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
	cover.shift = Vector2i(roundi(d.x / cell.x), roundi(d.z / cell.y))
	cover.rect = Rect2i(cover.raster_rect.position + cover.shift, cover.raster_rect.size) \
		.intersection(Rect2i(Vector2i.ZERO, dims))
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
		var u := Vector3((w.x - origin.x) / cell.x, w.y, (w.z - origin.z) / cell.y)
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
	var w := dims.x
	for region in merged:
		for z in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				heights[z * w + x] = baked[z * w + x]
		for node in covers:
			var cover: Cover = covers[node]
			var rect := cover.rect.intersection(region)
			if not rect.has_area():
				continue
			# The raster cell under floor cell (x, z) is (x, z) - shift.
			var o := cover.raster_rect.position + cover.shift
			var rw := cover.raster_rect.size.x
			for z in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var top := cover.raster[(z - o.y) * rw + x - o.x] + cover.rise
					if top > heights[z * w + x]:
						heights[z * w + x] = top
	image.set_data(w, dims.y, false, Image.FORMAT_RF, heights.to_byte_array())
	if texture:
		texture.update(image)


## Where rain stops at world XZ `q`: off the floor INF, where no rain falls, or -INF with `beyond`;
## -INF with no floor.
func floor_at(q: Vector3) -> float:
	if image == null:
		return -INF
	var x := floori((q.x - origin.x) / cell.x)
	var z := floori((q.z - origin.z) / cell.y)
	if x < 0 or z < 0 or x >= dims.x or z >= dims.y:
		return -INF if beyond else INF
	return heights[z * dims.x + x]
