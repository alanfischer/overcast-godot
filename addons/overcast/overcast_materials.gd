@tool
class_name OvercastMaterials
extends Object
## Puts cloud shadows, wet ground and snow on StandardMaterial3Ds, which cannot take Overcast's
## includes: each is swapped for a ShaderMaterial that draws it the same way (shaders/
## standard.gdshaderinc) with the clouds, rain and snow added. A material using a feature that
## shader does not have is left as it is.
##
##     OvercastMaterials.apply($Level)

const INCLUDE := "res://addons/overcast/shaders/standard.gdshaderinc"
const FILTERS := ["filter_nearest", "filter_linear", "filter_nearest_mipmap", "filter_linear_mipmap",
	"filter_nearest_mipmap_anisotropic", "filter_linear_mipmap_anisotropic"]
const CHANNELS := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1),
	Vector4(0.333333, 0.333333, 0.333333, 0)]
## Flags the shader does not draw: a material with any of them set is not converted.
const UNSUPPORTED: Array[StringName] = [&"rim_enabled", &"clearcoat_enabled", &"anisotropy_enabled",
	&"heightmap_enabled", &"subsurf_scatter_enabled", &"subsurf_scatter_transmittance_enabled",
	&"backlight_enabled", &"refraction_enabled", &"detail_enabled", &"bent_normal_enabled",
	&"uv1_triplanar", &"emission_on_uv2", &"ao_on_uv2", &"albedo_texture_msdf", &"use_point_size",
	&"fixed_size", &"proximity_fade_enabled", &"shadow_to_opacity", &"use_particle_trails",
	&"use_z_clip_scale", &"use_fov_override", &"grow"]
## Modes the shader draws, by property: any other value is not converted.
const ALLOWED := {
	&"shading_mode": [BaseMaterial3D.SHADING_MODE_PER_PIXEL],
	&"diffuse_mode": [BaseMaterial3D.DIFFUSE_BURLEY, BaseMaterial3D.DIFFUSE_LAMBERT],
	&"specular_mode": [BaseMaterial3D.SPECULAR_SCHLICK_GGX, BaseMaterial3D.SPECULAR_DISABLED],
	&"billboard_mode": [BaseMaterial3D.BILLBOARD_DISABLED],
	&"distance_fade_mode": [BaseMaterial3D.DISTANCE_FADE_DISABLED],
	&"alpha_antialiasing_mode": [BaseMaterial3D.ALPHA_ANTIALIASING_OFF],
	&"blend_mode": [BaseMaterial3D.BLEND_MODE_MIX, BaseMaterial3D.BLEND_MODE_ADD,
		BaseMaterial3D.BLEND_MODE_SUB, BaseMaterial3D.BLEND_MODE_MUL],
}

const SOURCE := &"overcast_source"

## Source material id -> its twin, held weakly: a twin lives as long as something draws with it,
## and holds its source. And shader code -> Shader.
static var _converted := {}
static var _prune_at := 64
static var _shaders := {}


## Converts the materials of every GeometryInstance3D under `root`, root included: each surface
## and the override. The meshes are not touched; the conversions go on as surface overrides, so a
## mesh shared with something not converted stays as it is. `puddle_scale` is how readily they
## pool (see wet.gdshaderinc). Returns how many surfaces it converted.
static func apply(root: Node, puddle_scale := 1.0) -> int:
	var count := _convert_node(root, puddle_scale)
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		count += _convert_node(node, puddle_scale)
	return count


## apply(root), and the same for each GeometryInstance3D added under it later, once the frame it
## was added in is over: game code that sets materials as things spawn sets them on the originals.
## Until `root` leaves the tree.
static func watch(root: Node, puddle_scale := 1.0) -> void:
	apply(root, puddle_scale)
	var tree := root.get_tree()
	var on_added := _on_added.bind(root, puddle_scale)
	tree.node_added.connect(on_added)
	root.tree_exiting.connect(tree.node_added.disconnect.bind(on_added), CONNECT_ONE_SHOT)


static func _on_added(node: Node, root: Node, puddle_scale: float) -> void:
	if node is GeometryInstance3D and root.is_ancestor_of(node):
		_convert_later.call_deferred(node, puddle_scale)


static func _convert_later(node: Node, puddle_scale: float) -> void:
	if is_instance_valid(node):
		_convert_node(node, puddle_scale)


static func _convert_node(node: Node, puddle_scale: float) -> int:
	var gi := node as GeometryInstance3D
	if gi == null:
		return 0
	if gi.material_override:
		var to := convert_material(gi.material_override, puddle_scale)
		if to == gi.material_override:
			return 0
		gi.material_override = to
		return 1
	var count := 0
	if gi is MeshInstance3D:
		for i in gi.get_surface_override_material_count():
			var mat: Material = gi.get_active_material(i)
			var to := convert_material(mat, puddle_scale)
			if to != mat:
				gi.set_surface_override_material(i, to)
				count += 1
	return count


## The Overcast twin of a BaseMaterial3D; anything else, or one it cannot draw, comes back as it
## is. The same material converts to the same twin, so one shared by many meshes stays shared.
## To change a converted material, change source_of(twin) and convert that again.
static func convert_material(mat: Material, puddle_scale := 1.0) -> Material:
	if not mat is BaseMaterial3D:
		return mat
	var key := mat.get_instance_id()
	var twin: ShaderMaterial = _converted[key].get_ref() if _converted.has(key) else null
	if twin and twin.get_shader_parameter("puddle_scale") == puddle_scale:
		return twin
	if not unsupported(mat).is_empty():
		return mat
	var src := mat as BaseMaterial3D
	var to := ShaderMaterial.new()
	to.shader = _shader(src)
	var params := _params(src)
	params["puddle_scale"] = puddle_scale
	for name in params:
		to.set_shader_parameter(name, params[name])
	to.render_priority = src.render_priority
	to.next_pass = convert_material(src.next_pass, puddle_scale)
	to.resource_name = src.resource_name
	to.set_meta(SOURCE, src)
	if _converted.size() >= _prune_at:
		for k in _converted.keys():
			if _converted[k].get_ref() == null:
				_converted.erase(k)
		_prune_at = maxi(64, _converted.size() * 2)
	_converted[key] = weakref(to)
	return to


