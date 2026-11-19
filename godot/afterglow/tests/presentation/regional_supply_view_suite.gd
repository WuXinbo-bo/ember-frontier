extends "res://tests/world/ecology_labor.gd"
## Explicit finite NPC/source/consent fixture. Real B supply, routes, C labor,
## and original D rigs; no E arbitration, normal economy, package or VA claim.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
var view:Node3D
var samples:Array=[]
var display_errors:Array=[]
var active_operations:Dictionary={}
var supplied_walk_samples:int=0
var water_prop_samples:int=0
var working_water_nodes:Dictionary={}
var read_only:bool=true
var restored_water:bool=false
const NPC="D:finite-worker"
const SOURCE="D:finite-source"
const SHOVEL="D:finite-shovel"

func issue(kind:String,actor_id:String=NPC,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":"D:regional-real:"+str(sequence),"actor_id":actor_id,"kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=runtime.command(request);commands.append({"request":request,"result":result});return result

func observe()->void:
	if not is_instance_valid(view):return
	var before:Dictionary=runtime.capture_checkpoint()
	view.sync(0)
	read_only=read_only and Data.json_equal(before,runtime.capture_checkpoint())
	var a:Dictionary=runtime.actor(NPC);var intent:Variant=a.get("intent")
	var state:String=view._states.get(NPC,"");var work:Dictionary=view._work_frames.get(NPC,{})
	var holder:String=str(runtime.tool(SHOVEL).get("holderId",""))
	if intent is Dictionary and intent.get("kind")=="zone_supply":
		supplied_walk_samples+=1
		if state not in ["Idle","Walk"] or not str(view._held_ids.get(NPC,"")).is_empty() or view._work_items.has(NPC):display_errors.append({"kind":"premature supply work or tool","state":state,"holder":holder})
	if work.get("available",false) and work.get("active",false):
		var op:String=str(work.get("operation",""));active_operations[op]=true
		if state!="Use":display_errors.append({"kind":"missing true effective Use","operation":op,"state":state})
		if op=="till" and (holder!="pack:"+NPC or view._held_ids.get(NPC)!=SHOVEL):display_errors.append({"kind":"actual shovel missing"})
		if op=="water":
			var prop:Node3D=view._work_items.get(NPC)
			if is_instance_valid(prop) and prop.get_meta("item_id","")=="r34:raw_water" and prop.get_meta("actual_pack_quantity",0)==a.pack.get("r34:raw_water",0):
				water_prop_samples+=1;working_water_nodes[prop.get_instance_id()]=true
			else:display_errors.append({"kind":"actual watering has no real carried water container","pack":a.pack,"state":state})
	if samples.size()<35 or (work.get("active",false) and not samples.any(func(row:Dictionary)->bool:return row.get("operation")==work.get("operation"))):
		samples.append({"time":runtime.clock(),"intent":intent.get("kind","") if intent is Dictionary else "","operation":work.get("operation",""),"state":state,"tool_id":view._held_ids.get(NPC,""),"holder":holder,"pack":a.pack.duplicate(true)})

func ticks(count:int,observing:bool=true)->void:
	for _i:int in count:
		runtime.tick(.1)
		if observing:observe()

func cold_water()->bool:
	var prop:Node3D=view._work_items.get(NPC)
	check("actual water can attaches to unchanged original palm",is_instance_valid(prop) and prop.global_position.distance_to(view._arms[NPC].to_global(Vector3(0,-.51,.06)))<.00001 and prop.global_basis.is_equal_approx(Basis.IDENTITY))
	runtime.set_paused(true);view.sync(0)
	var frozen:Transform3D=prop.global_transform if is_instance_valid(prop) else Transform3D.IDENTITY
	var before:Dictionary=runtime.capture_checkpoint();view.sync(.8)
	check("global pause freezes real water can and complete authority",is_instance_valid(prop) and prop.global_transform.is_equal_approx(frozen) and Data.json_equal(before,runtime.capture_checkpoint()))
	runtime.set_paused(false)
	var held:=issue("zonework.pause");ticks(3)
	check("manual held pause stows water without charging materials",held.get("ok",false) and not view._work_items.has(NPC) and runtime.actor(NPC).pack.get("r34:raw_water")==1)
	var encoded:=Store.encode(runtime.capture_checkpoint());var decoded:=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	check("real paused NPC water job encodes and cold decodes",decoded.get("ok",false),decoded.get("code"))
	if not decoded.get("ok",false):return false
	FileAccess.open(OS.get_cmdline_user_args()[0]+".water-paused.native.json",FileAccess.WRITE).store_string(encoded.text)
	var fresh_world:=World.new();var loaded:=fresh_world.load_snapshot(decoded.capture.world)
	var fresh_runtime:=Runtime.new()
	var fresh_services:Dictionary={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new()}
	var context:Dictionary=decoded.capture.duplicate(true);context.world=fresh_world;context.services=fresh_services
	var mounted:=fresh_runtime.configure(context) if loaded.get("ok",false) else loaded
	check("actual paused water job restores original owners and JSON cursor",mounted.get("ok",false),mounted.get("reason",mounted.get("code")))
	if not mounted.get("ok",false):return false
	runtime.retire();runtime=fresh_runtime;world=fresh_world;services=fresh_services
	var complete:bool=false;var batches:int=0;var warm_ok:bool=true
	while not complete and batches<128:
		var warm:=world.prepare_region_residency("RH-HOME",true,world.get_revision(),32)
		if not warm.get("ok",false):warm_ok=false;break
		complete=warm.complete;batches+=1
		if not commit(warm.world_changes).get("ok",false):warm_ok=false;break
	check("cold region warms only through original bounded residency CAS",warm_ok and complete and world.region_is_resident("RH-HOME"),{"batches":batches})
	view.configure(runtime);observe()
	check("new world retains paused work and real water without stale prop",not view._work_items.has(NPC) and runtime.actor(NPC).pack.get("r34:raw_water")==1 and not runtime.actor(NPC).intent.held)
	var resumed:=issue("zonework.resume")
	check("public control resumes exact restored water job",resumed.get("ok",false),resumed.get("reason"))
	return resumed.get("ok",false) and warm_ok and complete

func supply(operation:String)->bool:
	var cid:String=""
	for c:Dictionary in services.zonework.work_candidates(NPC):
		if c.get("operation")==operation:cid=c.id
	var offer:Dictionary={}
	for c:Dictionary in services.zonework.work_candidates(NPC):
		if c.get("kind")=="supply" and c.get("work_candidate_id")==cid and c.get("source_id")==SOURCE and c.get("valid",false):offer=c;break
	check("real finite supply candidate "+operation,not offer.is_empty(),offer)
	if offer.is_empty():return false
	var plan:Dictionary=services.actions.prepare_workforce({"actor_id":NPC,"candidate_id":offer.id,"command_id":"D:supply:"+operation})
	var result:Dictionary=runtime._commit(plan) if plan.get("ok",false) else plan
	check("original actions accepts real supply "+operation,result.get("ok",false),result.get("reason"))
	if not result.get("ok",false):return false
	observe()
	for _i:int in 220:
		ticks(1)
		if runtime.actor(NPC).get("intent")==null:break
	check("real pickup completed "+operation,runtime.actor(NPC).get("intent")==null,{"actor":runtime.actor(NPC),"source":runtime.stock(SOURCE)})
	return runtime.actor(NPC).get("intent")==null

func work(operation:String)->bool:
	var offer:Dictionary={}
	for c:Dictionary in services.zonework.work_candidates(NPC):
		if c.get("operation")==operation and c.get("valid",false):offer=c;break
	check("actual NPC labor candidate "+operation,not offer.is_empty(),services.zonework.work_candidates(NPC))
	if offer.is_empty():return false
	var result:=issue("zonework.start",NPC,str(offer.zone_id),{"candidate_id":offer.id})
	check("actual NPC labor begins "+operation,result.get("ok",false),result.get("reason"))
	if not result.get("ok",false):return false
	for _i:int in 250:
		ticks(1)
		if operation=="water" and not restored_water and view._work_frames.get(NPC,{}).get("active",false) and float(view._work_frames[NPC].get("progress_seconds",0))>.2:
			restored_water=true
			if not cold_water():return false
		if runtime.actor(NPC).get("intent")==null:break
	check("sole owner completes NPC labor "+operation,runtime.actor(NPC).get("intent")==null)
	return runtime.actor(NPC).get("intent")==null

func run()->void:
	check("original finite rural terrain loads",world.load_snapshot(Rural.generate(713)).get("ok",false))
	var prod:=Production.empty_state();prod.tools=[{"id":SHOVEL,"kind":"shovel","holderId":SOURCE,"durability":100.0,"qualities":{"shovel":1}}]
	check("declared source tool fixture enters original CAS",commit([{"op":"extension.set","id":Production.KEY,"before_exists":false,"before":null,"after":prod}]).get("ok",false))
	services={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new()}
	var a:Dictionary={"id":NPC,"name":"D finite worker","x":29.25,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{},"intent":null,"householdId":"home-residents","relationship":{"member":true,"consent":true}}
	var player:Dictionary=a.duplicate(true);player.id="player";player.x=27.25
	var at:Dictionary=G.location(a);at.x=31.25
	var configured:=runtime.configure({"world":world,"facts":{"actors":[player,a],"stocks":[{"id":SOURCE,"location":at,"owner":"home-residents","searched":true,"items":{"r34:potato_seed":2,"r34:raw_water":2}}],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":services})
	check("real services configure without workforce probe or fake intents",configured.get("ok",false),configured.get("reason"))
	if not configured.get("ok",false):return finish()
	view=Actors.new();root.add_child(view);view.set_process(false);view.configure(runtime)
	check("original rig and real materials assemble",view.assembly_report().ok,view.assembly_report())
	var created:=issue("zone.create","player","D:field",{"spec":{"kind":"farm","region_id":"RH-HOME","bounds":{"x0":58,"x1":59,"z0":60,"z1":61},"policy":{"crop_id":"potato","worker_ids":[NPC]}}})
	check("real public zone created",created.get("ok",false),created.get("reason"))
	if not created.get("ok",false):return finish()
	if not supply("till"):return finish()
	check("actual tool leaves source exactly once",runtime.tool(SHOVEL).holderId=="pack:"+NPC and runtime.actor(NPC).pack.is_empty())
	if not work("till"):return finish()
	if not supply("sow"):return finish()
	check("only actual seed deficit fetched",runtime.actor(NPC).pack.get("r34:potato_seed")==1 and runtime.stock(SOURCE).items.get("r34:potato_seed")==1)
	if not work("sow"):return finish()
	ticks(3010,false)
	if not supply("water"):return finish()
	check("actual raw water fetched without phantom bucket",runtime.actor(NPC).pack.get("r34:raw_water")==1 and not runtime.actor(NPC).pack.has("r34:water_bucket"))
	if not work("water"):return finish()
	check("water is consumed once by original ecology",runtime.actor(NPC).pack.get("r34:raw_water",0)==0 and runtime.stock(SOURCE).items.get("r34:raw_water")==1)
	check("completed work retires temporary water container",not view._work_items.has(NPC))
	ticks(3010,false)
	if not work("harvest_crop"):return finish()
	check("sole actual harvest credits produce and retained seed",runtime.actor(NPC).pack.get("r34:potato")==3 and runtime.actor(NPC).pack.get("r34:crop_residue")==1)
	check("personal crop pack is not fabricated into a delivery",not runtime.actor(NPC).has("pending_delivery") and not Actors.is_carrying(runtime.actor(NPC)))
	var walked:=issue("walk",NPC,"",{},at)
	check("explicit executor fixture walks real crop to source",walked.get("ok",false),walked.get("reason"))
	if walked.get("ok",false):
		for _i:int in 200:
			ticks(1)
			if runtime.actor(NPC).get("intent")==null:break
		var deposited:=issue("deposit",NPC,SOURCE,{"items":{"r34:potato":3}})
		check("original actual deposit conserves finite crop",deposited.get("ok",false) and runtime.actor(NPC).pack.get("r34:potato",0)==0 and runtime.stock(SOURCE).items.get("r34:potato")==3,deposited.get("reason"))
	check("actual supply was observed before transfer",supplied_walk_samples>0,supplied_walk_samples)
	check("true labor phases use original owner projection",["till","sow","water","harvest_crop"].all(func(op:String)->bool:return active_operations.has(op)),active_operations)
	check("true water reuses one can per work segment across pause and cold",water_prop_samples>0 and working_water_nodes.size()==2 and restored_water,{"samples":water_prop_samples,"nodes":working_water_nodes.size()})
	check("all rendering reads preserve full authority",read_only)
	check("no visual promise or missing real work item",display_errors.is_empty(),display_errors)
	finish()

func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"commands":commands,"samples":samples,"display_errors":display_errors,"scope":"Explicit finite NPC/consent/source/tools fixture; real Runtime commands/B supply-route-transfer/C ecology/original D nodes. Explicit requested walk/deposit, no E arbitration or automatic clearing. Not natural economy, PCK, renderer, VA, OS or FPS."}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	if is_instance_valid(view):view.free()
	runtime.retire();print("DDD_REGIONAL_SUPPLY ",checks.size()," failed=",failed);quit(0 if failed==0 else 1)
