extends SceneTree
const Modules=preload("res://scripts/modules/module_service.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const BuildingView=preload("res://scripts/buildings/building_view.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	if detail is Dictionary:detail={"code":detail.get("code"),"reason":detail.get("reason")}
	checks.append({"name":name,"ok":ok,"detail":detail});if not ok:print("FAIL "+name+" "+str(detail))
func run()->void:
	var opening:Dictionary=Assembly.prepare(Generator.generate(713,Modules.generation_profiles()));check("real opening",opening.ok,opening)
	if not opening.ok:finish();return
	var capture:Dictionary=opening.capture.duplicate(true);var modules:Dictionary=capture.world.extensions[Modules.KEY]
	var home:Dictionary=modules.instances.filter(func(m:Dictionary)->bool:return m.region=="RH-HOME" and m.definition_id=="r34.module.home_service")[0]
	var port:Dictionary=Shape.ports(home,Modules.definition(home.definition_id))[0]
	# Explicit isolated relocation of the two NPCs vacates the cold test region.
	# Formal restore proves both positions, not a user save or unpinned actor.
	for i:int in capture.facts.actors.size():
		var a:Dictionary=capture.facts.actors[i];a.x=float(port.location.x)+(i-1)*2.0;a.y=port.location.y;a.z=port.location.z;a.regionId=home.region;a.buildingId=null;a.storeyId=null;a.intent=null
	var host:=Native.new();var assembled:Dictionary=host._assemble(capture);check("vacated-region fixture passes actual spatial restore",assembled.ok,assembled)
	if not assembled.ok:host.free();finish();return
	var rt:RefCounted=assembled.runtime;var services:Dictionary=assembled.services;var world:RefCounted=assembled.world
	var before:Dictionary=rt.capture_checkpoint();var view:=BuildingView.new();root.add_child(view);view.configure({"service":services.buildings,"runtime":rt})
	var resident_stats:Dictionary=view.residency_statistics();var q:RefCounted=services.buildings.current_space();var old_derived:WeakRef=weakref(q);q=null
	check("building renderer has actual objects in distant region",int(resident_stats.regions.get("RH-VILLAGE",0))>0,resident_stats)
	var projected:Dictionary=services.modules.projection();var workshop:Dictionary=projected.instances.filter(func(m:Dictionary)->bool:return m.definition_id=="r34.module.hand_workshop")[0]
	check("unsearched stocks never expose exact visual actual rows",workshop.visuals.buffers.is_empty() and workshop.stock_visibility.values().all(func(v:Variant)->bool:return v==false))
	check("new village not globally discovered by generation",projected.instances.all(func(m:Dictionary)->bool:return m.region=="RH-HOME"))
	var hidden:Dictionary=modules.instances.filter(func(m:Dictionary)->bool:return m.region=="RH-VILLAGE")[0]
	check("remote discover refuses without mutating inventory",not rt.command({"kind":"module.discover","command_id":"far-discover","actor_id":"player","target_id":hidden.id}).ok and Data.json_equal(before,rt.capture_checkpoint()))
	var cold_plan:Dictionary=world.prepare_region_residency("RH-VILLAGE",false,world.get_revision());check("C cold-page planner has actual storage changes",cold_plan.ok and not cold_plan.world_changes.is_empty(),cold_plan)
	var cool:Dictionary=rt._commit(cold_plan);check("Runtime commits actual cold residency with living region pinned elsewhere",cool.ok,cool)
	var cold_stats:Dictionary=view.residency_statistics();var cold_query:RefCounted=services.buildings.current_space()
	check("cold building objects are freed, not hidden",not cold_stats.regions.has("RH-VILLAGE") and cold_stats.objects<resident_stats.objects,cold_stats)
	check("cold collision and navigation derived objects are released",cold_query.solid_entities.all(func(e:Dictionary)->bool:return e.regionId!="RH-VILLAGE") and cold_query.pieces.all(func(e:Dictionary)->bool:return e.regionId!="RH-VILLAGE") and old_derived.get_ref()==null)
	check("cold queries and renderer never grant new items",Data.json_equal(before.facts,rt.facts()))
	var stored:Dictionary=world.snapshot();check("actual chunk cells released to compressed pages",stored.chunks.values().any(func(c:Dictionary)->bool:return c.has("cell_page") and c.cells.is_empty()))
	var cold_host:=Native.new();var cold_restore:Dictionary=cold_host._assemble(rt.capture_checkpoint());check("mixed hot/cold world restores exact building state",cold_restore.ok,cold_restore)
	var wake_plan:Dictionary=world.prepare_region_residency("RH-VILLAGE",true,world.get_revision());check("actual compressed cold pages restore",wake_plan.ok and rt._commit(wake_plan).ok,wake_plan)
	var wake_stats:Dictionary=view.residency_statistics();check("revisit reconstructs same building objects and identities",wake_stats.objects==resident_stats.objects and wake_stats.static_batches==resident_stats.static_batches and wake_stats.regions==resident_stats.regions,wake_stats)
	check("cold load and revisit never refill generated stocks",Data.json_equal(before.facts,rt.facts()))
	var catalog_start:int=Time.get_ticks_usec()
	for i:int in 500:
		var d:Dictionary=Catalog.definition("r34.module.fuel_woodshop");d.hp=-1
	var catalog_time:int=Time.get_ticks_usec()-catalog_start
	check("catalog loads once and callers cannot mutate definitions",Catalog.statistics().file_reads==1 and Catalog.definition("r34.module.fuel_woodshop").hp==300,Catalog.statistics())
	var query_start:int=Time.get_ticks_usec()
	for i:int in 50:services.modules.projection()
	print(JSON.stringify({"catalog_500_us":catalog_time,"module_projection_50_us":Time.get_ticks_usec()-query_start,"catalog":Catalog.statistics(),"scope":"headless query CPU; not FPS or OS acceptance"}))
	view.free();host.free();cold_host.free();finish()
func finish()->void:
	var report:Dictionary={"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"scope":"BBB actual Runtime C compressed residency/B geometry release/restore/privacy/catalog CPU checks; isolated actors fixture; not package/OS/VA/performance acceptance","checks":checks}
	print(JSON.stringify(report));quit(0 if report.ok else 1)