## The material a twin was converted from, for code that edits materials; `mat` itself if it is
## not a twin.
static func source_of(mat: Material) -> Material:
	return mat.get_meta(SOURCE, mat) if mat else null


## Why `mat` cannot be converted: the first property it sets that the shader lacks, or "".
static func unsupported(mat: BaseMaterial3D) -> String:
	for prop in UNSUPPORTED:
		if mat.get(prop):
			return prop
	for prop in ALLOWED:
		if mat.get(prop) not in ALLOWED[prop]:
			return prop
	return ""


static func _shader(mat: BaseMaterial3D) -> Shader:
	var code := _code(mat)
	if not _shaders.has(code):
		var shader := Shader.new()
		shader.code = code
		_shaders[code] = shader
	return _shaders[code]


static func _code(mat: BaseMaterial3D) -> String:
	var modes: PackedStringArray = [
		["blend_mix", "blend_add", "blend_sub", "blend_mul"][mat.blend_mode],
		["depth_draw_opaque", "depth_draw_always", "depth_draw_never"][mat.depth_draw_mode],
		["cull_back", "cull_front", "cull_disabled"][mat.cull_mode],
	]
	var optional := {
		"depth_prepass_alpha": mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS,
		"shadows_disabled": mat.disable_receive_shadows,
		"depth_test_disabled": mat.no_depth_test,
		"ambient_light_disabled": mat.disable_ambient_light,
		"fog_disabled": mat.disable_fog,
		"specular_occlusion_disabled": mat.get("disable_specular_occlusion") == true,
	}
	for mode in optional:
		if optional[mode]:
			modes.append(mode)
	var params := _params(mat)
	var flags := {
		"OV_ALBEDO_TEXTURE": params["texture_albedo"] != null,
		"OV_METALLIC_TEXTURE": params["texture_metallic"] != null,
		"OV_ROUGHNESS_TEXTURE": params["texture_roughness"] != null,
		"OV_NORMAL": mat.normal_enabled,
		"OV_EMISSION": mat.emission_enabled,
		"OV_EMISSION_MULTIPLY": mat.emission_enabled
			and mat.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY,
		"OV_AO": mat.ao_enabled,
		"OV_VERTEX_COLOR": mat.vertex_color_use_as_albedo,
		"OV_VERTEX_COLOR_SRGB": mat.vertex_color_use_as_albedo and mat.vertex_color_is_srgb,
		"OV_ALPHA": mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
		"OV_ALPHA_SCISSOR": mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
		"OV_ALPHA_HASH": mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH,
		"OV_LAMBERT": mat.diffuse_mode == BaseMaterial3D.DIFFUSE_LAMBERT,
		"OV_NO_SPECULAR": mat.specular_mode == BaseMaterial3D.SPECULAR_DISABLED,
	}
	var code := "shader_type spatial;\nrender_mode %s;\n\n" % ", ".join(modes)
	code += "#define OV_FILTER %s\n" % FILTERS[clampi(mat.texture_filter, 0, FILTERS.size() - 1)]
	code += "#define OV_REPEAT %s\n" % ("repeat_enable" if mat.texture_repeat else "repeat_disable")
	for flag in flags:
		if flags[flag]:
			code += "#define %s\n" % flag
	return code + '#include "%s"\n' % INCLUDE


## The shader parameters that draw `mat`. An ORMMaterial3D's occlusion, roughness and metallic
## come from the one texture's red, green and blue.
static func _params(mat: BaseMaterial3D) -> Dictionary:
	var params := {
		"albedo": mat.albedo_color,
		"texture_albedo": mat.albedo_texture,
		"metallic": mat.metallic,
		"roughness": mat.roughness,
		"specular": mat.metallic_specular,
		"texture_metallic": mat.metallic_texture,
		"metallic_texture_channel": CHANNELS[mat.metallic_texture_channel],
		"texture_roughness": mat.roughness_texture,
		"roughness_texture_channel": CHANNELS[mat.roughness_texture_channel],
		"texture_normal": mat.normal_texture,
		"normal_scale": mat.normal_scale,
		"emission": mat.emission,
		"emission_energy": mat.emission_energy_multiplier,
		"texture_emission": mat.emission_texture,
		"texture_ambient_occlusion": mat.ao_texture,
		"ao_texture_channel": CHANNELS[mat.ao_texture_channel],
		"ao_light_affect": mat.ao_light_affect,
		"alpha_scissor_threshold": mat.alpha_scissor_threshold,
		"alpha_hash_scale": mat.alpha_hash_scale,
		"uv1_scale": mat.uv1_scale,
		"uv1_offset": mat.uv1_offset,
	}
	if mat is ORMMaterial3D:
		var orm: Texture2D = mat.get("orm_texture")
		params.merge({
			"texture_ambient_occlusion": orm, "ao_texture_channel": CHANNELS[0],
			"texture_roughness": orm, "roughness_texture_channel": CHANNELS[1],
			"texture_metallic": orm, "metallic_texture_channel": CHANNELS[2],
		}, true)
	return params
