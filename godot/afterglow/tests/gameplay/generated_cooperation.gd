extends "res://tests/integration/run_resident_life.gd"
## Unmodified generated opening, real commands and bounded physical travel.
## No teleports, inventory grants, forced consent, or replacement executors.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
var output_dir:String
var route_steps:Array=[]
var ticks:=0
var jumps:Array=[]
var previous:Dictionary={}
var command_prefix:="E-generated:"
var evidence_kind:="unmodified-generated-opening"

func persistent_world(value:Dictionary)->Dictionary:
	var result:Dictionary=value.duplicate(true)
	# C's codec restores cold chunks; A makes them resident in one transaction.
	# These are cache/CAS revisions, not persistent terrain or gameplay changes.
	result.erase("revision")
	for chunk:Dictionary in result.chunks.values():chunk.erase("revision")
	return result

func check(name:String,ok:bool,detail:Variant=null)->void:
	super.check(name,ok,detail)
	if runtime!=null and not output_dir.is_empty():write_progress()
	if not ok and runtime!=null:
		write_json("failure-"+str(checks.size())+"-capture.json",runtime.capture_checkpoint())

func write_progress()->void:
	var actors:Array=[]
	for a:Dictionary in runtime.facts().actors:
		var intent:Variant=a.get("intent")
		actors.append({"id":a.id,"at":Geometry.location(a),"activity":a.activity,"intent_owner":intent.get("owner") if intent is Dictionary else null,"intent_kind":intent.get("kind") if intent is Dictionary else null,"last_failure":a.get("self_routine",{}).get("last_failure"),"job":a.get("job")})
	write_json("progress.json",{"ticks":ticks,"time":runtime.clock(),"checks":checks,"actors":actors})

