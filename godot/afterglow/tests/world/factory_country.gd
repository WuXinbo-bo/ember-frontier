extends SceneTree
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Landscape=preload("res://scripts/world/factory_landscape.gd")
const Raster=preload("res://scripts/world/settlement_generator.gd")
const State=preload("res://scripts/world/world_state.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
var checks:Array=[]
var costs:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"costs":costs,"scope":costs.get("scope","R34 C actual terrain only. No fabricated module, stock, NPC, runtime assembly, app, VA or performance qualification.")}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)

func source_from(drafts:Array,seed:int)->Dictionary:
	var source:Dictionary={"schemaVersion":1,"worldId":"r34:factory:"+str(seed),"seed":seed,"generatorVersion":Factory.VERSION,"revision":0,"config":Data.DEFAULT_CONFIG.duplicate(true),"regions":{},"chunks":{},"entities":{},"retiredEntityIds":[],"extensions":{Factory.CONFIG_KEY:Contract.fresh([]).contract},"receipts":{}}
	for draft:Dictionary in drafts:
		source.regions[draft.region.id]=draft.region;source.chunks.merge(draft.chunks);source.entities.merge(draft.entities)
		source.extensions["generation:"+draft.region.id]=draft.plan
	return source

func raster_digest(source:Dictionary)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	var keys:Array=source.chunks.keys();keys.sort()
	for key:String in keys:hash.update(key.to_utf8_buffer());hash.update(PackedInt32Array(source.chunks[key].cells).to_byte_array())
	return hash.finish().hex_encode()

func surface_metrics(world:RefCounted,id:String)->Dictionary:
	var r:Dictionary=world.region(id);var lo:float=INF;var hi:float=-INF;var largest:float=0.0
	for z in 128:
		for x in 128:
			var wx:float=r.bounds.min.x+(x+0.5)*0.5;var wz:float=r.bounds.min.z+(z+0.5)*0.5
			var height:float=world.surface_height(wx,wz)
			lo=minf(lo,height);hi=maxf(hi,height)
			if x<127:largest=maxf(largest,absf(height-world.surface_height(wx+0.5,wz)))
			if z<127:largest=maxf(largest,absf(height-world.surface_height(wx,wz+0.5)))
	return {"min_m":lo,"max_m":hi,"largest_adjacent_step_m":largest}

func _location(world:RefCounted,x:float,z:float)->Dictionary:
	var at:Dictionary={"x":x,"y":float(world.surface_height(x,z)),"z":z,"buildingId":null,"storeyId":null}
	at.regionId=world.region_at(at).get("id","")
	return at

