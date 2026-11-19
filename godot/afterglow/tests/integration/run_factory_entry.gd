extends SceneTree
## Actual async factory entry, readiness and native storage; not OS/VA/perf.
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Legacy=preload("res://scripts/runtime/settlement_assembly.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const CameraInterest=preload("res://scripts/runtime/camera_interest.gd")
class TestClient extends Client:
	func _ready()->void:pass
var checks:Array=[]
var output:String
var host:Node3D
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	check("default testing entry retains fresh random map",Client.startup_options([])=={"ok":true,"resume":false,"seed":-1})
	check("normal economy is explicit and seed reproducible",Client.startup_options(["--normal-profile","--seed=2026"]).get("new_world_profile")=="normal")
	check("contradictory opening profiles reject",Client.startup_options(["--normal-profile","--playtest"]).get("code")=="CONFLICTING_PROFILE")
	host=TestClient.new();host.controls_path=output+"/controls.json";host.store=Store.new(output+"/saves");root.add_child(host)
	var test:Dictionary=await host.start_new_world(713,"r34-test-opening")
	check("shipping async entry and physical readiness mount actual R34",test.ok,test)
	if not test.ok:return finish()
	host.runtime.set_paused(true)
	check("new entry cannot silently mount old settlement",host.world.identity().generatorVersion=="factory-country-1" and host.runtime.facts().scenario=="factory-settlement-r34")
	var generation:Dictionary=host.world.extension("generation:factory-r34")
	check("formal new world adopts content12 regional production on pinned stable geography",generation.get("content_version")==12 and generation.get("zone_production_policy")=="regional-production-v1" and generation.get("repair_geometry_policy")=="repair-shed-quality-v1" and generation.get("parcel_orientation")=="road-court-camera-v2" and generation.get("family_policy")=="three-families-quality-v1" and generation.get("workyard_policy")=="empty-workyard-advice-v1" and generation.get("tool_recovery_policy")=="mt01-v1" and generation.get("water_recovery_policy")=="wt01-v1" and generation.get("story_site_policy")=="s01-s03-v1" and generation.get("story_entrance_policy")=="yard-stone-v1")
	check("formal new world explicitly opts into C physical story sources",host.world.extension("generation:factory-r34").get("story_clue_version")==1)
	var projection:Dictionary=CameraInterest.footprint(host.camera,host.world,1.0)
	check("actual viewport terrain slab has real generated adjacent coverage before promotion",projection.ok and host._regions.camera_interest_status().missing.is_empty() and host._terrain_view.readiness(CameraInterest.known_chunk_keys(host.world,projection.rect)).get("ready",false),host._regions.camera_interest_status())
	check("formal ordinary buildings use designed definitions and the old frame uses the accepted machine geometry",host.world.extension("r34:modules").instances.all(func(m:Dictionary)->bool:
		if m.has("restoration"):return m.definition_id=="r34.module.fuel_woodshop" and m.geometry_version==Modules.definition("r34.module.fuel_woodshop").geometry_version
		return Modules.definition(str(m.definition_id)).has("design_id")))
	check("finite testing tools are physical with actual holders",host.world.extension("r3:production").tools.filter(func(t:Dictionary)->bool:return t.holderId=="pack:player").size()==5)
	check("testing UI selects a real held tool",host.router.held_reference().id=="playtest:player:shovel" and host.runtime.tool(host.router.held_reference().id).holderId=="pack:player")
	var input_before:Dictionary=host.runtime.capture_checkpoint()
	var catalogue:Dictionary=host.runtime.factory_snapshot().modules
	var choices:Array=catalogue.get("build_definition_ids",[])
	check("current choices contain 30 paid mechanisms and ten original choices while all 79 historical definitions remain",choices.size()==40 and catalogue.definitions.size()==79 and catalogue.definitions.filter(func(row:Dictionary)->bool:return row.get("mechanism",{}).get("version")==2).size()==30 and choices.has("r34.module.repair_shed_v3") and not choices.has("r34.module.repair_shed_v2") and choices.all(func(id:String)->bool:return catalogue.definitions.any(func(row:Dictionary)->bool:return row.id==id)))
	var definition_id:String=choices[0] if not choices.is_empty() else "r34.module.unknown"
	check("unknown module selection cannot enter placement",not host.router.begin_module_placement("r34.module.unknown").ok and host.router.state().mode=="tool")
	check("real module catalogue selects one complete-module input mode",host.router.begin_module_placement(definition_id).ok and host.router.state().mode=="module_place" and host.router.state().module_definition_id==definition_id)
	host.interaction._cancel()
	check("escape cancels preview without cost or authority changes",host.router.state().mode=="tool" and host.router.state().module_definition_id.is_empty() and Data.json_equal(input_before,host.runtime.capture_checkpoint()))
	var existing:Dictionary=host.runtime.factory_snapshot().modules.instances[0]
	var target:Dictionary=host.interaction._describe(host.world.entity(existing.id))
	check("actual module entity opens complete-module management target",target.get("primary")=="module" and target.get("id")==existing.id and target.get("enabled",false))
	check("opening remains ephemeral before manual save",not FileAccess.file_exists(output+"/saves/active.json"))
	var saved:Dictionary=await host.save_async("manual-test-opening")
	check("manual save writes complete new module world",saved.ok,saved.get("reason"))
	if not saved.ok:return finish()
	var pointer:String=FileAccess.get_file_as_string(output+"/saves/active.json")
	var bytes:String=FileAccess.get_file_as_string(saved.path)
	var normal:Dictionary=await host.runtime.start_profiled_world("normal",2026,"r34-normal-opening")
	check("same formal entry can mount normal finite-source economy",normal.ok,normal)
	if not normal.ok:return finish()
	host.runtime.set_paused(true)
	check("new normal map protects previous explicit slot and active pointer",pointer==FileAccess.get_file_as_string(output+"/saves/active.json") and bytes==FileAccess.get_file_as_string(saved.path))
	var capture:Dictionary=host.runtime.capture_checkpoint()
	check("normal profile issues no testing tools or building gift pack",capture.source.get("playtest",{}).is_empty() and host.world.extension("r3:production").tools.all(func(t:Dictionary)->bool:return t.holderId!="pack:player") and host.runtime.actor("player").pack=={"food":1,"water":1})
	check("another world's tool shortcuts cannot survive normal opening",host.router.state().slots.all(func(ref:Dictionary)->bool:return ref.get("kind")!="tool"))
	check("normal tutorial is factory progression rather than old RH furniture",capture.facts.quests.size()==4 and capture.facts.quests[0].id=="R34-Q01")
	var actors:Array=host.runtime.facts().actors
	check("three real identities start unjoined with true containing regions",actors.size()==3 and actors.all(func(a:Dictionary)->bool:return host.world.region_at(a).get("id")==a.regionId and (a.id=="player" or not a.relationship.member and not a.relationship.consent)))
	var separated:bool=true
	for a:Dictionary in actors:
		for b:Dictionary in actors:
			if a.id!=b.id and Geometry.point(a).distance_squared_to(Geometry.point(b))<4.0:separated=false
	check("all real opening bodies are at least two metres apart",separated)
	var initial_modules:Array=host.world.extension("r34:modules").instances.filter(func(m:Dictionary)->bool:return m.region in ["RH-HOME","RH-VILLAGE"])
	check("natural workbench uses new repair geometry without changing the old frame",initial_modules.filter(func(m:Dictionary)->bool:return m.definition_id=="r34.module.repair_shed_v3" and m.geometry_version=="r34.module.repair_shed_v3.geometry-v2").size()==1 and initial_modules.all(func(m:Dictionary)->bool:return m.definition_id!="r34.module.repair_shed_v2"))
	var old_frames:Array=initial_modules.filter(func(m:Dictionary)->bool:return m.has("restoration"))
	check("new assembly keeps four normal modules plus exactly one uncompleted old frame",Assembly.generation_profiles().ok and initial_modules.size()==5 and old_frames.size()==1 and not old_frames[0].restoration.completed and old_frames[0].hp==120 and old_frames[0].status=="damaged")
	check("new designed machines require paid construction rather than generated grants",host.world.extension("r34:modules").instances.all(func(m:Dictionary)->bool:return m.definition_id not in ["r34.module.woodshop_long_v3","r34.module.woodshop_yard_v3"]))
	var yards:Array=host.world.extension("generation:RH-HOME").get("buildable_workyards",[])
	check("formal new entry persists one empty advisory workyard with both real geometry identities",yards.size()==1 and yards[0].status=="unbuilt-space-suggestion" and yards[0].candidate_definitions.size()==2 and yards[0].candidate_definitions.all(func(c:Dictionary)->bool:return c.geometry_version==c.definition_id+".geometry-v2"))
	var public_modules:Array=host.runtime.factory_snapshot().modules.instances
	check("initial catalogue never reveals undiscovered village modules",public_modules.size()==2 and public_modules.all(func(m:Dictionary)->bool:return m.region=="RH-HOME"))
	var visible_stock:bool=true
	for module:Dictionary in public_modules:
		for buffer:Dictionary in module.visuals.buffers:
			if not host.runtime.stock(buffer.stock_ref).get("searched",false):visible_stock=false
	check("module stock visuals cannot reveal unsearched quantities",visible_stock)
	var modules:RefCounted=host.runtime._services.modules
	var repeat:Dictionary=modules.prepare_generation(host.world)
	check("persistent generation receipts cannot replenish normal sources",repeat.ok and repeat.initial_stocks.is_empty() and repeat.initial_tools.is_empty() and repeat.initial_records.is_empty())
	var before:Dictionary=host.runtime.capture_checkpoint()
	var invalid:Dictionary=await host.runtime.start_profiled_world("invalid",2026,"invalid-profile")
	check("unknown profile refuses without changing any authority or save",not invalid.ok and Data.json_equal(before,host.runtime.capture_checkpoint()) and pointer==FileAccess.get_file_as_string(output+"/saves/active.json"))
	var normal_save:Dictionary=await host.save_async("manual-normal-opening")
	check("normal manual save is actual native checkpoint",normal_save.ok)
	var loaded:Dictionary=host.store.load_current()
	var cold:Dictionary=host._assemble(loaded.capture) if loaded.ok else loaded
	check("cold formal assembly keeps normal source and never regrants tools",cold.ok and cold.runtime.capture_checkpoint().source.get("playtest",{}).is_empty() and cold.world.extension("r3:production").tools.all(func(t:Dictionary)->bool:return t.holderId!="pack:player"),cold.get("reason"))
	check("prior testing save remains byte-identical after normal save",bytes==FileAccess.get_file_as_string(saved.path))
	var legacy:Dictionary=Legacy.prepare(Legacy.generate(713,Buildings.generation_profiles()))
	var legacy_built:Dictionary=host._assemble(legacy.capture) if legacy.ok else legacy
	check("explicit old settlement restore remains legacy rather than becoming R34",legacy_built.ok and legacy_built.world.identity().generatorVersion=="rural-3" and not legacy_built.services.has("modules"),legacy_built.get("reason"))
	finish()
func finish()->void:
	var report:Dictionary={"scope":"actual asynchronous NativeClient R34 dual-profile entry/readiness/explicit isolated store/restore; no packaged app, OS-input, VA or performance acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}))
	if is_instance_valid(host):host.free()
	quit(1 if report.failed else 0)
