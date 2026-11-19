extends "res://tests/gameplay/factory_story_normal.gd"
## Content9 affected normal journey. All mutations use the original Runtime.
## The inherited pressure/fixture entry points are never called.
var options:Dictionary={}
var activities:Dictionary={}
var plans:Array=[]
var machine_id:String=""
var storage_id:String=""
var cold_checks:Array=[]
const QualityWorld=preload("res://scripts/world/world_state.gd")
const QualityResidency=preload("res://scripts/runtime/region_residency.gd")

func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":"r34:e:quality9:"+branch+":%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=runtime.command(request)
	commands.append({"time":runtime.clock(),"request":request,"result":result})
	return result

func observe(runtime:RefCounted)->void:
	super.observe(runtime)
	for id:String in guards:
		var actor:Dictionary=runtime.actor(id)
		var intent:Variant=actor.get("intent")
		if intent is Dictionary:
			activities.get_or_add(id,{}).get_or_add(str(intent.get("kind","unknown")),{"first":runtime.clock(),"samples":0}).samples+=1

func cold_restore(runtime:RefCounted,label:String)->Dictionary:
	var encoded:Dictionary=save(runtime,label)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	var native:=Native.new();var restored:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	var fields:Dictionary={};var world_fields:Dictionary={};var exact:bool=restored.get("ok",false)
	var batches:Array=[]
	if exact:
		# Codec deliberately stores every chunk cold. Predict ONLY the existing
		# C residency transactions on a test oracle World, without a second Runtime,
		# clock, inventory or gameplay executor. Compare every resulting field.
		var expected:Dictionary=decoded.capture.duplicate(true)
		var oracle:=QualityWorld.new()
		exact=oracle.load_snapshot(expected.world).get("ok",false)
		for region:String in QualityResidency.required_regions(restored.runtime):
			while exact and not oracle.region_is_resident(region):
				var conversion:Dictionary=oracle.prepare_region_residency(region,true,oracle.get_revision(),int(options.native_residency_batch))
				if not conversion.get("ok",false) or conversion.world_changes.is_empty():exact=false;break
				batches.append({"region":region,"before_revision":oracle.get_revision(),"changes_sha256":JSON.stringify(conversion.world_changes,"",true,true).sha256_text()})
				var prepared:Dictionary=oracle.prepare_changes(conversion.world_changes,oracle.get_revision())
				if not prepared.get("ok",false) or not oracle.commit_prepared(prepared.capability).get("ok",false):exact=false;break
		expected.world=oracle.snapshot()
		var actual:Dictionary=restored.runtime.capture_checkpoint()
		for key:String in expected:
			fields[key]=actual.has(key) and Data.json_equal(expected[key],actual[key]);exact=exact and fields[key]
		for key:String in actual:exact=exact and expected.has(key)
		for key:String in expected.world:
			world_fields[key]=actual.world.has(key) and Data.json_equal(expected.world[key],actual.world[key])
	cold_checks.append({"label":label,"fields":fields,"world_fields":world_fields,"residency_batches":batches,"reason":restored.get("reason")})
	check("entire decoded canonical capture is exact after Native cold "+label,exact,cold_checks.back())
	return restored if exact else {"ok":false}

func run()->void:
	var args:=OS.get_cmdline_user_args();output_dir=args[0]
	DirAccess.make_dir_recursive_absolute(output_dir)
	options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	branch=str(options.get("probe_mode","restore"))
	if branch=="parse":
		check("driver instantiates without assembling or ticking a world",true)
		return finish()
	if branch=="restore":return normal_restore()
	var mounted:Dictionary=mount_actual(args[1])
	if not mounted.get("ok",false):return finish()
	live=mounted.runtime;frame_id="RH-HOME:woodshop-old-frame"
	check("continuation retains explicit content9 lock without regenerating input",int(live.world.extension("generation:RH-HOME").get("generation_content_version",0))==9)
	if branch=="cold-audit":
		save(live,"quality9-mounted-before-tick")
		cold_restore(live,"quality9-second-cold-no-tick")
		return finish()
	if branch=="restore-resume":
		var cold:Dictionary=cold_restore(live,"quality9-resume-active10")
		if not cold.get("ok",false):return finish()
		live=cold.runtime
		check("original active restoration completes its remaining paid seconds",progress(live,500).finished and frame(live).restoration.completed and frame(live).hp==300)
		check("original finite payment and hammer wear survive continuation",live.actor("player").pack.get("timber",0)==0 and live.actor("player").pack.get("scrap",0)==0 and live.actor("player").pack.get("r34:salvaged_drive_unit",0)==0 and absf(live.tool(HAMMER).durability-94)<0.000001)
		return finish_restoration(live)
	if branch=="cooperate-audit":return audit_cooperation()
	if branch.begins_with("cooperate"):return normal_cooperate()
	if branch=="build-resume":return finish_relocation(live)
	normal_relocate()

