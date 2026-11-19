extends "res://tests/buildings/door_transaction_suite.gd"
const Before=preload("res://tests/buildings/support_baseline_reference_meter.gd")
const Candidate=preload("res://tests/buildings/support_baseline_meter.gd")

func configure_case(imported:Dictionary,side:int,reference:bool)->Dictionary:
	var w:=World.new();w.load_snapshot(imported.world)
	var b:RefCounted=Before.new() if reference else Candidate.new()
	var r:=Runtime.new();var services:Dictionary={"buildings":b,"actions":Actions.new(),"production":Production.new()}
	var configured:Dictionary=r.configure({"world":w,"facts":imported.facts,"services":services})
	expect("same actual13 runtime configures",configured.ok,configured)
	var fixture:RefCounted=b.space();var door:Dictionary=fixture.by_id[DOOR]
	var stance:Dictionary=fixture.standing_point(fixture.use_points(door)[side]);var f:=r.facts()
	for a:Dictionary in f.actors:
		if a.id=="player":a.merge(stance,true);a.intent=null
	configured=r.configure({"world":w,"facts":f,"services":services})
	expect("two-side supported fixture preserves all five people",not stance.is_empty() and configured.ok and r.facts().actors.size()==5)
	return {"world":w,"building":b,"runtime":r,"services":services,"fixture":fixture}

func cold_case(imported:Dictionary,side:int,index:int,reference:bool)->Dictionary:
	var c:=configure_case(imported,side,reference);var b:RefCounted=c.building
	var before:Dictionary=c.runtime.capture_checkpoint();b.meters()
	var request:Dictionary={"kind":"door","actor_id":"player","target_id":DOOR,"command_id":"unprimed:"+str(index),"payload":{"operation":"close" if b.instance(DOOR).door.open else "open"}}
	var started:=Time.get_ticks_usec();var receipt:Dictionary=c.runtime.command(request)
	var elapsed:=float(Time.get_ticks_usec()-started)/1000.0;var meters:Dictionary=b.meters()
	expect("truly unprimed E still checks every support root",receipt.ok and meters.root_misses==971 and c.world.snapshot()==before.world,{"receipt":receipt,"roots":meters})
	return {"ms":elapsed,"roots":meters}

