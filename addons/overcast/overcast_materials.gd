@tool
class_name OvercastMaterials
extends Object
## Puts cloud shadows and wet ground on StandardMaterial3Ds, which cannot take Overcast's
## includes: each is swapped for a ShaderMaterial that draws it the same way (shaders/
## standard.gdshaderinc) with the clouds and rain added. A material using a feature that shader
## does not have is left as it is.
##
##     OvercastMaterials.apply($Level)

const INCLUDE := "res://addons/overcast/shaders/standard.gdshaderinc"
const FILTERS := ["filter_nearest", "filter_linear", "filter_nearest_mipmap", "filter_linear_mipmap",
	"filter_nearest_mipmap_anisotropic", "filter_linear_mipmap_anisotropic"]
const CHANNELS := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1),
	Vector4(0.333333, 0.333333, 0.333333, 0)]
## Features and flags the shader does not draw: a material with any of them is not converted.
const UNSUPPORTED := ["rim_enabled", "clearcoat_enabled", "anisotropy_enabled", "heightmap_enabled",
	"subsurf_scatter_enabled", "subsurf_scatter_transmittance_enabled", "backlight_enabled",
	"refraction_enabled", "detail_enabled", "bent_normal_enabled", "uv1_triplanar", "emission_on_uv2",
	"ao_on_uv2", "albedo_texture_msdf", "use_point_size", "fixed_size", "proximity_fade_enabled",
	"shadow_to_opacity", "use_particle_trails", "use_z_clip_scale", "use_fov_override"]

const SOURCE := &"overcast_source"

## Source material id -> [source, twin], both held weakly: a twin lives as long as something draws
## with it. And shader code -> Shader.
static var _converted := {}
static var _shaders := {}


## Converts the materials of every GeometryInstance3D under `root`, root included: each surface
## and the override. The meshes are not touched; the conversions go on as surface overrides, so a
## mesh shared with something not converted stays as it is. `puddle_scale` is how readily they
## pool (see wet.gdshaderinc). Returns how many surfaces it converted.
static func apply(root: Node, puddle_scale := 1.0) -> int:
	var count := 0
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "GeometryInstance3D", true, false))
	for node in nodes:
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.material_override:
				count += _swap(mi, "material_override", puddle_scale)
				continue
			for i in mi.get_surface_override_material_count():
				var mat := convert_material(mi.get_active_material(i), puddle_scale)
				if mat != mi.get_active_material(i):
					mi.set_surface_override_material(i, mat)
					count += 1
		elif node is GeometryInstance3D and node.material_override:
			count += _swap(node, "material_override", puddle_scale)
	return count


static func _swap(node: Object, property: StringName, puddle_scale: float) -> int:
	var mat: Material = node.get(property)
	var to := convert_material(mat, puddle_scale)
	if to == mat:
		return 0
	node.set(property, to)
	return 1


## The Overcast twin of a BaseMaterial3D; anything else, or one it cannot draw, comes back as it
## is. The same material converts to the same twin, so one shared by many meshes stays shared.
## To change a converted material, change source_of(twin) and convert that again.
static func convert_material(mat: Material, puddle_scale := 1.0) -> Material:
	if not mat is BaseMaterial3D or not unsupported(mat).is_empty():
		return mat
	var key := mat.get_instance_id()
	var pair: Array = _converted.get(key, [])
	if not pair.is_empty() and pair[0].get_ref() == mat:
		var twin: ShaderMaterial = pair[1].get_ref()
		if twin and twin.get_shader_parameter("puddle_scale") == puddle_scale:
			return twin
	var src := mat as BaseMaterial3D
	var to := ShaderMaterial.new()
	to.shader = _shader(src)
	_copy(src, to)
	to.set_shader_parameter("puddle_scale", puddle_scale)
	to.render_priority = src.render_priority
	to.next_pass = convert_material(src.next_pass, puddle_scale) if src.next_pass else null
	to.resource_name = src.resource_name
	to.set_meta(SOURCE, src)
	if _converted.size() >= 64 and not _converted.has(key):
		for k in _converted.keys():
			if _converted[k][1].get_ref() == null:
				_converted.erase(k)
	_converted[key] = [weakref(src), weakref(to)]
	return to


## The material a twin was converted from, for code that edits materials; `mat` itself if it is
## not a twin.
static func source_of(mat: Material) -> Material:
	return mat.get_meta(SOURCE, mat) if mat else null


