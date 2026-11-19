extends "res://tests/world/village_contours.gd"
const Broad=preload("res://scripts/world/broad_terraces.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
const TerrainView=preload("res://scripts/terrain/terrain_view.gd")
const Mesher=preload("res://scripts/terrain/terrain_mesher.gd")

func signature(world:RefCounted,id:String)->String:
	var region:Dictionary=world.region(id);var keys:Array=world.chunk_keys();keys.sort()
	var rows:Array=[]
	for key:String in keys:
		var c:Dictionary=world.chunk(key)
		if Data.contains(region.bounds,{"x":(c.coord.x+0.5)*8,"y":0,"z":(c.coord.z+0.5)*8}):rows.append([key,PackedInt32Array(c.cells)])
	var entities:Array=world.entities(id);entities.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.id<b.id)
	for e:Dictionary in entities:e.erase("revision")
	return var_to_bytes([rows,entities,world.extension("generation:"+id)]).hex_encode().sha256_text()

func metrics(world:RefCounted,id:String)->Dictionary:
	var region:Dictionary=world.region(id);var ox:float=region.bounds.min.x;var oz:float=region.bounds.min.z
	var h:=PackedInt32Array();h.resize(128*128)
	for z in 128:
		for x in 128:h[x+128*z]=roundi(world.surface_height(ox+(x+0.5)*0.5,oz+(z+0.5)*0.5)*2)
	var singleton:=0;var short_treads:=0;var treads:=0;var short_edges:=0;var all_edges:=0;var long_edges:=0;var longest:=0;var max_neighbor:=0
	for z in range(1,127):
		for x in range(1,127):
			var equal:=false
			for delta:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if h[x+128*z]==h[x+delta.x+128*(z+delta.y)]:equal=true
			if not equal:singleton+=1
	for axis in 2:
		for cross in 128:
			var last:int=h[cross*128] if axis==0 else h[cross]
			var length:=0
			for along in 129:
				var value:int=(h[along+cross*128] if axis==0 else h[cross+along*128]) if along<128 else -9999
				if value!=last:
					treads+=1
					if length<4:short_treads+=1
					length=0;last=value
				length+=1
		for cross in range(1,128):
			var last:Variant=null;var length:=0
			for along in 129:
				var pair:Variant=null
				if along<128:
					var a:Vector2i=Vector2i(cross-1,along) if axis==0 else Vector2i(along,cross-1)
					var b:Vector2i=a+(Vector2i.RIGHT if axis==0 else Vector2i.DOWN)
					max_neighbor=maxi(max_neighbor,absi(h[a.x+128*a.y]-h[b.x+128*b.y]))
					if h[a.x+128*a.y]!=h[b.x+128*b.y]:pair=Vector2i(h[a.x+128*a.y],h[b.x+128*b.y])
				if pair!=last:
					if last!=null:
						all_edges+=length;longest=maxi(longest,length)
						if length<4:short_edges+=length
						if length>=16:long_edges+=length
					length=0;last=pair
				if pair!=null:length+=1
	var values:Array=Array(h)
	return {"min_y":values.min()*0.5,"max_y":values.max()*0.5,"single_columns":singleton,"axis_treads_lt2m":short_treads,"axis_treads":treads,"riser_segments_lt2m_m":short_edges*0.5,"riser_total_m":all_edges*0.5,"riser_ge8m_m":long_edges*0.5,"longest_riser_m":longest*0.5,"max_axis_neighbor_step_m":max_neighbor*0.5,"heights":values}

func add_region(world:RefCounted,coord:Vector2i,profiles:Array)->Dictionary:
	var input:Dictionary=Rural.region_generation_input(world,profiles)
	var draft:Dictionary=Rural.draft_region_request(input,coord) if input.ok else input
	var prepared:Dictionary=Rural.prepare_region_draft(world,draft,world.get_revision()) if draft.ok else draft
	if not prepared.ok:return prepared
	var tx:Dictionary=world.prepare_changes(prepared.world_changes,world.get_revision())
	if not tx.ok:return tx
	var committed:Dictionary=world.commit_prepared(tx.capability)
	return {"ok":committed.ok,"draft":draft,"prepared":prepared}

