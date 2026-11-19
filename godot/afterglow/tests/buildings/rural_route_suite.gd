extends "res://tests/buildings/domain_suite.gd"
## Actual finite opening + formal offscreen assembler. No teleports/extra stock.
## Command-level route only: A still owns physical input/app/visual acceptance.
const Client=preload("res://scripts/runtime/native_client.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Store=preload("res://scripts/storage/native_store.gd")
var host:Node
var route_steps:Array=[]
class SparseDiagnostic extends "res://scripts/buildings/building_navigation.gd":
	func grid_plan(_start:Dictionary,_finish:Dictionary)->Dictionary:return {"ok":false,"reason":"sparse diagnostic only"}

func differences(a:Variant,b:Variant,path:String="",found:Array=[])->Array:
	if found.size()>=100:
		if found[-1].get("path")!="__difference_limit__":found.append({"path":"__difference_limit__","truncated":true})
		return found
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key):found.append({"path":path+"/"+str(key),"missing":true})
			else:differences(a[key],b[key],path+"/"+str(key),found)
		for key in b:
			if not a.has(key):found.append({"path":path+"/"+str(key),"extra":b[key]})
	elif a is Array and b is Array:
		if a.size()!=b.size():found.append({"path":path,"sizes":[a.size(),b.size()]})
		for i in mini(a.size(),b.size()):differences(a[i],b[i],path+"/"+str(i),found)
	elif a!=b:found.append({"path":path,"before":a,"after":b,"numeric_delta":float(b)-float(a) if (a is float or a is int) and (b is float or b is int) else null})
	return found

func continuous_roundtrip_only(changes:Array)->bool:
	# JSON preserves numeric meaning, not every double's last bit. Permit only
	# these named continuous fields, never inventory counts, IDs or state flags.
	for change:Dictionary in changes:
		var path:PackedStringArray=str(change.path).split("/")
		var allowed:bool=str(change.path)=="facts/time" or (path.size()==4 and ((path[0]=="facts" and path[1]=="ledger" and path[3]=="time") or (path[0]=="production" and path[1]=="tools" and path[3]=="durability") or (path[0]=="production" and path[1]=="orders" and path[3]=="elapsed")))
		if not allowed or not change.get("numeric_delta") is float or absf(float(change.numeric_delta))>1e-12:return false
	return true

func completed(limit:int=3000)->bool:
	for i in limit:
		if runtime.actor("player").get("intent")==null:return true
		runtime.tick(0.1)
	return false