func normal_restore()->void:
	var version:int=int(options.get("content_version",9))
	var profiles:Array=Modules.generation_profiles(true)
	if version!=9:
		var provider:RefCounted=Modules.new()
		profiles=provider.call("generation_profiles_for_content",version) if provider.has_method("generation_profiles_for_content") else []
	var lock:Dictionary=Contract.fresh(profiles,version,1)
	check("explicit versioned fresh profiles lock",lock.get("ok",false) and profiles.size()==(18 if version==9 else 19 if version==10 else -1),lock)
	if not lock.get("ok",false):return finish()
	var prepared:Dictionary=Assembly.prepare(Factory.generate(int(options.get("seed",713)),profiles,lock.contract))
	check("normal content9 original assembly prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var native:=Native.new();var made:Dictionary=native._assemble(prepared.capture);native.free()
	check("normal content9 original Native mounts",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false):return finish()
	var r:RefCounted=made.runtime;live=r;frame_id="RH-HOME:woodshop-old-frame"
	plans=r.world.extension("generation:RH-HOME").get("buildable_workyards",[])
	check("workyard is empty advice with two choices and no free machine",plans.size()==1 and plans[0].candidate_definitions.size()==2 and r.world.extension("r34:modules").instances.filter(func(m:Dictionary)->bool:return Catalog.definition(m.definition_id).get("generation_role")=="machine").size()==1 and not frame(r).restoration.completed)
	check("S01 keeps its original definition and damaged frame",frame(r).definition_id=="r34.module.fuel_woodshop" and frame(r).hp==120 and frame(r).status=="damaged" and not frame(r).player_built)
	var homes:Array=[]
	for id:String in ["r34:generated:RH-HOME:home","r34:generated:RH-VILLAGE:neighbor"]:
		homes.append(r._services.modules.instance(id).definition_id)
	check("both generated original life sites use the two new home variants",homes.has("r34.module.home_court_v3") and homes.has("r34.module.home_roadside_v3"),homes)
	save(r,"quality9-fresh-untouched")
	# Same real searched sources as factory_normal_path/story_normal.
	if not transfer(r,"take",TOOLSTOCK,{"timber":8,"scrap":4,"book_woodwork":1},[SHED+":tool:salvaged_axe",HAMMER,SAW]):return finish()
	var yard:String=str(r.world.extension("generation:RH-HOME").content_anchors[0].id)+":container"
	if not transfer(r,"take",yard,{"r34:salvaged_drive_unit":1},[yard+":tool:shovel",yard+":tool:pickaxe"]):return finish()
	var learned:Dictionary=send(r,"study",SHED+":record:book_woodwork",{"direct":false})
	check("actual carried original book requires its twelve-second study",learned.get("ok",false) and progress(r,300).finished and r.world.extension("r3:production").knowledge.player.has("basic_woodwork"),learned)
	if not learned.get("ok",false):return finish()
	if not recover_stamina(r) or not approach(r,port(r,frame_id,"work")):check("normal route reaches original frame work service",false);return finish()
	var found:Dictionary=send(r,"module.discover",frame_id)
	check("original frame discovered through real contact",found.get("ok",false),found)
	if not found.get("ok",false):return finish()
	var old:Dictionary=r.actor("player").pack.duplicate(true);var wear:float=r.tool(HAMMER).durability
	var restored:Dictionary=send(r,"module.restore",frame_id,{"source_id":"pack:player","tool_id":HAMMER})
	check("real finite same-id restoration begins",restored.get("ok",false),restored)
	if not restored.get("ok",false):return finish()
	step(r,100)
	var cold:Dictionary=cold_restore(r,"quality9-frame-active10")
	if not cold.get("ok",false):return finish()
	r=cold.runtime;live=r
	check("same original frame completes forty paid seconds after cold",progress(r,500).finished and frame(r).restoration.completed and frame(r).hp==300)
	check("restoration pays exact original materials and hammer wear",r.actor("player").pack.timber==old.timber-8 and r.actor("player").pack.scrap==old.scrap-4 and r.actor("player").pack.get("r34:salvaged_drive_unit",0)==0 and absf(wear-r.tool(HAMMER).durability-6)<0.000001)
	finish_restoration(r)

func finish_restoration(r:RefCounted)->void:
	if not harvest_three(r):check("real original tree supplies restored frame",false);return finish()
	if not produce(r,frame_id):return finish()
	step(r)
	check("real original recovery and paid output update story without fake built",r.world.extension(Gameplay.KEY).flags.get("real_machine_restored",false) and not r.world.extension(Gameplay.KEY).flags.get("real_machine_built",false) and r.world.extension(Gameplay.KEY).stories.ST01.flags.get("read_woodwork_record",false))
	var cold:Dictionary=cold_restore(r,"quality9-restored-output")
	if cold.get("ok",false):live=cold.runtime
	finish()

func produce(r:RefCounted,id:String)->bool:
	var machine:Dictionary=r._services.modules.instance(id)
	var before:float=float(r.stock(machine.stock_refs.output).items.get("timber",0))
	for pair:Array in [["input",2],["fuel",1]]:
		if not transfer(r,"deposit",machine.stock_refs[pair[0]],{"log":pair[1]}):return false
	var configured:Dictionary=send(r,"factory.configure",id,{"recipe_id":"saw_timber","batches":2})
	check("same original producer configures two paid batches "+id,configured.get("ok",false),configured)
	if not configured.get("ok",false):return false
	for i:int in 600:
		step(r)
		if r.stock(machine.stock_refs.output).items.get("timber",0)==before+8:break
	var ok:bool=r.stock(machine.stock_refs.output).items.get("timber",0)==before+8 and r.stock(machine.stock_refs.input).items.get("log",0)==0 and r.stock(machine.stock_refs.fuel).items.get("log",0)==0
	check("two actual batches consume three logs and produce eight boards "+id,ok)
	return ok

func plan_and_build(r:RefCounted,definition:String,id:String,suggestions:Array=[])->Dictionary:
	if not recover_stamina(r):return {}
	var candidates:Array=suggestions.duplicate(true)
	if candidates.is_empty():
		for z:int in range(10,57,2):
			for x:int in range(18,57,2):candidates.append({"position":{"x":float(x),"y":r.world.surface_height(x,z),"z":float(z),"regionId":"RH-HOME"},"quarter_turn":0})
	var chosen:Dictionary={};var refused:Dictionary={}
	for candidate:Dictionary in candidates:
		var position:Dictionary=candidate.position.duplicate(true)
		position.regionId=r.world.region_at(position).get("id","")
		var payload:Dictionary={"definition_id":definition,"position":position,"quarter_turn":candidate.quarter_turn,"source_id":"pack:player","tool_id":HAMMER}
		var request:Dictionary={"kind":"module.plan","actor_id":"player","target_id":id,"payload":payload}
		var preview:Dictionary=r._services.modules.preview(request)
		if not preview.get("ok",false):refused[preview.get("code","unknown")]=int(refused.get(preview.get("code","unknown"),0))+1;continue
		for p:Dictionary in preview.ports:
			if p.purpose not in ["work","repair","input","service"]:continue
			if r._services.actions.route("player",Geometry.location(r.actor("player")),p.location).get("ok",false):chosen={"payload":payload,"feet":p.location};break
		if not chosen.is_empty():break
	check("live B preview and original body route admit "+definition,not chosen.is_empty(),{"refusals":refused,"suggestions_only":not suggestions.is_empty()})
	if chosen.is_empty() or not approach(r,chosen.feet):return {}
	var old:Dictionary=r.actor("player").pack.duplicate(true)
	var begun:Dictionary=send(r,"module.plan",id,chosen.payload)
	check("actual finite materials start full-cost build "+definition,begun.get("ok",false),begun)
	if not begun.get("ok",false):return {}
	step(r,100)
	var cold:Dictionary=cold_restore(r,"quality9-building-active-"+id)
	if not cold.get("ok",false):return {}
	r=cold.runtime;live=r
	var finished:bool=progress(r,700).finished
	var instance:Dictionary=r._services.modules.instance(id)
	var paid:bool=true
	for item:String in Catalog.definition(definition).build_cost:
		paid=paid and r.actor("player").pack.get(item,0)==old.get(item,0)-Catalog.definition(definition).build_cost[item]
	check("same original construction settles exact cost after active cold "+definition,finished and instance.get("status")=="operational" and paid and Data.json_equal(instance.get("paid_cost",{}),Catalog.definition(definition).build_cost))
	return instance if finished and instance.get("status")=="operational" and paid else {}

func normal_relocate()->void:
	var r:RefCounted=live
	var available:float=float(r.stock(frame(r).stock_refs.output).items.get("timber",0))
	check("actual source has original paid restored frame and eight produced boards",frame(r).restoration.completed and available+r.actor("player").pack.get("timber",0)==8)
	if available>0 and not transfer(r,"take",frame(r).stock_refs.output,{"timber":8}):return finish()
	if not recover_stamina(r) or not approach(r,port(r,frame_id,"work")):return finish()
	var stopped:Dictionary=send(r,"factory.cancel",frame_id)
	check("original completed machine is explicitly stopped before controlled dismantle",stopped.get("ok",false),stopped)
	if not stopped.get("ok",false):return finish()
	var old:Dictionary=r.actor("player").pack.duplicate(true)
	var removed:Dictionary=send(r,"module.dismantle",frame_id,{"source_id":"pack:player","output_id":"pack:player","tool_id":HAMMER})
	check("actual restored frame controlled dismantle begins",removed.get("ok",false),removed)
	if not removed.get("ok",false):return finish()
	check("controlled restored dismantle returns only fifteen boards six scrap and same drive",progress(r,250).finished and frame(r).status=="dismantled" and r.actor("player").pack.timber==old.get("timber",0)+15 and r.actor("player").pack.scrap==old.get("scrap",0)+6 and r.actor("player").pack.get("r34:salvaged_drive_unit",0)==1)
	var yard:String=str(r.world.extension("generation:RH-HOME").content_anchors[0].id)+":container"
	if not transfer(r,"take",TOOLSTOCK,{"scrap":2}):return finish()
	if not transfer(r,"take",yard,{"scrap":4}):return finish()
	# Two more finite trees: three hand-saw inputs and three machine inputs/fuel.
	if not harvest_three(r) or not harvest_three(r):check("two actual remaining trees supply six logs",false);return finish()
	if not approach(r,port(r,SHED,"work")):return finish()
	for i:int in 3:
		if not recover_stamina(r):return finish()
		var crafted:Dictionary=send(r,"craft",SHED+":workbench",craft_request("saw_timber",SAW))
		check("real hand-saw batch pays log and original wear "+str(i),crafted.get("ok",false) and progress(r,400).finished,crafted)
		if not crafted.get("ok",false):return finish()
	finish_relocation(r)

func finish_relocation(r:RefCounted)->void:
	plans=r.world.extension("generation:RH-HOME").get("buildable_workyards",[])
	var definition:String=str(options.get("machine_definition","r34.module.woodshop_long_v3"))
	var choices:Array=plans[0].candidate_definitions.filter(func(c:Dictionary)->bool:return c.definition_id==definition) if plans.size()==1 else []
	check("machine uses one exact workyard suggestion rather than arbitrary fallback",choices.size()==1,choices)
	if choices.size()!=1:return finish()
	machine_id="r34:e:quality9-built-machine"
	var machine:Dictionary=plan_and_build(r,definition,machine_id,choices)
	if machine.is_empty():return finish()
	r=live
	storage_id="r34:e:quality9-built-warehouse"
	var storage:Dictionary=plan_and_build(r,str(options.get("storage_definition","r34.module.warehouse_long_v3")),storage_id)
	if storage.is_empty():return finish()
	r=live
	if not produce(r,machine_id):return finish()
	check("new legal machines do not regenerate original retired frame or duplicate drive",frame(r).status=="dismantled" and r.actor("player").pack.get("r34:salvaged_drive_unit",0)==0 and r.world.extension("r34:modules").instances.filter(func(m:Dictionary)->bool:return m.id==frame_id).size()==1)
	var cold:Dictionary=cold_restore(r,"quality9-new-machine-and-storage-output")
	if cold.get("ok",false):live=cold.runtime
	finish()

func normal_cooperate()->void:
	var r:RefCounted=live
	machine_id="r34:e:quality9-built-machine";storage_id="r34:e:quality9-built-warehouse"
	var machine:Dictionary=r._services.modules.instance(machine_id);var storage:Dictionary=r._services.modules.instance(storage_id)
	check("actual constructed new family checkpoint retains finite output",not machine.is_empty() and not storage.is_empty() and r.stock(machine.stock_refs.output).items.get("timber",0)==8)
	if machine.is_empty() or storage.is_empty():return finish()
	var needed:int=maxi(0,guards.filter(func(id:String)->bool:return not r.actor(id).relationship.get("member",false)).size()-int(r.actor("player").pack.get("food",0)))
	if needed>0 and not transfer(r,"take","r34:generated:RH-HOME:home:stock:supplies",{"food":needed}):return finish()
	# Social route copied from the original normal53 helper, not relationship edits.
	for id:String in guards:
		if r.actor(id).relationship.get("member",false):continue
		if not social_contact(r,id,true):check("real approach to original neighbour "+id,false);return finish()
		var talked:Dictionary=send(r,"talk",id)
		var helped:Dictionary=send(r,"help",id,{"items":{"food":1}})
		var invited:Dictionary=send(r,"invite",id) if helped.get("ok",false) else helped
		check("original neighbour voluntarily joins after real food help "+id,talked.get("ok",false) and helped.get("ok",false) and invited.get("ok",false),{"talk":talked,"help":helped,"invite":invited})
		if not invited.get("ok",false):return finish()
	if not approach(r,r.world.extension(Gameplay.KEY).layout.home):return finish()
	for i:int in 1000:
		step(r)
		if guards.all(func(id:String)->bool:return r.actor(id).relationship.get("home_arrived",false)):break
	check("both original volunteers actually return before work",guards.all(func(id:String)->bool:return r.actor(id).relationship.get("home_arrived",false)))
	save(r,"quality9-volunteers-home")
	var ids:Array=[]
	for id:String in guards:
		var logistics:Variant=r.world.extension("r34:logistics")
		var previous:Array=logistics.tasks.map(func(t:Dictionary)->String:return t.id) if logistics is Dictionary else []
		var created:Dictionary=send(r,"logistics.create","",{"source_id":machine.stock_refs.output,"destination_id":storage.stock_refs.storage,"items":{"timber":2},"repeat":false})
		check("real normal task configures without phantom boards "+id,created.get("ok",false),created)
		if not created.get("ok",false):return finish()
		var fresh:Array=r.world.extension("r34:logistics").tasks.filter(func(t:Dictionary)->bool:return not previous.has(t.id))
		if fresh.size()!=1:check("one real logistics task identity",false,fresh);return finish()
		ids.append(fresh[0].id);sequence+=1
		var assigned:Dictionary=r.command({"command_id":"r34:e:quality9:assign:%d"%sequence,"actor_id":id,"kind":"workforce.assign","payload":{"candidate_id":fresh[0].id}})
		commands.append({"time":r.clock(),"actor_id":id,"kind":"workforce.assign","candidate_id":fresh[0].id,"result":assigned})
		check("each original volunteer receives a real B task "+id,assigned.get("ok",false),assigned)
		if not assigned.get("ok",false):return finish()
	for i:int in 1500:
		step(r)
		if ids.all(func(id:String)->bool:return find_task(r,id).get("status")=="completed"):break
	var tasks:Array=ids.map(func(id:String)->Dictionary:return find_task(r,id))
	check("both original people physically deliver into new warehouse",deliveries_exact(r,tasks),tasks)
	check("finite new-machine output conserves eight actual boards across delivery",r.stock(machine.stock_refs.output).items.get("timber",0)==4 and r.stock(storage.stock_refs.storage).items.get("timber",0)==4 and guards.all(func(id:String)->bool:return r.actor(id).pack.get("timber",0)==0))
	step(r)
	for id:String in guards:
		var experience:Dictionary=r.world.extension(Gameplay.KEY).stories.ST02.get("experiences",{}).get(id,{})
		check("actual new destination delivery creates this person's real story "+id,not experience.is_empty() and experience.get("destination_id")==storage.stock_refs.storage,experience)
		if experience.is_empty() or not social_contact(r,id,true):return finish()
		var reviewed:Dictionary=send(r,"settlement.read_story",id,{"story_id":"ST02","person_id":id,"event_id":experience.event_id})
		check("real on-site once-only review of new family delivery "+id,reviewed.get("ok",false),reviewed)
		var rested:Dictionary=send(r,"job",id,{"job":"rest"})
		check("original optional life job is legally requested "+id,rested.get("ok",false) and r.actor(id).job=="rest",rested)
	step(r,130)
	observe_paid_life(r)
	var cold:Dictionary=cold_restore(r,"quality9-two-original-people-delivery-story-life")
	if cold.get("ok",false):live=cold.runtime
	finish()

func deliveries_exact(r:RefCounted,tasks:Array)->bool:
	if tasks.size()!=2 or not tasks.all(func(t:Dictionary)->bool:return t.status=="completed" and int(t.trips)==1):return false
	var events:Array=r.facts().ledger.filter(func(e:Dictionary)->bool:return e.kind=="logistics-delivery-completed" and e.get("destination_id")==storage_id+":stock:storage" and e.get("source_id")==machine_id+":stock:output")
	return events.size()==2 and guards.all(func(id:String)->bool:return events.filter(func(e:Dictionary)->bool:return e.actor_id==id and Data.json_equal(e.items,{"timber":2}) and tasks.any(func(t:Dictionary)->bool:return t.id==e.task_id)).size()==1)

func audit_cooperation()->void:
	var r:RefCounted=live
	machine_id="r34:e:quality9-built-machine";storage_id="r34:e:quality9-built-warehouse"
	var tasks:Array=r.world.extension("r34:logistics").tasks
	check("actual completed tasks identify both carriers by original delivery receipts",deliveries_exact(r,tasks))
	var story:Dictionary=r.world.extension(Gameplay.KEY).stories.ST02
	check("both actual new-family deliveries already reviewed onsite once",guards.all(func(id:String)->bool:return story.people[id].reviewed and story.experiences[id].destination_id==storage_id+":stock:storage" and r.actor(id).relationship.consent and r.actor(id).relationship.home_arrived))
	observe_paid_life(r)
	var cold:Dictionary=cold_restore(r,"quality9-audited-delivery-and-real-life")
	if cold.get("ok",false):live=cold.runtime
	finish()

func observe_paid_life(r:RefCounted)->void:
	var water_before:float=amount(r,"water")
	for i:int in 600:
		step(r)
		if guards.all(func(id:String)->bool:return r.actor(id).thirst>60):break
	check("original unreset needs trigger both real paid autonomous drinks",guards.all(func(id:String)->bool:return r.actor(id).thirst>60) and amount(r,"water")==water_before-2,{"actors":guards.map(func(id:String)->Dictionary:return r.actor(id)),"water_before":water_before,"water_after":amount(r,"water")})

func amount(r:RefCounted,item:String)->float:
	var total:float=0
	for actor:Dictionary in r.facts().actors:total+=float(actor.pack.get(item,0))
	for stock:Dictionary in r.facts().stocks:total+=float(stock.items.get(item,0))
	return total

func finish()->void:
	if live!=null:
		check("normal route keeps original three people and HP without injected changes",live.facts().actors.size()==3 and violations.is_empty(),violations)
		save(live,"quality9-final")
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"commands":commands,"checkpoints":checkpoints,"sources":sources,"violations":violations,"activities":activities,"cold_checks":cold_checks,"fixed_steps":ticks,"frame_id":frame_id,"machine_id":machine_id,"storage_id":storage_id,"options":options,"scope":str(options.get("package_basis","Unchanged24 plus exact B/C overlay"))+" New9 normal finite original commands only; no pressure fixture, capture/body/material/knowledge/clock edits. Bounded fixed-step function, not package/OS/VA/FPS/wall-clock-long/G5 acceptance."}
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
