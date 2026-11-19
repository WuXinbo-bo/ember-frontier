extends SceneTree
## Same-source public-definition/privacy/preference boundaries; no OS/VA claim.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Display=preload("res://scripts/runtime/factory_display.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Handbook=preload("res://scripts/runtime/factory_handbook.gd")
var checks:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func entry(view:Dictionary,id:String)->Dictionary:
	for row:Dictionary in view.entries:
		if row.id==id:return row
	return {}
func request(kind:String,id:String,enabled:Variant,command_id:String)->Dictionary:
	return {"kind":kind,"actor_id":"player","target_id":id,"payload":{"enabled":enabled},"command_id":command_id}
func run()->void:
	var args:Array=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Modules.generation_profiles()))
	check("real current normal world prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var native:=Native.new();var built:Dictionary=native._assemble(prepared.capture);native.free()
	check("real runtime assembles handbook owners",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;var before:Dictionary=runtime.capture_checkpoint()
	var book:Dictionary=runtime.handbook_snapshot()
	var debug:=FileAccess.open(output+"/initial-handbook.json",FileAccess.WRITE);debug.store_string(JSON.stringify(book,"\t",true,true));debug.close()
	check("single on-demand typed catalogue",book.available and book.schema=="afterglow-factory-handbook-v1" and book.world_id==runtime.world.identity().worldId)
	check("six sections use official vocabulary",book.sections.map(func(r:Dictionary)->String:return r.id)==["sources","materials","tools","modules","processes","knowledge"])
	check("seven categories retain one content registration",book.categories.size()==7 and book.categories.any(func(r:Dictionary)->bool:return r.id=="outdoor_segment"))
	check("all formal materials use unchanged item definitions",book.entries.filter(func(r:Dictionary)->bool:return r.kind=="item").size()==Content.item_definitions().size() and entry(book,"item:log").definition==Content.item_definition("log"))
	check("all six terrain cards use real material IDs and protected base",book.entries.filter(func(r:Dictionary)->bool:return r.kind=="terrain").size()==6 and not entry(book,"terrain:bedrock").definition.diggable and entry(book,"terrain:road").definition.item=="gravel_m3")
	check("five tools plus explicitly legacy descriptor use B formal definitions",book.entries.filter(func(r:Dictionary)->bool:return r.kind=="tool").size()==6 and Data.json_equal(entry(book,"tool:salvaged_axe").definition.qualities,{"chopping":1}) and entry(book,"tool:legacy_tool").definition.legacy)
	check("manual recipes are exact owner definitions with mode only",entry(book,"process:manual:saw_timber").definition.inputs==built.services.production.recipes.saw_timber.inputs and entry(book,"process:manual:saw_timber").definition.outputs==built.services.production.recipes.saw_timber.outputs)
	var machine:Dictionary=runtime.factory_snapshot().production.recipes[0]
	check("machine conditions are exact public owner recipe",entry(book,"process:machine:"+machine.id).definition==machine)
	check("ordinary modules and special legacy objects remain distinct",book.entries.filter(func(r:Dictionary)->bool:return r.kind=="module").size()==runtime.factory_snapshot().modules.definitions.size() and entry(book,"legacy:yard_wall").definition.legacy)
	var ids:Dictionary={};var relations_valid:bool=true
	for row:Dictionary in book.entries:ids[row.id]=true
	for row:Dictionary in book.entries:
		for id:String in row.related_ids:
			if not ids.has(id):relations_valid=false
		for link:Dictionary in row.sources+row.uses:
			if not ids.has(link.id):relations_valid=false
	check("every bidirectional relation resolves to a stable formal entry",relations_valid)
	check("material links include hand processing and complete module costs",entry(book,"item:log").uses.any(func(r:Dictionary)->bool:return r.id=="process:manual:saw_timber") and entry(book,"item:timber").sources.any(func(r:Dictionary)->bool:return r.id=="process:manual:saw_timber") and entry(book,"item:timber").uses.any(func(r:Dictionary)->bool:return r.id.begins_with("module:")))
	check("unlearned knowledge is not granted by a public recipe",not entry(book,"knowledge:basic_woodwork").learned and not entry(book,"process:manual:saw_timber").learned)
	var materials:Dictionary=runtime.handbook_snapshot("player","item:timber").selection
	var visible_ids:Array=["pack:player"]
	for module:Dictionary in runtime.factory_snapshot().modules.instances:
		for key:String in module.stock_refs:
			if module.stock_visibility.get(key,false):visible_ids.append(module.stock_refs[key])
	check("selected material contains only searched public owned stocks",materials.current.stocks.all(func(s:Dictionary)->bool:return visible_ids.has(s.id)) and not materials.current.stocks.any(func(s:Dictionary)->bool:return str(s.id).contains("RH-VILLAGE")))
	var manual:Dictionary=runtime.handbook_snapshot("player","process:manual:saw_timber").selection
	check("normal no-tool opening never promises current manual production",not manual.current.can_make and manual.current.blockers.any(func(r:Dictionary)->bool:return r.code=="KNOWLEDGE_MISSING"))
	var module_entry:Dictionary=runtime.handbook_snapshot("player","module:r34.module.fuel_woodshop").selection
	check("global material totals cannot promise unselected construction site",module_entry.current.can_make==null and module_entry.current.blockers.any(func(r:Dictionary)->bool:return r.code=="CHOOSE_SITE"))
	check("tool repair does not claim a new default building menu",runtime.handbook_snapshot("player","legacy:yard_wall").selection.current.can_make==false)
	check("unknown and non-player callers cannot query private handbook facts",not runtime.handbook_snapshot("unknown").available and not runtime.handbook_snapshot("repair-resident").available)
	check("unknown definition ID gives no invented selected data",runtime.handbook_snapshot("player","item:unknown").selection.is_empty())
	book.entries[0].definition.clear();book.preferences.favorites.append("fixture:tamper")
	check("queries and nested DTO edits do not mutate captures or preferences",Data.json_equal(before,runtime.capture_checkpoint()) and runtime.handbook_snapshot().preferences.favorites.is_empty())
	check("old display state absent or optional-field-free validates unchanged",not before.world.extensions.get(Display.KEY,{}).has("handbook") and Display.validate(before.world.extensions.get(Display.KEY,Display.initial())).ok)
	var rejected:Dictionary=runtime.command(request("handbook.favorite","item:missing",true,"book:invalid"))
	check("unknown entry rejected without authority changes",not rejected.ok and Data.json_equal(before,runtime.capture_checkpoint()),rejected)
	rejected=runtime.command(request("handbook.favorite","item:log","true","book:bad-type"))
	check("preference type is strict and failure atomic",not rejected.ok and Data.json_equal(before,runtime.capture_checkpoint()))
	var nonplayer:Dictionary=request("handbook.favorite","item:log",true,"book:nonplayer");nonplayer.actor_id="repair-resident"
	check("NPC cannot change player reading preferences",not runtime.command(nonplayer).ok and Data.json_equal(before,runtime.capture_checkpoint()))
	var favorite:Dictionary=request("handbook.favorite","item:log",true,"book:favorite")
	var accepted:Dictionary=runtime.command(favorite)
	check("explicit shared command saves a real favorite",accepted.ok and runtime.handbook_snapshot().preferences.favorites==["item:log"],accepted)
	var after:Dictionary=runtime.capture_checkpoint()
	check("read commands do not change inventory knowledge clock or gameplay ledger",Data.json_equal(before.facts,after.facts) and Data.json_equal(before.world.extensions.get("r3:production"),after.world.extensions.get("r3:production")) and before.content==after.content)
	check("command receipt replay is idempotent",runtime.command(favorite)==accepted and Data.json_equal(after,runtime.capture_checkpoint()))
	var stale:Dictionary=request("handbook.track","module:r34.module.fuel_woodshop",true,"book:stale");stale.expected_revision=0
	check("stale preference respects normal CAS",not runtime.command(stale).ok and Data.json_equal(after,runtime.capture_checkpoint()))
	check("tracking attaches only a definition target",runtime.command(request("handbook.track","module:r34.module.fuel_woodshop",true,"book:track")).ok and runtime.handbook_snapshot().preferences.tracked_target=="module:r34.module.fuel_woodshop")
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	check("native codec keeps optional preferences and original content lock",decoded.get("ok",false) and decoded.capture.content==before.content,decoded.get("reason"))
	var cold:Dictionary={}
	if decoded.get("ok",false):
		var cold_host:=Native.new();cold=cold_host._assemble(decoded.capture);cold_host.free()
	check("cold actual services keep favorite and tracking",cold.get("ok",false) and cold.runtime.handbook_snapshot().preferences==runtime.handbook_snapshot().preferences,cold.get("reason"))
	var malformed:Dictionary=Display.initial();malformed.handbook={"favorites":["item:log","item:log"],"tracked_target":""}
	check("duplicate saved favorites refuse restoration",not Display.validate(malformed).ok)
	malformed.handbook={"favorites":[],"tracked_target":{}}
	check("bad saved tracking type refuses restoration",not Display.validate(malformed).ok)
	check("unfavorite and untrack change no simulation facts",runtime.command(request("handbook.favorite","item:log",false,"book:unfavorite")).ok and runtime.command(request("handbook.track","module:r34.module.fuel_woodshop",false,"book:untrack")).ok and runtime.handbook_snapshot().preferences=={"favorites":[],"tracked_target":""} and Data.json_equal(runtime.facts(),before.facts))
	# Explicit privacy fixture, not a normal economy route: three synthetic
	# non-module containers at the real player location distinguish discovery
	# from owner permission. They never enter a production save or package.
	var fixture:Dictionary=before.duplicate(true)
	for spec:Array in [["fixture:public",true,null,7],["fixture:unsearched",false,null,111],["fixture:private",true,"repair-resident",222]]:
		fixture.facts.stocks.append({"id":spec[0],"searched":spec[1],"owner":spec[2],"items":{"stone_m3":spec[3]},"location":{"x":fixture.facts.actors[0].x,"y":fixture.facts.actors[0].y,"z":fixture.facts.actors[0].z,"regionId":fixture.facts.actors[0].regionId,"buildingId":null,"storeyId":null}})
	var fixture_host:=Native.new();var fixture_built:Dictionary=fixture_host._assemble(fixture);fixture_host.free()
	check("explicit privacy fixture assembles through original validators",fixture_built.get("ok",false),fixture_built.get("reason"))
	if fixture_built.get("ok",false):
		var fixture_before:Dictionary=fixture_built.runtime.capture_checkpoint()
		var stone:Dictionary=fixture_built.runtime.handbook_snapshot("player","item:stone_m3").selection.current
		check("searched public non-module stock appears without private or unsearched quantities",stone.actual==7 and stone.stocks.size()==1 and stone.stocks[0].id=="fixture:public" and stone.stocks[0].onsite)
		check("fixture query cannot reveal container sentinels or mutate originals",not JSON.stringify(stone).contains("111") and not JSON.stringify(stone).contains("222") and Data.json_equal(fixture_before,fixture_built.runtime.capture_checkpoint()))
	if args.size()>1:
		var old:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
		var archived:Dictionary={}
		if old.get("ok",false):
			var archived_host:=Native.new();archived=archived_host._assemble(old.capture);archived_host.free()
		check("exact archived normal-economy save accepts unchanged source",archived.get("ok",false),archived.get("reason"))
		if archived.get("ok",false):
			var original:Dictionary=archived.runtime.capture_checkpoint()
			var known:Dictionary=archived.runtime.handbook_snapshot("player","process:manual:saw_timber")
			check("archive reads actual learned knowledge",known.selection.learned and entry(known,"knowledge:basic_woodwork").learned)
			check("archive queries preserve all facts and optional field absence",Data.json_equal(original,archived.runtime.capture_checkpoint()) and not original.world.extensions[Display.KEY].has("handbook"))
			var chosen:Dictionary=archived.runtime.handbook_snapshot("player","module:r34.module.fuel_woodshop").selection
			check("known module detail never leaks hidden generated instances",chosen.current.known_instances.all(func(m:Dictionary)->bool:return m.discovered))
			var head:Dictionary=archived.runtime.handbook_snapshot("player","item:axe_head").selection.current
			check("actual searched finite stockyard source is tracked without forcing module ownership",head.actual==1 and head.stocks.any(func(s:Dictionary)->bool:return s.id=="RH-HOME:stockyard-content:container") and head.onsite_free==0)
			var boards:Dictionary=archived.runtime.handbook_snapshot("player","item:timber").selection.current
			check("actual remote warehouse and carried material stay separate",boards.actual==10 and boards.onsite_free==2 and boards.stocks.any(func(s:Dictionary)->bool:return s.id=="r34:normal-built-warehouse:stock:storage" and not s.onsite and s.quantity.actual==8) and boards.stocks.any(func(s:Dictionary)->bool:return s.id=="pack:player" and s.onsite and s.quantity.actual==2),boards)
			var owner_reservations:bool=true
			for stock:Dictionary in boards.stocks:
				if stock.quantity.reserved!=archived.services.production.reserved(stock.id,"timber"):owner_reservations=false
			check("single owner hold read matches canonical input reservations",owner_reservations)
			var modes:Array=known.entries.filter(func(r:Dictionary)->bool:return r.kind=="process" and r.source_id=="saw_timber")
			check("same action recipe has two distinct mode cards and knowledge conditions",modes.size()==2 and modes[0].id!=modes[1].id and entry(known,"process:manual:saw_timber").definition.has("knowledge") and not entry(known,"process:machine:saw_timber").definition.has("knowledge"))
			var process:Dictionary=archived.runtime.handbook_snapshot("player","process:machine:saw_timber").selection
			var exact:Dictionary=archived.runtime.factory_snapshot().production.orders[0]
			check("actual completed machine order is not current running permission",not process.current.can_make and process.current.orders.size()==1 and process.current.orders[0].id==exact.id and process.current.blockers.any(func(b:Dictionary)->bool:return b.code=="target_met"),process.current)
			var paused:Dictionary=archived.runtime.command({"actor_id":"player","kind":"factory.pause","target_id":exact.module_id,"payload":{},"command_id":"handbook:actual-pause"})
			process=archived.runtime.handbook_snapshot("player","process:machine:saw_timber").selection
			check("actual pause uses owner order blocker rather than village materials",paused.get("ok",false) and not process.current.can_make and process.current.blockers.any(func(b:Dictionary)->bool:return b.code=="paused") and process.current.blockers.all(func(b:Dictionary)->bool:return b.code not in ["MATERIAL_REMOTE","MATERIAL_MISSING"]),process.current)
			# Explicit read-only DTO counterexample: a generic badge must not
			# grant readiness to an unrelated recipe. No production facts change.
			var projection:Dictionary=archived.runtime.factory_snapshot();var counter_before:Dictionary=archived.runtime.capture_checkpoint()
			for m:Dictionary in projection.modules.instances:m.state_code="running"
			for o:Dictionary in projection.production.orders:o.recipe_id="fixture:other-recipe";o.state_code="running";o.blockers=[]
			var counter:Dictionary={"known_instances":[],"blockers":[]}
			Handbook._machine_current(process,counter,projection,[])
			check("explicit unrelated-order DTO never borrows running host badge",not counter.can_make and counter.orders.is_empty() and counter.blockers.any(func(b:Dictionary)->bool:return b.code=="MACHINE_NOT_CONFIGURED") and Data.json_equal(counter_before,archived.runtime.capture_checkpoint()))
	finish()
func finish()->void:
	var report:Dictionary={"scope":"source-only actual runtime handbook definitions/privacy/commands/native restore; archive compatibility separately identified; no PCK, OS, VA or performance acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
