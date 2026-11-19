extends "res://tests/gameplay/factory_normal_cooperative.gd"
## A real normal-economy continuation. No injected actor, stock, job or need.
var task_id:String
var carrier:String
var delivered_events:Dictionary={}
func observe(runtime:RefCounted)->void:
	super.observe(runtime)
	for event:Dictionary in runtime.facts().ledger:
		if event.kind=="logistics-delivery-completed":delivered_events[event.id]=event.duplicate(true)
func cold_restore(runtime:RefCounted,label:String)->Dictionary:
	var encoded:Dictionary=save(runtime,label)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var native:=Native.new();var restored:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	var same:bool=restored.get("ok",false) and persisted_restore_equal(decoded.capture,restored.runtime.facts(),restored.world)
	check("canonical native payload restores complete facts and all E production cargo states "+label,same,restored.get("reason"))
	return restored if same else {"ok":false}
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"command_id":"r34:e:normal-cargo:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})
func social_contact(runtime:RefCounted,id:String,enabled:bool=false)->bool:
	# Use the social command's own actual contact/LOS policy, including when
	# revoked pack access intentionally denies the separate handoff policy.
	var started:float=runtime.clock();var attempts:Array=[]
	for attempt:int in 18:
		var ready:Dictionary=runtime.life_availability({"actor_id":"player","kind":"consent","target_id":id,"payload":{"enabled":enabled}})
		if ready.ok:
			costs.get_or_add("social_approaches",[]).append({"target":id,"started":started,"finished":runtime.clock(),"attempts":attempts})
			return true
		var goal:Dictionary=Geometry.location(runtime.actor(id))
		var offset:Vector2=Vector2.RIGHT.rotated(float(attempt%8)*PI/4)*0.9
		goal.x+=offset.x;goal.z+=offset.y
		var feet:Dictionary=runtime._services.buildings.current_space().standing_point(goal)
		var reached:Dictionary=walk(runtime,feet) if not feet.is_empty() else {"ok":false,"reason":"no supported social approach"}
		attempts.append({"time":runtime.clock(),"availability":ready,"reached":reached.get("ok",false),"target":Geometry.location(runtime.actor(id)),"player":Geometry.location(runtime.actor("player"))})
	costs.get_or_add("social_approaches",[]).append({"target":id,"started":started,"finished":runtime.clock(),"attempts":attempts})
	return false
func task(runtime:RefCounted)->Dictionary:
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if row.id==task_id:return row
	return {}
func story(runtime:RefCounted)->Dictionary:
	for row:Dictionary in runtime._services.workforce.projection().stories:
		if row.id=="ST02":return row
	return {}
func total_timber(runtime:RefCounted)->float:
	var total:float=0
	for row:Dictionary in runtime.facts().stocks:total+=float(row.items.get("timber",0))
	for row:Dictionary in runtime.facts().actors:total+=float(row.pack.get("timber",0))
	return total
