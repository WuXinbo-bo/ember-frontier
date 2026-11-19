extends RefCounted
## Byte-identical existing PNGs; native renderer sampling, no generated textures.
var _cache: Dictionary = {}
var _manifest: Dictionary = {}
var missing: Array = []
var _terrain_cache: Dictionary = {}
const GroundSurface = preload("res://scripts/environment/ground_surface.gdshader")
const ContactSurface = preload("res://scripts/environment/contact_surface.gdshader")
const ShoulderSurface = preload("res://scripts/environment/shoulder_surface.gdshader")
const GROUND_VARIANTS = {"grass_top":"grass_top_detail","gravel":"gravel_fine","soil_top":"soil_top_fine"}
const GROUND_DETAIL_MIP_BIAS := 0.75
const Quality=preload("res://scripts/environment/environment_quality.gd")
var quality:=Quality.new()
var _world_style:=""
var _content_version:int=0

func set_world_style(generator_version:String,content_version:int=0)->void:
	if _world_style==generator_version and _content_version==content_version:return
	_world_style=generator_version;_content_version=content_version;_terrain_cache.clear()

func _terrain_source(id:String,face:String,voxel_material:int=-1)->String:
	# Select from the saved content lock, never the current default generator.
	# Road cuttings retain their old source; tops/shoulders keep their original
	# earth image. Unknown callers and content versions use the compatible path.
	if _world_style=="factory-country-1" and _content_version in [8,9,10] and face=="side" and id=="soil_side" and voxel_material in [1,2]:
		return "natural_soil_side"
	return "soil_side" if id=="soil_top" else id

func _init() -> void:
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/environment-materials.json"))
	if rows is Array:
		for row in rows: _manifest[row.id] = row

func material(id: String) -> StandardMaterial3D:
	if _cache.has(id): return _cache[id]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "C:"+id
	mat.roughness = 0.96
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.texture_repeat = true
	var row: Dictionary = _manifest.get(id,{})
	if not row.is_empty():
		var texture: Texture2D
		if ResourceLoader.exists(row.resource): texture = load(row.resource)
		else:
			var source := Image.load_from_file(row.resource)
			if source != null: texture = ImageTexture.create_from_image(source)
		if texture != null: mat.albedo_texture = texture
		else: missing.append(id)
	elif id != "dry_grass": missing.append(id)
	if mat.albedo_texture != null and row.get("metres") is Array:
		# Existing imports had mipmaps/generate=false: a mipmap sampler alone
		# cannot fix minification noise. Native imports supply the chain after
		# A's next import; this native Image fallback also covers first-use PNGs.
		var image := mat.albedo_texture.get_image()
		if image != null and not image.has_mipmaps():
			image.generate_mipmaps()
			mat.albedo_texture = ImageTexture.create_from_image(image)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if id in ["grass_edge","grass_corner","leaves","moss_edge","low_cover_atlas"]:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.4
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if id == "low_cover_atlas":
		# The four cells retain their 24px transparent borders and 8px colour
		# protection. No repeat or atlas-wide mip chain that mixes distant cells.
		mat.texture_repeat = false
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if id == "dry_grass": mat.albedo_color = Color("8c9462")
	_cache[id] = mat
	return mat

func manifest() -> Dictionary: return _manifest.duplicate(true)

func terrain_preparation(data:Dictionary)->Array:
	# One existing texture/material dependency per cooperative unit. Otherwise
	# first mesh upload silently includes several synchronous PNG/mip loads.
	# No bulk preload, new assets, worker-side Resource or material substitution.
	var requests:Dictionary={}
	for g:Dictionary in data.groups.values():
		var top:bool=g.normals[0].y>0.5
		var id:String="soil_top" if top and g.material==2 else g.texture
		if _world_style in ["rural-3","factory-country-1"] and id=="stone":
			var key:String="r01_weathered_stone" if top else "r02_fractured_stone"
			requests["quality:"+key]={"kind":"quality","id":key}
			continue
		var source:String=_terrain_source(id,"top" if top else "side",g.material)
		requests["base:"+source]={"kind":"base","id":source}
		if top and GROUND_VARIANTS.has(id):
			var variant:String=GROUND_VARIANTS[id];requests["base:"+variant]={"kind":"base","id":variant}
	return requests.values()

func ground_preparation(contact_quads:int,field_groups:Dictionary,shoulder_groups:Dictionary)->Array:
	# Dependencies come from actual exposed/supported arrays, never an eager
	# catalogue preload. The existing terrain queue prepares one image per unit.
	var requests:Dictionary={}
	if contact_quads>0:requests["base:soil_top_fine"]={"kind":"base","id":"soil_top_fine"}
	for id:String in field_groups:requests["quality:"+id]={"kind":"quality","id":id}
	var ids:Array=shoulder_groups.keys();ids.sort()
	for neighbor:int in ids:
		var earth:String={2:"soil_top",4:"dirt_road",6:"gravel"}[neighbor]
		var source:String="soil_side" if earth=="soil_top" else earth
		for id:String in ["grass_top","grass_top_detail","grass_edge",source,GROUND_VARIANTS.get(earth,source)]:
			requests["base:"+id]={"kind":"base","id":id}
	return requests.values()

