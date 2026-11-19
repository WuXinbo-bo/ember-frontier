extends SceneTree
## E chooses; actual B logistics commands, haul actions and single inventory settle.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var host:Node
var runtime:RefCounted
var checks:Array=[]
var sequence:int=0
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func command(kind:String,payload:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"kind":kind,"actor_id":"player","command_id":"E-logistics-test:"+str(sequence),"payload":payload})
func mount(capture:Dictionary)->bool:
	var built:Dictionary=host._assemble(capture)
	check("real native services mount explicit finite logistics fixture",built.ok,built.get("reason"))
	if built.ok:runtime=built.runtime
	return built.ok
func task()->Dictionary:
	var state:Dictionary=runtime.world.extension("r34:logistics")
	return state.tasks[0] if not state.get("tasks",[]).is_empty() else {}
func until_carried()->bool:
	for i in 70:
		runtime.tick(0.1)
		if runtime.actor("repair-resident").get("pending_delivery",{}).get("phase")=="deliver":return true
	return false
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	host=Native.new()
	var profiles:Dictionary=Assembly.generation_profiles();var initial:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.get("profiles",[])))
	check("actual normal generation and A B E opening available",initial.ok,initial.get("reason"))
	if not initial.ok:finish();return
	if not mount(initial.capture):finish();return
	var fixture:Dictionary=runtime.capture_checkpoint()
	var person:Dictionary=runtime.actor("repair-resident");var destination:Dictionary=G.location(person);destination.x+=3.0
	destination=runtime._services.buildings.current_space().standing_point(destination)
	check("receiver uses real B-supported local feet",not destination.is_empty())
	if destination.is_empty():finish();return
	# Consent and prior return are explicit fixtures; survival suite proves return.
	for a:Dictionary in fixture.facts.actors:
		if a.id=="repair-resident":a.relationship.member=true;a.relationship.consent=true;a.relationship.home_arrived=true;a.householdId="home-residents";a.job="rest";a.pack={"water":1};a.thirst=80.0;a.hunger=80.0;a.fatigue=0.0;a.intent=null
	fixture.facts.stocks.append({"id":"fixture:finite-source","location":G.location(person),"items":{"timber":2},"owner":"home-residents","searched":true})
	fixture.facts.stocks.append({"id":"fixture:finite-receiver","location":destination,"items":{},"owner":"home-residents","searched":true})
	if not mount(fixture):finish();return
	var created:Dictionary=command("logistics.create",{"source_id":"fixture:finite-source","destination_id":"fixture:finite-receiver","items":{"timber":1},"repeat":true})
	check("real B command queues repeat transport without moving inventory",created.ok and runtime.stock("fixture:finite-source").items.timber==2 and not runtime.stock("fixture:finite-receiver").items.has("timber"),created)
	check("E consumes actual B candidate projection",runtime._services.workforce.projection("repair-resident").available)
	check("E admits real B collect path and physical pickup",until_carried(),runtime.actor("repair-resident"))
	check("pickup conserves one physical timber in original pack",runtime.stock("fixture:finite-source").items.timber==1 and runtime.actor("repair-resident").pack.get("timber")==1 and runtime.stock("fixture:finite-receiver").items.get("timber",0)==0)
	var before:Dictionary=runtime.actor("repair-resident");var after:Dictionary=before.duplicate(true);after.thirst=20.0
	var thirsty:Dictionary=runtime._commit({"fact_changes":[{"collection":"actors","id":before.id,"before":before,"after":after}],"world_changes":[],"events":[{"kind":"inventory-transfer","actor_id":"player"}]})
	check("actual A mutation fixture creates urgent need while carrying",thirsty.ok)
	runtime.tick(0.1)
	var cared:Dictionary=runtime.actor("repair-resident")
	check("N2 atomically pauses B cargo task and starts A care",cared.get("intent") is Dictionary and cared.intent.owner=="runtime" and cared.intent.kind=="drink" and task().status=="cargo_held",{"actor":cared,"task":task()})
	check("care handoff keeps timber and releases only destination promise",cared.pack.get("timber")==1 and runtime.stock("fixture:finite-receiver").items.get("timber",0)==0 and runtime.world.extension("r34:logistics").reservations.is_empty())
	for i in 180:
		runtime.tick(0.1)
		if int(task().get("trips",0))==2:break
	check("N5 resumes original cargo then repeat trip through B executor",int(task().get("trips",0))==2,{"task":task(),"actor":runtime.actor("repair-resident")})
	check("two real trips conserve all finite timber without phantom production",runtime.stock("fixture:finite-source").items.timber==0 and runtime.stock("fixture:finite-receiver").items.get("timber")==2 and float(runtime.actor("repair-resident").pack.get("timber",0))==0)
	check("A consumes exactly one water during transport pause",runtime.actor("repair-resident").pack.get("water")==0 and runtime.actor("repair-resident").thirst>60)
	var conserved:Array=[runtime.stock("fixture:finite-source").items,runtime.stock("fixture:finite-receiver").items,runtime.actor("repair-resident").pack]
	for i in 25:runtime.tick(0.1)
	check("empty repeat source cannot issue imaginary pickup or trip",int(task().get("trips",0))==2 and Data.json_equal(conserved,[runtime.stock("fixture:finite-source").items,runtime.stock("fixture:finite-receiver").items,runtime.actor("repair-resident").pack]))
	if not mount(fixture):finish();return
	created=command("logistics.create",{"source_id":"fixture:finite-source","destination_id":"fixture:finite-receiver","items":{"timber":1},"repeat":false})
	check("second real pickup fixture begins",created.ok and until_carried())
	before=runtime.actor("repair-resident");after=before.duplicate(true);after.relationship.consent=false
	var release:Dictionary=runtime._commit({"fact_changes":[{"collection":"actors","id":before.id,"before":before,"after":after}],"world_changes":[],"events":[{"kind":"consent","actor_id":"player","target_id":before.id}]})
	check("withdrawn consent releases work without teleporting cargo",release.ok and runtime.actor("repair-resident").pack.get("timber")==1 and runtime.stock("fixture:finite-receiver").items.get("timber",0)==0 and runtime.world.extension("r34:logistics").reservations.is_empty(),release)
	for i in 15:runtime.tick(0.1)
	check("withdrawn worker cannot silently finish a logistics delivery",runtime.actor("repair-resident").pack.get("timber")==1 and runtime.stock("fixture:finite-receiver").items.get("timber",0)==0 and int(task().get("trips",0))==0)
	if not mount(fixture):finish();return
	created=command("logistics.create",{"source_id":"fixture:finite-source","destination_id":"fixture:finite-receiver","items":{"timber":1},"repeat":false})
	check("cancelled cargo scenario reaches actual pickup",created.ok and until_carried())
	sequence+=1
	var cancelled:Dictionary=runtime.command({"kind":"logistics.cancel","actor_id":"player","target_id":task().id,"command_id":"E-logistics-cancel:"+str(sequence),"payload":{}})
	check("B cancellation keeps original carried cargo and blocks automatic resumption",cancelled.ok and task().status=="cargo_held" and not runtime._services.actions.workforce_candidate("repair-resident",str(task().id)).valid,cancelled)
	for i in 25:runtime.tick(0.1)
	check("E N5 cannot silently restart a player-cancelled delivery",runtime.actor("repair-resident").pack.get("timber")==1 and runtime.stock("fixture:finite-receiver").items.get("timber",0)==0 and int(task().get("trips",0))==0 and runtime.actor("repair-resident").get("intent")==null)
	# Retarget one real task after the old source is gone. The picked-up item
	# already belongs to this actor's pack, not to the deleted endpoint.
	var destroyed:Dictionary=runtime.capture_checkpoint();destroyed.facts.stocks=destroyed.facts.stocks.filter(func(s:Dictionary)->bool:return s.id!="fixture:finite-source")
	var original_destination:Dictionary=runtime.stock("fixture:finite-receiver").location
	destroyed.facts.stocks.append({"id":"fixture:alternate-receiver","location":original_destination.duplicate(true),"owner":"home-residents","searched":true,"items":{}})
	if not mount(destroyed):finish();return
	var original_task_id:String=str(task().id);var original_pack:Dictionary=runtime.actor("repair-resident").pack.duplicate(true)
	sequence+=1
	var retargeted:Dictionary=runtime.command({"kind":"logistics.retarget","actor_id":"player","target_id":original_task_id,"command_id":"E-logistics-retarget:"+str(sequence),"payload":{"destination_id":"fixture:alternate-receiver"}})
	check("B retarget changes only one existing task destination after source loss",retargeted.ok and task().id==original_task_id and task().source_id=="fixture:finite-source" and runtime.actor("repair-resident").pack==original_pack and runtime.stock("fixture:alternate-receiver").items.is_empty(),retargeted)
	for i in 80:
		runtime.tick(0.1)
		if task().status=="completed":break
	check("E resumes retargeted original cargo without requiring destroyed source",task().status=="completed" and task().id==original_task_id and runtime.stock("fixture:alternate-receiver").items.get("timber")==1 and float(runtime.actor("repair-resident").pack.get("timber",0))==0 and runtime.stock("fixture:finite-receiver").items.get("timber",0)==0,{"task":task(),"actor":runtime.actor("repair-resident")})
	finish()
func finish()->void:
	var report:Dictionary={"scope":"actual C713 and A B E assembly, real logistics.create, E scheduler, B physical haul and A need preemption; finite local sources and prior consent/return explicitly fixtures; no capacity machine PCK OS VA acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));runtime=null;host.free();quit(1 if report.failed else 0)
