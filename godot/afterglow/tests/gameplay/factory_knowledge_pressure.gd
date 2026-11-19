extends "res://tests/gameplay/factory_normal_mixed.gd"
## Tests-only continuation of immutable 18. No capture edits or material grants.
const Tx=preload("res://scripts/actions/domain_draft.gd")
const SHED="r34:generated:RH-HOME:woodwork"
const TOOLSTOCK=SHED+":stock:tools"
const SAW=SHED+":tool:hand_saw"
const HAMMER=SHED+":tool:hammer"
const BOARDS="r34:normal-built-woodshop:stock:output"
const CACHE="r34:normal-built-woodshop:stock:tools"
const HOME="r34:generated:RH-HOME:home:stock:supplies"
var injections:Array=[]
var sources:Array=[]
var started:int=Time.get_ticks_msec()
var ticks:int=0
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"command_id":"r34:e:knowledge-pressure:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})
func step(runtime:RefCounted,count:int=1)->void:
	for i:int in count:
		if Time.get_ticks_msec()-started>100000 or ticks>=20000:
			check("bounded driver budget",false,{"ticks":ticks});finish();return
		runtime.tick(0.1);ticks+=1;observe(runtime)
func load_actual(path:String)->Dictionary:
	var text:String=FileAccess.get_file_as_string(path)
	sources.append({"path":path,"sha256":text.sha256_text()})
	var d:Dictionary=Store.decode(text)
	check("untouched explicit source decodes "+path.get_file(),d.ok)
	if not d.ok:return d
	var n:=Native.new();var b:Dictionary=n._assemble(d.capture);n.free()
	check("18 mounts actual source "+path.get_file(),b.get("ok",false),b.get("reason"))
	return b
func contact(runtime:RefCounted,id:String)->bool:
	var stock:Dictionary=runtime.stock(id)
	for offset:Vector2 in [Vector2.ZERO,Vector2(0,-1.2),Vector2(1.2,0),Vector2(-1.2,0),Vector2(0,1.2)]:
		if runtime._services.production.reach("player",id,stock,"search")==null:return true
		var at:Dictionary=stock.location.duplicate(true);at.x+=offset.x;at.z+=offset.y
		var feet:Dictionary=runtime._services.buildings.current_space().standing_point(at)
		if not feet.is_empty():walk(runtime,feet)
	return runtime._services.production.reach("player",id,stock,"search")==null
func transfer(runtime:RefCounted,kind:String,id:String,items:Dictionary,tools:Array=[])->bool:
	if not contact(runtime,id):check("real contact "+id,false);return false
	if not runtime.stock(id).get("searched",false):
		var searched:Dictionary=send(runtime,"search",id)
		if not searched.ok or not progress(runtime).finished:return false
	var r:Dictionary=send(runtime,kind,id,{"items":items,"tool_ids":tools})
	check("finite actual "+kind+" "+id,r.ok,r)
	return r.ok
func craft_request(recipe:String,tool:String)->Dictionary:
	return {"direct":false,"recipe_id":recipe,"source_id":"pack:player","output_id":"pack:player","tool_ids":[tool]}
func knowledge()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	var b:Dictionary=load_actual(args[1]);if not b.get("ok",false):return
	var r:RefCounted=b.runtime
	var known:Dictionary=r.world.extension("r3:production").knowledge
	if not transfer(r,"take","RH-HOME:stockyard-content:container",{"r34:salvaged_drive_unit":1}):return
	if not transfer(r,"take",TOOLSTOCK,{"timber":1},[SAW]):return
	check("real finite salvaged drive pickup grants no knowledge",Data.json_equal(known,r.world.extension("r3:production").knowledge) and r.actor("player").pack.get("r34:salvaged_drive_unit")==1)
	var negative_payload:Dictionary=craft_request("make_handle",SAW);negative_payload.direct=true
	var refused:Dictionary=send(r,"craft",SHED+":workbench",negative_payload)
	check("carrying equipment cannot bypass a real existing recipe knowledge gate",not refused.ok and str(refused.get("reason","")).contains("尚未学习"),refused)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	check("18 has no salvaged drive manufacturing recipe; no invented technology claimed",not catalog.production_recipes.any(func(recipe:Dictionary)->bool:return recipe.outputs.has("r34:salvaged_drive_unit")))
	var cold:Dictionary=cold_restore(r,"equipment-without-knowledge")
	if not cold.ok:return
	check("cold preserves physical equipment and absence of learned woodwork",cold.runtime.actor("player").pack.get("r34:salvaged_drive_unit")==1 and not cold.runtime.world.extension("r3:production").knowledge.get("player",[]).has("basic_woodwork"))
	b=load_actual(args[2]);if not b.get("ok",false):return
	r=b.runtime
	var p:Dictionary=r.world.extension("r3:production")
	check("C actual source retains learned books and completed paid trials",p.knowledge.get("player",[]).has("basic_woodwork") and p.knowledge.player.has("basic_tool_repair") and p.orders.any(func(o:Dictionary)->bool:return o.kind=="craft" and o.targetId=="make_handle" and o.status=="completed"),{"knowledge":p.knowledge,"orders":p.orders})
	if not contact(r,TOOLSTOCK):check("real return to learned station",false);return
	var before:Dictionary=r.world.extension("r3:production").knowledge
	var materials:Dictionary=r.actor("player").pack.duplicate(true)
	var damage:Dictionary=r._services.modules.prepare_damage(SHED,1000,"r34:e:fixture:learned-station-ruin")
	var committed:Dictionary=r._commit(damage) if damage.ok else damage
	injections.append({"kind":"isolated_adverse_stimulus","api":"modules.prepare_damage -> Runtime._commit","module":SHED,"amount":1000,"receipt":committed,"not_natural_journey":true})
	check("original B damage and A transaction authorize explicit station ruin",committed.ok,committed)
	if not committed.ok:return
	refused=send(r,"craft",SHED+":workbench",craft_request("make_handle",SAW))
	check("ruined learned workbench rejects actual craft without amnesia or free settlement",not refused.ok and str(refused.get("reason","")).contains("工位") and Data.json_equal(before,r.world.extension("r3:production").knowledge) and Data.json_equal(materials,r.actor("player").pack),refused)
	cold=cold_restore(r,"learned-tested-station-ruined")
	check("canonical cold retains knowledge after paid trial and station destruction",cold.ok and Data.json_equal(before,cold.runtime.world.extension("r3:production").knowledge))