func perform(label:String,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->bool:
	var result:=command(kind,target,payload,destination)
	var done:bool=result.ok and completed()
	expect(label,done,result if not done else null)
	route_steps.append({"label":label,"kind":kind,"target":target,"ok":done,"position":Geometry.location(runtime.actor("player")),"time":runtime.clock()})
	return done

func reach_stock(id:String)->bool:
	var stock:Dictionary=runtime.stock(id)
	var points:Array=building.use_points(str(stock.get("structureId","")))
	if points.is_empty():points=[Geometry.location(stock)]
	var attempts:Array=[]
	for point in points:
		var r:=command("walk","",{},point)
		attempts.append({"point":point,"result":r})
		if r.ok and completed() and production.reach("player",id,stock,"search")==null:
			route_steps.append({"label":"real arrival","target":id,"position":Geometry.location(runtime.actor("player")),"time":runtime.clock()})
			return true
	var nav:=SparseDiagnostic.new()
	var proof:Dictionary=nav.plan(building.current_space(),"player",Geometry.location(runtime.actor("player")),points[0])
	var neighbors:Array=[]
	for key in nav.edges:
		if nav.edges[key].ok:neighbors.append({"edge":key,"steps":nav.edges[key].steps})
	print("ROUTE_DIAGNOSTIC "+JSON.stringify({"proof":proof,"nodes":nav.nodes,"successful_edges":neighbors}))
	expect("real route reaches "+id,false,{"stock":stock,"actor":runtime.actor("player"),"attempts":attempts})
	return false

func route_opening()->void:
	var home:="rural:v1:RH-HOME:old-house"
	var shed:="rural:v1:RH-HOME:shed"
	var pack:="pack:player"
	if not reach_stock(home+":storage"):return
	if not perform("take finite home bedding and water","take",home+":storage",{"items":{"cloth":2,"water":1}}):return
	var bed:Dictionary=world.entity(home+":sleeping-place")
	var near:Dictionary=Geometry.location(bed);near.x+=1.1
	if not perform("walk through real rooms to sleeping place","walk","",{},near):return
	if not perform("prepare bedding using the two taken cloth","care",bed.id,{"source_id":pack}):return
	if not perform("prepared bed supports actual fatigue recovery","rest",bed.id):return
	if not reach_stock(shed+":storage"):return
	if not perform("search actual shed cabinet","search",shed+":storage"):return
	if not perform("take actual tools books and finite shed materials","take",shed+":storage",{"items":{"timber":8,"scrap":6,"book_woodwork":1,"book_tool_repair":1},"tool_ids":[shed+":hammer",shed+":hand_saw",shed+":salvaged_axe"]}):return
	if not perform("read physical woodworking manual","study",shed+":record:woodwork",{"record_id":shed+":record:woodwork"}):return
	if not perform("read physical tool repair manual","study",shed+":record:repair",{"record_id":shed+":record:repair"}):return
	var gate:=home+":yard-gate"
	var points:Array=building.use_points(gate)
	if not perform("walk back to actual yard gate","walk","",{},points[0]):return
	if not perform("repair finite gate with taken material and tool","structure",gate,{"kind":"repair","source_id":pack,"output_id":pack,"tool_id":shed+":hammer"}):return
	var bench:Dictionary=actions.camp_work_targets().filter(func(t:Dictionary)->bool:return str(t.id).begins_with("work:build:"))[0].work_payload.instance
	var bench_use:Dictionary=building.current_space().use_points(bench)[0]
	if not perform("walk to reserved real workbench position","walk","",{},bench_use):return
	if not perform("construct learned workstation using finite materials","structure",bench.id,{"kind":"place","instance":bench,"source_id":pack,"output_id":pack,"tool_id":shed+":hammer"}):return
	if not perform("make usable replacement handle at constructed station","craft",bench.id,{"recipe_id":"make_handle","source_id":pack,"output_id":pack,"tool_ids":[shed+":hand_saw"]}):return
	expect("finite route produces one physical tool handle",runtime.actor("player").pack.get("tool_handle",0)==1)
	var capture:=runtime.capture_checkpoint()
	var saved:=Store.encode(capture)
	var decoded:=Store.decode(saved.get("text",""))
	var assembled:Dictionary=host._assemble(decoded.capture) if saved.ok and decoded.ok else {"ok":false,"reason":saved.get("reason",decoded.get("reason"))}
	expect("same formal assembler restores completed finite camp route",assembled.ok,assembled.get("reason"))
	if assembled.ok:
		var restored:RefCounted=assembled.runtime
		var changes:Array=differences(capture.facts,restored.facts(),"facts",[])
		changes.append_array(differences(capture.world.extensions[Production.KEY],restored.world.extension(Production.KEY),"production",[]))
		var max_error:=0.0
		for change:Dictionary in changes:
			if change.get("numeric_delta") is float:max_error=maxf(max_error,absf(float(change.numeric_delta)))
		expect("save preserves exact discrete facts and continuous values within 1e-12",continuous_roundtrip_only(changes),{"max_absolute_error":max_error,"all_differences":changes,"absolute_tolerance":1e-12,"exact_fields":"all fields except time, ledger.time, tools.durability, orders.elapsed"})
		expect("roundtrip comparator never tolerates inventory loss or larger time changes",not continuous_roundtrip_only([{"path":"facts/actors/0/pack/timber","numeric_delta":1e-14}]) and not continuous_roundtrip_only([{"path":"facts/time","numeric_delta":1e-9}]))
		expect("save retains prepared bed repaired gate and constructed station",assembled.world.entity(bed.id).data.prepared and assembled.services.buildings.instance(gate).hp==120 and not assembled.services.buildings.instance(bench.id).is_empty())

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("actual source rural world loads",world.load_snapshot(Generator.generate(713)).ok)
	building.configure({"world":world,"runtime":runtime})
	var seed:Dictionary=building.seed_rural(world)
	var facts:Dictionary=Initial.facts(seed)
	var changes:Array=seed.world_changes.duplicate(true)
	changes.append_array([building.extension_change(Production.KEY,Initial.production(seed)),building.extension_change(Gameplay.KEY,Gameplay.initial()),building.extension_change("r3:structure-orders",{"version":1,"orders":[]})])
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	var safe:Dictionary=building.validate_world_draft(draft.view,facts,changes) if draft.ok else draft
	expect("unmodified finite opening safe for all actual residents",safe.ok,safe.get("reason"))
	if not safe.ok:finish_route(started);return
	expect("actual initial world commits",world.commit_prepared(draft.capability).ok)
	host=Client.new()
	var assembled:Dictionary=host._assemble({"world":world.snapshot(),"facts":facts,"source":{"test":"B unmodified opening command route"}})
	expect("formal assembler connects all real services",assembled.ok,assembled.get("reason"))
	if not assembled.ok:finish_route(started);return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
	expect("actual starting player has only original food water",runtime.actor("player").pack=={"food":1,"water":1} and runtime.facts().actors.size()==3)
	expect("actual starting camp has no free home workbench or knowledge",production.state().knowledge.is_empty() and not building.structures().instances.any(func(v:Dictionary)->bool:return v.definitionId=="workbench" and v.regionId=="RH-HOME"))
	route_opening()
	print("ACTUAL_OPENING_ROUTE "+JSON.stringify(route_steps))
	finish_route(started)

func finish_route(started:int)->void:
	if host!=null:host.free()
	finish(started)
