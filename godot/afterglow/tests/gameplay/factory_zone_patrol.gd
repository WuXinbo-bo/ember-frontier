extends SceneTree
## Actual finite normal04 -> legal role/zone commands -> E N6/B guard paths.
## No fixture, grants, enemy injection, need reset, teleport or capture edits.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Cold=preload("res://tests/gameplay/factory_route_cold.gd")
var runtime:RefCounted
var output:String
var options:Dictionary
var checks:Array=[]
var commands:Array=[]
var observations:Array=[]
var sequence:int=0
var steps:int=0
var maximum_step:float=0
var previous:Dictionary={}
var guard_id:String="repair-resident"
var zone_id:String=""
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name)
func command(kind:String,target:String="",payload:Dictionary={},actor_id:String="player")->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":"E:zone:patrol:"+str(options.run_id)+":"+str(sequence),"actor_id":actor_id,"kind":kind,"target_id":target,"payload":payload}
	var result:Dictionary=runtime.command(request)
	commands.append({"time":runtime.clock(),"request":request,"result":result})
	return result
func water()->float:
	var total:float=0
	for stock:Dictionary in runtime.facts().stocks:total+=float(stock.items.get("water",0))
	for actor:Dictionary in runtime.facts().actors:total+=float(actor.pack.get("water",0))
	return total
func save(label:String)->Dictionary:
	var result:Dictionary=Store.encode(runtime.capture_checkpoint())
	if result.get("ok",false):FileAccess.open(output+"/"+label+".native.json",FileAccess.WRITE).store_string(result.text)
	return result
func cold(label:String)->bool:
	var encoded:Dictionary=save(label)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	var compared:Dictionary=Cold.compare(decoded.capture,built.runtime,int(options.native_residency_batch)) if built.get("ok",false) else built
	check("entire canonical authority cold "+label,compared.get("ok",false),compared)
	if compared.get("ok",false):runtime.retire();runtime=built.runtime
	return compared.get("ok",false)
