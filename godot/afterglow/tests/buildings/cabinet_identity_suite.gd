extends "res://tests/buildings/domain_suite.gd"
## Only the already-defined nearby same-storey cabinet move is supported.
## This is not a new portable machine or permission to move complete modules.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Data=preload("res://scripts/world/world_data.gd")
var hosts:Array=[]
func wait_work(limit:int=250)->void:
	for i:int in limit:
		if runtime.actor("player").intent==null:return
		runtime.tick(0.1)
func move_request(id:String,z:float)->Dictionary:
	return {"command_id":id,"actor_id":"player","kind":"structure","target_id":"B:identity:cabinet","payload":{"kind":"move","destination":{"position":{"x":32,"y":0,"z":z},"quarterTurn":0},"source_id":"pack:player","output_id":"pack:player","tool_id":"rural:v1:RH-HOME:shed:hammer"}}
func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real retained legacy world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seeded:Dictionary=building.seed_rural(world)
	var prepared:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("legacy seed commits into sole world",prepared.ok and world.commit_prepared(prepared.capability).ok)
	if not prepared.ok:finish(started);return
	initialize_at({"x":31.2,"y":0,"z":42,"regionId":"RH-HOME","buildingId":null,"storeyId":null},[],seeded.initial_stocks)
	var facts:Dictionary=runtime.facts();facts.actors[0].pack={"timber":20,"scrap":20,"food":2,"book_woodwork":1}
	# Explicit finite physical ownership fixture, not duplicate book identities.
	for stock:Dictionary in facts.stocks:
		if stock.items.has("book_woodwork"):stock.items.book_woodwork=0
	var p:Dictionary=Production.empty_state();p.tools=seeded.initial_tools;p.records=seeded.initial_records;p.knowledge={"player":["basic_woodwork"]}
	for t:Dictionary in p.tools:t.holderId="pack:player"
	for record:Dictionary in p.records:
		if record.itemId=="book_woodwork":record.holderId="pack:player"
	expect("finite supplies restore into real runtime",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	prepared=world.prepare_changes([building.extension_change(Production.KEY,p)],world.get_revision())
	expect("original tools and book register without duplicate identity",prepared.ok and world.commit_prepared(prepared.capability).ok)
	var cabinet:Dictionary=building.make_instance("cabinet","B:identity:cabinet",{"x":32,"y":0,"z":43,"regionId":"RH-HOME"})
	var original_pack:Dictionary=runtime.actor("player").pack.duplicate(true)
	var place:=command("structure",cabinet.id,{"kind":"place","instance":cabinet,"source_id":"pack:player","tool_id":"rural:v1:RH-HOME:shed:hammer"})
	expect("existing cabinet is actually paid and constructed",place.ok,place)
	if not place.ok:finish(started);return
	wait_work()
	var paid:Dictionary=original_pack.duplicate(true)
	for item:String in building.geometry.definitions.cabinet.cost:paid[item]=float(paid[item])-float(building.geometry.definitions.cabinet.cost[item])
	expect("only initial placement consumes exact existing cost",not building.instance(cabinet.id).is_empty() and Data.json_equal(paid,runtime.actor("player").pack))
	var axe:String="rural:v1:RH-HOME:shed:salvaged_axe"
	expect("real deposit stores finite food book and original axe",command("deposit",cabinet.id,{"items":{"food":1,"book_woodwork":1},"tool_ids":[axe]}).ok)
	var stock:Dictionary=runtime.stock(cabinet.id);var old_piece:Dictionary=building.instance(cabinet.id)
	var old_pack:Dictionary=runtime.actor("player").pack.duplicate(true)
	var old_tools:Array=production.state().tools.duplicate(true);var old_records:Array=production.state().records.duplicate(true)
	var rejected_before:Dictionary=runtime.capture_checkpoint()
	var far:=runtime.command(move_request("B:identity:far-refuse",47.0))
	expect("out-of-range heavy cabinet move rejects atomically",not far.ok and Data.json_equal(rejected_before,runtime.capture_checkpoint()),far)
	var request:=move_request("B:identity:move-once",43.8)
	var moved:=runtime.command(request)
	expect("same loaded cabinet admits only existing nearby move",moved.ok,moved)
	if not moved.ok:finish(started);return
	for i:int in 20:runtime.tick(0.1)
	expect("partial real labor does not duplicate cabinet contents or charge costs",building.instance(cabinet.id).position==old_piece.position and runtime.stock(cabinet.id)==stock and Data.json_equal(old_pack,runtime.actor("player").pack))
	var host:=Native.new();hosts.append(host)
	var cold:Dictionary=host._assemble(runtime.capture_checkpoint())
	expect("in-progress loaded cabinet and owner identities cold restore",cold.ok,cold.get("reason"))
	if not cold.ok:finish(started);return
	runtime=cold.runtime;world=cold.world;building=cold.services.buildings;actions=cold.services.actions;production=cold.services.production
	wait_work()
	var result:Dictionary=building.instance(cabinet.id);var after:Dictionary=runtime.stock(cabinet.id)
	expect("five seconds move original structure identity and version once",result.id==old_piece.id and result.definitionId==old_piece.definitionId and result.owner==old_piece.owner and result.hp==old_piece.hp and result.version==old_piece.version+1 and is_equal_approx(float(result.position.z),43.8))
	expect("one original stock follows same object without replacing owner or contents",after.id==stock.id and after.structureId==stock.structureId and after.owner==stock.owner and after.searched==stock.searched and Data.json_equal(after.items,stock.items) and is_equal_approx(float(after.location.z),43.8))
	var tool_identity_ok:bool=production.state().tools.size()==old_tools.size()
	for old_tool:Dictionary in old_tools:
		var actual:Dictionary=runtime.tool(old_tool.id);var original:Dictionary=old_tool.duplicate(true)
		var wear:float=0.75 if old_tool.kind=="hammer" else 0.0
		tool_identity_ok=tool_identity_ok and is_equal_approx(float(actual.durability),float(original.durability)-wear)
		actual.erase("durability");original.erase("durability")
		tool_identity_ok=tool_identity_ok and Data.json_equal(original,actual)
	expect("physical tool and book identities persist with only actual hammer labor wear",tool_identity_ok and Data.json_equal(old_records,production.state().records) and runtime.tool(axe).holderId==cabinet.id and Draft.find(production.state().records,"rural:v1:RH-HOME:shed:record:woodwork").holderId==cabinet.id,{"old_tools":old_tools,"actual_tools":production.state().tools,"old_records":old_records,"actual_records":production.state().records})
	expect("move never repeats original manufacture material cost",Data.json_equal(old_pack,runtime.actor("player").pack))
	expect("one entity record and one stock survive the move",building.structures().instances.filter(func(v:Dictionary)->bool:return v.id==cabinet.id).size()==1 and runtime.facts().stocks.filter(func(s:Dictionary)->bool:return s.id==cabinet.id).size()==1 and is_equal_approx(float(world.entity(cabinet.id).position.z),43.8))
	var completed:Dictionary=runtime.capture_checkpoint()
	expect("same move command replay cannot move duplicate or charge again",runtime.command(request).ok and Data.json_equal(completed,runtime.capture_checkpoint()))
	var final_host:=Native.new();hosts.append(final_host);var final:Dictionary=final_host._assemble(completed)
	expect("completed move cold restore keeps original world stock tools and records",final.ok and Data.json_equal(completed.facts,final.runtime.facts()) and Data.json_equal(production.state(),final.services.production.state()) and final.services.buildings.instance(cabinet.id)==result)
	finish(started)
func finish(started:int)->void:
	var result:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"finite paid legacy cabinet, actual 5sec nearby same-storey move, original contents/tools/book identity and Native cold restore; no general module relocation/OS/VA acceptance"}
	if not OS.get_cmdline_user_args().is_empty():
		var output:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(result,"\t",true,true));file.close()
	print(JSON.stringify(result))
	for host:Node in hosts:host.free()
	quit(0 if failures.is_empty() else 1)
