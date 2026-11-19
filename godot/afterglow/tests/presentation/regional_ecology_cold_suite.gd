extends "res://tests/world/ecology_labor.gd"
## Replay the unchanged actual finite labor save through canonical JSON.
const FactoryServices=preload("res://scripts/runtime/factory_services.gd")
const EcologyView=preload("res://scripts/presentation/ecology_visual.gd")
const PlanningView=preload("res://scripts/presentation/planning_visual.gd")
var observations:Array=[]
func run()->void:
	var args:=OS.get_cmdline_user_args();var raw:String=FileAccess.get_file_as_string(args[1])
	check("original labor capture exact identity",raw.sha256_text()=="8c023501251f3f777aec7ba2ef7bf406db69ae989d50ce6db66c171ed4cb7c6f")
	var decoded:Dictionary=Store.decode(raw)
	check("unchanged canonical Native save decodes",decoded.ok,decoded.get("code"))
	if not decoded.ok:return finish()
	var ecology:=EcologyView.new();root.add_child(ecology);ecology.set_process(false)
	var planning:=PlanningView.new();root.add_child(planning);planning.set_process(false)
	var first_visuals:Array=[];var first_instances:int=0;var query_basis:String=""
	for pass_index:int in 2:
		world=World.new();runtime=Runtime.new()
		check("cold World accepts unconverted JSON "+str(pass_index),world.load_snapshot(decoded.capture.world).ok)
		var attached:Dictionary=FactoryServices.attach({"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new()},decoded.capture)
		check("actual A services attach after cold JSON "+str(pass_index),attached.ok,attached.get("code"))
		if not attached.ok:break
		var context:Dictionary=decoded.capture.duplicate(true);context.world=world;context.services=attached.services
		var configured:Dictionary=runtime.configure(context)
		check("full Runtime accepts real ecology integer-valued JSON floats "+str(pass_index),configured.ok,configured)
		if not configured.ok:break
		ecology.configure(runtime)
		check("codec cold pages correctly disclose no detailed plants "+str(pass_index),not world.region_is_resident("RH-HOME") and ecology.statistics().available and ecology.statistics().visuals.is_empty())
		var plants_before:Dictionary=world.extension(Ecology.KEY);var facts_before:Dictionary=runtime.facts()
		var complete:bool=false;var batches:int=0;var warm_ok:bool=true
		while not complete and batches<128:
			var warm:Dictionary=world.prepare_region_residency("RH-HOME",true,world.get_revision(),32)
			if not warm.ok:warm_ok=false;break
			complete=warm.complete;batches+=1
			if not commit(warm.world_changes).ok:warm_ok=false;break
		check("public bounded residency CAS warms actual saved region "+str(pass_index),warm_ok and complete and world.region_is_resident("RH-HOME"),{"batches":batches,"chunk_budget":32})
		check("residency preparation cannot invent crop stock intent or labor "+str(pass_index),Data.json_equal(plants_before,world.extension(Ecology.KEY)) and Data.json_equal(facts_before,runtime.facts()))
		var before:Dictionary=runtime.capture_checkpoint()
		ecology.configure(runtime);planning.configure(runtime);planning.set_selected("C:field");planning.sync()
		var report:Dictionary=ecology.statistics();var dto:Dictionary=runtime.domain_service("ecology").presentation_projection("player")
		var expected:Array=[]
		for row:Dictionary in dto.visuals:
			if row.known and row.resident and row.visible:expected.append(row.id)
		var displayed:Array=report.visuals.map(func(row:Dictionary)->String:return row.id)
		expected.sort();displayed.sort()
		check("cold consumer draws exactly known resident visible real DTO "+str(pass_index),report.available and report.issues.is_empty() and displayed==expected and not displayed.is_empty(),report)
		check("cold farm selection retains actual authoritative field cell "+str(pass_index),planning.statistics().counts.get("selected")==1,planning.statistics())
		check("cold render queries cannot alter actor/world/clock/inventory "+str(pass_index),Data.json_equal(before,runtime.capture_checkpoint()))
		var warm_rebuilds:int=report.rebuilds;ecology.sync()
		check("same actual cold basis reuses existing batches "+str(pass_index),ecology.statistics().rebuilds==warm_rebuilds)
		if pass_index==0:
			first_visuals=report.visuals.duplicate(true);first_instances=int(report.instances);query_basis=ecology._query_basis
		else:
			check("second cold Runtime keeps exact plants stages moisture and instances",Data.json_equal(report.visuals,first_visuals) and report.instances==first_instances,{"first":first_visuals,"second":report.visuals,"instances":report.instances})
			check("same Node drops prior Runtime/world cache identity",ecology._query_basis!=query_basis)
		observations.append({"pass":pass_index,"ecology":report,"planning":planning.statistics(),"basis":runtime.domain_service("ecology").presentation_basis("player")})
		runtime.tick(.1);var time_before:float=runtime.clock();var after_tick:Dictionary=runtime.capture_checkpoint();ecology.sync();planning.sync()
		check("restored owner clock advances while display remains read-only "+str(pass_index),time_before>float(decoded.capture.facts.time) and Data.json_equal(after_tick,runtime.capture_checkpoint()))
		var saved:Dictionary=Store.encode(runtime.capture_checkpoint());decoded=Store.decode(saved.text) if saved.ok else saved
		check("actual recovered checkpoint roundtrips for next cold world "+str(pass_index),decoded.ok,decoded.get("code"))
		runtime.retire()
		if not decoded.ok:break
	check("original source capture bytes unchanged",FileAccess.get_file_as_string(args[1])==raw)
	ecology.free();planning.free();await process_frame
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"scope":"Unchanged finite actual C labor Native save 8c023501 through canonical Store JSON, actual C restore02+FactoryServices+full Runtime, explicit original public 32-chunk residency CAS warm as test preparation, same Ecology/Planning Nodes over two cold/warm worlds, real DTO/instances and read-only checks. No forced resident field, original capture change, natural economy, actual scheduler/route, PCK/GPU/OS/VA/FPS claim.","checks":checks,"failed":failed,"observations":observations},"\t",true,true))
	print("DDD_REGIONAL_ECOLOGY_COLD ",checks.size()," failed=",failed);quit(0 if failed==0 else 1)