func tick()->void:
	runtime.tick(.1);steps+=1
	for actor:Dictionary in runtime.facts().actors:
		if previous.has(actor.id):maximum_step=maxf(maximum_step,G.point(actor).distance_to(previous[actor.id]))
		previous[actor.id]=G.point(actor)
	if steps%10==0:
		var a:Dictionary=runtime.actor(guard_id)
		observations.append({"step":steps,"time":runtime.clock(),"actor":a,"guard_candidates":runtime.domain_service("actions").workforce_candidates(guard_id).filter(func(c:Dictionary)->bool:return c.get("kind")=="guard"),"zones":runtime.zone_records()})
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("untouched actual finite normal04 source mounts",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime
	var original:Dictionary=runtime.capture_checkpoint();var original_water:float=water();var start:float=runtime.clock()
	var old_tools:Variant=runtime.world.extension("r3:production").get("tools",[])
	check("original consenting guard is naturally near thirst threshold",runtime.actor(guard_id).relationship.get("consent",false) and float(runtime.actor(guard_id).thirst)>=35 and float(runtime.actor(guard_id).thirst)<36)
	var a:Dictionary=runtime.actor(guard_id);var x:int=floori(float(a.x)*2);var z:int=floori(float(a.z)*2)
	for offset:Vector2i in [Vector2i(0,4),Vector2i(4,0),Vector2i(0,-8),Vector2i(-8,0),Vector2i(8,4),Vector2i(8,-8)]:
		var spec:Dictionary={"kind":"patrol","region_id":a.regionId,"bounds":{"x0":x+offset.x,"z0":z+offset.y,"x1":x+offset.x+8,"z1":z+offset.y+8},"policy":{"priority":5}}
		var preview:Dictionary=runtime.zone_preview(spec)
		if not preview.get("ok",false) or int(preview.get("valid_count",0))<4:continue
		var id:String="E:actual-patrol:"+str(sequence)
		var created:Dictionary=command("zone.create",id,{"spec":spec})
		if not created.get("ok",false):continue
		zone_id=id;break
	check("real supported known cells create an enabled patrol zone",not zone_id.is_empty(),runtime.zone_records())
	if zone_id.is_empty():return finish()
	var targets:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.get("job")=="guard")
	check("created real patrol has a legal public guard role target",not targets.is_empty(),targets)
	if targets.is_empty():return finish()
	var assignments:Array=runtime.world.extension("r34:workforce").get("assignments",[])
	var cleared:Dictionary=command("workforce.clear","",{},guard_id) if assignments.any(func(row:Dictionary)->bool:return row.actor_id==guard_id) else {"ok":true,"code":"NO_PRIOR_ASSIGNMENT"}
	var assigned:Dictionary=command("job",guard_id,{"job":"guard","work_target_id":targets[0].id})
	check("original commands clear only old assignment and set legitimate guard role",cleared.get("ok",false) and assigned.get("ok",false),{"clear":cleared,"job":assigned})
	if not cleared.get("ok",false) or not assigned.get("ok",false):return finish()
	var seen:bool=false;var need:bool=false;var recovered:bool=false;var resumed:bool=false;var mid:bool=false;var arrivals:Dictionary={}
	for i:int in 750:
		tick()
		a=runtime.actor(guard_id)
		if a.get("intent") is Dictionary and a.intent.get("owner")=="actions" and a.intent.get("kind")=="guard" and a.intent.get("guard_site_id")==zone_id:
			seen=true
			if recovered:resumed=true
			if not mid:mid=cold("actual-patrol-active-cold")
		if a.get("intent") is Dictionary and a.intent.get("owner")=="runtime" and a.intent.get("kind")=="drink":need=true
		if need and float(a.thirst)>70:recovered=true
		for event:Dictionary in runtime.facts().ledger:
			if event.get("kind")=="guard-arrived" and event.get("actor_id")==guard_id and event.get("site_id")==zone_id and float(event.get("time",0))>=start:arrivals[JSON.stringify(event.get("location",{}),"",true,true)]=true
		if resumed and arrivals.size()>=2:break
	check("E N6 really admits B guard movement without manual NPC walking",seen)
	check("B actual arrivals reach at least two different physical patrol points",arrivals.size()>=2,{"points":arrivals.keys(),"steps":steps})
	check("natural N2 thirst interrupts patrol and A actually consumes finite safe water",need and recovered and water()<=original_water-1,{"need":need,"recovered":recovered,"before_water":original_water,"after_water":water(),"actor":runtime.actor(guard_id)})
	check("same consent original patrol resumes after natural self care and active cold",mid and resumed)
	var cancelled:Dictionary=command("zone.cancel",zone_id)
	check("original zone cancellation succeeds without removing the real world",cancelled.get("ok",false),cancelled)
	for i:int in 250:
		tick();a=runtime.actor(guard_id)
		if not a.get("intent") is Dictionary or a.intent.get("guard_site_id")!=zone_id:break
	for i:int in 15:tick()
	var remaining:Array=runtime.domain_service("actions").workforce_candidates(guard_id).filter(func(c:Dictionary)->bool:return c.get("site_id")==zone_id)
	check("cancelled patrol issues no new eligible work",remaining.is_empty() and (not runtime.actor(guard_id).get("intent") is Dictionary or runtime.actor(guard_id).intent.get("guard_site_id")!=zone_id))
	check("same original people HP consent and physical tools retain authority",runtime.facts().actors.size()==original.facts.actors.size() and original.facts.actors.all(func(old:Dictionary)->bool:return runtime.actor(str(old.id)).hp==old.hp and Data.json_equal(runtime.actor(str(old.id)).relationship,old.relationship)) and Data.json_equal(old_tools,runtime.world.extension("r3:production").get("tools",[])))
	check("actual movement obeys original fixed step body budget",maximum_step<=.36,{"max_metres_per_step":maximum_step})
	cold("actual-patrol-final-cold")
	finish()
func finish()->void:
	if runtime!=null:save("actual-patrol-final")
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"commands":commands,"observations":observations,"steps":steps,"scope":"Exact frozen source snapshot with immutable25 PCK carrier and actual normal04 input. Real role/zone public commands, E N6/B guard movement, natural needs, original finite water, active/final cold and cancellation. No injection/teleport/capture edit. Not fresh12 agriculture, real enemy defense, package/OS/VA/FPS or wall long qualification."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
