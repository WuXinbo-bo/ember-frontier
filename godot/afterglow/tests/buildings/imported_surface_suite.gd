extends "res://tests/buildings/domain_suite.gd"
## Post-A-import resource check only. Never import/export, open an app, or
## substitute source PNGs for a missing actual CompressedTexture2D resource.
const View=preload("res://scripts/buildings/building_view.gd")
const Dressing=preload("res://scripts/buildings/building_dressing.gd")
const DressingGeometry=preload("res://scripts/buildings/dressing_geometry.gd")

func pixels(texture:Texture2D)->PackedByteArray:
	if texture==null:return PackedByteArray()
	var original:Image=texture.get_image()
	if original==null:return PackedByteArray()
	var image:Image=original.duplicate()
	if image.is_compressed() and image.decompress()!=OK:return PackedByteArray()
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	return image.get_data()

func run()->void:
	var started:=Time.get_ticks_msec()
	var view:=View.new();view.manifest=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	var ids:Array=[];var rows:Array=[]
	for family:String in ["brick","plaster","wood","roof","zinc","paint"]:
		for state:String in ["intact","aged","damaged","repaired","damage_detail","repair_detail"]:ids.append("b_"+family+"_"+state)
	ids.append("straw_fibres")
	for id:String in ids:
		var entry:Dictionary=view.manifest.textures[id];var path:String=entry.resource
		var remap:=ConfigFile.new();var read:int=remap.load(path+".import")
		var imported_path:String=remap.get_value("remap","path","") if read==OK else ""
		expect("actual A-generated texture import/remap exists "+id,read==OK and remap.get_value("remap","importer","")=="texture" and FileAccess.file_exists(imported_path) and ResourceLoader.exists(path),path)
		var imported:Texture2D=load(path)
		expect("actual native compressed resource is loaded without source fallback "+id,imported is CompressedTexture2D and imported.resource_path==path)
		if imported==null:continue
		var material:StandardMaterial3D=view.material(id)
		var actual:Texture2D=material.albedo_texture if material!=null else null
		var direct_pixels:=pixels(imported);var consumer_pixels:=pixels(actual)
		expect("real consumer preserves exact imported base pixels "+id,not direct_pixels.is_empty() and direct_pixels==consumer_pixels and actual.get_size()==imported.get_size())
		expect("approved source bytes remain identical "+id,FileAccess.get_sha256(path)==entry.sha256)
		var tiled:bool=entry.uv.get("repeat",true)
		expect("consumer uses intended pixel sampler/mips/alpha "+id,material!=null and material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS and material.texture_repeat==tiled and ((tiled and actual.get_image().has_mipmaps()) or (not tiled and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(material.alpha_scissor_threshold,0.25))))
		expect("native imported resource remains unmodified and material remains shared "+id,pixels(imported)==direct_pixels and view.material(id)==material)
		rows.append({"id":id,"resource":path,"imported_class":imported.get_class(),"consumer_class":actual.get_class(),"size":str(actual.get_size()),"consumer_mipmaps":actual.get_image().has_mipmaps(),"derived_mips":actual!=imported,"approved_source_sha256":entry.sha256})
	# Verify c08 has a real mesh consumer, not just a loaded manifest entry.
	var profiles:Array=Dressing.profiles().filter(func(p:Dictionary)->bool:return p.id=="haystack")
	expect("canonical haystack profile exists",profiles.size()==1)
	if profiles.size()==1:
		var entity:Dictionary=Dressing.entity_for(profiles[0],{"id":"fixture:imported-hay","profile_id":"haystack","position":{"x":32,"y":0,"z":40},"quarter_turn":0,"state":"aged"},"RH-HOME")
		var root:Node3D=DressingGeometry.create(entity,view);var pending:Array=[root];var straw_vertices:=0;var rope:=false
		while not pending.is_empty():
			var node:Node=pending.pop_back();pending.append_array(node.get_children())
			if not node is MeshInstance3D:continue
			for surface:int in node.mesh.get_surface_count():
				var material:Material=node.get_active_material(surface)
				if material==view.materials.get("straw_fibres"):straw_vertices+=node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
				if material==view.materials.get("hemp_rope"):rope=true
		expect("all nine actual straw bales use real imported c08 consumer",straw_vertices==9*24 and rope,{"straw_vertices":straw_vertices,"rope":rope})
		root.free()
	view.free()
	print("ACTUAL_IMPORTED_BUILDING_RESOURCES "+JSON.stringify(rows))
	finish(started)
