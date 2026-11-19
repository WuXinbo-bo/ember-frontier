extends SceneTree
const Modules=preload("res://scripts/modules/module_service.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const World=preload("res://scripts/world/world_state.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	if detail is Dictionary:detail={"code":detail.get("code"),"reason":detail.get("reason")}
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func run()->void:
	check("catalog source validates",Catalog.validate().ok)
	var profiles:=Modules.generation_profiles()
	check("starting workshop never grants autonomous machine",profiles.filter(func(p:Dictionary)->bool:return p.generation_role=="workshop").all(func(p:Dictionary)->bool:return Catalog.definition(p.id).shape=="manual" and not Catalog.definition(p.id).recipe_modes.has("machine")))
	for seed:int in [713,2026]:
		var generated:Dictionary=Generator.generate(seed,profiles)
		check("real C generator accepts BBB working aprons "+str(seed),not generated.has("ok") or generated.get("ok",false),generated.get("code"))
		if generated.get("ok")==false:continue
		var world:=World.new();var loaded:Dictionary=world.load_snapshot(generated)
		check("real world loads generated voxels "+str(seed),loaded.ok,loaded)
		if not loaded.ok:continue
		var modules:=Modules.new();var before:=world.snapshot();var registered:Dictionary=modules.prepare_generation(world)
		check("unconfigured generation adapter returns real prepared changes "+str(seed),registered.ok and registered.world_changes.size()>0,registered.get("code"))
		check("generation planning never commits or mutates C world "+str(seed),before==world.snapshot())
		if not registered.ok:continue
		var stocks:Array=registered.seed_result.initial_stocks;var ids:Dictionary={}
		for stock:Dictionary in stocks:ids[stock.id]=true
		check("one canonical stock array without duplicate IDs "+str(seed),stocks==registered.initial_stocks and ids.size()==stocks.size())
		check("all physical tools and books have real stock source "+str(seed),registered.initial_tools.all(func(t:Dictionary)->bool:return ids.has(t.holderId)) and registered.initial_records.all(func(r:Dictionary)->bool:return ids.has(r.holderId)))
		var draft:Dictionary=world.prepare_changes(registered.world_changes,world.get_revision())
		check("world accepts module entities and old workbench identity "+str(seed),draft.ok,draft)
		if not draft.ok:continue
		check("generated adapter does not tick or grant hidden labor "+str(seed),not registered.has("time") and registered.fact_changes.is_empty())
		var commit:Dictionary=world.commit_prepared(draft.capability)
		check("single world CAS commits registered members "+str(seed),commit.ok,commit)
		var again:Dictionary=modules.prepare_generation(world)
		check("revisit cannot grant stock tool or book again "+str(seed),again.ok and again.world_changes.is_empty() and again.initial_stocks.is_empty() and again.initial_tools.is_empty() and again.initial_records.is_empty(),again.get("code"))
		var fresh:Dictionary=Assembly.prepare(generated)
		check("A actual assembly joins C/B/E single world "+str(seed),fresh.ok,fresh.get("reason",fresh.get("code")))
		if fresh.ok:
			var host:=Native.new();var assembled:Dictionary=host._assemble(fresh.capture)
			check("formal native assembler installs real module service "+str(seed),assembled.ok,assembled.get("reason",assembled.get("code")))
			if assembled.ok:
				var rt:RefCounted=assembled.runtime;var state:Dictionary=rt.factory_snapshot()
				check("public factory facade exposes actual module instances "+str(seed),state.available and state.modules.instances.size()>0)
				var capture:Dictionary=rt.capture_checkpoint();var projection:Dictionary=rt.factory_snapshot();projection.modules.instances[0].hp=-1
				check("queries cannot mutate world or stocks "+str(seed),capture==rt.capture_checkpoint())
				var service:RefCounted=assembled.services.modules;var broken:Dictionary=assembled.world.extension(Modules.KEY)
				broken.instances[0].geometry_version="future-geometry"
				check("geometry revisions cannot silently replace old module "+str(seed),service.validate_extensions(rt.facts(),{Modules.KEY:broken}).code=="MODULE_GEOMETRY_VERSION_MISMATCH")
				for v:Dictionary in assembled.world.extension(Modules.KEY).instances:
					for port:Dictionary in Shape.ports(v,Modules.definition(v.definition_id)):
						check("real body supported at "+port.id+" "+str(seed),not assembled.services.buildings.current_space().standing_point(port.location).is_empty(),port.location)
			host.free()
	var report:Dictionary={"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"scope":"BBB real generator/module/assembly source checks; no official application, package, OS, quality or performance acceptance","checks":checks}
	print(JSON.stringify(report));quit(0 if report.ok else 1)
