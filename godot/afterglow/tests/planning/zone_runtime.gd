extends SceneTree
## Real generated/native authority for planning; food cases are explicit finite
## inventory fixtures, never evidence of a normal agricultural/economic journey.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Zones=preload("res://scripts/planning/zone_service.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var hosts:Array=[]
var serial:int=0
var output:String
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func resource_facts(facts:Dictionary)->Dictionary:
	var result:Dictionary=facts.duplicate(true);result.erase("ledger")
	return result
func mount(capture:Dictionary)->Dictionary:
	var host:=Native.new();hosts.append(host)
	return host._assemble(capture)
func command(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},id:String="")->Dictionary:
	serial+=1
	return runtime.command({"kind":kind,"actor_id":"player","target_id":target,"payload":payload,"command_id":id if not id.is_empty() else "A:zone:"+str(serial)})
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output=args[0] if not args.is_empty() else "/tmp/afterglow-zone-runtime"
	DirAccess.make_dir_recursive_absolute(output)
	check("unsafe raw/filtered water, seeds and raw crops are not consumables",["r34:raw_water","r34:filtered_water","r34:potato_seed","r34:rice_seed","r34:potato","r34:rice"].all(func(id:String)->bool:return Content.consumable_definition(id).is_empty()))
	check("legacy consumables retain exact effects",Content.consumable_definition("food").restore==35 and Content.consumable_definition("water").restore==45 and Content.consumable_definition("medicine").restore==30)
	check("new meals have one typed content effect",Content.consumable_definition("r34:meal_simple","eat").get("restore")==35 and Content.consumable_definition("r34:meal_simple","drink").is_empty())
	var profiles:Dictionary=Assembly.generation_profiles()
	check("real generation profiles available",profiles.get("ok",false),profiles)
	if not profiles.get("ok",false):return finish()
	var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("real current factory opening prepares",opening.get("ok",false),opening.get("reason"))
	if not opening.get("ok",false):return finish()
	var built:Dictionary=mount(opening.capture)
	check("shipping Native assembly attaches zones ecology and zonework",built.get("ok",false) and built.get("services",{}).has_all(["zones","ecology","zonework"]),built.get("reason"))
	if not built.get("ok",false):return finish()
	var rt:RefCounted=built.runtime
	check("old opening without zone state remains unmodified by read",not rt.world.has_extension(Zones.KEY) and rt.zone_projection().zones.is_empty())
	var before:Dictionary=rt.capture_checkpoint()
	var bad:Dictionary=rt.zone_preview({"kind":"farm","region_id":"RH-HOME","bounds":{"x0":0,"z0":0,"x1":1000000,"z1":1000000}})
	check("oversized area rejects without mutation",not bad.ok and Data.json_equal(before,rt.capture_checkpoint()),bad.get("code"))
	var selected:Dictionary={}
	var player:Dictionary=rt.actor("player");var s:float=rt.world.config().cellSize
	for dz:int in [-16,-8,0,8,16,24]:
		for dx:int in [-16,-8,0,8,16,24]:
			var x:int=floori(float(player.x)/s)+dx;var z:int=floori(float(player.z)/s)+dz
			var spec:Dictionary={"kind":"farm","region_id":player.regionId,"bounds":{"x0":x,"z0":z,"x1":x+2,"z1":z+2},"policy":{"crop_id":"potato"}}
			var preview:Dictionary=rt.zone_preview(spec)
			if preview.get("ok",false):selected=spec;break
		if not selected.is_empty():break
	check("C actual land preview finds a valid local field",not selected.is_empty())
	if selected.is_empty():return finish()
	check("land preview is read only",Data.json_equal(before,rt.capture_checkpoint()))
	var receipt:Dictionary=command(rt,"zone.create","A:test:field",{"spec":selected},"A:zone:once")
	check("zone creation uses the actual Runtime transaction",receipt.get("ok",false),receipt)
	if not receipt.get("ok",false):return finish()
	check("planning creates no stock or labor products",Data.json_equal(resource_facts(before.facts),resource_facts(rt.facts())))
	check("selected projection returns cells, list only exposes counts",rt.zone_projection("player","A:test:field").selection.cells.size()>0 and not rt.zone_projection().zones[0].has("cells"))
	var cache_before:Dictionary=rt.capture_checkpoint()
	var dto:Dictionary=rt.zone_projection("player","A:test:field")
	dto.selection.cells.clear();dto.zones[0].name="external mutation"
	check("cached projection remains detached from callers and authority",not rt.zone_projection("player","A:test:field").selection.cells.is_empty() and rt.zone_projection().zones[0].name!="external mutation" and Data.json_equal(cache_before,rt.capture_checkpoint()))
	check("unknown actor cannot read zone jobs or selection",not rt.zone_view_basis("unknown").available and rt.zone_projection("unknown","A:test:field").selection.is_empty() and not rt.zone_work_projection("unknown").available)
	check("public UI descriptors use exact ecology rules and defaults",rt.zone_projection().crops.potato.seed=="r34:potato_seed" and rt.zone_projection().trees.conifer.seedling=="r34:conifer_seedling" and rt.zone_projection().defaults.forestry.replant==true)
	check("cheap view basis and jobs-only query are read-only",rt.zone_view_basis().zones_revision==1 and rt.zone_work_projection().candidates.is_empty() and Data.json_equal(cache_before,rt.capture_checkpoint()))
	var once:Dictionary=rt.capture_checkpoint()
	var replay:Dictionary=command(rt,"zone.create","A:test:field",{"spec":selected},"A:zone:once")
	check("same command receipt cannot duplicate a zone",replay.get("ok",false) and Data.json_equal(once,rt.capture_checkpoint()))
	check("overlapping second work area cannot claim same land",not command(rt,"zone.create","A:test:overlap",{"spec":selected}).get("ok",false) and rt.zone_records().size()==1)
	check("unknown policy cannot inject free resources",not command(rt,"zone.policy","A:test:field",{"patch":{"policy":{"free_food":999}}}).get("ok",false))
	var policy:Dictionary=command(rt,"zone.policy","A:test:field",{"patch":{"policy":{"priority":4,"reserve_seed":2}}})
	check("policy changes increment the persistent zone revision",policy.get("ok",false) and rt.zone_projection().revision==2 and rt.zone_records()[0].revision==2)
	var cell:Dictionary=rt.zone_records()[0].cells[0].duplicate(true)
	var count:int=rt.zone_records()[0].cells.size()
	var erased:Dictionary=command(rt,"zone.erase","A:test:field",{"cells":[cell]})
	check("erasing affects only designated cells",erased.get("ok",false) and rt.zone_records()[0].cells.size()==count-1 and Data.json_equal(resource_facts(before.facts),resource_facts(rt.facts())))
	var append_bounds:Dictionary=selected.bounds.duplicate(true)
	append_bounds.x0=int(append_bounds.x1);append_bounds.x1=int(append_bounds.x0)+1
	var addition:Dictionary=rt.zone_preview(selected.merged({"id":"A:test:field","bounds":append_bounds},true))
	if addition.get("ok",false):
		var appended:Dictionary=command(rt,"zone.update","A:test:field",{"patch":{"append_bounds":append_bounds}})
		check("append unions actual new cells without refilling erased holes",appended.get("ok",false) and not rt.zone_records()[0].cells.has(cell),appended)
	var cancelled:Dictionary=command(rt,"zone.cancel","A:test:field")
	check("cancel retains the plan and real world resources",cancelled.get("ok",false) and not rt.zone_records()[0].enabled and Data.json_equal(resource_facts(before.facts),resource_facts(rt.facts())))
	var saved:Dictionary=rt.capture_checkpoint()
	var cold:Dictionary=mount(JSON.parse_string(JSON.stringify(saved)))
	check("zone policies cells cancellation survive canonical cold restore",cold.get("ok",false) and Data.json_equal(saved.world.extensions[Zones.KEY],cold.get("world",rt.world).extension(Zones.KEY)),cold.get("reason"))
	if cold.get("ok",false):
		var cold_rt:RefCounted=cold.runtime
		var basis:Dictionary=cold_rt.zone_view_basis()
		cold_rt.tick(.1)
		check("ordinary simulation does not invalidate zone-list revision",basis.zones_revision==cold_rt.zone_view_basis().zones_revision and basis.runtime_generation!=rt.zone_view_basis().runtime_generation)
	# Explicit corruption/invalidation fixtures on a separate authority. These
	# bypass Runtime only to prove caches never trust stored revision metadata.
	if cold.get("ok",false) and cold.world.has_method("extension_token"):
		var cw:RefCounted=cold.world;var cz:RefCounted=cold.services.zones
		var initial_world:Dictionary=cw.snapshot()
		check("first full validation establishes an authority-bound proof",cz.validate_extensions(cold.runtime.facts()).ok)
		var token:Dictionary=cw.extension_token(Zones.KEY)
		var changed:Dictionary=cw.extension(Zones.KEY);changed.zones[0].name="same-revision authoritative edit"
		var prepared:Dictionary=cw.prepare_changes([{"op":"extension.set","id":Zones.KEY,"before_exists":true,"before":cw.extension(Zones.KEY),"after":changed}],cw.get_revision())
		check("preparing extension changes does not advance cache token",prepared.get("ok",false) and token==cw.extension_token(Zones.KEY))
		if prepared.get("ok",false):
			var committed:Dictionary=cw.commit_prepared(prepared.capability)
			check("same persisted revision successful commit invalidates projection",committed.get("ok",false) and token!=cw.extension_token(Zones.KEY) and cz.projection("player","A:test:field").selection.name=="same-revision authoritative edit")
		var malformed:Dictionary=cw.extension(Zones.KEY);malformed.zones.append(malformed.zones[0].duplicate(true))
		var proof:Dictionary=cw.extension_token(Zones.KEY)
		check("explicit malformed override never uses authority cache",not cz.validate_extensions(cold.runtime.facts(),{Zones.KEY:malformed}).ok and proof==cw.extension_token(Zones.KEY))
		var bad_draft:Dictionary=cw.prepare_changes([{"op":"extension.set","id":Zones.KEY,"before_exists":true,"before":cw.extension(Zones.KEY),"after":malformed}],cw.get_revision())
		if bad_draft.get("ok",false):
			cw.commit_prepared(bad_draft.capability)
			check("same-revision malformed authority cannot reuse old validation",not cz.validate_extensions(cold.runtime.facts()).ok)
		var before_load:Dictionary=cw.extension_token(Zones.KEY)
		var loaded:Dictionary=cw.load_snapshot(initial_world)
		check("same authority reload invalidates all cached proofs and display",loaded.get("ok",false) and before_load!=cw.extension_token(Zones.KEY) and cz.validate_extensions(cold.runtime.facts()).ok and cz.projection("player","A:test:field").selection.name==saved.world.extensions[Zones.KEY].zones[0].name)
	var corrupt:Dictionary=saved.duplicate(true)
	corrupt.world.extensions[Zones.KEY].zones.append(corrupt.world.extensions[Zones.KEY].zones[0].duplicate(true))
	var rejected:Dictionary=mount(corrupt)
	check("duplicate zone identity rejects restore",not rejected.get("ok",false),rejected.get("code"))
	# Explicit finite consumption fixture: no claim of farming/cooking sources.
	var meal:Dictionary=opening.capture.duplicate(true)
	for a:Dictionary in meal.facts.actors:
		if a.id=="player":a.pack={"r34:meal_simple":1,"r34:raw_water":1,"r34:potato_seed":1};a.hunger=30.0;a.intent=null
	var fed:Dictionary=mount(meal)
	check("finite prepared-meal fixture restores",fed.get("ok",false),fed.get("reason"))
	if fed.get("ok",false):
		var food_rt:RefCounted=fed.runtime
		check("consumable listing excludes seed and raw water",food_rt.life_consumables().size()==1 and food_rt.life_consumables()[0].item_id=="r34:meal_simple")
		var unsafe:Dictionary=food_rt.capture_checkpoint()
		check("unsafe explicit drinking rejects atomically",not command(food_rt,"drink","",{"item_id":"r34:raw_water"}).get("ok",false) and Data.json_equal(unsafe,food_rt.capture_checkpoint()))
		var eating:Dictionary=command(food_rt,"eat","",{"item_id":"r34:meal_simple"})
		check("actual eating intent pins its precise meal identity",eating.get("ok",false) and food_rt.actor("player").intent.get("item_id")=="r34:meal_simple",eating)
		for i:int in 5:food_rt.tick(.1)
		var midway:Dictionary=mount(JSON.parse_string(JSON.stringify(food_rt.capture_checkpoint())))
		check("mid-meal cold restore retains the same reservation and item",midway.get("ok",false) and midway.runtime.actor("player").intent.get("item_id")=="r34:meal_simple",midway.get("reason"))
		if midway.get("ok",false):
			for i:int in 10:midway.runtime.tick(.1)
			var a:Dictionary=midway.runtime.actor("player")
			check("actual elapsed eating consumes once and restores hunger",a.intent==null and a.pack.get("r34:meal_simple")==0 and float(a.hunger)>64 and a.pack.get("r34:raw_water")==1 and a.pack.get("r34:potato_seed")==1,a)
	finish()
func finish()->void:
	var ok:bool=checks.all(func(row:Dictionary)->bool:return row.ok)
	var file:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"checks":checks,"scope":"real Native planning; explicit finite meal fixtures; not normal economy, PCK, OS, visuals or performance"},"\t"));file.close()
	print("ZONE_RUNTIME "+str(checks.filter(func(row:Dictionary)->bool:return row.ok).size())+"/"+str(checks.size()))
	for host in hosts:
		if is_instance_valid(host):host.free()
	quit(0 if ok else 1)
