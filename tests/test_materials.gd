extends "res://tests/suite.gd"
## StandardMaterial3Ds converted to Overcast's twin: cloud shadows and wet ground on materials that
## cannot take the includes.

const Materials = preload("res://addons/overcast/overcast_materials.gd")


func _names(mat: ShaderMaterial) -> Array:
	return mat.shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u["name"])


func test_a_plain_material_converts_and_compiles() -> void:
	var src := StandardMaterial3D.new()
	src.albedo_color = Color(0.2, 0.4, 0.6)
	src.roughness = 0.3
	src.metallic = 0.5
	src.metallic_specular = 0.7
	var to := Materials.convert_material(src) as ShaderMaterial
	assert_ne(to, null, "a ShaderMaterial")
	var names := _names(to)
	assert_true(names.has("albedo") and names.has("puddle_scale"), "it compiles: %s" % [names])
	assert_false(names.has("texture_albedo"), "no texture, no sampler")
	assert_eq(to.get_shader_parameter("albedo"), src.albedo_color)
	assert_eq(to.get_shader_parameter("roughness"), src.roughness)
	assert_eq(to.get_shader_parameter("metallic"), src.metallic)
	assert_eq(to.get_shader_parameter("specular"), src.metallic_specular)


func test_every_supported_feature_compiles_together() -> void:
	var tex := PlaceholderTexture2D.new()
	var src := StandardMaterial3D.new()
	src.albedo_texture = tex
	src.metallic_texture = tex
	src.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	src.roughness_texture = tex
	src.normal_enabled = true
	src.normal_texture = tex
	src.normal_scale = 2.0
	src.emission_enabled = true
	src.emission = Color.RED
	src.emission_texture = tex
	src.ao_enabled = true
	src.ao_texture = tex
	src.vertex_color_use_as_albedo = true
	src.vertex_color_is_srgb = true
	src.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	src.alpha_scissor_threshold = 0.3
	src.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	src.uv1_scale = Vector3(2, 3, 1)
	var to := Materials.convert_material(src) as ShaderMaterial
	var names := _names(to)
	for name in ["texture_albedo", "texture_metallic", "texture_roughness", "texture_normal",
			"texture_emission", "texture_ambient_occlusion", "alpha_scissor_threshold", "uv1_scale"]:
		assert_true(names.has(name), "declares %s" % name)
	assert_eq(to.get_shader_parameter("texture_albedo"), tex)
	assert_eq(to.get_shader_parameter("metallic_texture_channel"), Vector4(0, 0, 1, 0))
	assert_eq(to.get_shader_parameter("normal_scale"), 2.0)
	assert_eq(to.get_shader_parameter("alpha_scissor_threshold"), src.alpha_scissor_threshold)
	assert_eq(to.get_shader_parameter("uv1_scale"), Vector3(2, 3, 1))
	assert_true("filter_nearest" in to.shader.code, "samples as the material did")


func test_render_modes_follow_the_material() -> void:
	var src := StandardMaterial3D.new()
	src.cull_mode = BaseMaterial3D.CULL_DISABLED
	src.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	src.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	src.disable_receive_shadows = true
	var code: String = (Materials.convert_material(src) as ShaderMaterial).shader.code
	for mode in ["cull_disabled", "depth_prepass_alpha", "blend_add", "shadows_disabled"]:
		assert_true(mode in code, mode)
	assert_true("#define OV_ALPHA\n" in code, "draws its alpha")


func test_orm_materials_read_their_channels() -> void:
	var tex := PlaceholderTexture2D.new()
	var src := ORMMaterial3D.new()
	src.orm_texture = tex
	src.ao_enabled = true
	var to := Materials.convert_material(src) as ShaderMaterial
	assert_eq(to.get_shader_parameter("texture_roughness"), tex)
	assert_eq(to.get_shader_parameter("roughness_texture_channel"), Vector4(0, 1, 0, 0))
	assert_eq(to.get_shader_parameter("metallic_texture_channel"), Vector4(0, 0, 1, 0))
	assert_eq(to.get_shader_parameter("ao_texture_channel"), Vector4(1, 0, 0, 0))


func test_what_it_cannot_draw_is_left_alone() -> void:
	var src := StandardMaterial3D.new()
	src.rim_enabled = true
	assert_eq(Materials.unsupported(src), "rim_enabled")
	assert_eq(Materials.convert_material(src), src, "kept as it is")
	var unshaded := StandardMaterial3D.new()
	unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	assert_eq(Materials.convert_material(unshaded), unshaded, "unshaded: no light to shade")
	var shader := ShaderMaterial.new()
	assert_eq(Materials.convert_material(shader), shader, "a ShaderMaterial is the game's own")
	assert_eq(Materials.convert_material(null), null)


func test_shared_materials_stay_shared() -> void:
	var a := StandardMaterial3D.new()
	var b := StandardMaterial3D.new()
	b.albedo_color = Color.RED
	var ta := Materials.convert_material(a) as ShaderMaterial
	assert_eq(Materials.convert_material(a), ta, "one twin per material")
	var tb := Materials.convert_material(b) as ShaderMaterial
	assert_ne(tb, ta)
	assert_eq(tb.shader, ta.shader, "the same features share one shader")


func test_apply_overrides_surfaces_and_leaves_the_mesh() -> void:
	var mesh := BoxMesh.new()
	var src := StandardMaterial3D.new()
	mesh.material = src
	var root := _keep(Node3D.new()) as Node3D
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	var other := MeshInstance3D.new()
	other.mesh = BoxMesh.new()
	other.material_override = StandardMaterial3D.new()
	mi.add_child(other)
	assert_eq(Materials.apply(root, 0.25), 2, "both converted")
	assert_eq(mesh.material, src, "the mesh keeps its material")
	var to := mi.get_surface_override_material(0) as ShaderMaterial
	assert_ne(to, null, "the surface is overridden")
	assert_eq(to.get_shader_parameter("puddle_scale"), 0.25)
	assert_true(other.material_override is ShaderMaterial, "an override is replaced in place")
	assert_eq(Materials.apply(root, 0.25), 0, "once")


func test_the_include_compiles_on_its_own() -> void:
	var shader := Shader.new()
	shader.code = 'shader_type spatial;\n#define OV_FILTER filter_linear\n#define OV_REPEAT repeat_enable\n#include "%s"\n' % Materials.INCLUDE
	var names := shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u["name"])
	assert_true(names.has("albedo"), "compiles: %s" % [names])
