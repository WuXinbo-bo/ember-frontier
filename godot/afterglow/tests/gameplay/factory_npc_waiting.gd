extends SceneTree
## Actual25 overlap recovery; real Runtime ticks, no body/source injection.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Cold=preload("res://tests/gameplay/factory_route_cold.gd")
var checks:Array=[]
var samples:Array=[]
var commands:Array=[]
var output:String
var runtime:RefCounted
var options:Dictionary
var steps:int=0
var max_displacement:float=0.0
var previous:Dictionary={}
var seen_walk:bool=false
var source_path:String
var source_sha:String
func check(name:String,ok:bool,detail:Variant=null)->void:checks.append({"name":name,"ok":ok,"detail":detail})
func save(label:String)->Dictionary:
	var packed:Dictionary=Store.encode(runtime.capture_checkpoint())
	if packed.get("ok",false):FileAccess.open(output+"/"+label+".native.json",FileAccess.WRITE).store_string(packed.text)
	return packed
func cold(label:String)->void:
	var encoded:Dictionary=save(label)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	var oracle:Dictionary=Cold.compare(decoded.capture,built.runtime,int(options.native_residency_batch)) if built.get("ok",false) else built
	check("full capture including world/chunks/revision cold "+label,oracle.get("ok",false),oracle)
	if oracle.get("ok",false):runtime=built.runtime
func snapshot()->Array:
	var result:Array=[]
	for id:String in ["player","village-resident","repair-resident"]:
		var a:Dictionary=runtime.actor(id)
		result.append({"id":id,"location":Geometry.location(a),"hp":a.hp,"pack":a.pack,"hunger":a.hunger,"thirst":a.thirst,"job":a.job,"intent":a.intent,"activity":a.activity,"relationship":a.relationship})
	return result
func tick()->void:
	runtime.tick(0.1);steps+=1
	for id:String in ["village-resident","repair-resident"]:
		var a:Dictionary=runtime.actor(id);var at:Vector3=Geometry.point(a)
		if previous.has(id):max_displacement=maxf(max_displacement,at.distance_to(previous[id]))
		previous[id]=at
		if a.intent is Dictionary and a.intent.get("purpose")=="yield-service":seen_walk=true
	if steps<=30 or steps%100==0:samples.append({"step":steps,"time":runtime.clock(),"actors":snapshot()})
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];source_path=args[1];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var raw:String=FileAccess.get_file_as_string(source_path);source_sha=raw.sha256_text()
	var decoded:Dictionary=Store.decode(raw);var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("actual original overlap checkpoint mounts",built.get("ok",false))
	if not built.get("ok",false):return finish()
	runtime=built.runtime
	var before:Dictionary=runtime.facts();var workforce:Variant=runtime.world.extension("r34:workforce")
	var production:Variant=runtime.world.extension("r3:production")
	var start:Array=snapshot();samples.append({"step":0,"time":runtime.clock(),"actors":start})
	if options.probe_mode=="supply":
		var initial:float=water_total()
		# The player is already thirsty in A's real capture. Use their original
		# water before waiting for NPCs' unchanged natural threshold.
		var required_water:int=1
		if runtime.actor("player").thirst<35:
			var drank:Dictionary=runtime.command({"command_id":"r34:e:waiting:player-drink","actor_id":"player","kind":"drink"})
			commands.append({"kind":"drink","result":drank});check("player consumes original carried water lawfully",drank.get("ok",false));required_water+=1
		var supply_used:bool=false
		for i:int in 6200:
			tick()
			if runtime.facts().ledger.any(func(e:Dictionary)->bool:return e.kind=="inventory-transfer" and e.get("actor_id") in ["village-resident","repair-resident"] and float(e.get("time",0))>float(decoded.capture.facts.time) and e.get("source_id")=="r34:generated:RH-HOME:home:stock:supplies" and e.get("items",{}).get("water",0)==1):supply_used=true
			if supply_used and water_total()<=initial-required_water and ["village-resident","repair-resident"].any(func(id:String)->bool:return runtime.actor(id).thirst>60):break
		check("same shared source remains usable after real waiting and natural needs",supply_used and water_total()<=initial-required_water and ["village-resident","repair-resident"].any(func(id:String)->bool:return runtime.actor(id).thirst>60),{"water_before":initial,"water_after":water_total(),"required_actual_consumption":required_water})
	else:
		for i:int in 150:
			tick()
			if i==2:cold("mid-real-waiting-walk")
		check("idle overlap resolves through actual B walk",seen_walk and Geometry.point(runtime.actor("village-resident")).distance_to(Geometry.point(runtime.actor("repair-resident")))>=0.67,{"saw_yield_walk":seen_walk,"actors":snapshot()})
		check("short waiting does not change inventory tools or assignments",Data.json_equal(before.stocks,runtime.facts().stocks) and Data.json_equal(production,runtime.world.extension("r3:production")) and Data.json_equal(workforce,runtime.world.extension("r34:workforce")))
	check("real movement remains bounded per original fixed step",max_displacement<=0.36,{"max_displacement":max_displacement})
	check("all original bodies identities consent and place ownership remain",["player","village-resident","repair-resident"].all(func(id:String)->bool:return runtime.actor(id).hp==100 and runtime.actor(id).regionId=="RH-HOME" and runtime.actor(id).get("buildingId")==null and runtime.actor(id).get("storeyId")==null and Data.json_equal(runtime.actor(id).relationship,before.actors.filter(func(a:Dictionary)->bool:return a.id==id)[0].relationship)))
	cold("final-waiting")
	finish()
func water_total()->float:
	var total:float=0
	for stock:Dictionary in runtime.facts().stocks:total+=float(stock.get("items",{}).get("water",0))
	return total
func finish()->void:
	if runtime!=null:save("waiting-final")
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"input":{"path":source_path,"sha256":source_sha},"fixed_steps":steps,"samples":samples,"commands":commands,"scope":"Exact actual25 capture functional affected check. No actor/item/need/HP/capture injections; fixed STEP is not wall long/OS/VA/FPS qualification."}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
