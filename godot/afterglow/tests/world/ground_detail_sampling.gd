extends SceneTree
## Native resource/mesh contract check. Not Metal rendering or a VA screenshot.
const Materials = preload("res://scripts/environment/environment_materials.gd")
const Generator = preload("res://scripts/world/settlement_generator.gd")
const State = preload("res://scripts/world/world_state.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Mesher = preload("res://scripts/terrain/terrain_mesher.gd")
var checks: Array=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func hash_file(path: String) -> String:
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(FileAccess.get_file_as_bytes(path));return hash.finish().hex_encode()
func run() -> void:
	var materials := Materials.new()
	var exact := true;var mipmaps := true
	for row in materials.manifest().values():
		exact=exact and hash_file(row.resource)==row.sha256
		if row.metres is Array:
			var source: Texture2D=materials.material(row.id).albedo_texture
			mipmaps=mipmaps and source!=null and source.get_image().has_mipmaps()
	check("all sixteen source images remain byte identical",exact and materials.manifest().size()==16)
	check("metre textures expose actual native mip chains",mipmaps)
	var grass: ShaderMaterial=materials.terrain_material("grass_top")
	var ground_uniforms: Array=grass.shader.get_shader_uniform_list().map(func(row: Dictionary)->String:return row.name)
	check("ground shader native resource exposes explicit detail control",ground_uniforms.has("detail_mip_bias"),ground_uniforms)
	for id in ["grass_top","dirt_road","gravel","soil_top"]:
		var top: ShaderMaterial=materials.terrain_material(id)
		check("same metre scale and bounded native detail bias "+id,top.get_shader_parameter("sample_metres")==Vector2(1.6,1.6) and top.get_shader_parameter("detail_mip_bias")==0.75)
	for material_id in [2,4,6]:
		var shoulder: ShaderMaterial=materials.shoulder_material(material_id)
		var earth_id: String={2:"soil_top",4:"dirt_road",6:"gravel"}[material_id]
		var earth: ShaderMaterial=materials.terrain_material(earth_id)
		check("shoulder joins exact opaque endpoint texture/scale/bias "+str(material_id),shoulder.get_shader_parameter("grass_texture")==grass.get_shader_parameter("ground_texture") and shoulder.get_shader_parameter("earth_texture")==earth.get_shader_parameter("ground_texture") and shoulder.get_shader_parameter("grass_metres")==grass.get_shader_parameter("sample_metres") and shoulder.get_shader_parameter("earth_metres")==earth.get_shader_parameter("sample_metres") and shoulder.get_shader_parameter("grass_mip_bias")==grass.get_shader_parameter("detail_mip_bias") and shoulder.get_shader_parameter("earth_mip_bias")==earth.get_shader_parameter("detail_mip_bias"))
	check("vertical excavated soil retains native directional material",materials.terrain_material("soil_side","side") is StandardMaterial3D)
	var cover: StandardMaterial3D=materials.material("low_cover_atlas")
	check("alpha foliage atlas keeps exact crop/filter/scissor semantics",cover.texture_filter==BaseMaterial3D.TEXTURE_FILTER_LINEAR and not cover.texture_repeat and cover.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(cover.alpha_scissor_threshold,0.4),{"native_threshold":cover.alpha_scissor_threshold})
	var draft: Dictionary=Generator.draft_region(713,Vector2i(1,0))
	var world := State.new()
	var snapshot := {"schemaVersion":1,"worldId":"rural:v2:713","seed":713,"generatorVersion":"rural-2","revision":0,"config":Data.DEFAULT_CONFIG.duplicate(true),"regions":{draft.region.id:draft.region},"chunks":draft.chunks,"entities":draft.entities,"retiredEntityIds":[],"extensions":{"generation:R2:1:0":draft.plan},"receipts":{}}
	check("actual nonflat authoritative half-metre region loads",world.load_snapshot(snapshot).ok and world.config().cellSize==0.5)
	var facts: Dictionary=world.snapshot()
	var uv_ok := true;var surfaces := 0
	# Across the actual east region's neighbouring columns and vertical layers.
	for key in ["11,-1,3","12,-1,3","11,0,3","12,0,3"]:
		var data: Dictionary=Mesher.build(world,key)
		var mesh: ArrayMesh=Mesher.mesh(data,materials)
		surfaces+=mesh.get_surface_count()
		for surface in mesh.get_surface_count():
			var arrays: Array=mesh.surface_get_arrays(surface)
			for i in arrays[Mesh.ARRAY_VERTEX].size():
				var p: Vector3=arrays[Mesh.ARRAY_VERTEX][i]
				var n: Vector3=arrays[Mesh.ARRAY_NORMAL][i]
				var uv: Vector2=arrays[Mesh.ARRAY_TEX_UV][i]
				uv_ok=uv_ok and uv.is_equal_approx(Vector2(p.x,p.z) if absf(n.y)>0.5 else Vector2(p.z if absf(n.x)>0.5 else p.x,p.y))
	check("half-metre cell/greedy borders retain world-metre UV without tile resets",uv_ok and surfaces>0,{"surfaces":surfaces})
	check("material correction cannot change saved cells/entities/plan",Data.json_equal(facts,world.snapshot()))
	var failed := checks.filter(func(row: Dictionary)->bool:return not row.ok).size()
	var result := {"checks":checks,"failed":failed,"scope":"native shader resources/material and actual voxel mesh contracts; formal Metal/render/VA pending","detail_mip_bias":0.75,"asset_bytes_changed":false,"metre_scale_changed":false}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if failed else 0)