func pressure()->void:
	var b:Dictionary=load_actual(OS.get_cmdline_user_args()[3]);if not b.get("ok",false):return
	var r:RefCounted=b.runtime
	# Preserve original held cargo. Stop repetition, then let its original owner finish.
	for t:Dictionary in r.world.extension("r34:logistics").tasks:
		if t.status not in ["completed","cancelled"]:
			send(r,"logistics.cancel",t.id)
			if t.phase=="deliver" and not str(t.actor_id).is_empty():
				var original:Dictionary=send(r,"logistics.retarget",t.id,{"destination_id":t.destination_id})
				check("original long-run held cargo explicitly resumes before new work",original.ok,original)
	step(r,800)
	check("one original returned volunteer remains unavailable by actual consent",not r.actor("repair-resident").relationship.consent and r.actor("village-resident").relationship.consent)
	var baseline:float=total_timber(r)
	if not transfer(r,"take",BOARDS,{"timber":15}):return
	if not transfer(r,"deposit",CACHE,{"timber":15}):return
	var cap:Dictionary=r._services.production.capacity_check(CACHE,{"timber":2})
	check("real destination holds 15 of original 16 and refuses two more",r.stock(CACHE).items.get("timber")==15 and not cap.ok and cap.code=="BUFFER_FULL",cap)
	# Explicit downward-only existing-tool fixture, through original draft/CAS validation.
	var tx:=Tx.new(r._services.production.context)
	var state:Dictionary=tx.extension("r3:production")
	var old:float=r.tool(SAW).durability
	Tx.find(state.tools,SAW).durability=0.25
	var lowered:Dictionary=r._commit(tx.result())
	injections.append({"kind":"isolated_adverse_stimulus","api":"DomainDraft extension -> Runtime._commit","tool_id":SAW,"before":old,"after":0.25,"receipt":lowered,"not_natural_wear":true})
	check("existing saw only loses durability under original authority",lowered.ok and r.tool(SAW).durability==0.25 and total_timber(r)==baseline,lowered)
	if not lowered.ok:return
	if not contact(r,TOOLSTOCK):check("real route to low tool labor",false);return
	var pack_before:Dictionary=r.actor("player").pack.duplicate(true)
	var attempted:Dictionary=send(r,"craft",SHED+":workbench",craft_request("make_handle",SAW))
	step(r,160)
	var blocked:Array=r.world.extension("r3:production").orders.filter(func(o:Dictionary)->bool:return o.actorId=="player" and o.targetId=="make_handle" and o.status=="blocked")
	check("near broken saw performs paid labor then blocks without output or material charge",attempted.ok and r.tool(SAW).durability==0 and blocked.size()==1 and str(blocked[0].reason).contains("工具") and Data.json_equal(pack_before,r.actor("player").pack),{"start":attempted,"blocked":blocked,"tool":r.tool(SAW)})
	var cancelled_work:Dictionary=send(r,"cancel")
	check("original cancel releases broken-tool order without repairing or duplicating stock",cancelled_work.ok and r.tool(SAW).durability==0 and total_timber(r)==baseline,cancelled_work)
	# Empty original machine input is a genuine finite supply outage; no grant.
	var machine:Dictionary=send(r,"factory.configure","r34:normal-built-woodshop",{"recipe_id":"saw_timber","batches":1})
	check("real machine accepts bounded order while original input remains empty",machine.ok and r.stock("r34:normal-built-woodshop:stock:input").items.get("log",0)==0,machine)
	step(r,5)
	var outage:Array=r._services.production.factory_projection().orders.filter(func(o:Dictionary)->bool:return o.module_id=="r34:normal-built-woodshop")
	check("supply outage has real missing-input blocker and cannot create boards",total_timber(r)==baseline and outage.size()==1 and outage[0].blockers.has("missing_input"),outage)
	var cancelled_machine:Dictionary=send(r,"factory.cancel","r34:normal-built-woodshop")
	check("original machine supply outage can be cancelled without phantom output",cancelled_machine.ok and total_timber(r)==baseline,cancelled_machine)
	if not contact(r,BOARDS):check("player reaches cargo source",false);return
	var ids:Array=r.world.extension("r34:logistics").tasks.map(func(t:Dictionary)->String:return t.id)
	var created:Dictionary=send(r,"logistics.create","",{"source_id":BOARDS,"destination_id":CACHE,"items":{"timber":1},"repeat":false})
	check("near full cache accepts exactly one finite original-person trip",created.ok,created)
	if not created.ok:return
	for t:Dictionary in r.world.extension("r34:logistics").tasks:
		if not ids.has(t.id):task_id=t.id
	sequence+=1
	var assignment:Dictionary=r.command({"command_id":"r34:e:pressure:assign:%d"%sequence,"actor_id":"village-resident","kind":"workforce.assign","payload":{"candidate_id":task_id}})
	check("explicit original volunteer assignment replaces completed previous request",assignment.ok,assignment)
	if not assignment.ok:return
	carrier=""
	for i:int in 900:
		step(r)
		if task(r).phase=="deliver" and not str(task(r).actor_id).is_empty():carrier=task(r).actor_id;break
	check("only available original volunteer physically picks original board",carrier=="village-resident" and r.actor(carrier).pack.get("timber",0)>=1 and task(r).trips==0,task(r))
	if carrier.is_empty():save(r,"pressure-no-pickup");return
	note(r,"near-full-low-tool-one-volunteer-in-transit")
	var cold:Dictionary=cold_restore(r,"pressure-in-transit")
	if not cold.ok:return
	r=cold.runtime
	check("mid-route cold preserves low tool full cache unavailable person and physical cargo",r.tool(SAW).durability==0 and r.stock(CACHE).items.get("timber")==15 and not r.actor("repair-resident").relationship.consent and task(r).phase=="deliver" and task(r).trips==0)
	var stopped:Dictionary=send(r,"logistics.cancel",task_id)
	check("original cancellation keeps physical cargo and releases own reservation",stopped.ok and task(r).status=="cargo_held" and not r.world.extension("r34:logistics").reservations.any(func(x:Dictionary)->bool:return x.task_id==task_id) and total_timber(r)==baseline,stopped)
	cold=cold_restore(r,"pressure-cancelled-cargo")
	if not cold.ok:return
	r=cold.runtime
	var home_before:float=r.stock(HOME).items.get("timber",0)
	var retarget:Dictionary=send(r,"logistics.retarget",task_id,{"destination_id":HOME})
	check("original owner legally retargets cancelled carried board",retarget.ok,retarget)
	if not retarget.ok:return
	for i:int in 1200:
		step(r)
		if task(r).status=="completed":break
	check("same volunteer completes original cargo once after cancel cold and retarget",task(r).status=="completed" and task(r).trips==1 and r.stock(HOME).items.get("timber")==home_before+1 and r.stock(CACHE).items.get("timber")==15 and total_timber(r)==baseline,task(r))
	check("recovery never grants tool wear repair consent or additional people",r.tool(SAW).durability==0 and not r.actor("repair-resident").relationship.consent and r.facts().actors.filter(func(a:Dictionary)->bool:return a.get("faction")!="infected").size()==3)
	cold=cold_restore(r,"pressure-recovered")
	check("final canonical cold preserves single paid delivery and all stocks",cold.ok and task(cold.runtime).trips==1 and total_timber(cold.runtime)==baseline)
func cold_restore(runtime:RefCounted,label:String)->Dictionary:
	var encoded:Dictionary=save(runtime,label)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var n:=Native.new();var restored:Dictionary=n._assemble(decoded.capture) if decoded.ok else decoded;n.free()
	var same:bool=restored.get("ok",false) and persisted_restore_equal(decoded.capture,restored.runtime.facts(),restored.world) and Data.json_equal(decoded.capture.simulation,restored.runtime.capture_checkpoint().simulation)
	check("strict canonical facts extensions entities and sole simulation restore "+label,same,restored.get("reason"))
	return restored if same else {"ok":false}
func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	knowledge();pressure();finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"sources":sources,"injections":injections,"stages":stage_rows,"costs":costs,"ticks":ticks,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"scope":"Immutable18 headless bounded tests-only; two real C source branches and actual1800 final continuation. Explicit station ruin and downward tool fixture are not natural journey. Existing paid knowledge, finite transfers, one unavailable volunteer, near-full cache, missing machine input, cancel/carried-cargo/cold/retarget only. No new needs, stock, clock, executor; no whole R34-43/56, OS/VA/FPS/long-time qualification. Low saw works to zero and remains broken, not repaired; no drive manufacturing recipe exists."}
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