func prepare_terrain_input(request:Dictionary)->void:
	# Engine texture decoding/mip creation remains one non-preemptible native
	# operation. Measure its own peak instead of claiming it fits a hard4ms.
	if request.kind=="quality":quality.material(request.id)
	else:material(request.id)

func terrain_material(id: String,face: String="top",voxel_material:int=-1) -> Material:
	var source_id:String=_terrain_source(id,face,voxel_material)
	var key := id+":"+face+":"+source_id
	if _terrain_cache.has(key): return _terrain_cache[key]
	if _world_style in ["rural-3","factory-country-1"] and id=="stone":
		var rock:=quality.material("r01_weathered_stone" if face=="top" else "r02_fractured_stone")
		_terrain_cache[key]=rock;return rock
	# soil_top is a render-only surface alias, not a new saved voxel material.
	# The isotropic original soil source supplies its coarse earth texture;
	# the dedicated fine loose-soil image supplies its top variation, not road.
	var base := material(source_id)
	var metres: Variant = _manifest.get(source_id,{}).get("metres",[1.6,1.6])
	var scale := Vector2(float(metres[0]),float(metres[1]))
	var result: Material
	if face=="top" and id in ["grass_top","dirt_road","gravel","soil_top"] and base.albedo_texture != null:
		var ground := ShaderMaterial.new()
		ground.resource_name = "C:metre-ground:"+id
		ground.shader = GroundSurface
		ground.set_shader_parameter("ground_texture",base.albedo_texture)
		ground.set_shader_parameter("sample_metres",scale)
		ground.set_shader_parameter("detail_mip_bias",GROUND_DETAIL_MIP_BIAS)
		if GROUND_VARIANTS.has(id):
			var variant := material(GROUND_VARIANTS[id])
			ground.set_shader_parameter("variant_texture",variant.albedo_texture)
			ground.set_shader_parameter("use_variant",variant.albedo_texture!=null)
		result = ground
	else:
		var native := base.duplicate() as StandardMaterial3D
		native.uv1_scale = Vector3(1.0/scale.x,1.0/scale.y,1)
		result = native
	_terrain_cache[key] = result
	return result

func contact_material() -> ShaderMaterial:
	if _terrain_cache.has("foundation-contact"): return _terrain_cache["foundation-contact"]
	var mat := ShaderMaterial.new()
	mat.resource_name = "C:derived-foundation-earth"
	mat.shader = ContactSurface
	mat.set_shader_parameter("soil_texture",material("soil_top_fine").albedo_texture)
	_terrain_cache["foundation-contact"] = mat
	return mat

func shoulder_material(neighbor_material: int) -> ShaderMaterial:
	# Only actual exposed grass/earth adjacency calls this. No new terrain fact,
	# images or second world buffer. Both endpoints reuse terrain's exact sampler.
	var key := "shoulder:"+str(neighbor_material)
	if _terrain_cache.has(key): return _terrain_cache[key]
	var earth_id: String = {2:"soil_top",4:"dirt_road",6:"gravel"}[neighbor_material]
	var source_id := "soil_side" if earth_id=="soil_top" else earth_id
	var mat := ShaderMaterial.new()
	mat.resource_name = "C:derived-shoulder:"+earth_id
	mat.shader = ShoulderSurface
	mat.set_shader_parameter("grass_texture",material("grass_top").albedo_texture)
	mat.set_shader_parameter("grass_variant",material("grass_top_detail").albedo_texture)
	mat.set_shader_parameter("edge_texture",material("grass_edge").albedo_texture)
	mat.set_shader_parameter("earth_texture",material(source_id).albedo_texture)
	var variant_id: String = GROUND_VARIANTS.get(earth_id,source_id)
	mat.set_shader_parameter("earth_variant",material(variant_id).albedo_texture)
	mat.set_shader_parameter("earth_use_variant",GROUND_VARIANTS.has(earth_id))
	mat.set_shader_parameter("grass_mip_bias",GROUND_DETAIL_MIP_BIAS)
	mat.set_shader_parameter("earth_mip_bias",GROUND_DETAIL_MIP_BIAS)
	var grass_scale: Array = _manifest.grass_top.metres
	var earth_scale: Array = _manifest[source_id].metres
	mat.set_shader_parameter("grass_metres",Vector2(grass_scale[0],grass_scale[1]))
	mat.set_shader_parameter("earth_metres",Vector2(earth_scale[0],earth_scale[1]))
	_terrain_cache[key] = mat
	return mat
