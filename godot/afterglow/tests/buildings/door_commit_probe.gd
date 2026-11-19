extends "res://tests/buildings/door_cost_suite.gd"
## Inclusive test-only hooks around actual E completion. Never add nested rows.
class MeteredWorld extends "res://scripts/world/world_state.gd":
	var meters:Dictionary={}
	func record(label:String,t:int)->void:
		if not meters.has(label):meters[label]={"calls":0,"usec":0}
		meters[label].calls+=1;meters[label].usec+=Time.get_ticks_usec()-t
	func prepare_changes(changes:Array,revision:int)->Dictionary:
		var t:=Time.get_ticks_usec();var out:=super.prepare_changes(changes,revision);record("C_prepare_changes",t);return out
	func commit_prepared(capability:Variant)->Dictionary:
		var t:=Time.get_ticks_usec();var out:=super.commit_prepared(capability);record("C_commit_prepared",t);return out
class MeteredBuilding extends "res://tests/buildings/door_phase_suite.gd".MeteredBuilding:
	func validate_world_draft(view:RefCounted,facts:Dictionary,changes:Array)->Dictionary:
		var t:=Time.get_ticks_usec();var out:=super.validate_world_draft(view,facts,changes);record("B_validate_world_draft",t);return out

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var rows:Array=[]
	for side in 2:
		var w:=MeteredWorld.new();w.load_snapshot(imported.world)
		var b:=MeteredBuilding.new();var r:=Runtime.new();var services:Dictionary={"buildings":b,"actions":Actions.new(),"production":Production.new()}
		expect("actual runtime configures",r.configure({"world":w,"facts":imported.facts,"services":services}).ok)
		var q:RefCounted=b.space();var f:=r.facts();var points:Array=q.use_points(q.by_id[DOOR])
		for a:Dictionary in f.actors:
			if a.id=="player":a.merge(q.standing_point(points[side]),true);a.intent=null
		expect("actual stance fixture configures",r.configure({"world":w,"facts":f,"services":services}).ok)
		var request:Dictionary={"command_id":"commit-probe:"+str(side),"actor_id":"player","kind":"door","target_id":DOOR,"payload":{"operation":"open"}}
		b.meters.clear();w.meters.clear();var t:=Time.get_ticks_usec();var result:=r.command(request)
		rows.append({"side":side,"phase":"actual_cold_E_start","elapsed_ms":float(Time.get_ticks_usec()-t)/1000.0,"B":b.meters.duplicate(true),"C":w.meters.duplicate(true)})
		expect("actual cold E starts",result.ok,result)
		for i in 3:r.tick(0.1)
		b.meters.clear();w.meters.clear();t=Time.get_ticks_usec();r.tick(0.1)
		rows.append({"side":side,"phase":"actual_E_completion_tick","elapsed_ms":float(Time.get_ticks_usec()-t)/1000.0,"B":b.meters.duplicate(true),"C":w.meters.duplicate(true)})
		expect("actual completion opens existing door",b.instance(DOOR).door.open and r.actor("player").intent==null)
	print(JSON.stringify({"ok":not failed,"checks":checks,"rows":rows,"scope":"nested inclusive test-only native CPU hooks on real E start and .4s completion, not additive phases, quiet/PCK/FPS qualification"}))
	quit(1 if failed else 0)
