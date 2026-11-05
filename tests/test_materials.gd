extends "res://tests/suite.gd"
## StandardMaterial3Ds converted to Overcast's twin: cloud shadows and wet ground on materials that
## cannot take the includes.

const Materials = preload("res://addons/overcast/overcast_materials.gd")


func test_a_plain_material_converts_and_compiles() -> void:
	var src := StandardMaterial3D.new()
	src.albedo_color = Color(0.2, 0.4, 0.6)
	src.roughness = 0.3
	src.metallic = 0.5
	src.metallic_specular = 0.7
	var to := Materials.convert_material(src) as ShaderMaterial
	assert_ne(to, null, "a ShaderMaterial")
	var names := _uniform_names(to.shader)
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
	var names := _uniform_names(to.shader)
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
	var names := _uniform_names(shader)
	assert_true(names.has("albedo"), "compiles: %s" % [names])


func test_a_twin_leads_back_to_its_source() -> void:
	var src := StandardMaterial3D.new()
	var to := Materials.convert_material(src)
	assert_eq(Materials.source_of(to), src)
	assert_eq(Materials.source_of(src), src, "not a twin: itself")
	assert_eq(Materials.source_of(null), null)
	# The way to change one: edit the source's copy, convert that.
	var faded := Materials.source_of(to).duplicate() as StandardMaterial3D
	faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var again := Materials.convert_material(faded) as ShaderMaterial
	assert_true("#define OV_ALPHA\n" in again.shader.code, "the change shows")


func test_a_twin_nothing_draws_with_is_let_go() -> void:
	var src := StandardMaterial3D.new()
	var id := Materials.convert_material(src).get_instance_id()
	assert_eq(instance_from_id(id), null, "freed with its last user")
	assert_ne(Materials.convert_material(src), null, "and made again on asking")


func test_watch_converts_what_spawns_after_its_ready() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var root := _keep(Node3D.new()) as Node3D
	tree.root.add_child(root)
	Materials.watch(root)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = StandardMaterial3D.new()
	root.add_child(mi)
	# As a spawn's _ready would: the game sets its material after it enters the tree.
	var skin := StandardMaterial3D.new()
	mi.material_override = skin
	assert_eq(mi.material_override, skin, "not yet: the frame is not over")
	await tree.process_frame
	assert_eq(Materials.source_of(mi.material_override), skin, "converted, from what the game set")
	root.remove_child(mi)
	tree.root.remove_child(root)
	var later := MeshInstance3D.new()
	later.material_override = StandardMaterial3D.new()
	tree.root.add_child(later)
	await tree.process_frame
	assert_true(later.material_override is StandardMaterial3D, "a root that has left stops watching")
	later.free()
	mi.free()


func test_a_source_edited_in_place_converts_to_the_edit() -> void:
	var src := StandardMaterial3D.new()
	var to := Materials.convert_material(src) as ShaderMaterial
	src.albedo_color = Color.RED
	src.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var again := Materials.convert_material(src) as ShaderMaterial
	assert_eq(again.get_shader_parameter("albedo"), Color.RED, "the new colour")
	assert_true("#define OV_ALPHA\n" in again.shader.code, "and the new switches")
	assert_eq(again, to, "still the one twin, so what draws with it changes too")
