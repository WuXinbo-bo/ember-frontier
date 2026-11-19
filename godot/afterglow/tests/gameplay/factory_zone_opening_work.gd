extends "res://tests/gameplay/factory_zone_opening_journey.gd"
## Natural opening05 continuation: original finite container and tool sources,
## real player staging, then E arbitration/B supply and labor. No fixtures.
const SupplyExecutor=preload("res://scripts/actions/zone_supply_executor.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var rack:String="RH-HOME:stockyard-content:container"
var forest:String="E:actual12:forest"
var farm:String="E:actual12:farm"
var tracked_events:Dictionary={}
var task_id:String=""
var tree_id:String=""
var supply_cold:bool=false

func reach_stock(id:String)->bool:
	var stock:Dictionary=runtime.stock(id)
	if stock.is_empty():check("original source still exists "+id,false);return false
	var actions:RefCounted=runtime.domain_service("actions")
	if id==rack and not stock.get("searched",false):
		# Supply is deliberately forbidden on an unsearched rack. Reuse the
		# original normal-source search stance, not a forged searched DTO.
		var anchor:Dictionary=runtime.world.extension("generation:RH-HOME").content_anchors[0]
		var hint:Dictionary=anchor.position.duplicate(true);hint.z-=1.2
		var feet:Dictionary=runtime.domain_service("buildings").current_space().standing_point(hint)
		check("actual original stockyard search stance is supported",not feet.is_empty())
		return not feet.is_empty() and await go(feet,"player reaches original stockyard search stance")
	var route:Dictionary=SupplyExecutor.stock_path(actions,Draft.new(actions.context),runtime.actor("player"),stock)
	check("original B contact planner finds a real container side "+id,route.get("ok",false),route if not route.get("ok",false) else null)
	if not route.get("ok",false):return false
	var at:Dictionary=G.location(runtime.actor("player")) if route.steps.is_empty() else route.steps[-1].to
	return await go(at,"player physically reaches original contact side "+id)

func tick()->void:
	super.tick()
	for event:Dictionary in runtime.facts().ledger:
		if event.get("kind") in ["zone-supply-completed","zonework-started","zonework-completed","tree-felled","inventory-transfer","logistics-delivery-completed","life-completed","ecology-work-completed"]:tracked_events[str(event.id)]=event.duplicate(true)

func create_zone(id:String,spec:Dictionary)->bool:
	var preview:Dictionary=runtime.zone_preview(spec)
	if not preview.get("ok",false) or int(preview.get("valid_count",0))<1:return false
	var result:Dictionary=send_to("zone.create",id,{"spec":spec})
	return result.get("ok",false)

func find_forest()->bool:
	var trees:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.kind=="tree" and e.get("data",{}).get("harvest",{}).get("phase")=="standing" and e.get("data",{}).get("appearance",{}).get("model","")!="dead_tree")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return G.point(a.position).distance_squared_to(G.point(runtime.actor("repair-resident")))<G.point(b.position).distance_squared_to(G.point(runtime.actor("repair-resident"))))
	for tree:Dictionary in trees.slice(0,12):
		var x:int=floori(float(tree.position.x)*2);var z:int=floori(float(tree.position.z)*2)
		if not create_zone(forest,{"kind":"forestry","region_id":"RH-HOME","bounds":{"x0":x,"z0":z,"x1":x+1,"z1":z+1},"policy":{"mature_only":true,"replant":false,"priority":5,"worker_ids":["repair-resident"]}}):continue
		var rows:Array=runtime.domain_service("zonework").work_candidates("repair-resident")
		if rows.any(func(c:Dictionary)->bool:return c.zone_id==forest and c.kind=="supply" and c.valid and not c.tool_ids.is_empty()):tree_id=tree.id;return true
		send_to("zone.cancel",forest)
	return false

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("actual paid new12 two-member success mounts unchanged",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime;initial=runtime.capture_checkpoint();elapsed_start=runtime.clock()
	check("only original voluntarily returned two people can work",runtime.facts().actors.size()==3 and ["village-resident","repair-resident"].all(func(id:String)->bool:return runtime.actor(id).relationship.consent and runtime.actor(id).relationship.get("home_arrived",false)))
	note("actual12-paid-members-input")
	# Open an actual legacy ground container. It has no module filter and is
	# not a generated test rack; original generic capacity/ownership still apply.
	if not await reach_stock(rack):return finish()
	if not runtime.stock(rack).get("searched",false) and not perform("original timed search opens finite stockyard rack","search",rack):return finish()
	var axes:Array=[]
	for tool:Dictionary in runtime.world.extension("r3:production").tools:
		if tool.holderId=="pack:player" and tool.kind=="salvaged_axe":axes.append(tool.id)
	check("player stages the original recovered axe identity",axes.size()==1,axes)
	if axes.size()!=1:return finish()
	var staged:Dictionary={"r34:potato_seed":1,"r34:water_bucket":1}
	if not perform("player really deposits original axe seed and reusable bucket into old container","deposit",rack,{"items":staged,"tool_ids":axes}):return finish()
	check("original shovel remains in original searched rack for autonomous pickup",runtime.world.extension("r3:production").tools.any(func(t:Dictionary)->bool:return t.holderId==rack and t.kind=="shovel"))
	if not await take_stock(source_home,{"food":1,"water":1}):return finish()
	note("finite-world-supplies-staged-by-player")
	var selected:bool=find_forest();check("real generated local tree creates autonomous missing-tool offer",selected,{"zones":runtime.zone_records(),"candidates":runtime.domain_service("zonework").work_candidates("repair-resident")})
	if not selected:return finish()
	var tool_start:float=float(runtime.tool(axes[0]).durability)
	var seen_supply:bool=false;var seen_harvest:bool=false
	for i:int in 1500:
		tick()
		var a:Dictionary=runtime.actor("repair-resident")
		if a.get("intent") is Dictionary and a.intent.get("kind")=="zone_supply":
			seen_supply=true
			if not supply_cold:supply_cold=cold("actual12-autonomous-supply-active-cold")
		if a.get("intent") is Dictionary and a.intent.get("kind")=="harvest":seen_harvest=true
		if tracked_events.values().any(func(e:Dictionary)->bool:return e.kind=="tree-felled" and e.get("actor_id")=="repair-resident" and e.get("target_id",e.get("tree_id"))==tree_id):break
		if runtime.world.entity(tree_id).get("data",{}).get("harvest",{}).get("phase")=="stump":break
	var felled:bool=runtime.world.entity(tree_id).get("data",{}).get("harvest",{}).get("phase")=="stump"
	check("E alone admits B supply from the original finite rack with active cold",seen_supply and supply_cold and runtime.tool(axes[0]).holderId=="pack:repair-resident",runtime.actor("repair-resident"))
	check("same NPC really moves and fells original tree with paid axe wear",seen_harvest and felled and float(runtime.tool(axes[0]).durability)<tool_start,{"actor":runtime.actor("repair-resident"),"tree":runtime.world.entity(tree_id),"events":tracked_events.values()})
	if not felled:return finish()
	send_to("zone.cancel",forest)
	note("autonomous-real-forestry-completed")
	cold("actual12-forestry-completed-cold")
	check("original HP consent finite seeds bucket and population persist",initial.facts.actors.all(func(a:Dictionary)->bool:return runtime.actor(a.id).hp==a.hp) and ["village-resident","repair-resident"].all(func(id:String)->bool:return runtime.actor(id).relationship.consent) and quantities().get("r34:potato_seed")==4 and quantities().get("r34:water_bucket")==1)
	finish()

func finish()->void:
	if runtime!=null:
		FileAccess.open(output+"/work-events.json",FileAccess.WRITE).store_string(JSON.stringify(tracked_events,"\t",true,true))
		save("actual12-autonomous-work-final")
	super.finish()