func workforce_availability_case(runtime:RefCounted,actor_id:String,member:bool,consent:bool,home_arrived:bool,outside:bool)->Dictionary:
	var capture:Dictionary=runtime.capture_checkpoint().duplicate(true)
	for actor:Dictionary in capture.facts.actors:
		if actor.id!=actor_id:continue
		actor.relationship.member=member;actor.relationship.consent=consent;actor.relationship.home_arrived=home_arrived
		if outside:actor.x+=40.0
	var native:=Native.new();var built:Dictionary=native._assemble(capture);native.free()
	if not built.ok:return built
	var result:Dictionary=built.services.workforce.availability({"actor_id":actor_id,"kind":"workforce.assign","payload":{"candidate_id":"missing-candidate"}})
	built.runtime=null;built.world=null
	return result

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output_dir=args[0];source_path=args[1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	var text:String=FileAccess.get_file_as_string(source_path);source_sha=text.sha256_text()
	var decoded:Dictionary=Store.decode(text)
	check("explicit normal successful prerequisite decodes unedited",decoded.ok)
	if not decoded.ok:return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("normal cargo continuation mounts actual services",built.ok,built.get("reason"))
	if not built.ok:return finish()
	var runtime:RefCounted=built.runtime
	var boundary_unjoined:Dictionary=workforce_availability_case(runtime,"repair-resident",false,false,false,true)
	check("unjoined member outside home is rejected before candidate lookup",boundary_unjoined.code=="NO_CONSENT",boundary_unjoined)
	var boundary_revoked:Dictionary=workforce_availability_case(runtime,"repair-resident",true,false,true,true)
	check("revoked consent outside home is rejected before candidate lookup",boundary_revoked.code=="NO_CONSENT",boundary_revoked)
	var boundary_unreturned:Dictionary=workforce_availability_case(runtime,"repair-resident",true,true,false,true)
	check("member outside home without returned fact is rejected",boundary_unreturned.code=="NO_CONSENT",boundary_unreturned)
	var boundary_returned:Dictionary=workforce_availability_case(runtime,"repair-resident",true,true,true,true)
	check("returned member outside radius passes home gate and reaches B candidate validation",boundary_returned.code!="NO_CONSENT",boundary_returned)
	check("original two people retain real earned consent and return",guards.all(func(id:String)->bool:return runtime.actor(id).relationship.consent and runtime.actor(id).relationship.home_arrived))
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if row.status not in ["completed","cancelled"]:
			var cancelled:Dictionary=send(runtime,"logistics.cancel",row.id)
			check("normal completed repeating queue can be stopped",cancelled.ok,cancelled)
	var source:String=route_stock(runtime,"warehouse","storage")
	var destination:String=route_stock(runtime,"machine","output")
	var home_source:String="r34:generated:RH-HOME:home:stock:supplies"
	var conservation:float=total_timber(runtime)
	var approached:Dictionary=walk(runtime,runtime.stock(source).location)
	check("player physically reaches finite already produced boards",approached.get("ok",false),approached.get("reason"))
	if not approached.get("ok",false):return finish()
	var source_before:float=float(runtime.stock(source).items.get("timber",0))
	var destination_before:float=float(runtime.stock(destination).items.get("timber",0))
	var ids:Array=runtime.world.extension("r34:logistics").tasks.map(func(t:Dictionary)->String:return t.id)
	var created:Dictionary=send(runtime,"logistics.create","",{"source_id":source,"destination_id":destination,"items":{"timber":1},"repeat":false})
	check("normal task configuration moves no board",created.ok and total_timber(runtime)==conservation and runtime.stock(source).items.timber==source_before,created)
	if not created.ok:return finish()
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if not ids.has(row.id):task_id=row.id
	for i:int in 700:
		step(runtime)
		if task(runtime).get("phase")=="deliver" and not str(task(runtime).get("actor_id","")).is_empty():carrier=task(runtime).actor_id;break
	check("one real voluntary original person physically picks finite cargo",carrier in guards and runtime.actor(carrier).pack.get("timber")==1 and runtime.stock(source).items.timber==source_before-1 and runtime.stock(destination).items.get("timber",0)==destination_before,{"task":task(runtime),"carrier":carrier})
	if carrier.is_empty():return finish()
	note(runtime,"actual finite pickup before consent withdrawal")
	var withdrawn:Dictionary=send(runtime,"consent",carrier,{"enabled":false})
	check("normal near-field consent command interrupts real carrying",withdrawn.ok and not runtime.actor(carrier).relationship.consent and task(runtime).status=="cargo_held",withdrawn)
	if not withdrawn.ok:return finish()
	step(runtime,25)
	check("withdrawn person retains exact physical cargo and performs no delivery",runtime.actor(carrier).pack.get("timber")==1 and task(runtime).trips==0 and runtime.stock(destination).items.get("timber",0)==destination_before and total_timber(runtime)==conservation)
	check("withdrawal releases capacity without erasing task origin",runtime.world.extension("r34:logistics").reservations.is_empty() and task(runtime).source_id==source and task(runtime).actor_id==carrier)
	var dialogue:Dictionary=story(runtime)
	check("actual withdrawal dialogue preserves that person's prior real delivery",not dialogue.people[carrier].consent and dialogue.people[carrier].real_delivery and dialogue.text.contains("撤回合作") and dialogue.text.contains("确实送到过"),dialogue)
	var logistics:Dictionary=runtime.world.extension("r34:logistics")
	var restored:Dictionary=cold_restore(runtime,"normal-withdrawn-real-cargo")
	if not restored.ok:return finish()
	runtime=restored.runtime
	check("cold restore retains withdrawn task cargo identity and all reservations",Data.json_equal(logistics,runtime.world.extension("r34:logistics")) and not runtime.actor(carrier).relationship.consent and runtime.actor(carrier).pack.get("timber")==1)
	step(runtime,25)
	check("restored withdrawal cannot silently restart delivery",task(runtime).trips==0 and runtime.actor(carrier).pack.get("timber")==1 and total_timber(runtime)==conservation)
	# Restoring consent uses the social command's own contact policy. Pack
	# handoff permission intentionally remains false while consent is revoked.
	var other:String=guards.filter(func(id:String)->bool:return id!=carrier)[0]
	var other_reached:bool=social_contact(runtime,other)
	check("player really reaches other original person before withdrawal",other_reached,{"player":Geometry.location(runtime.actor("player")),"other":Geometry.location(runtime.actor(other))})
	if not other_reached:return finish()
	var other_withdrawn:Dictionary=send(runtime,"consent",other,{"enabled":false})
	check("other original person voluntarily pauses before explicit mixed assignment",other_withdrawn.ok,other_withdrawn)
	if not other_withdrawn.ok:return finish()
	var ids_before:Array=runtime.world.extension("r34:logistics").tasks.map(func(t:Dictionary)->String:return t.id)
	var next_created:Dictionary=send(runtime,"logistics.create","",{"source_id":source,"destination_id":home_source,"items":{"timber":1},"repeat":false})
	check("new finite queue configures without borrowing already carried board",next_created.ok and total_timber(runtime)==conservation and runtime.actor(carrier).pack.get("timber")==1,next_created)
	if not next_created.ok:return finish()
	var next_id:String=""
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if not ids_before.has(row.id):next_id=row.id
	var carrier_reached:bool=social_contact(runtime,carrier,true)
	check("player really returns to original withdrawn carrier without moving cargo",carrier_reached and task(runtime).trips==0 and runtime.actor(carrier).pack.get("timber")==1 and total_timber(runtime)==conservation)
	if not carrier_reached:return finish()
	var agreed:Dictionary=send(runtime,"consent",carrier,{"enabled":true})
	check("original physical carrier explicitly renews consent",agreed.ok,agreed)
	if not agreed.ok:return finish()
	sequence+=1
	check("carrier consent and home facts remain after real approach",runtime.actor(carrier).relationship.consent and runtime.actor(carrier).relationship.member and runtime.actor(carrier).relationship.home_arrived,{"actor":runtime.actor(carrier),"layout":runtime.world.extension("r34:gameplay").layout})
	var assigned:Dictionary=runtime.command({"command_id":"r34:e:mixed:assign:%d"%sequence,"actor_id":carrier,"kind":"workforce.assign","payload":{"candidate_id":next_id}})
	check("normal explicit new task assignment records intent without transferring old cargo",assigned.ok and runtime.actor(carrier).pack.get("timber")==1 and total_timber(runtime)==conservation,assigned)
	if not assigned.ok:return finish()
	var unsafe:Dictionary=runtime._services.actions.safe_handoff(carrier,next_id)
	check("B independently refuses to hand old cargo to different task",not unsafe.ok and unsafe.code=="CARGO_HANDOFF_REQUIRED",unsafe)
	note(runtime,"renewed carrier has real old cargo and new explicit assignment")
	restored=cold_restore(runtime,"normal-mixed-cargo-assignment")
	if not restored.ok:return finish()
	runtime=restored.runtime
	var old_complete:bool=false;var extra_pickup_before_old:bool=false
	for i:int in 700:
		step(runtime)
		var next_task:Dictionary=find_task(runtime,next_id)
		if task(runtime).status!="completed" and (next_task.phase=="deliver" or next_task.trips>0):extra_pickup_before_old=true
		if task(runtime).status=="completed":old_complete=true;break
	check("old reachable real cargo finishes once before explicit reassignment can occupy slot",old_complete and task(runtime).trips==1 and not extra_pickup_before_old and runtime.stock(destination).items.get("timber",0)==destination_before+1 and total_timber(runtime)==conservation,{"original":task(runtime),"next":find_task(runtime,next_id),"actor":runtime.actor(carrier)})
	if not old_complete:
		save(runtime,"normal-mixed-original-cargo-stalled");return finish()
	for i:int in 700:
		step(runtime)
		if find_task(runtime,next_id).status=="completed":break
	check("pending explicit assignment subsequently takes its own one board through B",find_task(runtime,next_id).status=="completed" and find_task(runtime,next_id).trips==1 and task(runtime).trips==1 and total_timber(runtime)==conservation,{"original":task(runtime),"next":find_task(runtime,next_id),"actor":runtime.actor(carrier)})
	check("one physical slot and original person own both sequential paid deliveries",delivered_events.values().filter(func(e:Dictionary)->bool:return e.get("task_id") in [task_id,next_id] and e.get("actor_id")==carrier).size()==2 and runtime.actor(carrier).pack.get("timber",0)==0)
	restored=cold_restore(runtime,"normal-mixed-both-delivered")
	check("final exact canonical restore preserves two single trips and conservation",restored.ok and total_timber(restored.runtime)==conservation and task(restored.runtime).trips==1 and find_task(restored.runtime,next_id).trips==1)
	finish()
func find_task(runtime:RefCounted,id:String)->Dictionary:
	for row:Dictionary in runtime.world.extension("r34:logistics").tasks:
		if row.id==id:return row
	return {}
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"stages":stage_rows,"costs":costs,"prerequisite":{"path":source_path,"sha256":source_sha},"scope":"Explicit actual A normal-economy successful save continuation; real consent/held-cargo/explicit-reassignment/sequential-delivery boundaries, no fixture facts or production simulation changes; not whole-opening rerun or PCK/OS/VA/performance qualification."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