func run()->void:
	var args:=OS.get_cmdline_user_args();var folder:String=args[0].get_base_dir()
	var baseline:String=args[1];var profiles:Array=Building.generation_profiles()
	var contract:Dictionary=Contract.fresh(profiles).contract.duplicate(true);contract.landscape_model=Broad.MODEL
	check("explicit v5 resolves while fresh default remains v4",Contract.resolve(contract,profiles).ok and Contract.fresh(profiles).contract.landscape_model=="village-contours-v4")
	check("negative positive quarter-metre ties remain one half-metre step",floori(-0.25*2+0.5)==0 and floori(0.25*2+0.5)==1)
	var rows:Array=[];var primary:RefCounted;var primary_facts:Dictionary={};var candidate_sources:Array=[]
	for seed:int in [12,713]:
		var old:Dictionary=FileAccess.open(baseline+"/seed%d-source.var"%seed,FileAccess.READ).get_var()
		var repeated_old:Dictionary=Landscape.generate(seed,profiles)
		check("all old v4 world fields remain exactly unchanged "+str(seed),var_to_bytes(old)==var_to_bytes(repeated_old))
		var start:=Time.get_ticks_usec();var source:Dictionary=Landscape.generate(seed,profiles,contract)
		var generate_ms:float=(Time.get_ticks_usec()-start)/1000.0
		check("full opt-in v5 generator succeeds "+str(seed),source.has("chunks"),source.get("reason"))
		if not source.has("chunks"):continue
		check("same seed/version/coordinate repeats exact source "+str(seed),var_to_bytes(source)==var_to_bytes(Landscape.generate(seed,profiles,contract)))
		candidate_sources.append(raster_digest(source))
		var old_world:=State.new();var world:=State.new()
		check("actual sole world accepts both models "+str(seed),old_world.load_snapshot(old).ok and world.load_snapshot(source).ok)
		var row:Dictionary={"seed":seed,"generate_ms":generate_ms,"raster_sha256":raster_digest(source),"regions":{}}
		for id:String in ["RH-HOME","RH-VILLAGE"]:
			var before:Dictionary=metrics(old_world,id);var after:Dictionary=metrics(world,id)
			var changed:=0
			for i in after.heights.size():
				if before.heights[i]!=after.heights[i]:changed+=1
			before.erase("heights");after.erase("heights")
			row.regions[id]={"before":before,"after":after,"changed_columns":changed}
			var plan:Dictionary=world.extension("generation:"+id)
			check("v5 actual raster retains nonflat broad treads "+str(seed)+id,after.max_y-after.min_y>=1.5 and after.axis_treads_lt2m==0 and after.single_columns==0 and after.max_axis_neighbor_step_m<=0.5,after)
			check("explicit plan revision and finite immutable grid "+str(seed)+id,plan.landscape_model==Broad.MODEL and plan.height.terrain_revision==5 and plan.height.broad_surface.height_half_metres.size()==35*35)
			var roots_ok:=true;var patches_ok:=true
			for tree:Dictionary in plan.resource_sites:
				for dx:float in [-0.35,0,0.35]:
					for dz:float in [-0.35,0,0.35]:roots_ok=roots_ok and world.surface_height(tree.position.x+dx,tree.position.z+dz)==tree.position.y
			for patch:Dictionary in plan.ecology.patches:
				for dx:float in [-float(patch.footprint[0])*0.5,float(patch.footprint[0])*0.5]:
					for dz:float in [-float(patch.footprint[1])*0.5,float(patch.footprint[1])*0.5]:patches_ok=patches_ok and world.surface_height(patch.position.x+dx,patch.position.z+dz)==patch.position.y
			check("real tree roots and ground-card footprint touch one true tread "+str(seed)+id,roots_ok and patches_ok,{"roots":roots_ok,"patches":patches_ok,"trees":plan.resource_sites.size(),"patches_count":plan.ecology.patches.size()})
			row.regions[id].content={"trees":plan.resource_sites.size(),"patches":plan.ecology.patches.size(),"fields":plan.landforms.filter(func(l:Dictionary)->bool:return l.use=="field").size(),"dressing":plan.dressing.size()}
		start=Time.get_ticks_usec();var assembled:Dictionary=Assembly.prepare(source)
		row.assembly_ms=(Time.get_ticks_usec()-start)/1000.0
		check("actual formal A/B complete assembly accepts new terrain "+str(seed),assembled.ok,assembled.get("reason"))
		if not assembled.ok:rows.append(row);continue
		world=State.new();world.load_snapshot(assembled.capture.world)
		var runtime:=Runtime.new();var building:=Building.new()
		var configured:Dictionary=runtime.configure({"world":world,"facts":assembled.capture.facts,"source":assembled.capture.source,"services":{"buildings":building,"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new()}})
		check("same production runtime accepts opening facts "+str(seed),configured.ok,configured)
		if not configured.ok:rows.append(row);continue
		var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
		check("full native capture encodes without live slot "+str(seed),encoded.ok,encoded.get("reason"))
		if encoded.ok:
			FileAccess.open(folder+"/seed%d-v5.native.json"%seed,FileAccess.WRITE).store_string(encoded.text)
			var decoded:Dictionary=Store.decode(encoded.text);var native:=Native.new()
			var restored:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded
			check("actual Native offline safety assembles candidate capture "+str(seed),restored.ok,restored.get("reason"))
			native.free()
		walk_paths(world,building,"v5 seed "+str(seed))
		# A bounded route fixture at the persisted road arrival; captures above
		# keep all actual opening actors. No extra supply or gameplay pass claimed.
		var facts:Dictionary=assembled.capture.facts.duplicate(true)
		var at:Dictionary=actor_at(world.extension("generation:RH-HOME").anchors.arrival)
		for a:Dictionary in facts.actors:
			if a.id=="player":a.merge({"x":at.x,"y":at.y,"z":at.z,"regionId":"RH-HOME","buildingId":null,"storeyId":null},true)
		runtime=Runtime.new();building=Building.new()
		check("bounded arrival route fixture is valid "+str(seed),runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":Actions.new(),"production":Production.new()}}).ok)
		var route:Dictionary=walk_home_to_village(runtime,world)
		check("real router/runtime movement crosses home village boundary "+str(seed),route.ok,route)
		row.route=route
		rows.append(row)
		if seed==12:primary=world;primary_facts=runtime.facts()
	check("different seeds retain different actual playable rasters",candidate_sources.size()==2 and candidate_sources[0]!=candidate_sources[1],candidate_sources)
	costs.rows=rows
	if primary!=null:
		var east:Dictionary=add_region(primary,Vector2i(1,0),profiles);var west:Dictionary=add_region(primary,Vector2i(-1,0),profiles)
		check("real positive negative peripheral drafts commit same v5 contract",east.ok and west.ok,east.get("reason",west.get("reason")))
		if east.ok and west.ok:
			var reverse:=State.new();reverse.load_snapshot(Landscape.generate(12,profiles,contract))
			var a:Dictionary=add_region(reverse,Vector2i(-1,0),profiles);var b:Dictionary=add_region(reverse,Vector2i(1,0),profiles)
			check("opposite region generation order retains exact plans cells resource IDs",a.ok and b.ok and signature(primary,"R2:1:0")==signature(reverse,"R2:1:0") and signature(primary,"R2:-1:0")==signature(reverse,"R2:-1:0"))
			var seam:=0.0;var diagonal:=0.0
			for edge:float in [0,64]:
				for z in 128:
					var wz:float=(z+0.5)*0.5
					seam=maxf(seam,absf(primary.surface_height(edge-0.25,wz)-primary.surface_height(edge+0.25,wz)))
			for x in 128:seam=maxf(seam,absf(primary.surface_height((x+0.5)*0.5,-0.25)-primary.surface_height((x+0.5)*0.5,0.25)))
			for region_id:String in ["RH-HOME","RH-VILLAGE","R2:1:0","R2:-1:0"]:
				var region:Dictionary=primary.region(region_id)
				for z in range(1,128):
					for x in range(1,128):
						var wx:float=region.bounds.min.x+x*0.5;var wz:float=region.bounds.min.z+z*0.5
						var hs:Array=[]
						for dx:float in [-0.25,0.25]:
							for dz:float in [-0.25,0.25]:hs.append(primary.surface_height(wx+dx,wz+dz))
						diagonal=maxf(diagonal,float(hs.max())-float(hs.min()))
			check("real positive negative seams and all four-column body corners <= one step",seam<=0.5 and diagonal<=0.5,{"max_seam_m":seam,"max_corner_m":diagonal})
			await labor_and_restore(primary,primary_facts,profiles)
	costs.scope="Explicit v5 new-world source candidate only. v4 exact snapshots retained; same production Assembly/Native/body and isolated runtime movement/labor. No formal app/Metal/VA or performance qualification; default v4 unchanged."
	finish()

func labor_and_restore(world:RefCounted,facts:Dictionary,profiles:Array)->void:
	var trees:Array=world.entities("R2:1:0").filter(func(e:Dictionary)->bool:return e.kind=="tree")
	check("peripheral world retains real harvestable trees",not trees.is_empty())
	if trees.is_empty():return
	var tree:Dictionary=trees[0];var p:Dictionary=tree.position
	var building:=Building.new();building.geometry.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json")))
	var at:Dictionary=actor_at({"x":p.x+1.75,"y":world.surface_height(p.x+1.75,p.z),"z":p.z});at.regionId=tree.regionId
	var feet:Dictionary=building.space(world).standing_point(at)
	check("peripheral labor has real nine-probe safe feet",not feet.is_empty(),feet)
	if feet.is_empty():return
	for actor:Dictionary in facts.actors:
		if actor.id=="player":actor.merge(feet,true);actor.intent=null
	for stock:Dictionary in Rural.empty_resource_stocks(world):
		if not facts.stocks.any(func(s:Dictionary)->bool:return s.id==stock.id):facts.stocks.append(stock)
	var prod:Dictionary=world.extension("r3:production")
	prod.tools.append_array([{"id":"v5:test:axe","kind":"salvaged_axe","holderId":"pack:player","durability":100.0},{"id":"v5:test:shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1}}])
	var tx:Dictionary=world.prepare_changes([{"op":"extension.set","id":"r3:production","before_exists":true,"before":world.extension("r3:production"),"after":prod}],world.get_revision())
	if tx.ok:world.commit_prepared(tx.capability)
	var runtime:=Runtime.new()
	check("real labor runtime retains original stocks with isolated test tools",runtime.configure({"world":world,"facts":facts,"services":{"terrain":Terrain.new(),"buildings":building,"production":Production.new(),"actions":Actions.new()}}).ok)
	var harvest:Dictionary=runtime.command({"command_id":"v5:harvest","actor_id":"player","kind":"harvest","target_id":tree.id,"payload":{"tree_id":tree.id,"output_id":tree.data.outputId,"tool_ids":["v5:test:axe"],"held":true}})
	if harvest.ok:
		for i in 280:runtime.tick(0.1)
	check("actual harvest leaves saved stump and finite original log yield",harvest.ok and world.entity(tree.id).data.harvest.phase=="stump" and runtime.stock(tree.data.outputId).items.get("log",0)==3,harvest)
	var actor:Dictionary=runtime.actor("player");var cx:int=floori((actor.x+0.5)*2);var cz:int=floori((actor.z+0.5)*2)
	var cy:int=roundi(world.surface_height((cx+0.5)*0.5,(cz+0.5)*0.5)*2)-1
	var cell:Dictionary={"x":cx,"y":cy,"z":cz}
	var hit:Dictionary=Queries.pick(world,Vector3((cx+0.5)*0.5,15,(cz+0.5)*0.5),Vector3((cx+0.5)*0.5,-3,(cz+0.5)*0.5))
	check("real v5 pick is stable authoritative cell ID",hit.get("target_id")=="terrain:%d:%d:%d"%[cx,cy,cz],hit)
	var view:=TerrainView.new();root.add_child(view);view.configure({"world":world});view.set_process(false)
	view._rebuild(Data.key(Data.cell_chunk(Vector3i(cx,cy,cz),16)))
	await physics_frame;await process_frame
	var ray:=PhysicsRayQueryParameters3D.create(Vector3((cx+0.5)*0.5,15,(cz+0.5)*0.5),Vector3((cx+0.5)*0.5,-3,(cz+0.5)*0.5))
	var collision:Dictionary=view.get_world_3d().direct_space_state.intersect_ray(ray)
	check("actual native collider agrees with authoritative broad terrain",not collision.is_empty() and absf(collision.position.y-(cy+1)*0.5)<0.001,str(collision.get("position")))
	view.free()
	var soil_before:float=runtime.actor("player").pack.get("soil_m3",0)
	var dig:Dictionary=runtime.command({"command_id":"v5:dig","actor_id":"player","kind":"terrain","payload":{"edit":{"operation":"dig","cells":[cell]},"tool_id":"v5:test:shovel"}})
	if dig.ok:
		for i in 100:runtime.tick(0.1)
	check("real dig conserves soil volume",dig.ok and world.cell_at(cx,cy,cz)==0 and runtime.actor("player").pack.get("soil_m3",0)==soil_before+0.125,dig)
	var fill:Dictionary=runtime.command({"command_id":"v5:fill","actor_id":"player","kind":"terrain","payload":{"edit":{"operation":"fill","material":2,"cells":[cell]},"tool_id":"v5:test:shovel"}})
	if fill.ok:
		for i in 100:runtime.tick(0.1)
	check("real fill consumes the same soil",fill.ok and world.cell_at(cx,cy,cz)==2 and runtime.actor("player").pack.get("soil_m3",0)==soil_before,fill)
	var saved:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(saved.text) if saved.ok else saved
	var restored:=State.new();var loaded:Dictionary=restored.load_snapshot(decoded.capture.world) if decoded.ok else decoded
	check("full native codec retains v5 edit stump finite stock and exact raster",loaded.ok and raster_digest(restored.snapshot())==raster_digest(world.snapshot()) and restored.cell_at(cx,cy,cz)==2 and restored.entity(tree.id).data.harvest.phase=="stump" and decoded.capture.facts.stocks.filter(func(s:Dictionary)->bool:return s.id==tree.data.outputId)[0].items.get("log",0)==3,loaded)
	var again:Dictionary=Rural.prepare_region(restored,Vector2i(1,0),profiles)
	check("cold revisit neither redraws modified v5 nor replenishes tree",again.ok and again.already_generated and again.world_changes.is_empty() and again.initial_stocks.is_empty() and not restored.is_cell_resident(cx,cy,cz))