## Why `mat` cannot be converted: the first feature it uses that the shader lacks, or "".
static func unsupported(mat: BaseMaterial3D) -> String:
	for prop in UNSUPPORTED:
		if mat.get(prop):
			return prop
	if mat.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		return "shading_mode"
	if mat.diffuse_mode not in [BaseMaterial3D.DIFFUSE_BURLEY, BaseMaterial3D.DIFFUSE_LAMBERT]:
		return "diffuse_mode"
	if mat.specular_mode not in [BaseMaterial3D.SPECULAR_SCHLICK_GGX, BaseMaterial3D.SPECULAR_DISABLED]:
		return "specular_mode"
	if mat.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return "billboard_mode"
	if mat.grow:
		return "grow"
	if mat.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
		return "distance_fade_mode"
	if mat.alpha_antialiasing_mode != BaseMaterial3D.ALPHA_ANTIALIASING_OFF:
		return "alpha_antialiasing_mode"
	if mat.blend_mode not in [BaseMaterial3D.BLEND_MODE_MIX, BaseMaterial3D.BLEND_MODE_ADD,
			BaseMaterial3D.BLEND_MODE_SUB, BaseMaterial3D.BLEND_MODE_MUL]:
		return "blend_mode"
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
	if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
		modes.append("depth_prepass_alpha")
	if mat.disable_receive_shadows:
		modes.append("shadows_disabled")
	if mat.no_depth_test:
		modes.append("depth_test_disabled")
	if mat.disable_ambient_light:
		modes.append("ambient_light_disabled")
	if mat.disable_fog:
		modes.append("fog_disabled")
	if mat.get("disable_specular_occlusion"):
		modes.append("specular_occlusion_disabled")
	var defines: PackedStringArray = [
		"OV_FILTER " + FILTERS[clampi(mat.texture_filter, 0, FILTERS.size() - 1)],
		"OV_REPEAT " + ("repeat_enable" if mat.texture_repeat else "repeat_disable"),
	]
	var orm: Texture2D = mat.get("orm_texture")
	var flags := {
		"OV_ALBEDO_TEXTURE": mat.albedo_texture != null,
		"OV_METALLIC_TEXTURE": (orm if mat is ORMMaterial3D else mat.metallic_texture) != null,
		"OV_ROUGHNESS_TEXTURE": (orm if mat is ORMMaterial3D else mat.roughness_texture) != null,
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
	for flag in flags:
		if flags[flag]:
			defines.append(flag)
	var code := "shader_type spatial;\nrender_mode %s;\n\n" % ", ".join(modes)
	for d in defines:
		code += "#define %s\n" % d
	return code + '#include "%s"\n' % INCLUDE


static func _copy(mat: BaseMaterial3D, to: ShaderMaterial) -> void:
	var orm := mat is ORMMaterial3D
	var orm_texture: Texture2D = mat.get("orm_texture")
	var params := {
		"albedo": mat.albedo_color,
		"texture_albedo": mat.albedo_texture,
		"metallic": mat.metallic,
		"roughness": mat.roughness,
		"specular": mat.metallic_specular,
		"texture_metallic": orm_texture if orm else mat.metallic_texture,
		"metallic_texture_channel": CHANNELS[2] if orm else CHANNELS[mat.metallic_texture_channel],
		"texture_roughness": orm_texture if orm else mat.roughness_texture,
		"roughness_texture_channel": CHANNELS[1] if orm else CHANNELS[mat.roughness_texture_channel],
		"texture_normal": mat.normal_texture,
		"normal_scale": mat.normal_scale,
		"emission": mat.emission,
		"emission_energy": mat.emission_energy_multiplier,
		"texture_emission": mat.emission_texture,
		"texture_ambient_occlusion": orm_texture if orm else mat.ao_texture,
		"ao_texture_channel": CHANNELS[0] if orm else CHANNELS[mat.ao_texture_channel],
		"ao_light_affect": mat.ao_light_affect,
		"alpha_scissor_threshold": mat.alpha_scissor_threshold,
		"alpha_hash_scale": mat.alpha_hash_scale,
		"uv1_scale": mat.uv1_scale,
		"uv1_offset": mat.uv1_offset,
	}
	var declared := {}
	for u in to.shader.get_shader_uniform_list():
		declared[u["name"]] = true
	for key in params:
		if declared.has(key) and params[key] != null:
			to.set_shader_parameter(key, params[key])
