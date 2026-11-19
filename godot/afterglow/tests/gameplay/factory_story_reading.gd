extends "res://tests/world/factory_normal_path.gd"
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
const Stories=preload("res://scripts/runtime/factory_gameplay_story.gd")

func card(runtime:RefCounted,id:String)->Dictionary:
	for row:Dictionary in runtime._services.workforce.projection().stories:
		if row.id==id:return row
	return {}

func read_count(runtime:RefCounted)->int:
	return runtime.facts().ledger.filter(func(event:Dictionary)->bool:return event.kind=="settlement-story-read").size()

func restore(runtime:RefCounted)->Dictionary:
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	if not decoded.ok:return decoded
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	return built

func run()->void:
	var opening:Dictionary=normal_tools(Contract.fresh(Modules.generation_profiles(),3,1).contract)
	if not opening.ok:return finish()
	var runtime:RefCounted=opening.runtime;var world:RefCounted=opening.world
	runtime.tick(0.1)
	var plan:Dictionary=world.extension("generation:RH-VILLAGE")
	var seed:Dictionary=plan.module_seeds.filter(func(s:Dictionary)->bool:return s.purpose=="store")[0]
	var source:String=world.extension("r34:modules").source_receipts[seed.source_key].stock_ids[0]
	var request:Dictionary={"story_id":"ST03","source_id":source}
	var projection:Dictionary=runtime._services.workforce.projection()
	check("unknown store and people do not leak source IDs or dialogue",not card(runtime,"ST03").available and card(runtime,"ST03").sources.is_empty() and not card(runtime,"ST02").available and card(runtime,"ST02").people.is_empty())
	check("searched normal tool and recovery sources reveal only their real stories",card(runtime,"ST01").available and card(runtime,"ST04").available and not card(runtime,"ST01").flags.get("read_woodwork_record",false))
	check("unread records never reveal the route on the map",projection.map_markers.all(func(row:Dictionary)->bool:return row.kind!="route_clue"))
	var before:Dictionary=runtime.capture_checkpoint()
	var remote:Dictionary=send(runtime,"settlement.read_story","",request)
	check("unsearched remote source cannot be read",not remote.ok and Data.json_equal(before,runtime.capture_checkpoint()),remote)
	var approached:Dictionary=walk(runtime,runtime.stock(source).location)
	check("normal actor physically walks to the actual generated store stock",approached.get("ok",false),approached)
	if not approached.get("ok",false):return finish()
	var searched:Dictionary=send(runtime,"search",source)
	if searched.ok:progress(runtime)
	runtime.tick(0.1)
	check("actual search exposes a source-bound read action, not an already read clue",searched.ok and card(runtime,"ST03").commands.size()==1 and card(runtime,"ST03").clues.is_empty(),searched)
	var taken:Dictionary=send(runtime,"take",source,{"items":{"water":1}});runtime.tick(0.1)
	check("real finite supplies change ST03 stage through actual transfer",taken.ok and card(runtime,"ST03").flags.get("real_supplies_taken",false),taken)
	before=runtime.capture_checkpoint()
	var invalid:Dictionary=send(runtime,"settlement.read_story","",{"story_id":"ST03","source_id":opening.tool_stock})
	check("unrelated searched stocks cannot stand in for the store record",not invalid.ok and Data.json_equal(before,runtime.capture_checkpoint()),invalid)
	var home:Dictionary=world.extension(Gameplay.KEY).layout.home
	var away:Dictionary=walk(runtime,home)
	before=runtime.capture_checkpoint();remote=send(runtime,"settlement.read_story","",request)
	check("known searched record still requires B physical contact",away.get("ok",false) and not remote.ok and Data.json_equal(before,runtime.capture_checkpoint()),remote)
	approached=walk(runtime,runtime.stock(source).location)
	if not approached.get("ok",false):check("return to record source",false,approached);return finish()
	var inventory:Dictionary={"pack":runtime.actor("player").pack,"stock":runtime.stock(source)}
	var read:Dictionary=send(runtime,"settlement.read_story","",request)
	var state:Dictionary=world.extension(Gameplay.KEY)
	check("onsite read persists exactly this true source without granting items",read.ok and state.stories.ST03.flags.get("read_source:"+source,false) and inventory.pack==runtime.actor("player").pack and inventory.stock==runtime.stock(source),read)
	check("reading does not survey accept risk clear stone or begin the threat",state.defense.status=="dormant" and state.get("regional_objectives",{}).is_empty() and plan.regional_sites[0].obstacle_cells.all(func(c:Dictionary)->bool:return world.cell_at(c.x,c.y,c.z)==3))
	var known:Dictionary=card(runtime,"ST03")
	var markers:Array=runtime._services.workforce.projection().map_markers.filter(func(row:Dictionary)->bool:return row.kind=="route_clue")
	check("read clue maps only the actual C survey point with its stable identity",known.stage=="route_read" and known.commands.is_empty() and markers.size()==1 and markers[0].id==plan.regional_sites[0].id and markers[0].location==plan.regional_sites[0].survey_point,markers)
	var count:int=read_count(runtime);send(runtime,"settlement.read_story","",request)
	check("re-reading has no repeated story event inventory or reward",count==1 and read_count(runtime)==count and inventory.pack==runtime.actor("player").pack and inventory.stock==runtime.stock(source))
	var restored:Dictionary=restore(runtime)
	check("real native cold restore retains read flag finite stock and known clue",restored.get("ok",false) and Data.json_equal(card(restored.runtime,"ST03"),known) and Data.json_equal(restored.runtime.actor("player").pack,inventory.pack) and Data.json_equal(restored.runtime.stock(source),inventory.stock),restored.get("reason"))
	if restored.get("ok",false):
		runtime=restored.runtime;world=restored.world
		var reread:Dictionary=send(runtime,"settlement.read_story","",request)
		check("restored re-read cannot duplicate an event or grant",reread.ok and read_count(runtime)==count and Data.json_equal(runtime.stock(source),inventory.stock),{"request":reread,"expected_events":count,"actual_events":read_count(runtime),"stock_before":inventory.stock,"stock_after":runtime.stock(source)})
	# Explicit projection fixtures exercise individual wording, not recruitment.
	var fixture:Dictionary=state.duplicate(true)
	fixture.stories.ST02.people={"village-resident":{"met":true,"helped":true,"member":false,"consent":false},"repair-resident":{"met":false,"helped":false,"member":false,"consent":false}}
	var rows:Array=Stories.projection(fixture,runtime.facts())
	var neighbor:Dictionary=rows.filter(func(r:Dictionary)->bool:return r.id=="ST02")[0]
	check("help dialogue does not auto-recruit or expose the other unknown person",neighbor.people.size()==1 and neighbor.text.contains("不等于替我答应") and not neighbor.text.contains("老许"))
	fixture.stories.ST02.people["village-resident"].merge({"member":true,"consent":true,"home_arrived":false},true)
	neighbor=Stories.projection(fixture,runtime.facts()).filter(func(r:Dictionary)->bool:return r.id=="ST02")[0]
	check("consenting arrival dialogue does not claim the person already at work",neighbor.text.contains("到家前"))
	fixture.stories.ST02.people["village-resident"].merge({"consent":false,"home_arrived":true,"real_delivery":true},true)
	neighbor=Stories.projection(fixture,runtime.facts()).filter(func(r:Dictionary)->bool:return r.id=="ST02")[0]
	check("withdrawal preserves actual delivery history without assigning more work",neighbor.text.contains("撤回合作") and neighbor.text.contains("确实送到过"))
	before=runtime.capture_checkpoint();var detached:Dictionary=card(runtime,"ST03");detached.flags.clear();detached.clues.clear()
	check("story projection remains detached from authoritative facts and clock",Data.json_equal(before,runtime.capture_checkpoint()))
	costs.scope="Actual finite normal source tools and store walk/search/take/read/native restore; relationship wording checks use explicit projection fixtures, not normal recruitment. No PCK OS VA or performance qualification."
	finish()