func write_json(name:String,value:Variant)->void:
	var file:=FileAccess.open(output_dir+"/"+name,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t",true,true));file.close()

func send(kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	seq+=1
	var request:Dictionary={"command_id":command_prefix+str(seq),"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"expected_revision":runtime.get_revision()}
	if not destination.is_empty():request.destination=destination
	var result:Dictionary=runtime.command(request)
	route_steps.append({"request":request,"result":result,"player":Geometry.location(runtime.actor("player")),"time":runtime.clock()})
	return result

func step()->void:
	for id:String in ["player","village-resident","repair-resident"]:previous[id]=Geometry.point(runtime.actor(id))
	runtime.tick(0.1);ticks+=1
	var movement:Dictionary=runtime.actor_presentation().get("movement",{})
	for id:String in previous:
		var delta:Vector3=Geometry.point(runtime.actor(id))-previous[id]
		# B measures walking speed in x/z and snaps feet to real 0.5m steps.
		# A slope step's 3D diagonal is not a horizontal speed violation.
		var speed:float=Movement.RUN_SPEED if movement.get(id,{}).get("mode")=="run" else Movement.WALK_SPEED
		if Vector2(delta.x,delta.z).length()>speed*0.1+0.001 or absf(delta.y)>0.501:jumps.append({"id":id,"time":runtime.clock(),"delta":[delta.x,delta.y,delta.z]})
	if ticks%50==0:
		var actors:Array=[]
		for a:Dictionary in runtime.facts().actors:actors.append({"id":a.id,"at":Geometry.location(a),"activity":a.activity,"intent":a.get("intent"),"relationship":a.relationship})
		route_steps.append({"time":runtime.clock(),"actors":actors})
		write_progress()

func idle(limit:int=2000)->bool:
	for i:int in limit:
		if runtime.actor("player").intent==null:return true
		step()
	return false

func perform(label:String,kind:String,target:String="",payload:Dictionary={})->bool:
	var r:Dictionary=send(kind,target,payload)
	var ok:bool=r.ok and idle()
	check(label,ok,r if not ok else null)
	return ok

func walk(point:Dictionary,label:String)->bool:
	var start:Dictionary=Geometry.location(runtime.actor("player"))
	var r:Dictionary=send("walk","",{},point)
	var ok:bool=r.ok and idle() and runtime.actor("player").regionId==point.regionId and Geometry.point(runtime.actor("player")).distance_to(Geometry.point(point))<0.4
	check(label,ok,{"from":start,"to":point,"result":r,"actor":runtime.actor("player")} if not ok else null)
	return ok

func stock_at(id:String)->bool:
	var s:Dictionary=runtime.stock(id)
	var points:Array=runtime._services.buildings.use_points(str(s.get("structureId","")))
	if points.is_empty():points=[Geometry.location(s)]
	var trials:Array=[]
	for point:Dictionary in points:
		var r:Dictionary=send("walk","",{},point)
		if r.ok and idle() and runtime._services.production.reach("player",id,runtime.stock(id),"search")==null:
			check("physical arrival at "+id,true);return true
		trials.append({"point":point,"result":r,"actor":runtime.actor("player")})
	check("physical arrival at "+id,false,trials);return false

func near_person(id:String)->bool:
	var player:Dictionary=runtime.actor("player");var person:Dictionary=runtime.actor(id)
	return player.regionId==person.regionId and player.get("buildingId")==person.get("buildingId") and player.get("storeyId")==person.get("storeyId") and Geometry.point(player).distance_to(Geometry.point(person))<=2.1 and runtime._services.buildings.current_space().line_clear(Geometry.location(player),Geometry.location(person),"")

func approach(id:String)->bool:
	# Cooperating followers are already walking to the player. Give that real
	# route time to arrive before chasing their older destination in reverse.
	var target:Dictionary=runtime.actor(id)
	if target.relationship.get("consent",false) and target.get("job")=="follow":
		for i:int in 800:
			if near_person(id):return true
			if runtime.actor(id).intent==null and Geometry.point(runtime.actor("player")).distance_to(Geometry.point(runtime.actor(id)))<=2.5:break
			step()
	for attempt:int in 6:
		if near_person(id):return true
		var p:Dictionary=Geometry.location(runtime.actor(id))
		var r:Dictionary=send("walk","",{},p)
		if not r.ok:
			check("physical approach to "+id,false,{"target":runtime.actor(id),"player":runtime.actor("player"),"result":r});return false
		for i:int in 1800:
			# The autonomous person keeps moving. Stop the player's real route
			# as soon as actually in interaction range, rather than chasing an
			# obsolete destination after already walking past the person.
			if near_person(id):
				if runtime.actor("player").intent!=null:return send("cancel").ok
				return true
			if runtime.actor("player").intent==null:break
			step()
	check("physical approach to "+id,false,{"target":runtime.actor(id),"player":runtime.actor("player")});return false

func wait_fact(label:String,predicate:Callable,limit:int=2200)->bool:
	for i:int in limit:
		if predicate.call():check(label,true);return true
		step()
	check(label,false,{"actors":runtime.facts().actors,"orders":runtime.world.extension("r3:production").orders,"structure_orders":runtime.world.extension("r3:structure-orders")});return false

func roundtrip(label:String)->bool:
	var capture:Dictionary=runtime.capture_checkpoint()
	write_json("roundtrip-"+str(seq)+"-before.json",capture)
	var encoded:Dictionary=Store.encode(capture)
	var decoded:Dictionary=Store.decode(encoded.get("text",""))
	check(label+" native codec",encoded.ok and decoded.ok,encoded.get("reason",decoded.get("reason")))
	if not encoded.ok or not decoded.ok:return false
	if not mount(decoded.capture):return false
	write_json("roundtrip-"+str(seq)+"-after.json",runtime.capture_checkpoint())
	var canonical:Dictionary=JSON.parse_string(JSON.stringify(capture,"",true,true))
	var changed:Array=differences(canonical.facts,runtime.facts(),"facts",[])
	differences(persistent_world(canonical.world),persistent_world(runtime.world.snapshot()),"world",changed)
	check(label+" exact discrete facts/cells and bounded JSON continuous roundtrip",changed.is_empty(),changed)
	check(label+" comparator rejects changed inventory and meaningful time",not differences({"pack":{"food":1.0}},{"pack":{"food":1.00000000000001}},"facts",[]).is_empty() and not differences({"time":1.0},{"time":1.000000001},"facts",[]).is_empty())
	return changed.is_empty()

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	host=Client.new()
	var generated:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("unmodified current generated opening prepares",generated.ok,generated.get("reason"))
	if not generated.ok or not mount(generated.capture):finish();return
	write_json("opening-capture.json",runtime.capture_checkpoint())
	check("original three actors and finite original player pack",runtime.facts().actors.size()==3 and runtime.actor("player").pack=={"food":1,"water":1})
	cooperation_route()
	finish()

func cooperation_route()->void:
	var layout:Dictionary=runtime.world.extension(Gameplay.KEY).layout
	var home:String=str(layout.home_building)
	var home_stock:String=home+":storage"
	var shed_stock:String="RH-HOME:shed:storage"
	if not stock_at(home_stock):return
	if not perform("take finite home help supplies","take",home_stock,{"items":{"food":1,"water":2}}):return
	if not stock_at(shed_stock):return
	if not perform("search actual generated shed","search",shed_stock):return
	var tools:Array=[]
	for t:Dictionary in runtime.world.extension("r3:production").tools:
		if t.holderId==shed_stock:tools.append(t.id)
	if not perform("take actual finite tools manual materials","take",shed_stock,{"items":{"timber":8,"scrap":6,"book_woodwork":1},"tool_ids":tools}):return
	for id:String in ["village-resident","repair-resident"]:
		if not approach(id):return
		var before:Dictionary=runtime.actor("player").pack.duplicate(true)
		var item:String="water" if id=="village-resident" else "food"
		if not perform("real paid help "+id,"help",id,{"items":{item:1}}):return
		check("help debits player and credits exactly one "+id,float(runtime.actor("player").pack[item])==float(before[item])-1 and float(runtime.actor(id).pack.get(item,0))==1)
		if not perform("voluntary invitation "+id,"invite",id):return
		var denied:Dictionary=send("job",id,{"job":"gather","work_target_id":"none"})
		check("assignment never bypasses actual home arrival or invents a work target "+id,not denied.ok and denied.code in ["RETURN_HOME_FIRST","MISSING_WORK_TARGET"],denied)
	if not stock_at(home_stock):return
	if not wait_fact("both original residents physically follow home",func()->bool:return runtime.actor("village-resident").relationship.get("home_arrived",false) and runtime.actor("repair-resident").relationship.get("home_arrived",false)):return
	check("both home facts reflect actual generated radius",runtime._services.gameplay._at_home(runtime.actor("village-resident")) and runtime._services.gameplay._at_home(runtime.actor("repair-resident")))
	if not roundtrip("real joined return-home route"):return
	write_json("returned-home-capture.json",runtime.capture_checkpoint())
	if not approach("repair-resident"):return
	var hammer:String="";var saw:String="";var axe:String=""
	for t:Dictionary in runtime.world.extension("r3:production").tools:
		if t.holderId!="pack:player":continue
		match str(t.kind):
			"hammer":hammer=t.id
			"hand_saw":saw=t.id
			"salvaged_axe":axe=t.id
	check("finite original tools remain actual carried identities",not hammer.is_empty() and not saw.is_empty() and not axe.is_empty(),tools)
	if hammer.is_empty() or saw.is_empty() or axe.is_empty():return
	if not perform("hand real tools manual materials to consenting repair resident","deposit","pack:repair-resident",{"items":{"timber":6,"scrap":2,"book_woodwork":1},"tool_ids":[hammer,saw]}):return
	var study:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.work_payload.get("action_kind")=="study" and runtime.world.extension("r3:production").records.any(func(r:Dictionary)->bool:return r.id==t.actual_target_id and r.holderId=="pack:repair-resident"))
	check("one actual transferred manual is assignable",study.size()==1,study)
	if study.size()!=1:return
	if not perform("assign existing B study executor","job","repair-resident",{"job":"craft","work_target_id":study[0].id}):return
	if not wait_fact("repair resident really learns carried finite manual",func()->bool:return runtime.world.extension("r3:production").knowledge.get("repair-resident",[]).has("basic_woodwork")):return
	var builds:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return str(t.id).begins_with("work:build:"))
	check("generated real workbench reservation exists",builds.size()==1,builds)
	if builds.size()!=1:return
	if not perform("assign existing B construction executor","job","repair-resident",{"job":"craft","work_target_id":builds[0].id}):return
	var bench:String=builds[0].actual_target_id
	if not wait_fact("resident physically builds generated home workbench",func()->bool:return not runtime.world.entity(bench).is_empty()):return
	check("real construction consumes finite NPC materials",runtime.actor("repair-resident").pack.timber==2 and runtime.actor("repair-resident").pack.scrap==0)
	var crafts:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.actual_target_id==bench and t.work_payload.get("recipe_id")=="make_handle")
	check("built workbench exposes actual handle recipe",crafts.size()==1,crafts)
	if crafts.size()!=1:return
	if not perform("assign real handle craft","job","repair-resident",{"job":"craft","work_target_id":crafts[0].id}):return
	if not wait_fact("resident makes actual handle with carried saw",func()->bool:return float(runtime.actor("repair-resident").pack.get("tool_handle",0))==1):return
	if not perform("voluntary rest after product","job","repair-resident",{"job":"rest"}):return
	var resting_position:Vector3=Geometry.point(runtime.actor("repair-resident"))
	if not approach("village-resident"):return
	if not perform("hand finite axe to consenting original village resident","deposit","pack:village-resident",{"tool_ids":[axe]}):return
	var trees:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.job=="gather" and runtime.world.entity(t.actual_target_id).regionId=="RH-HOME")
	trees.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return Geometry.point(runtime.world.entity(x.actual_target_id)).distance_squared_to(Geometry.point(runtime.actor("village-resident")))<Geometry.point(runtime.world.entity(y.actual_target_id)).distance_squared_to(Geometry.point(runtime.actor("village-resident"))))
	check("generated home has actual harvest targets",not trees.is_empty())
	if trees.is_empty():return
	var tree:Dictionary=trees[0]
	check("generated harvest has actual home delivery ID",tree.work_payload.delivery_id==home_stock,tree)
	var logs_before:float=float(runtime.stock(home_stock).items.get("log",0))
	if not perform("assign actual generated tree labor","job","village-resident",{"job":"gather","work_target_id":tree.id}):return
	if not wait_fact("original resident harvests and physically hauls logs home",func()->bool:return float(runtime.stock(home_stock).items.get("log",0))==logs_before+3,1400):return
	check("actual tool is worn by work and remains same owned identity",runtime.tool(axe).holderId=="pack:village-resident" and runtime.tool(axe).durability<90)
	if not perform("stop repeating completed tree via rest","job","village-resident",{"job":"rest"}):return
	check("voluntary resting companion stays home instead of resuming old village patrol",Geometry.point(runtime.actor("repair-resident")).distance_to(resting_position)<0.001,runtime.actor("repair-resident"))
	if not roundtrip("completed finite cooperative labor"):return
	write_json("completed-labor-capture.json",runtime.capture_checkpoint())

func finish()->void:
	if runtime!=null:write_json("final-capture.json",runtime.capture_checkpoint())
	check("all observed steps obey B horizontal speed and supported half-metre steps",jumps.is_empty(),jumps)
	var report:Dictionary={"scope":"actual original-NPC command route or explicitly supplied recorded-route continuation; no OS-input/app/VA/performance qualification","evidence_kind":evidence_kind,"generator":runtime.world.identity().get("generatorVersion","") if runtime!=null else "","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"ticks":ticks,"route":route_steps}
	write_json("results.json",report)
	print(JSON.stringify({"failed":report.failed,"checks":checks.size(),"ticks":ticks}))
	if host!=null:host.free()
	quit(1 if report.failed else 0)
