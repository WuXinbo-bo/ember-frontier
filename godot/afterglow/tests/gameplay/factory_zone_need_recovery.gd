extends SceneTree
## Real needs after B's existing finite normal paid-home success branch.
## This run injects nothing: original needs cross their natural threshold,
## B really transfers water and A consumes it; full Native cold oracle.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Cold=preload("res://tests/gameplay/factory_route_cold.gd")
var checks:Array=[]
var observations:Array=[]
var commands:Array=[]
var output:String
var runtime:RefCounted
var options:Dictionary
var steps:int=0
var previous:Dictionary={}
var max_step:float=0
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name)
func water()->float:
	var total:float=0
	for s:Dictionary in runtime.facts().stocks:total+=float(s.get("items",{}).get("water",0))
	for a:Dictionary in runtime.facts().actors:total+=float(a.get("pack",{}).get("water",0))
	return total
func save(label:String)->Dictionary:
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	if encoded.get("ok",false):FileAccess.open(output+"/"+label+".native.json",FileAccess.WRITE).store_string(encoded.text)
	return encoded
func cold(label:String)->bool:
	var encoded:Dictionary=save(label);var decoded:Dictionary=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	var result:Dictionary=Cold.compare(decoded.capture,built.runtime,int(options.native_residency_batch)) if built.get("ok",false) else built
	check("full facts world voxels revisions receipts cold "+label,result.get("ok",false),result)
	if result.get("ok",false):runtime.retire();runtime=built.runtime
	return result.get("ok",false)
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("exact original recovery success save mounts without edits",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime;var start:Dictionary=runtime.facts();var original_water:float=water()
	var original_tools:Variant=runtime.world.extension("r3:production").get("tools",[])
	check("original two consenting residents are naturally just above thirst threshold",["village-resident","repair-resident"].all(func(id:String)->bool:return float(runtime.actor(id).thirst)>=35 and float(runtime.actor(id).thirst)<36 and runtime.actor(id).relationship.get("consent",false)))
	var mid_saved:bool=false;var drank:Dictionary={}
	for i:int in 900:
		runtime.tick(0.1);steps+=1
		var rows:Array=[]
		for id:String in ["village-resident","repair-resident"]:
			var a:Dictionary=runtime.actor(id);var at:Vector3=G.point(a)
			if previous.has(id):max_step=maxf(max_step,at.distance_to(previous[id]))
			previous[id]=at
			if a.intent is Dictionary and a.intent.get("owner")=="runtime" and a.intent.get("kind")=="drink" and not mid_saved:
				mid_saved=cold("mid-actual-autonomous-drink")
				a=runtime.actor(id)
			if float(a.thirst)>70:drank[id]=true
			rows.append({"id":id,"thirst":a.thirst,"hunger":a.hunger,"fatigue":a.fatigue,"hp":a.hp,"pack":a.pack,"location":G.location(a),"intent":a.intent,"decision":a.get("self_routine",{}).get("factory_decision",{})})
		if steps%10==0:observations.append({"step":steps,"time":runtime.clock(),"actors":rows})
		if drank.size()==2:break
	check("both original residents really cross need and drink finite safe water",drank.size()==2 and water()==original_water-2,{"drank":drank,"before":original_water,"after":water(),"steps":steps})
	check("actual autonomous timed drinking survives cold mid-action",mid_saved)
	check("same B shared source really transfers each water before consumption",["village-resident","repair-resident"].all(func(id:String)->bool:return runtime.facts().ledger.any(func(e:Dictionary)->bool:return e.get("kind")=="inventory-transfer" and e.get("actor_id")==id and float(e.get("time",0))>float(start.time) and float(e.get("items",{}).get("water",0))==1)))
	check("real original movement remains within fixed-step body budget",max_step<=0.36,{"max_metres_per_step":max_step})
	check("original HP identities cooperation and food retained without a grant",runtime.facts().actors.size()==start.actors.size() and start.actors.all(func(old:Dictionary)->bool:return runtime.actor(str(old.id)).hp==old.hp and Data.json_equal(runtime.actor(str(old.id)).relationship,old.relationship) and runtime.actor(str(old.id)).pack.get("food",0)==old.pack.get("food",0)))
	check("no tools replenished replaced or consumed by water self care",Data.json_equal(original_tools,runtime.world.extension("r3:production").get("tools",[])))
	cold("final-actual-autonomous-needs")
	finish()
func finish()->void:
	if runtime!=null:save("actual-needs-final")
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"steps":steps,"observations":observations,"scope":"Actual immutable B normal04 finite paid-home success input. This run only original Runtime ticks and autonomous B water transfer/A timed consumption/full cold; no fixture, no changed needs/HP/position/materials. Not content12 fresh journey/forestry/farm/canteen/beds/OS/VA/FPS or wall long."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
