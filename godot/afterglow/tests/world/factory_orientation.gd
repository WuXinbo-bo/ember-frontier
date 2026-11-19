extends "res://tests/world/factory_normal_path.gd"
## Actual B geometry/Native/normal finite tool routes for explicit content4.
const Turn=preload("res://scripts/world/factory_parcel_orientation.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")

func close(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a).distance_to(Geometry.point(b))<0.00001
func location(p:Dictionary,id:String)->Dictionary:
	var at:Dictionary=p.duplicate(true);at.merge({"regionId":id,"buildingId":null,"storeyId":null},true);return at

func without_clues(plan:Dictionary)->Dictionary:
	var p:Dictionary=plan.duplicate(true);p.erase("configuration_sha256")
	for source:Dictionary in p.module_seeds:source.erase("story_clues")
	return p

func seams(world:RefCounted)->bool:
	for coord:Vector2i in [Vector2i(0,-1),Vector2i(0,1),Vector2i(-1,0)]:
		for i:int in 128:
			var across:float=(i+0.5)*0.5
			var a:float;var b:float
			if coord.x:
				a=world.surface_height(-0.25,across);b=world.surface_height(0.25,across)
			else:
				var z:float=64.0 if coord.y==1 else 0.0
				a=world.surface_height(across,z-0.25);b=world.surface_height(across,z+0.25)
			if absf(a-b)>0.5:return false
	return true

func geometry_checks(profiles:Array)->void:
	for profile:Dictionary in profiles:
		if not profile.has("design_id"):continue
		for q:int in 4:
			var forced:Dictionary=profile.duplicate(true);forced.allowed_quarter_turns=[q]
			var p:Dictionary=Turn.parcel(forced,Vector2(6,6),Vector2(34,30),"test:"+profile.id)
			var instance:Dictionary={"position":p.origin,"quarter_turn":q,"region":"RH-HOME"}
			var ports:Array=Shape.ports(instance,Modules.definition(profile.id))
			var exact:bool=p.quarter_turn==q and ports.size()==p.entrance_ports.size()
			for i:int in ports.size():
				var a:Dictionary=ports[i];var b:Dictionary=p.entrance_ports[i]
				exact=exact and close(a.location,b.position) and close(a.normal,b.normal)
				for j:int in a.use_points.size():exact=exact and close(a.use_points[j],b.use_points[j])
				var direction:Vector3=Turn.DIRECTIONS[b.direction]
				exact=exact and direction.distance_to(Geometry.point(a.normal))<0.00001
			var low:=Vector3(INF,INF,INF);var high:Vector3=-low
			for x:float in [profile.footprint.min.x,profile.footprint.max.x]:
				for y:float in [profile.footprint.min.y,profile.footprint.max.y]:
					for z:float in [profile.footprint.min.z,profile.footprint.max.z]:
						var at:Vector3=Geometry.rotate(Vector3(x,y,z),q);low=low.min(at);high=high.max(at)
			exact=exact and low.distance_to(Geometry.point(p.footprint.min))<0.00001 and high.distance_to(Geometry.point(p.footprint.max))<0.00001
			for i:int in profile.foundation.pad_rectangles.size():
				var original:Array=profile.foundation.pad_rectangles[i];var r:Array=p.foundation.pad_rectangles[i]
				for x:float in [original[0],original[2]]:
					for z:float in [original[1],original[3]]:
						var at:Vector3=Geometry.rotate(Vector3(x,0,z),q)
						exact=exact and at.x>=r[0]-0.00001 and at.x<=r[2]+0.00001 and at.z>=r[1]-0.00001 and at.z<=r[3]+0.00001
			check("all complete B footprint/foundation/ports/usepoints transform "+profile.id+" q"+str(q),exact)
	# Actual target positions change orientation without a camera input.
	var example:Dictionary=profiles.filter(func(p:Dictionary)->bool:return p.get("design_id")=="home_roadside_v2")[0] if profiles.any(func(p:Dictionary)->bool:return p.get("design_id")=="home_roadside_v2") else profiles.filter(func(p:Dictionary)->bool:return p.generation_role=="home")[0]
	var chosen:Array=[]
	for target:Vector2 in [Vector2(8,-100),Vector2(100,8),Vector2(8,100),Vector2(-100,8)]:chosen.append(Turn.select(example,Vector2(6,6),target))
	check("road target determines all four facings independently of camera",chosen==[0,1,2,3],chosen)

