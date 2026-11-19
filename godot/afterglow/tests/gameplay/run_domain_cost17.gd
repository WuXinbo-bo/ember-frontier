extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Projects=preload("res://scripts/modules/module_projects.gd")
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
const OldFactory=preload("res://tests/gameplay/fixtures/performance17/factory_kernel_before17.gd")
const OldProjects=preload("res://tests/gameplay/fixtures/performance17/module_projects_before17.gd")
const OldModules=preload("res://tests/gameplay/fixtures/performance17/module_service_before17.gd")
const OldWorkforce=preload("res://tests/gameplay/fixtures/performance17/settlement_workforce_before17.gd")
const OldGameplay=preload("res://tests/gameplay/fixtures/performance17/factory_gameplay_before17.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
var checks:Array=[]
var measurements:Array=[]
var runtime:RefCounted
var output:String
class FieldWorld:
	extends RefCounted
	var present:bool
	var value:Variant
	func has_extension(_key:String)->bool:return present
	func extension(_key:String)->Variant:return value.duplicate(true) if value is Dictionary or value is Array else value
	func extension_fields(_key:String,fields:Array[String])->Dictionary:
		var result:Dictionary={}
		if value is Dictionary:
			for field:String in fields:
				if value.has(field):result[field]=value[field].duplicate(true) if value[field] is Dictionary or value[field] is Array else value[field]
		return result
class ModuleHost:
	extends RefCounted
	var context:Dictionary
	var _production:WeakRef
	func initial()->Dictionary:return {"version":1,"instances":[],"projects":[],"source_receipts":{},"next_id":1}
class ProductionWorld:
	extends RefCounted
	var original:RefCounted
	var overlays:Dictionary
	func extension(key:String)->Variant:return overlays[key].duplicate(true) if overlays.has(key) else original.extension(key)
	func has_extension(key:String)->bool:return overlays.has(key) or original.has_extension(key)
	func get_revision()->int:return original.get_revision()
	func is_cell_resident(x:int,y:int,z:int)->bool:return original.is_cell_resident(x,y,z)
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func pair(label:String,original:Callable,current:Callable,count:int=12)->void:
	var expected:Variant=original.call();var actual:Variant=current.call()
	check(label+" exact result equivalence",Data.json_equal(expected,actual),{"old_code":expected.get("code"),"new_code":actual.get("code")})
	var rows:Array=[]
	for mode:String in ["reference","current","current","reference"]:
		var method:Callable=original if mode=="reference" else current
		var begin:int=Time.get_ticks_usec()
		for repeat:int in count:method.call()
		rows.append({"mode":mode,"calls":count,"mean_usec":float(Time.get_ticks_usec()-begin)/count})
	measurements.append({"operation":label,"abba":rows})
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	# Array/number extensions cannot finish the original Draft.result(): its
	# cross-type != raises before either implementation can return a plan.
	# Preserve that pre-existing boundary rather than changing the shared Draft.
	for edge:String in ["missing","null","inactive"]:
		var world:=FieldWorld.new();world.present=edge!="missing"
		world.value=[] if edge=="array" else 7 if edge=="number" else {"version":1,"instances":[],"projects":[],"source_receipts":{},"next_id":1} if edge=="inactive" else null
		var owner:=ModuleHost.new();owner.context={"world":world,"facts":func()->Dictionary:return {"actors":[],"stocks":[],"actions":[],"quests":[]}}
		check("selected-field module observation keeps old extension edge "+edge,Data.json_equal(OldProjects.advance(owner,.1),Projects.advance(owner,.1)))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("actual finite16 checksum input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("same actual16 source fully mounts",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime
	var shared:Dictionary=runtime._context.duplicate()
	shared.merge({"runtime":runtime,"services":built.services,"world":built.world,"spatial":built.services.buildings,"facts":runtime.facts,"draft_snapshot":runtime._draft_facts_snapshot,"actor":runtime.actor,"stock":runtime.stock,"tool":runtime.tool,"clock":runtime.clock},true)
	var old_modules:=OldModules.new();old_modules.configure(shared)
	var old_workforce:=OldWorkforce.new();old_workforce.configure(shared)
	var before:Dictionary=runtime.capture_checkpoint()
	pair("inactive module prepare",func()->Dictionary:return OldProjects.advance(built.services.modules,.1),func()->Dictionary:return Projects.advance(built.services.modules,.1))
	pair("production prepare",func()->Dictionary:return OldFactory.advance(built.services.production,.1),func()->Dictionary:return Factory.advance(built.services.production,.1))
	pair("workforce prepare",func()->Dictionary:return old_workforce.advance(.1),func()->Dictionary:return built.services.workforce.advance(.1),6)
	var facts:Dictionary=runtime.facts()
	pair("module full validation",func()->Dictionary:return old_modules.validate_extensions(facts),func()->Dictionary:return built.services.modules.validate_extensions(facts))
	var domain:Dictionary=built.world.extension("r34:modules")
	for mutation:String in ["capacity","duplicate_module","geometry","origin","missing_stock"]:
		var current_facts:Dictionary=facts.duplicate(true);var current_domain:Dictionary=domain.duplicate(true)
		match mutation:
			"capacity":current_facts.stocks[0].items["food"]=999999
			"duplicate_module":current_domain.instances.append(current_domain.instances[0].duplicate(true))
			"geometry":current_domain.instances[0].geometry_version="wrong"
			"origin":current_domain.instances[0].source_key="unregistered-origin"
			"missing_stock":current_facts.stocks.remove_at(0)
		var overrides:Dictionary={"r34:modules":current_domain}
		var original:Dictionary=old_modules.validate_extensions(current_facts,overrides)
		var actual:Dictionary=built.services.modules.validate_extensions(current_facts,overrides)
		check("module rejection same "+mutation,Data.json_equal(original,actual),actual.get("code"))
	# The JSON reuse proof is local to one advance, with a deep independent
	# snapshot. An edited nested layout is always checked at the original depth.
	var state:Dictionary=built.world.extension(Gameplay.KEY)
	for mutation:String in ["same","changed_json","invalid_vector","invalid_nan","unknown_key","deep"]:
		var changed:Dictionary=state.duplicate(true);var basis:Dictionary={"layout":state.layout.duplicate(true)}
		match mutation:
			"changed_json":changed.layout.home.x+=.25
			"invalid_vector":changed.layout.home.x=Vector3.ONE
			"invalid_nan":changed.layout.home.x=NAN
			"unknown_key":changed[Vector3.ONE]="invalid"
			"deep":
				var deep:Array=[];var cursor:Array=deep
				for index:int in 65:
					var next:Array=[];cursor.append(next);cursor=next
				changed.layout.extra=deep
		check("same-call JSON basis preserves full rejection "+mutation,Data.json_equal(OldGameplay.validate_state(changed),Gameplay._validate_state(changed,basis)))
	var all_full:Array=[];var all_person:Array=[]
	for id:String in ["village-resident","repair-resident"]:
		var began:int=Time.get_ticks_usec();var full:Dictionary=built.services.workforce.projection(id);all_full.append(Time.get_ticks_usec()-began)
		began=Time.get_ticks_usec();var person:Dictionary=built.services.workforce.person_projection(id);all_person.append(Time.get_ticks_usec()-began)
		var expected:Dictionary=Draft.find(full.people,id)
		# People DTOs identify their actor via actor_id, not id.
		for row:Dictionary in full.people:
			if row.actor_id==id:expected=row;break
		check("single-person public DTO equals original full row "+id,Data.json_equal(person,expected))
		person.last_failure["test_only"]=true
		check("single-person DTO nested edit cannot mutate authority "+id,not runtime.actor(id).get("self_routine",{}).get("last_failure",{}).has("test_only"))
	measurements.append({"operation":"two real person queries","full_usec":all_full,"person_usec":all_person})
	check("single-person endpoint never exposes unknown or hostile actor",built.services.workforce.person_projection("unknown").is_empty() and built.services.workforce.person_projection("*").is_empty())
	check("all pure prepare/validator/projection probes preserve exact authority checkpoint",Data.json_equal(before,runtime.capture_checkpoint()))
	active_production_fixture(built)
	finish()
func active_production_fixture(built:Dictionary)->void:
	# Explicit isolated unit adapter, never mounted/committed into the real
	# finite world: proves the lazy Draft fork on consumption/output/refund.
	var actual_before:Dictionary=runtime.facts()
	var modules:Dictionary=built.world.extension("r34:modules");var machine:Dictionary={}
	for row:Dictionary in modules.instances:
		if Factory.machine_module(row):machine=row;break
	check("active production unit adapter has an original machine definition",not machine.is_empty())
	if machine.is_empty():return
	machine.status="operational";machine.hp=Catalog.definition_view(machine.definition_id).hp
	if machine.has("restoration"):machine.restoration.completed=true
	var fixture_facts:Dictionary=runtime.facts()
	for stock:Dictionary in fixture_facts.stocks:
		if stock.id==machine.stock_refs.input:stock.items={"log":2.0}
		if stock.id==machine.stock_refs.fuel:stock.items={"log":1.0}
		if stock.id==machine.stock_refs.output:stock.items={}
	var world:=ProductionWorld.new();world.original=built.world
	var source:Dictionary=Factory.initial()
	var order:Dictionary={"id":machine.id+":machine","module_id":machine.id,"recipe_id":"saw_timber","mode":"machine","remaining":2,"paused":false,"energy_seconds":0.0,"completed":0,"created_at":runtime.clock()}
	source.orders.append(order);world.overlays={"r34:modules":modules,"r34:production":source}
	var fixture:=Production.new()
	fixture.configure({"world":world,"spatial":built.services.buildings,"services":{},"definitions":{},"facts":func()->Dictionary:return fixture_facts.duplicate(true),"draft_snapshot":func()->Dictionary:return fixture_facts,"actor":func(id:String)->Dictionary:return Draft.find(fixture_facts.actors,id),"stock":func(id:String)->Dictionary:return Draft.find(fixture_facts.stocks,id),"tool":func(_id:String)->Dictionary:return {},"clock":runtime.clock,"region_is_detailed":func(_id:String)->bool:return true})
	for phase:String in ["start","complete","refund","blocked"]:
		if phase!="start":
			order.energy_seconds=1.0
			source.batches=[{"id":"unit17:batch","module_id":machine.id,"order_id":order.id,"recipe_id":"saw_timber","input_id":machine.stock_refs.input,"output_id":machine.stock_refs.output,"wip":{"log":1.0},"outputs":{"timber":4.0},"status":"refund_pending" if phase=="refund" else "active","elapsed":9.9,"duration":10.0,"effective_work":0.0,"paused_reason":"","settlement_id":"","started_at":runtime.clock()}]
		if phase=="blocked":Draft.find(fixture_facts.stocks,machine.stock_refs.output).items={"timber":999999}
		var before:Dictionary=fixture_facts.duplicate(true)
		var original:Dictionary=OldFactory.advance(fixture,.1);var current:Dictionary=Factory.advance(fixture,.1)
		check("active inventory fork preserves exact original plan "+phase,Data.json_equal(original,current))
		check("active inventory fork never mutates borrowed input "+phase,Data.json_equal(fixture_facts,before))
		if phase=="start":check("active consumption adapter exercises two real stock deltas",current.get("fact_changes",[]).size()==2 and current.get("world_changes",[]).size()>0)
		if phase=="complete":check("active completion adapter exercises original output settlement",current.get("events",[]).any(func(event:Dictionary)->bool:return event.kind=="factory-batch-completed"))
		if phase=="refund":check("active refund adapter exercises original stock return",current.get("fact_changes",[]).size()==1)
	check("explicit unit adapter leaves actual runtime facts unchanged",Data.json_equal(runtime.facts(),actual_before))
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"suite":"domain-cost17","checks":checks,"failed":failed,"measurements":measurements,"scope":"Exact same real16 finite checkpoint; ABBA pure original/current prepare plans, validators and targeted member DTO equality; no tick-frequency/resource/consent/collision/CAS changes. Source CPU micro-measurements, not shipping PCK or GPU/FPS."},"\t",true,true))
	if runtime!=null:runtime.retire()
	print(JSON.stringify({"suite":"domain-cost17","checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
