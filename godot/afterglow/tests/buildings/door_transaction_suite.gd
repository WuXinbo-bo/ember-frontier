extends "res://tests/buildings/door_cost_suite.gd"
## Frozen old B stack versus current B in the SAME current A/Actions runtime.
## Real commands, four 0.1s steps, exact source population/HP/consent and source
## bytes. Controlled NPC command movement is not an autonomous AI/FPS claim.
const ReferenceBuilding=preload("res://tests/buildings/supplement_reference/building_service.gd")

func reference_building()->RefCounted:return ReferenceBuilding.new()

func configure_case(imported:Dictionary,side:int,reference:bool)->Dictionary:
	var w:=World.new();w.load_snapshot(imported.world)
	var b:RefCounted=reference_building() if reference else Building.new()
	var r:=Runtime.new();var services:Dictionary={"buildings":b,"actions":Actions.new(),"production":Production.new()}
	var configured:Dictionary=r.configure({"world":w,"facts":imported.facts,"services":services})
	expect("real phase runtime configures",configured.ok,configured)
	var fixture:RefCounted=b.space();var door:Dictionary=fixture.by_id[DOOR]
	var stance:Dictionary=fixture.standing_point(fixture.use_points(door)[side])
	var f:=r.facts()
	for a:Dictionary in f.actors:
		if a.id=="player":a.merge(stance,true);a.intent=null
	configured=r.configure({"world":w,"facts":f,"services":services})
	expect("explicit two-side supported stance fixture",not stance.is_empty() and configured.ok and r.facts().actors.size()==5)
	return {"world":w,"building":b,"runtime":r,"services":services,"fixture":fixture}

func move_actual(c:Dictionary,id_suffix:String)->Dictionary:
	var moved:Array=[];var costs:Array=[]
	for a:Dictionary in c.runtime.facts().actors:
		for delta:Vector2 in [Vector2(0.007,0),Vector2(-0.007,0),Vector2(0,0.007),Vector2(0,-0.007)]:
			var destination:=Geometry.location(a);destination.x=float(destination.x)+delta.x;destination.z=float(destination.z)+delta.y
			var feet:Dictionary=c.fixture.standing_point(destination)
			if feet.is_empty() or absf(float(feet.y)-float(a.y))>=0.025 or feet.get("storeyId")!=a.get("storeyId") or feet.get("buildingId")!=a.get("buildingId"):continue
			var start:=Time.get_ticks_usec()
			var result:Dictionary=c.runtime.command({"command_id":"door-phase:move:"+id_suffix+":"+str(a.id),"actor_id":a.id,"kind":"direct_move","destination":destination,"payload":{"movement_dt":0.1,"movement_mode":"walk"}})
			costs.append(float(Time.get_ticks_usec()-start)/1000.0)
			if result.ok and Geometry.location(c.runtime.actor(a.id))!=Geometry.location(a):moved.append(a.id)
			else:expect("actual movement accepted "+str(a.id),false,result)
			break
	return {"moved":moved,"command_ms":costs}

func hint(c:Dictionary,request:Dictionary,reference:bool)->Dictionary:
	return c.runtime.availability(request) if reference else c.building.door_preview(request)