func plan_checks(seed:int,plan:Dictionary,profiles:Array)->void:
	var suffix:String=" "+str(seed)+" "+plan.region_id
	var clear:bool=true;var roads:bool=true;var anchors:bool=true;var rows:Array=[]
	for p:Dictionary in plan.parcels:
		var primary:Dictionary=p.entrance_ports.filter(func(port:Dictionary)->bool:return port.id==p.orientation.primary_port_id)[0]
		var toward:Vector3=Geometry.point(p.orientation.target)-Geometry.point(p.origin);toward.y=0
		var facing:float=Geometry.point(primary.normal).dot(toward.normalized())
		clear=clear and facing>0.5 and p.orientation.policy=="road-court-v1" and profiles.filter(func(v:Dictionary)->bool:return v.id==p.definition_id)[0].allowed_quarter_turns.any(func(q:Variant)->bool:return q==p.quarter_turn)
		for port:Dictionary in p.entrance_ports:
			var paths:Array=plan.paths.filter(func(path:Dictionary)->bool:return path.id=="access:"+p.id+":"+port.id)
			roads=roads and paths.size()==1
			if paths.size()==1:
				var path:Dictionary=paths[0];var first:Vector3=Geometry.point(path.points[1])-Geometry.point(path.points[0]);first.y=0
				roads=roads and close(path.points[0],port.position) and close(path.points[-1],p.orientation.target) and first.normalized().dot(Geometry.point(port.normal))>0.99
			for at:Dictionary in port.use_points:
				anchors=anchors and absf(at.y-p.pad.height)<0.00001
		for a:Dictionary in p.npc_anchors:
			anchors=anchors and absf(a.position.y-p.pad.height)<0.00001 and p.entrance_ports.any(func(v:Dictionary)->bool:return v.id==a.port_id and v.use_points.any(func(point:Dictionary)->bool:return close(point,a.position))) and plan.npc_anchors.any(func(v:Dictionary)->bool:return v.id==a.id and close(v.position,a.position))
		for reserve:Dictionary in p.use_reservations:anchors=anchors and is_equal_approx(reserve.bounds.min.y,p.pad.height) and reserve.bounds.max.y-reserve.bounds.min.y>=1.79
		rows.append({"parcel":p.id,"definition":p.definition_id,"q":p.quarter_turn,"port":primary.id,"direction":primary.direction,"facing_dot":facing,"origin":p.origin,"pad":p.pad,"target":p.orientation.target})
	check("primary fronts face actual shared road/courtyard"+suffix,clear,rows)
	check("every service mouth has outward real road into same junction"+suffix,roads)
	check("fitted NPC/use/reservation anchors share final pad plane"+suffix,anchors)
	var resources:bool=true
	for tree:Dictionary in plan.resource_sites:
		for p:Dictionary in plan.parcels:resources=resources and Raster._rect_distance(tree.position.x,tree.position.z,p.pad.xz)>=2.2
	check("actual finite tree resources retain service pad clearance"+suffix,resources)
	costs[str(seed)+":"+plan.region_id]={"parcels":rows,"trees":plan.resource_sites.size(),"paths":plan.paths.size(),"npc_use_anchors":plan.npc_anchors.size()}