func startup_case(imported:Dictionary,side:int,index:int,reference:bool)->Dictionary:
	var c:=configure_case(imported,side,reference);var b:RefCounted=c.building;var r:RefCounted=c.runtime
	var times:Dictionary={};var meters:Dictionary={}
	# Match the already-shipping NativeClient._assemble boundary. No new
	# warm-up, no artificial query before the measured first E below.
	b.meters();var started:=Time.get_ticks_usec()
	var referential:Dictionary=b.validate_snapshot(c.world,r.facts())
	times.startup_referential=float(Time.get_ticks_usec()-started)/1000.0
	started=Time.get_ticks_usec()
	var valid:Dictionary=b.validate_structures(c.world,b.structures(),r.facts())
	times.startup_spatial=float(Time.get_ticks_usec()-started)/1000.0
	meters.startup=b.meters()
	expect("real startup full safety computes all971 roots once",referential.ok and valid.ok and meters.startup.root_misses==971,{"referential":referential,"spatial":valid,"roots":meters.startup})
	var motion:=move_actual(c,str(index)+":startup-first")
	expect("all five actors move through real commands after startup",motion.moved.size()==5,motion)
	var opening:bool=not b.instance(DOOR).door.open
	var request:Dictionary={"kind":"door","actor_id":"player","target_id":DOOR,"command_id":"startup-E:"+str(index),"payload":{"operation":"open" if opening else "close"}}
	var before:Dictionary=r.capture_checkpoint()
	started=Time.get_ticks_usec();var preview:Dictionary=b.door_preview(request)
	times.first_hint=float(Time.get_ticks_usec()-started)/1000.0
	expect("first moving local hint remains pending and pure",preview.ok and preview.proof_state=="pending" and r.capture_checkpoint()==before,preview)
	times.hot_hints=[]
	for n in 8:
		started=Time.get_ticks_usec();preview=b.door_preview(request)
		times.hot_hints.append(float(Time.get_ticks_usec()-started)/1000.0)
		expect("hot pending hint has no authoritative side effect",preview.ok and r.capture_checkpoint()==before)
	b.meters();started=Time.get_ticks_usec()
	var receipt:Dictionary=r.command(request)
	times.startup_first_E=float(Time.get_ticks_usec()-started)/1000.0;meters.startup_first_E=b.meters()
	expect("first E without earlier authority preflight starts actual intent",receipt.ok and r.actor("player").get("intent",{}).get("kind")=="door" and b.instance(DOOR).door.open!=opening,receipt)
	if not reference:expect("first E reuses only actual startup support roots",meters.startup_first_E.root_hits==971 and meters.startup_first_E.root_misses==0,meters.startup_first_E)
	var begun:Dictionary=r.capture_checkpoint();var duplicate:Dictionary=r.command(request)
	expect("duplicate E identity does not repeat the action",duplicate==receipt and r.capture_checkpoint()==begun)
	times.completion_ticks=[];b.meters()
	for n in 4:
		started=Time.get_ticks_usec();r.tick(0.1)
		times.completion_ticks.append(float(Time.get_ticks_usec()-started)/1000.0)
	times.completion=times.completion_ticks[-1];meters.completion=b.meters()
	expect("real0.4 completion commits exact door and clears intent",b.instance(DOOR).door.open==opening and r.actor("player").intent==null and is_equal_approx(r.clock(),float(before.facts.time)+0.4))
	motion=move_actual(c,str(index)+":after-door")
	expect("all five actors really move again after door commit",motion.moved.size()==5,motion)
	request.command_id+="-reverse";request.payload.operation="close" if opening else "open"
	var after:Dictionary=r.capture_checkpoint();started=Time.get_ticks_usec();preview=b.door_preview(request)
	times.post_door_hint=float(Time.get_ticks_usec()-started)/1000.0
	expect("first post-door hint is fresh and pure",preview.ok and r.capture_checkpoint()==after,preview)
	b.meters();started=Time.get_ticks_usec();receipt=r.command(request)
	times.post_door_moving_E=float(Time.get_ticks_usec()-started)/1000.0;meters.post_door_moving_E=b.meters()
	expect("post-door moving E starts without a warm authority call",receipt.ok,receipt)
	if not reference:expect("paired door commit preserves only static support proof",meters.post_door_moving_E.root_hits==971 and meters.post_door_moving_E.root_misses==0,meters.post_door_moving_E)
	for n in 4:r.tick(0.1)
	expect("reverse completion preserves original five-actor game outcome",b.instance(DOOR).door.open!=opening and r.actor("player").intent==null and r.facts().actors.size()==5)
	return {"side":side,"index":index,"ms":times,"roots":meters,"world":c.world.snapshot(),"facts":r.facts()}

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:=Codec.decode_checkpoint(raw)
	expect("preserved city input decodes",decoded.ok)
	if not decoded.ok:quit(1);return
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	expect("same sole-authority tool migration",imported.ok)
	var rows:Array=[]
	for side in 2:
		for index in 4:
			var pair:Dictionary={}
			for reference:bool in ([true,false] if index%2==0 else [false,true]):
				var name:="reference" if reference else "production"
				pair[name]=startup_case(imported,side,index,reference)
				pair[name].unprimed=cold_case(imported,side,index,reference)
			expect("complete world/facts equal actual13 plus identical Snapshot %d/%d"%[side,index],pair.reference.world==pair.production.world and pair.reference.facts==pair.production.facts)
			for name:String in ["reference","production"]:pair[name].erase("world");pair[name].erase("facts")
			rows.append(pair)
	expect("original v5 input bytes unchanged",FileAccess.get_file_as_string(args[0])==raw)
	print(JSON.stringify({"ok":not failed,"checks":checks,"groups":rows,"scope":"actual13 plus identical Snapshot both sides; startup already-full safety then real five-person movement/first E/no authority warmup/.4s/door/movement/next E; unprimed cold separate; nonquiet CPU not OS/FPS/P0 qualification"}))
	quit(1 if failed else 0)