func phase_case(imported:Dictionary,side:int,index:int,reference:bool)->Dictionary:
	var c:=configure_case(imported,side,reference);var b:RefCounted=c.building;var r:RefCounted=c.runtime
	var motion:=move_actual(c,str(index)+":initial")
	expect("all original five actors really move by accepted commands",motion.moved.size()==5,motion)
	# Reset derived caches only; never time fixture setup/configuration as a door.
	var configured:Dictionary=r.configure({"world":c.world,"facts":r.facts(),"services":c.services})
	expect("fresh derived state keeps moved authority",configured.ok)
	var opening:bool=not b.instance(DOOR).door.open
	var request:Dictionary={"kind":"door","actor_id":"player","target_id":DOOR,"command_id":"door-phase:E:"+str(index),"payload":{"operation":"open" if opening else "close"}}
	var before:Dictionary=r.capture_checkpoint();var times:Dictionary={}
	var started:=Time.get_ticks_usec();var preview:=hint(c,request,reference);times.first_hint=float(Time.get_ticks_usec()-started)/1000.0
	expect("cold actual hint succeeds without authority mutation",preview.ok and r.capture_checkpoint()==before,preview)
	if not reference:expect("local hint is explicitly pending not capability",preview.proof_state=="pending" and preview.world_changes.is_empty() and preview.fact_changes.is_empty())
	times.hot_hints=[]
	for i in 8:
		started=Time.get_ticks_usec();preview=hint(c,request,reference);times.hot_hints.append(float(Time.get_ticks_usec()-started)/1000.0)
		expect("pure stationary hint has no authority effect",preview.ok and r.capture_checkpoint()==before)
	r.configure({"world":c.world,"facts":r.facts(),"services":c.services})
	started=Time.get_ticks_usec();var full:Dictionary=r.availability(request);times.cold_full_authority=float(Time.get_ticks_usec()-started)/1000.0
	expect("complete authority check still succeeds",full.ok and r.capture_checkpoint()==before,full)
	r.configure({"world":c.world,"facts":r.facts(),"services":c.services})
	started=Time.get_ticks_usec();var receipt:Dictionary=r.command(request);times.E_start_cold=float(Time.get_ticks_usec()-started)/1000.0
	expect("actual E starts timed intent without premature world effect",receipt.ok and r.actor("player").get("intent",{}).get("kind")=="door" and b.instance(DOOR).door.open!=opening,receipt)
	var begun:Dictionary=r.capture_checkpoint();var duplicate:Dictionary=r.command(request)
	expect("duplicate E identity returns receipt with no double work",duplicate==receipt and r.capture_checkpoint()==begun)
	times.fixed_ticks=[]
	for i in 4:
		started=Time.get_ticks_usec();r.tick(0.1);times.fixed_ticks.append(float(Time.get_ticks_usec()-started)/1000.0)
	times.E_completion_tick=times.fixed_ticks[-1]
	expect("actual .4s final safety commit changes exact door",b.instance(DOOR).door.open==opening and r.actor("player").intent==null and is_equal_approx(r.clock(),float(before.facts.time)+0.4),{"door":b.instance(DOOR).door,"actor":r.actor("player"),"tick_ms":times.fixed_ticks})
	var after:Dictionary=r.capture_checkpoint();request.payload.operation="close" if opening else "open";request.command_id+="-reverse"
	started=Time.get_ticks_usec();preview=hint(c,request,reference);times.post_door_first_hint=float(Time.get_ticks_usec()-started)/1000.0
	expect("first hint after physical door commit is live and pure",preview.ok and r.capture_checkpoint()==after,preview)
	started=Time.get_ticks_usec();full=r.availability(request);times.post_door_full_authority=float(Time.get_ticks_usec()-started)/1000.0
	expect("full post-door authority uses updated leaf and original residents",full.ok and r.capture_checkpoint()==after,full)
	motion=move_actual(c,str(index)+":post-door")
	expect("controlled NPC activity really moves all five after opening",motion.moved.size()==5,motion)
	var moving:Dictionary=r.capture_checkpoint()
	started=Time.get_ticks_usec();preview=hint(c,request,reference);times.moving_hint=float(Time.get_ticks_usec()-started)/1000.0
	started=Time.get_ticks_usec();full=r.availability(request);times.moving_full_authority=float(Time.get_ticks_usec()-started)/1000.0
	expect("moving actual NPC positions do not reuse stale authorization",preview.ok and full.ok and r.capture_checkpoint()==moving)
	return {"side":side,"index":index,"reference":reference,"ms":times,"motion":motion,"world":c.world.snapshot(),"facts":r.facts()}

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:=Codec.decode_checkpoint(raw)
	expect("original city source decodes",decoded.ok)
	if not decoded.ok:quit(1);return
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	expect("sole-authority tools migrate",imported.ok)
	var rows:Array=[]
	for side in 2:
		for index in 4:
			var pair:Dictionary={}
			for reference:bool in ([true,false] if index%2==0 else [false,true]):
				pair["reference" if reference else "production"]=phase_case(imported,side,index,reference)
			expect("complete real commit and actor outcome equal frozen original %d/%d"%[side,index],pair.reference.world==pair.production.world and pair.reference.facts==pair.production.facts)
			for label:String in ["reference","production"]:pair[label].erase("world");pair[label].erase("facts")
			rows.append(pair)
	expect("original v5 source bytes unchanged",FileAccess.get_file_as_string(args[0])==raw)
	print(JSON.stringify({"ok":not failed,"checks":checks,"source_sha256":raw.sha256_text(),"door_id":DOOR,"groups":rows,"scope":"headless same-current-A/runtime with frozen old-vs-current B; cold/hot hints are intentionally different public consumers; all five source actors move by actual commands; small 8-pair CPU diagnostic, no autonomous legacy AI, PCK, OS, FPS or quiet-budget qualification"}))
	quit(1 if failed else 0)