func run()->void:
	var profiles:Array=Modules.generation_profiles();geometry_checks(profiles)
	var policy:Dictionary=Contract.fresh(profiles,4,1)
	check("real B profiles explicitly opt into content4 story1",policy.ok,policy)
	if not policy.ok:return finish()
	var no_story:Dictionary=Contract.fresh(profiles,4,0)
	check("content4 also supports explicit story0 without implicit clue field",no_story.ok and not no_story.contract.has("story_clue_version") and Contract.resolve(no_story.contract,profiles).ok)
	for seed:int in [713,2026]:
		var flag_only:bool=true
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1),Vector2i(0,1)]:
			var a:Dictionary=Factory.plan_region(seed,coord,profiles,policy.contract)
			var b:Dictionary=Factory.plan_region(seed,coord,profiles,no_story.contract)
			flag_only=flag_only and a.ok and b.ok and Data.json_equal(without_clues(a.plan),without_clues(b.plan)) and b.plan.module_seeds.all(func(s:Dictionary)->bool:return not s.has("story_clues"))
		check("optional story0/1 keeps same full4 geometry roads resources "+str(seed),flag_only)
		var start:int=Time.get_ticks_usec();var actual:Dictionary=normal_tools(policy.contract,seed)
		if not actual.ok:return finish()
		var built:Dictionary=actual.built;var runtime:RefCounted=actual.runtime;var world:RefCounted=actual.world;var query:RefCounted=actual.query
		var home:Dictionary=world.extension("generation:RH-HOME");var village:Dictionary=world.extension("generation:RH-VILLAGE")
		plan_checks(seed,home,profiles);plan_checks(seed,village,profiles)
		var reachable:bool=true;var blocked:Array=[]
		for m:Dictionary in world.extension("r34:modules").instances:
			var parcel:Dictionary=world.extension("generation:"+m.region).parcels.filter(func(p:Dictionary)->bool:return "r34:generated:"+p.id==m.id)[0]
			var truth:Array=Shape.ports(m,Modules.definition(m.definition_id))
			for port:Dictionary in truth:
				var expected:Dictionary=parcel.entrance_ports.filter(func(p:Dictionary)->bool:return p.id==port.id)[0]
				for i:int in port.use_points.size():
					var at:Dictionary=port.use_points[i];var feet:Dictionary=query.standing_point(at)
					var route:Dictionary=built.services.actions.route("player",runtime.actor("player"),feet) if not feet.is_empty() else {"ok":false}
					if feet.is_empty() or not close(at,expected.use_points[i]) or not route.ok:reachable=false;blocked.append({"module":m.id,"port":port.id,"at":at,"feet":feet,"route_code":route.get("code"),"reason":route.get("reason")})
		check("actual assembled B4q bodies reach every real usepoint "+str(seed),reachable,blocked)
		for stock:String in ["r34:generated:RH-HOME:home:stock:supplies","r34:generated:RH-VILLAGE:store:stock:supplies"]:
			var row:Dictionary=runtime.stock(stock);var walked:Dictionary=walk(runtime,row.location) if not row.is_empty() else {"ok":false}
			var searched:Dictionary=send(runtime,"search",stock) if walked.get("ok",false) else walked
			if searched.get("ok",false):progress(runtime)
			check("normal finite-tool actor physically reaches and searches source "+str(seed)+stock,walked.get("ok",false) and searched.get("ok",false) and runtime.stock(stock).searched,{"walk":walked,"search_code":searched.get("code"),"reason":searched.get("reason")})
		var at:Dictionary=query.standing_point(_location(world,55.0,15.0));var walked:Dictionary=walk(runtime,at) if not at.is_empty() else {"ok":false}
		var y:int=roundi(world.surface_height(55.75,15.75)*2)-1
		var cell:Dictionary={"x":111,"y":y,"z":31};var work:Dictionary=send(runtime,"terrain","",brush(cell,"dig",actual.pickaxe)) if walked.get("ok",false) else walked
		if work.get("ok",false):progress(runtime,150)
		check("normal recovered pickaxe makes actual persisted edit after changed entrances "+str(seed),work.get("ok",false) and world.cell_at(111,y,31)==0,{"walk":walked,"work":work})
		var jobs:=Scheduler.new();jobs.attach(runtime,built.services.buildings,34,built.services.modules)
		for coord:Vector2i in [Vector2i(-1,0),Vector2i(0,1)]:
			var added:Dictionary=await peripheral(jobs,coord)
			check("real A worker B registration adopts oriented true-coordinate perimeter "+str(seed)+str(coord),added.get("ok",false),added)
			if not added.get("ok",false):jobs.shutdown();return finish()
			plan_checks(seed,world.extension("generation:"+Factory.region_id(coord)),profiles)
		jobs.shutdown()
		check("real adjacent positive/negative half-metre cell seams remain bounded "+str(seed),seams(world))
		var outer:Dictionary=world.extension("generation:"+Factory.region_id(Vector2i(0,1)))
		check("true peripheral storage parcel is actually generated and registered "+str(seed),outer.parcels.size()==1 and world.extension("r34:modules").instances.any(func(m:Dictionary)->bool:return m.id==outer.module_seeds[0].id and m.quarter_turn==outer.module_seeds[0].quarter_turn))
		var exact:Array=[]
		for coord:Vector2i in [Vector2i(0,1),Vector2i(-1,0),Vector2i.ZERO]:
			var draft:Dictionary=Factory.draft_region(seed,coord,profiles,policy.contract)
			exact.append(draft.ok and Data.json_equal(draft.plan,world.extension("generation:"+Factory.region_id(coord))))
			if draft.ok:costs[str(seed)+":"+Factory.region_id(coord)].draft_cost=draft.cost
		check("reverse prepare order preserves each complete oriented plan "+str(seed),exact.all(func(v:bool)->bool:return v),exact)
		var modules:Dictionary=world.extension("r34:modules");var raster:String=raster_digest(world.snapshot())
		var saved:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(saved.text) if saved.ok else saved
		var host:=Native.new();var restored:Dictionary=host._assemble(decoded.capture) if decoded.ok else decoded;host.free()
		check("actual Native cold restore keeps4 lock transforms receipts and edit "+str(seed),restored.get("ok",false) and Data.json_equal(restored.world.extension(Factory.CONFIG_KEY),policy.contract) and Data.json_equal(restored.world.extension("r34:modules"),modules) and raster_digest(restored.world.snapshot())==raster and restored.world.cell_at(111,y,31)==0,restored.get("reason"))
		if not restored.get("ok",false):return finish()
		var all_warm:bool=true
		for id:String in ["RH-HOME","RH-VILLAGE",Factory.region_id(Vector2i(-1,0)),Factory.region_id(Vector2i(0,1))]:
			var warm:Dictionary=restored.world.prepare_region_residency(id,true,restored.world.get_revision())
			var tx:Dictionary=restored.world.prepare_changes(warm.world_changes,restored.world.get_revision()) if warm.ok else warm
			var committed:Dictionary=restored.world.commit_prepared(tx.capability) if tx.ok else tx
			all_warm=all_warm and committed.ok
		check("cold page warm restores same oriented geometry and changed cell "+str(seed),all_warm and restored.world.cell_at(111,y,31)==0 and raster_digest(restored.world.snapshot())==raster)
		var request:Dictionary=Factory.draft_region_request(Factory.region_generation_input(restored.world,profiles),Vector2i.ZERO)
		var revisit:Dictionary=Factory.prepare_region_draft(restored.world,request,restored.world.get_revision())
		check("modified explored4 never redraws rotates or refills sources "+str(seed),revisit.ok and revisit.already_generated and revisit.world_changes.is_empty() and revisit.module_seeds.is_empty() and revisit.initial_stocks.is_empty() and restored.world.cell_at(111,y,31)==0)
		var args:=OS.get_cmdline_user_args()
		if not args.is_empty() and saved.ok:FileAccess.open(args[0].get_base_dir()+"/normal-oriented-%d.native.json"%seed,FileAccess.WRITE).store_string(saved.text)
		costs[str(seed)+":normal"]={"elapsed_ms":(Time.get_ticks_usec()-start)/1000.0,"raster_sha256":raster,"native_bytes":saved.text.length(),"normal_tools":[actual.axe,actual.shovel,actual.pickaxe],"final_actor":runtime.actor("player"),"module_count":modules.instances.size()}
	costs.scope="Explicit content4 full parcel transforms, real B4q/Native/normal finite tool and source routes, actual edit/save/cold/warm/perimeter workers only. No A formal entry change, OS renderer/VA or performance qualification."
	finish()
