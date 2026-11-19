extends SceneTree
## Tests only. Natural C4/story1 parcels, exact catalogue, Native assembly and
## the real region scheduler/BuildingSpace. No edited plans, terrain, positions,
## actor relocation, free machine, renderer, imports, saves or simulation tick.
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Scheduler=preload("res://scripts/runtime/region_scheduler.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const SEEDS=[713,2026,42,9001]
# Fixed before inspecting any family selection; every extra is truly adjacent.
const EXTRA_COORDS=[Vector2i(0,1),Vector2i(1,0),Vector2i(-1,0),Vector2i(0,-2)]
const REGION_MSEC=15000
const TOTAL_MSEC=240000
var checks:Array=[]
var seed_rows:Array=[]
var design_rows:Dictionary={}
var output:String=""
var began:int

func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func failed()->int:return checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
static func find(rows:Array,id:String)->Dictionary:
	for row:Dictionary in rows:
		if row.get("id")==id:return row
	return {}
static func same_point(a:Dictionary,b:Dictionary)->bool:
	# Only float32 transform roundoff, never a placement/height/body tolerance.
	return G.point(a).distance_to(G.point(b))<0.00001
static func direction(normal:Dictionary)->String:
	var v:=G.point(normal)
	for name:String in {"north":Vector3(0,0,-1),"east":Vector3(1,0,0),"south":Vector3(0,0,1),"west":Vector3(-1,0,0)}:
		if v=={"north":Vector3(0,0,-1),"east":Vector3(1,0,0),"south":Vector3(0,0,1),"west":Vector3(-1,0,0)}[name]:return name
	return "invalid"
func raster(world:RefCounted,id:String)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	var keys:Array=world.region_chunk_keys(id);keys.sort()
	for key:String in keys:
		hash.update(key.to_utf8_buffer());hash.update(PackedInt32Array(world.chunk(key).cells).to_byte_array())
	return hash.finish().hex_encode()
func write_json(name:String,value:Dictionary)->void:
	if not output.is_empty():FileAccess.open(output+"/"+name,FileAccess.WRITE).store_string(JSON.stringify(value,"\t",true,true))

func run()->void:
	began=Time.get_ticks_msec();var args:=OS.get_cmdline_user_args()
	if not args.is_empty():output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var profiles:Array=Catalog.profiles();var policy:Dictionary=Contract.fresh(profiles,4,1)
	check("exact current catalogue locks content4/story1",policy.get("ok",false) and policy.contract.content_version==4 and policy.contract.story_clue_version==1 and policy.contract.parcel_orientation=="road-court-v1")
	if not policy.get("ok",false):finish();return
	for d:Dictionary in Catalog.definitions().filter(func(row:Dictionary)->bool:return row.get("geometry_family_version",1)<2):
		if d.has("design_id"):design_rows[d.id]={"definition_id":d.id,"design_id":d.design_id,"generation_role":d.generation_role,"geometry_version":d.geometry_version,"hits":[],"quarter_turns":[],"port_directions":[]}
	for seed:int in SEEDS:
		if Time.get_ticks_msec()-began>TOTAL_MSEC:
			check("bounded test completed every predetermined seed",false,{"next_seed":seed,"limit_msec":TOTAL_MSEC});break
		await inspect_seed(seed,profiles,policy.contract)
		write_json("partial-results.json",report())
	check("all four fixed seeds actually exercised",seed_rows.size()==SEEDS.size() and seed_rows.all(func(row:Dictionary)->bool:return row.get("assembled",false)),SEEDS)
	finish()

func inspect_seed(seed:int,profiles:Array,policy:Dictionary)->void:
	var row:Dictionary={"seed":seed,"assembled":false,"regions":[],"generation":[],"modules":[]};seed_rows.append(row)
	var source:Dictionary=Factory.generate(seed,profiles,policy)
	check("natural C4 source "+str(seed),source.has("chunks") and source.has("worldId"),source.get("reason"))
	if not source.has("chunks"):return
	var opening:Dictionary=Assembly.prepare(source)
	check("normal finite opening source "+str(seed),opening.get("ok",false),opening.get("reason"))
	if not opening.get("ok",false):return
	var host:=Native.new();var built:Dictionary=host._assemble(opening.capture)
	check("original Native authoritative assembly "+str(seed),built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):host.free();return
	row.assembled=true
	var rt:RefCounted=built.runtime;var world:RefCounted=built.world;var service:RefCounted=built.services.modules
	var original:Dictionary=rt.capture_checkpoint();var original_modules:Dictionary=service.state()
	var original_rasters:Dictionary={};var original_plans:Dictionary={}
	for region:Dictionary in world.regions():
		original_rasters[region.id]=raster(world,region.id);original_plans[region.id]=world.extension("generation:"+str(region.id))
	var scheduler:=Scheduler.new();scheduler.attach(rt,built.services.buildings,1,service)
	for at:Vector2i in EXTRA_COORDS:
		var id:String=Factory.region_id(at);var started:int=Time.get_ticks_msec();var completed:Dictionary={}
		var request:Dictionary=scheduler.request(at)
		if request.get("ok",false):
			while world.region(id).is_empty() and Time.get_ticks_msec()-started<REGION_MSEC and Time.get_ticks_msec()-began<TOTAL_MSEC:
				var result:Dictionary=scheduler.poll(0.0,true)
				if not result.is_empty():completed=result
				if not completed.is_empty() and not completed.get("ok",false):break
				await create_timer(0.005).timeout
		var done:bool=not world.region(id).is_empty() and completed.get("ok",false)
		row.generation.append({"coord":{"x":at.x,"z":at.y},"id":id,"ok":done,"request":request,"completed":completed,"elapsed_msec":Time.get_ticks_msec()-started})
		check("actual scheduler registers adjacent region "+str(seed)+" "+id,done,row.generation[-1])
		if not done:break
	scheduler.shutdown()
	check("fixed six-region natural sample reached "+str(seed),world.regions().size()==2+EXTRA_COORDS.size())
	var keep:bool=Data.json_equal(original.facts.actors,rt.facts().actors) and original.facts.time==rt.facts().time
	for id:String in original_rasters:keep=keep and original_rasters[id]==raster(world,id) and Data.json_equal(original_plans[id],world.extension("generation:"+id))
	for v:Dictionary in original_modules.instances:keep=keep and Data.json_equal(v,service.instance(v.id))
	check("extension preserves original actors clock modules plans and voxels "+str(seed),keep)
	var before:Dictionary=rt.capture_checkpoint();var query:RefCounted=built.services.buildings.current_space()
	var public:Dictionary=service.projection("player");var all_modules:Array=service.state().instances
	var terrain_low:float=INF;var terrain_high:float=-INF;var all_rasters:Dictionary={}
	for region:Dictionary in world.regions():
		var plan:Dictionary=world.extension("generation:"+str(region.id));var low:float=INF;var high:float=-INF
		for x:int in range(4,64,8):
			for z:int in range(4,64,8):
				var y:float=world.surface_height(float(region.bounds.min.x)+x,float(region.bounds.min.z)+z)
				low=minf(low,y);high=maxf(high,y)
		terrain_low=minf(terrain_low,low);terrain_high=maxf(terrain_high,high);all_rasters[region.id]=raster(world,region.id)
		row.regions.append({"id":region.id,"content_version":plan.get("generation_content_version"),"plan_sha256":Contract.digest(plan),"raster_sha256":all_rasters[region.id],"sample_surface_min":low,"sample_surface_max":high,"module_seeds":plan.module_seeds})
		check("region uses unchanged C4 locked plan "+str(seed)+" "+str(region.id),plan.get("generation_content_version")==4 and plan.get("configuration_sha256")==Contract.digest(policy))
		for module_seed:Dictionary in plan.module_seeds:
			var v:Dictionary=service.instance(module_seed.id)
			check("real seed is registered once "+str(seed)+" "+str(module_seed.id),not v.is_empty() and all_modules.filter(func(m:Dictionary)->bool:return m.id==module_seed.id).size()==1)
			if not v.is_empty():row.modules.append(inspect_module(seed,built,query,public,all_modules,plan,module_seed,v))
	check("natural voxel relief retained outside pads "+str(seed),terrain_high>terrain_low,{"sample_min":terrain_low,"sample_max":terrain_high})
	var after:Dictionary=rt.capture_checkpoint()
	check("all spatial and public queries leave exact checkpoint untouched "+str(seed),Data.json_equal(before,after))
	var rasters_unchanged:bool=true
	for id:String in all_rasters:rasters_unchanged=rasters_unchanged and all_rasters[id]==raster(world,id)
	check("no test terrain writes or flattening "+str(seed),rasters_unchanged and Data.json_equal(world.extension(Factory.CONFIG_KEY),policy))
	row.query_capture_sha256=Contract.digest(before);row.lock_sha256=Contract.digest(policy)
	if row.modules.any(func(m:Dictionary)->bool:return not m.ok):write_json("red-seed-"+str(seed)+".capture.json",before)
	host.free()

func inspect_module(seed:int,built:Dictionary,query:RefCounted,public:Dictionary,all_modules:Array,plan:Dictionary,module_seed:Dictionary,v:Dictionary)->Dictionary:
	var start_failures:int=failed();var world:RefCounted=built.world;var d:Dictionary=Catalog.definition(v.definition_id)
	var parcel:Dictionary=find(plan.parcels,str(v.id).trim_prefix("r34:generated:"))
	var footprint:AABB=Shape.transform_box(v,G.aabb(d.footprint));var ports:Array=Shape.ports(v,d)
	var label:String=str(seed)+" "+str(v.id)
	var row:Dictionary={"module_id":v.id,"definition_id":v.definition_id,"design_id":d.get("design_id",""),"geometry_version":v.geometry_version,"source_key":v.source_key,"region":v.region,"position":v.position,"quarter_turn":v.quarter_turn,"footprint":G.json_box(footprint),"ports":[],"members":v.members}
	var from_seed:bool=true
	for key:String in ["id","definition_id","definition_version","geometry_version","region","position","quarter_turn","source_key","player_built"]:from_seed=from_seed and Data.json_equal(v.get(key),module_seed.get(key))
	check("module uses exact natural seed geometry "+label,from_seed and not parcel.is_empty(),row)
	if parcel.is_empty():row.ok=false;return row
	var plan_box:=G.aabb(parcel.footprint);plan_box.position+=G.point(parcel.origin)
	check("rotated footprint agrees with real parcel including seams "+label,same_point(G.json_point(plan_box.position),G.json_point(footprint.position)) and same_point(G.json_point(plan_box.end),G.json_point(footprint.end)) and same_point(parcel.origin,v.position),{"actual":row.footprint,"plan":G.json_box(plan_box)})
	var cells:Dictionary=footprint_voxels(world,footprint)
	row.voxels=cells
	check("full half-metre footprint support and raw body-height terrain clearance "+label,cells.unsupported.is_empty() and cells.occupied.is_empty() and query.terrain_supports(v.region,footprint),cells)
	var members:Dictionary=members_check(built,v,d,footprint);row.member_check=members
	check("exact real members root parts and original workbench "+label,members.errors.is_empty(),members)
	var overlaps:Array=[]
	for other:Dictionary in all_modules:
		if other.id!=v.id and other.status!="dismantled" and G.overlap(footprint,Shape.transform_box(other,G.aabb(Catalog.definition(other.definition_id).footprint))):overlaps.append({"module":other.id})
	for entity:Dictionary in query.solid_entities:
		if not members.ids.has(entity.id) and G.overlap(footprint,G.aabb(entity.bounds)):overlaps.append({"foreign_entity":entity.id,"bounds":entity.bounds})
	for piece:Dictionary in query.pieces:
		if members.ids.has(piece.id) or float(piece.hp)<=0:continue
		for collider:AABB in query.geometry.boxes(piece):
			if G.overlap(footprint,collider):overlaps.append({"foreign_structure":piece.id,"bounds":G.json_box(collider)})
	check("footprint has no foreign shell structure or solid prop "+label,overlaps.is_empty(),overlaps)
	# A module's reserved building box is deliberately NOT its body collider.
	# Existing people can brush its edge/courtyard without hitting an actual
	# member. Keep broad-phase overlap as evidence, then prove the real body.
	var live_overlaps:Array=[];var live_clear:bool=true
	for actor:Dictionary in built.runtime.facts().actors:
		var at:Dictionary=G.location(actor)
		if float(actor.hp)<=0 or not G.overlap(footprint,AABB(G.point(at)-Vector3(0.26,0,0.26),Vector3(0.52,1.8,0.52))):continue
		var feet:Dictionary=query.standing_point(at)
		var body_ok:bool=not feet.is_empty() and same_point(feet,at) and query.blockers(at,at,str(actor.id)).ok
		live_clear=live_clear and body_ok;live_overlaps.append({"id":actor.id,"location":at,"original_standing_point":feet,"actual_body_clear":body_ok})
	row.live_footprint_overlaps=live_overlaps
	check("live people near footprint retain original support and real-body clearance "+label,live_clear,live_overlaps)
	var collar:Dictionary=collar_check(query,v.region,footprint);row.collar=collar
	check("all four exterior footprint seams retain supported body collar "+label,collar.errors.is_empty(),collar)
	var visible:Dictionary=find(public.instances,v.id)
	var permitted:bool=Modules.permitted(built.runtime.actor("player"),v.owner)
	if v.get("discovered",false) and permitted:
		check("existing public module projection matches real ports members and geometry "+label,not visible.is_empty() and Data.json_equal(visible.get("ports"),ports) and Data.json_equal(visible.get("members"),v.members) and visible.get("geometry_version")==v.geometry_version and same_point(visible.get("location",{}),v.position))
		var guidance:Dictionary=built.runtime.module_service_approaches(v.id);row.public_service=guidance
		var guidance_ok:bool=guidance.get("available",false) and not guidance.approaches.is_empty()
		for approach:Dictionary in guidance.get("approaches",[]):
			var port:Dictionary=find(ports,str(approach.port_id))
			guidance_ok=guidance_ok and approach.get("available",false) and port.get("use_points",[]).any(func(at:Dictionary)->bool:return same_point(at,approach.get("location",{})))
		check("public facade provides actual original-player service routes "+label,guidance_ok,guidance)
	else:
		check("undiscovered or unpermitted modules do not leak public routes "+label,visible.is_empty() and not built.runtime.module_service_approaches(v.id).get("available",false))
	for port:Dictionary in ports:row.ports.append(inspect_port(query,v,port,parcel,plan,label))
	row.ok=failed()==start_failures
	if design_rows.has(d.id):
		var coverage:Dictionary=design_rows[d.id]
		coverage.hits.append({"seed":seed,"module_id":v.id,"region":v.region,"position":v.position,"quarter_turn":v.quarter_turn,"ok":row.ok})
		if int(v.quarter_turn) not in coverage.quarter_turns:coverage.quarter_turns.append(int(v.quarter_turn))
		for port:Dictionary in ports:
			var facing:String=direction(port.normal)
			if facing not in coverage.port_directions:coverage.port_directions.append(facing)
	return row

func footprint_voxels(world:RefCounted,b:AABB)->Dictionary:
	var result:Dictionary={"support_cells":0,"body_cells":0,"unsupported":[],"occupied":[],"chunk_columns":[]}
	var columns:Dictionary={};var y:int=roundi(b.position.y*2)
	for x:int in range(floori(b.position.x*2),ceili(b.end.x*2)):
		for z:int in range(floori(b.position.z*2),ceili(b.end.z*2)):
			result.support_cells+=1;columns["%d,%d"%[floori(float(x)/16),floori(float(z)/16)]]=true
			if not world.is_cell_resident(x,y-1,z) or not Data.material_blocks(world.cell_at(x,y-1,z),"support"):
				if result.unsupported.size()<8:result.unsupported.append({"x":x,"y":y-1,"z":z,"material":world.cell_at(x,y-1,z)})
			for cy:int in range(y,ceili(b.end.y*2)):
				result.body_cells+=1
				if not world.is_cell_resident(x,cy,z) or Data.material_blocks(world.cell_at(x,cy,z),"body"):
					if result.occupied.size()<8:result.occupied.append({"x":x,"y":cy,"z":z,"material":world.cell_at(x,cy,z)})
	result.chunk_columns=columns.keys();return result

func members_check(built:Dictionary,v:Dictionary,d:Dictionary,footprint:AABB)->Dictionary:
	var ids:Dictionary={};var expected:Dictionary={v.id:"entity"};var errors:Array=[];var parts:Array=Shape.entities(v,d)
	for member:Dictionary in v.members:
		if ids.has(member.id):errors.append("duplicate member "+str(member.id))
		ids[member.id]=member.kind
	for entity:Dictionary in parts:
		expected[entity.id]="entity";var actual:Dictionary=built.world.entity(entity.id)
		for field:String in ["id","kind","regionId","position","bounds","blocksTerrain","supportBounds","data"]:
			if not Data.json_equal(actual.get(field),entity.get(field)):errors.append({"member":entity.id,"field":field,"expected":entity.get(field),"actual":actual.get(field)})
		if not footprint.grow(0.00001).encloses(G.aabb(entity.bounds)):errors.append("part outside actual footprint "+str(entity.id))
	if d.shape=="manual":
		var id:String=str(v.id)+":workbench";expected[id]="structure"
		var piece:Dictionary=find(built.services.buildings.structures(built.world).instances,id)
		var actual:Dictionary=built.world.entity(id)
		var expected_entity:Dictionary=built.services.buildings.geometry.entity(piece) if not piece.is_empty() else {}
		# World commit revision is an authority stamp, not structure geometry.
		# Compare every other field, including archived geometryVersion/version.
		actual=actual.duplicate(true);actual.erase("revision");expected_entity.erase("revision")
		if piece.is_empty() or piece.definitionId!="workbench" or int(piece.quarterTurn)!=int(v.quarter_turn) or not same_point(piece.position,Shape.at(v,Shape.Families.bench_offset(d))) or not Data.json_equal(actual,expected_entity):errors.append({"bench":id,"actual_without_commit_revision":actual,"expected_without_commit_revision":expected_entity})
	var root_entity:Dictionary=built.world.entity(v.id)
	if root_entity.get("data",{}).get("solid",true) or root_entity.get("data",{}).get("opaque",true) or not root_entity.get("data",{}).get("module_target",false) or not same_point(root_entity.get("position",{}),v.position) or not Data.json_equal(root_entity.get("bounds"),G.json_box(footprint)):errors.append("aggregate must be exact selectable non-solid target")
	if not Data.json_equal(ids,expected):errors.append({"expected_members":expected,"actual_members":ids})
	return {"ids":ids,"expected_part_count":parts.size(),"errors":errors}

func collar_check(query:RefCounted,region:String,b:AABB)->Dictionary:
	var samples:Array=[];var errors:Array=[]
	# At least one complete actual body outside each bounding seam. The full
	# footprint itself is sealed; this does not promise a walkable interior.
	for side:String in ["north","east","south","west"]:
		var length:float=b.size.x if side in ["north","south"] else b.size.z
		for n:int in range(ceili(length*2)+1):
			var t:float=minf(float(n)*0.5,length)
			var x:float=b.position.x+t if side in ["north","south"] else b.end.x+0.55 if side=="east" else b.position.x-0.55
			var z:float=b.position.z+t if side in ["east","west"] else b.end.z+0.55 if side=="south" else b.position.z-0.55
			var at:Dictionary=G.location({"x":x,"y":b.position.y,"z":z,"regionId":region})
			var feet:Dictionary=query.standing_point(at);var ok:bool=not feet.is_empty() and same_point(at,feet)
			samples.append({"side":side,"location":at,"ok":ok,"feet":feet})
			if not ok:errors.append(samples[-1])
	return {"sample_count":samples.size(),"samples":samples,"errors":errors}

func inspect_port(query:RefCounted,v:Dictionary,port:Dictionary,parcel:Dictionary,plan:Dictionary,label:String)->Dictionary:
	var actual_plan:Dictionary=find(parcel.entrance_ports,port.id);var facing:String=direction(port.normal)
	var row:Dictionary={"port_id":port.id,"purpose":port.purpose,"direction":facing,"location":port.location,"normal":port.normal,"use_points":[],"clearance":port.clearance}
	var transform_ok:bool=not actual_plan.is_empty() and actual_plan.get("direction")==facing and same_point(actual_plan.get("position",{}),port.location) and Data.json_equal(actual_plan.get("normal"),port.normal) and actual_plan.get("use_points",[]).size()==port.use_points.size()
	for i:int in port.use_points.size():
		if i<actual_plan.get("use_points",[]).size():transform_ok=transform_ok and same_point(actual_plan.use_points[i],port.use_points[i])
	check("C parcel and B exact rotated service transform "+label+" "+str(port.id),transform_ok,row)
	var path:Dictionary=find(plan.paths,"access:"+str(parcel.id)+":"+str(port.id))
	check("actual module-service path begins at exact mouth "+label+" "+str(port.id),path.get("purpose")=="module-service" and not path.get("points",[]).is_empty() and same_point(path.points[0],port.location),path)
	var points:Array=[port.location];points.append_array(port.use_points)
	for i:int in points.size():
		var at:Dictionary=points[i];var feet:Dictionary=query.standing_point(at)
		var r:float=port.clearance.radius;var height:float=port.clearance.height
		var volume:=AABB(G.point(at)-Vector3(r,0,r),Vector3(r*2,height,r*2))
		var occupied:Array=[]
		for piece:Dictionary in query.nearby_pieces(v.region,volume):
			for collider:AABB in query.geometry.boxes(piece):
				if G.overlap(collider,volume):occupied.append(piece.id)
		var clear:bool=not feet.is_empty() and same_point(feet,at) and query.terrain_supports(v.region,volume) and query.terrain_clear(v.region,volume) and occupied.is_empty()
		var approach:Dictionary={"location":at,"feet":feet,"reserved_body":G.json_box(volume),"structure_blockers":occupied,"clear":clear}
		check("exact port/usepoint full reserved body stands "+label+" "+str(port.id)+" #"+str(i),clear,approach)
		var from:Dictionary=G.location(plan.anchors.arrival)
		# Declared mouth and usepoint often coincide. Share that identical
		# immutable spatial proof; still validate both declarations above.
		var previous:Dictionary=row.use_points[0] if not row.use_points.is_empty() and same_point(row.use_points[0].location,at) else {}
		approach.from_arrival=previous.from_arrival if not previous.is_empty() else verified_route(query,from,at)
		approach.to_arrival=previous.to_arrival if not previous.is_empty() else verified_route(query,at,from)
		check("original body route to and from service point "+label+" "+str(port.id)+" #"+str(i),approach.from_arrival.ok and approach.to_arrival.ok,approach)
		row.use_points.append(approach)
	return row

func verified_route(query:RefCounted,from:Dictionary,to:Dictionary)->Dictionary:
	# A spatial proof from the generated road junction, NOT a teleported player
	# or proof that the player/NPC has executed the returned command.
	var route:Dictionary=query.route("player",from,to);var current:Dictionary=from.duplicate(true)
	var errors:Array=[]
	if route.get("ok",false):
		for step:Dictionary in route.get("steps",[]):
			if step.get("kind")!="move":errors.append({"unexpected_exterior_step":step});break
			var swept:Dictionary=query.walk("player",current,step.to)
			if not swept.get("ok",false) or not same_point(swept.get("location",{}),step.to):errors.append({"from":current,"step":step,"sweep":swept});break
			current=swept.location
	var ok:bool=route.get("ok",false) and errors.is_empty() and same_point(current,to)
	return {"ok":ok,"from":from,"to":to,"route":route,"sweep_errors":errors}

func report()->Dictionary:
	var coverage:Array=[];var missing:Array=[];var directions:Array=[]
	for d:Dictionary in design_rows.values():
		var row:Dictionary=d.duplicate(true);row.hit_count=row.hits.size();row.hit=row.hit_count>0
		row.missing_quarter_turns=[];row.missing_port_directions=[]
		for turn:int in 4:
			if turn not in row.quarter_turns:row.missing_quarter_turns.append(turn)
		for side:String in ["north","east","south","west"]:
			if side not in row.port_directions:row.missing_port_directions.append(side)
			elif side not in directions:directions.append(side)
		if not row.hit:missing.append(row.definition_id)
		row.coverage="natural-generated-only" if row.hit else "NOT HIT: no generated instance in this fixed sample; no support/route/VA claim"
		coverage.append(row)
	return {"ok":failed()==0,"checks":checks,"seeds":SEEDS,"fixed_extra_coordinates":EXTRA_COORDS.map(func(p:Vector2i)->Dictionary:return {"x":p.x,"z":p.y}),"seed_results":seed_rows,"design_coverage":coverage,"missing_designs":missing,"observed_port_directions":directions,"all_seven_designs_covered":missing.is_empty() and design_rows.size()==7,"elapsed_msec":Time.get_ticks_msec()-began,"scope":"B new test of natural content4/story1 terrain, Native registration, original BuildingSpace and existing public projection. Static query routes from real arrival anchors are not executed player/NPC journeys. No production/lock/plan/terrain/location edits; no VA, OS, package or performance qualification."}
func finish()->void:
	var result:Dictionary=report();write_json("results.json",result)
	# Existing bounded runner recognizes a JSON line beginning with ok/checks.
	print(JSON.stringify(result,"",false,true));quit(0 if result.ok else 1)
