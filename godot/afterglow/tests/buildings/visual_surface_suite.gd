extends "res://tests/buildings/family_generation_suite.gd"
## Actual assembler/view/Texture2D evidence; not Metal/OS visual acceptance.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
var surface_rows:Array=[]
var furniture_rows:Array=[]

func furniture_geometry(view:Node3D)->void:
	var count:=0
	for piece:Dictionary in building.structures().instances:
		var definition:Dictionary=building.geometry.definition(piece)
		if definition.kind not in ["cabinet","workbench"] or float(piece.hp)<=0:continue
		var actual:Node3D=view.objects.get(piece.id)
		if definition.id!="cabinet":
			# kind=cabinet also classifies real kitchen/table/chair/desk for
			# gameplay. Never turn these semantic classes into storage cupboards.
			var source:Dictionary=view.manifest.models[definition.assetId]
			expect(piece.id+" keeps its unchanged dedicated GLB and original UV transform",not actual.has_node("CabinetJoinery") and not actual.has_node("SourceModel") and actual.transform==view.xform(piece) and FileAccess.get_sha256(source.resource)==source.sha256,{"asset":definition.assetId,"rendered":str(view.model_bounds(actual))})
			continue
		var expected:AABB=building.geometry.boxes(piece)[0]
		var bounds:AABB=view.model_bounds(actual)
		expect(piece.id+" reused real model fills actual collision/support volume",bounds.position.distance_to(expected.position)<0.0001 and bounds.size.distance_to(expected.size)<0.0001,{"actual":str(bounds),"expected":str(expected)})
		var detail:MeshInstance3D=actual.get_node("CabinetJoinery")
		var canonical:AABB=Geometry.aabb(definition.solids[0])
		var contained:=true;var metric:=true;var surfaces:Array=[]
		for s:int in detail.mesh.get_surface_count():
			var arrays:Array=detail.mesh.surface_get_arrays(s)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var material:Material=detail.mesh.surface_get_material(s)
			var id:=""
			for key:String in view.materials:
				if view.materials[key]==material:id=key;break
			if id.is_empty():metric=false;continue
			var meters:float=view.manifest.textures[id].tile_meters
			for v:Vector3 in vertices:
				if not canonical.grow(0.0001).has_point(v):contained=false
			for i:int in range(0,indices.size(),3):
				for edge:int in 3:
					var a:int=indices[i+edge];var b:int=indices[i+(edge+1)%3]
					if absf(vertices[a].distance_to(vertices[b])-uvs[a].distance_to(uvs[b])*meters)>0.00001:metric=false
			surfaces.append(id)
		expect(piece.id+" joinery stays inside existing collision and uses real metre surfaces",contained and metric and surfaces.size()==3,{"contained":contained,"metric":metric,"surfaces":surfaces})
		# Explicit derived pose fixtures, not free gameplay moves or new facts.
		for turn:int in 4:
			var fixture:=piece.duplicate(true);fixture.quarterTurn=turn;fixture.position.y+=0.5
			var moved:Node3D=view.furniture(fixture,definition)
			var moved_bounds:AABB=view.model_bounds(moved);var moved_expected:AABB=building.geometry.boxes(fixture)[0]
			expect(piece.id+" derived model remains aligned at turn "+str(turn),moved_bounds.position.distance_to(moved_expected.position)<0.0001 and moved_bounds.size.distance_to(moved_expected.size)<0.0001)
			moved.free()
		furniture_rows.append({"id":piece.id,"rendered":str(bounds),"authoritative":str(expected),"materials":surfaces})
		count+=1
	expect("actual generated settlement contains native movable cabinets",count>0,count)

func texture_chains(view:Node3D)->void:
	for id:String in view.manifest.textures:
		var entry:Dictionary=view.manifest.textures[id]
		# New source PNGs may deliberately await A's one official import.
		# Exercise the same native raw-image fallback, never run an importer here.
		var source:Texture2D=view.texture(entry.resource,false)
		var original:Image=source.get_image()
		# The formal view intentionally loads new surfaces on actual use. This
		# catalogue audit explicitly requests each surface rather than requiring
		# the runtime to eagerly allocate all future material families.
		var material:StandardMaterial3D=view.material(id)
		var actual:Image=material.albedo_texture.get_image()
		var repeating:bool=entry.uv.get("repeat",true)
		var base:Image=actual.duplicate();base.clear_mipmaps()
		var original_base:Image=original.duplicate();original_base.clear_mipmaps()
		expect(id+" actual base pixels and metre/atlas UV conventions stay unchanged",base.get_format()==original_base.get_format() and base.get_size()==original_base.get_size() and base.get_data()==original_base.get_data())
		if repeating:
			expect(id+" actual repeated surface supplies a complete native mip chain",actual.has_mipmaps() and actual.get_mipmap_count()==floori(log(float(maxi(actual.get_width(),actual.get_height())))/log(2.0)),{"source_had_mips":original.has_mipmaps(),"actual_mips":actual.get_mipmap_count(),"size":str(actual.get_size())})
		else:
			expect(id+" protected atlas/decal retains native source and no invented cross-cell chain",material.albedo_texture==source and actual.has_mipmaps()==original.has_mipmaps())
		expect(id+" repeated texture queries reuse the same real resource",view.texture(entry.resource,repeating)==material.albedo_texture)
		surface_rows.append({"id":id,"source_mips":original.get_mipmap_count(),"actual_mips":actual.get_mipmap_count(),"repeating":repeating,"filter":material.texture_filter})

func run()->void:
	var started:=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(713,Building.generation_profiles()))
	expect("actual generated world prepares for texture evidence",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(started);return
	var host:=Client.new();var assembled:Dictionary=host._assemble(prepared.capture)
	expect("formal full assembler supplies actual B renderer",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings
	var before:=runtime.capture_checkpoint()
	var view:Node3D=building.create_view({"runtime":runtime})
	var original_pngs:Dictionary={}
	for entry:Dictionary in view.manifest.textures.values():original_pngs[entry.resource]=FileAccess.get_sha256(entry.resource)
	texture_chains(view)
	furniture_geometry(view)
	var unchanged:=true
	for path:String in original_pngs:
		if FileAccess.get_sha256(path)!=original_pngs[path]:unchanged=false
	expect("native image adaptation never writes original PNG resources",unchanged)
	expect("actual rendered materials never alter world stocks clocks or permissions",preload("res://scripts/world/world_data.gd").json_equal(before,runtime.capture_checkpoint()))
	print("ACTUAL_BUILDING_TEXTURE_CHAINS "+JSON.stringify(surface_rows))
	print("ACTUAL_CABINET_GEOMETRY "+JSON.stringify(furniture_rows))
	view.free();host.free();finish(started)
