extends SceneTree
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func run()->void:
	var service:=Terrain.new()
	var intent:Dictionary={"schema_version":1,"id":"test:terrain","source_id":"pack:player","cost":{"soil_m3":0.125},"owner":"terrain","kind":"terrain","request":{"command_id":"test:terrain","actor_id":"player","kind":"terrain","payload":{"tool_id":"tool:shovel","edit":{"operation":"fill","material":2,"cells":[{"x":-1,"y":0,"z":2}]}}},"elapsed":0.25,"duration":1.5,"tool_id":"tool:shovel","held":true}
	var actor:Dictionary={"id":"player","hp":100,"intent":intent};var facts:Dictionary={"actors":[actor]}
	check("v1 provider works before scene/world configure",service.validate_intent(intent,actor,facts).ok)
	var old:Dictionary=intent.duplicate(true);old.erase("schema_version")
	check("explicit legacy terrain v0 accepted",service.validate_intent(old,actor,facts).ok)
	for pair:Array in [["schema_version",2],["schema_version","1"],["owner","other"],["kind","other"],["id",null],["elapsed",NAN],["duration",0],["elapsed",2],["held",1],["cost",[]],["cost",{"soil_m3":-1}],["source_id","pack:other"],["tool_id","tool:other"]]:
		var bad:Dictionary=intent.duplicate(true);bad[pair[0]]=pair[1]
		check("reject bad "+str(pair),not service.validate_intent(bad,actor,facts).ok)
	for field:String in ["request","elapsed","duration","held","tool_id","cost","source_id"]:
		var bad:Dictionary=intent.duplicate(true);bad.erase(field)
		check("v1 rejects missing "+field,not service.validate_intent(bad,actor,facts).ok)
	for edit:Variant in [{"operation":"water"},{"operation":"fill","cells":"wrong"},{"operation":"dig","cells":[{"x":0.5,"y":0,"z":0}]},{"operation":"fill","cells":[]},{"operation":"fill","material":99,"cells":[{"x":0,"y":0,"z":0}]},{"operation":"level","area":{},"height":NAN}]:
		var bad:Dictionary=intent.duplicate(true);bad.request.payload.edit=edit
		check("reject malformed edit "+str(edit),not service.validate_intent(bad,actor,facts).ok)
	var wrong:Dictionary=actor.duplicate(true);wrong.id="other"
	check("bad actor reference rejected",not service.validate_intent(intent,wrong,facts).ok)
	var stamp:Dictionary=facts.duplicate(true);var holds:Array=service.hold_descriptors(facts)
	check("one derived hold has exact cost/tool/source",holds.size()==1 and holds[0].cost=={"soil_m3":0.125} and holds[0].tool_ids==["tool:shovel"] and holds[0].source_id=="pack:player" and holds[0].phase=="active")
	holds[0].cost.soil_m3=999
	check("provider never leaks mutable facts",Data.json_equal(facts,stamp))
	actor.intent.held=false
	check("paused physical held state retains paused reservation",service.hold_descriptors(facts)[0].phase=="paused")
	actor.hp=0
	check("disabled actor emits no live hold",service.hold_descriptors(facts).is_empty())
	actor.hp=100;actor.intent=null
	check("cancelled intent releases hold without a persistent table",service.hold_descriptors(facts).is_empty())
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"scope":"pure terrain schema/derived hold only; real runtime consumption separately tested"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(1 if failed else 0)