func run()->void:
	check("playable generation refuses missing module definitions",Factory.generate(713,[]).get("code")=="MISSING_MODULE_GENERATION_PROFILES")
	check("out of finite range refused",Factory.plan_region(713,Vector2i(9,0)).get("code")=="GENERATION_COORD_LIMIT")
	var digests:Array=[];var primary:RefCounted
	for seed:int in [713,2026]:
		var start:int=Time.get_ticks_usec();var drafts:Array=[]
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1),Vector2i(1,0),Vector2i(-1,0)]:
			var draft:Dictionary=Factory.draft_region(seed,coord,[])
			check("actual half-metre voxel draft "+str(seed)+str(coord),draft.get("ok",false),draft.get("reason"))
			if not draft.get("ok",false):return finish()
			drafts.append(draft)
		var source:Dictionary=source_from(drafts,seed);var world:=State.new()
		check("sole authority validates new version actual lattice "+str(seed),world.load_snapshot(source).ok)
		var row:Dictionary={"generate_ms":(Time.get_ticks_usec()-start)/1000.0,"raster_sha256":raster_digest(source),"regions":{}}
		digests.append(row.raster_sha256)
		for draft:Dictionary in drafts:
			var plan:Dictionary=draft.plan;var metrics:Dictionary=surface_metrics(world,plan.region_id)
			row.regions[plan.region_id]={"metrics":metrics,"trees":plan.resource_sites.size(),"patches":plan.ecology.patches.size(),"cost":draft.cost}
			check("six purpose spaces and genuine bounded relief "+str(seed)+plan.region_id,plan.spaces.size()==6 and metrics.max_m-metrics.min_m>=1.5 and metrics.largest_adjacent_step_m<=0.5,metrics)
			var roots:bool=true;var models:Dictionary={}
			for site:Dictionary in plan.resource_sites:
				models[site.appearance.model]=true
				for dx:float in [-0.35,0.0,0.35]:
					for dz:float in [-0.35,0.0,0.35]:roots=roots and world.surface_height(site.position.x+dx,site.position.z+dz)==site.position.y
			check("three finite tree species have actual supported roots "+str(seed)+plan.region_id,roots and models.size()==3,{"species":models,"roots":roots})
			var paths_ok:bool=true;var failure:Dictionary={}
			for path:Dictionary in plan.paths:
				for i in path.points.size()-1:
					var a:Dictionary=path.points[i];var b:Dictionary=path.points[i+1]
					var distance:float=Vector2(b.x-a.x,b.z-a.z).length()
					for step in ceili(distance/0.5)+1:
						var t:float=minf(float(step)*0.5/maxf(distance,0.5),1.0)
						var x:float=lerpf(a.x,b.x,t);var z:float=lerpf(a.z,b.z,t)
						if x<=draft.region.bounds.min.x+0.5 or x>=draft.region.bounds.max.x-0.5 or z<=draft.region.bounds.min.z+0.5 or z>=draft.region.bounds.max.z-0.5:continue
						var heights:Array=[]
						for dx:float in [-0.26,0.0,0.26]:
							for dz:float in [-0.26,0.0,0.26]:heights.append(world.surface_height(x+dx,z+dz))
						if heights.max()-heights.min()>0.5:paths_ok=false;failure={"path":path.id,"at":[x,z],"heights":heights}
			check("real route width uses nine body probes "+str(seed)+plan.region_id,paths_ok,failure)
		var seam:bool=true;var seam_ports:bool=true
		for offset:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,-1)]:
			var boundary:float=64.0 if offset.x==1 else 0.0
			for i in 128:
				var cross:float=(i+0.5)*0.5
				var a:float=world.surface_height(boundary-0.25,cross) if offset.x else world.surface_height(cross,-0.25)
				var b:float=world.surface_height(boundary+0.25,cross) if offset.x else world.surface_height(cross,0.25)
				seam=seam and absf(a-b)<=0.5
			var own:Dictionary=world.extension("generation:RH-HOME");var other:Dictionary=world.extension("generation:"+Factory.region_id(offset))
			var direction:String="east" if offset.x==1 else "west" if offset.x==-1 else "north"
			var opposite:String="west" if offset.x==1 else "east" if offset.x==-1 else "south"
			var p:Dictionary=own.road_ports.filter(func(v:Dictionary)->bool:return v.direction==direction)[0]
			var q:Dictionary=other.road_ports.filter(func(v:Dictionary)->bool:return v.direction==opposite)[0]
			seam_ports=seam_ports and p.id==q.id and Data.json_equal(p.position,q.position)
		check("positive negative shared edges and road endpoints agree "+str(seed),seam and seam_ports,{"cell_seams":seam,"ports":seam_ports})
		var repeated:Dictionary=Factory.draft_region(seed,Vector2i.ZERO,[])
		check("reverse query order preserves full saved plan and cells "+str(seed),Data.json_equal(drafts[0].plan,repeated.plan) and raster_digest(source_from([drafts[0]],seed))==raster_digest(source_from([repeated],seed)))
		costs[str(seed)]=row
		if seed==713:primary=world
	check("different seed has actual terrain variation",digests.size()==2 and digests[0]!=digests[1],digests)
	if primary!=null:
		var input:Dictionary=Factory.region_generation_input(primary,[])
		var worker:Dictionary=Factory.draft_region_request(input,Vector2i(-1,-1))
		var prepared:Dictionary=Factory.prepare_region_draft(primary,worker,primary.get_revision()) if worker.ok else worker
		check("detached request prepares real negative-coordinate region",prepared.ok,prepared.get("reason"))
		if prepared.ok:
			var tx:Dictionary=primary.prepare_changes(prepared.world_changes,primary.get_revision())
			check("real unique authority accepts peripheral CAS",tx.ok,tx.get("reason"))
			if tx.ok:primary.commit_prepared(tx.capability)
		var cx:int=-80;var cz:int=-80;var cy:int=roundi(primary.surface_height((cx+0.5)*0.5,(cz+0.5)*0.5)*2)-1
		var pick:Dictionary=Queries.pick(primary,Vector3((cx+0.5)*0.5,15,(cz+0.5)*0.5),Vector3((cx+0.5)*0.5,-3,(cz+0.5)*0.5))
		check("DDA selects real persistent negative cell",pick.get("target_id")=="terrain:%d:%d:%d"%[cx,cy,cz],pick)
		var change:Dictionary=primary.prepare_changes([{"op":"voxel.set","cell":{"x":cx,"y":cy,"z":cz},"before":primary.cell_at(cx,cy,cz),"after":0}],primary.get_revision())
		check("unique world modification authority edits peripheral cell",change.ok)
		if change.ok:primary.commit_prepared(change.capability)
		var saved:Dictionary=Codec.encode_checkpoint(primary.snapshot(),{},"r34:domain:edited")
		var restored:Dictionary=Codec.decode_checkpoint(saved.envelope) if saved.ok else saved
		var cold:=State.new();var loaded:Dictionary=cold.load_snapshot(restored.state) if restored.ok else restored
		check("native world codec cold roundtrip retains edited cell",loaded.ok and cold.cell_at(cx,cy,cz)==0 and not cold.is_cell_resident(cx,cy,cz),loaded)
		if loaded.ok:
			var replay:Dictionary=Factory.prepare_region_draft(cold,worker,cold.get_revision())
			check("revisit never redraws or grants module content",replay.ok and replay.already_generated and replay.world_changes.is_empty() and replay.initial_stocks.is_empty() and replay.module_seeds.is_empty(),replay.get("reason"))
	finish()
