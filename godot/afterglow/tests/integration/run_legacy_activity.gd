extends SceneTree
const Store=preload("res://scripts/storage/native_store.gd")
const Client=preload("res://scripts/runtime/native_client.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var host:Node
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+name+" "+str(detail))
func run()->void:
	var args:=OS.get_cmdline_user_args();var directory:String=args[0]
	host=Client.new()
	for kind:String in ["drink","rest","move"]:
		var text:=FileAccess.get_file_as_string(directory+"/"+kind+".v5.json")
		var decoded:=Store.decode(text)
		check(kind+" actual old runtime checkpoint decodes",decoded.ok,decoded.get("reason"))
		if not decoded.ok:continue
		var original:Dictionary=decoded.capture.facts.actors[0].duplicate(true)
		var old:Dictionary=original.intent.duplicate(true)
		var assembly:Dictionary=host._assemble(decoded.capture)
		check(kind+" formal offscreen assembly converts before activation",assembly.ok,assembly.get("reason"))
		if not assembly.ok:continue
		var runtime:RefCounted=assembly.runtime
		var player:Dictionary=runtime.actor("player")
		check(kind+" conversion does not move actor or consume anything",Geometry.point(player)==Geometry.point(original) and player.pack==original.pack and runtime.clock()==decoded.capture.facts.time)
		check(kind+" source activity stays unchanged",Data.json_equal(decoded.capture.facts.actors[0],original))
		if kind=="drink":
			check("drink retains elapsed and duration",player.intent.owner=="runtime" and player.intent.elapsed==old.elapsed and player.intent.duration==old.duration,player.intent)
			for n in 4:runtime.tick(0.1)
			check("drink remaining work does not consume early",runtime.actor("player").pack.water==original.pack.water and runtime.actor("player").intent!=null)
			var encoded:=Store.encode(runtime.capture_checkpoint());var restored:=Store.decode(encoded.get("text",""))
			var again:Dictionary=host._assemble(restored.capture) if encoded.ok and restored.ok else {"ok":false}
			check("partially resumed native activity saves and restores once",again.ok)
			if again.ok:runtime=again.runtime
			for n in 8:runtime.tick(0.1)
			check("drink completes with exactly one real water",runtime.actor("player").pack.water==original.pack.water-1 and runtime.actor("player").intent==null,runtime.actor("player"))
			for n in 12:runtime.tick(0.1)
			check("converted activity cannot consume again",runtime.actor("player").pack.water==original.pack.water-1)
		elif kind=="rest":
			for n in 10:runtime.tick(0.1)
			var actual:Dictionary=runtime.actor("player")
			check("legacy rest retains duration and source fatigue rate",actual.intent.duration==12 and is_equal_approx(actual.fatigue,float(original.fatigue)+0.012-0.12),{"fatigue":actual.fatigue,"before":original.fatigue})
		else:
			check("old path becomes B-owned real walk",player.intent.owner=="actions" and player.intent.kind=="walk" and not player.intent.steps.is_empty(),player.intent)
			var destination:Vector3=Geometry.point(old.destination)
			for n in 150:
				runtime.tick(0.1)
				if runtime.actor("player").intent==null:break
			check("movement finishes through real collision-checked steps",Geometry.point(runtime.actor("player")).distance_to(destination)<0.15,{"player":runtime.actor("player"),"destination":old.destination})
	var bad:=Store.decode(FileAccess.get_file_as_string(directory+"/drink.v5.json"))
	if bad.ok:
		bad.capture.facts.actors[0].intent.kind="terrain"
		var rejected:Dictionary=host._assemble(bad.capture)
		check("unadapted terrain refuses rather than loading a hung actor",not rejected.ok and rejected.code=="UNSUPPORTED_LEGACY_ACTIVITY",rejected)
		bad.capture.source.conversion.active_intents="adapted"
		var unowned:Dictionary=host._assemble(bad.capture)
		check("native loading also refuses an ownerless live intent",not unowned.ok and unowned.code=="UNSUPPORTED_INTENT",unowned)
	var report:Dictionary={"scope":"actual JS-created activity fixtures and formal native assembly; not app player migration acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report));host.free();quit(1 if report.failed else 0)
