extends SceneTree
## Actual C v2 cells, A assembly, E survey/risk, B terrain and unchanged combat.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Regional=preload("res://scripts/runtime/factory_gameplay_region.gd")
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const StockRoute=preload("res://scripts/actions/zone_supply_executor.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Opening=preload("res://scripts/runtime/playtest_profile.gd")
const REMOTE_STORE="r34:generated:RH-VILLAGE:store"
const HOME_WORKSHOP="r34:generated:RH-HOME:woodwork"
var checks:Array=[]
var host:Node
var runtime:RefCounted
var output:String
var seq:int=0
var delivery_case:bool=false
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func command(kind:String,payload:Dictionary={},target_id:String="")->Dictionary:
	seq+=1
	var request:Dictionary={"kind":kind,"actor_id":"player","command_id":"E-site:"+str(seq),"payload":payload}
	if not target_id.is_empty():request.target_id=target_id
	if kind=="walk":request.destination=payload.destination
	return runtime.command(request)
func mount(capture:Dictionary)->bool:
	var assembled:Dictionary=host._assemble(capture)
	check("actual native assembly accepts region checkpoint",assembled.ok,assembled.get("reason"))
	if assembled.ok:runtime=assembled.runtime
	return assembled.ok
func settle()->bool:
	for i in 400:
		runtime.tick(0.1)
		if runtime.actor("player").get("intent")==null:return true
	return false
func run()->void:
	var args:=OS.get_cmdline_user_args()
	output=args[0];delivery_case=args.has("--delivery");DirAccess.make_dir_recursive_absolute(output);host=Native.new()
	var profiles:Dictionary=Assembly.generation_profiles()
	var fresh:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.get("profiles",[])))
	check("real fresh v2 C B A E opening composes",fresh.ok,fresh.get("reason",fresh.get("code")))
	if not fresh.ok:finish();return
	var sites:Array=fresh.layout.get("regional_sites",[])
	check("A layout adopts actual C persisted regional sites",sites.size()==1)
	if sites.size()!=1:finish();return
	var site:Dictionary=sites[0]
	check("C site uses exact E accepted DTO",Regional.site_valid(site),site)
	if not mount(fresh.capture):finish();return
	var workforce:RefCounted=runtime._services.workforce
	var cells:Array=site.obstacle_cells
	check("C generated real stone obstruction and preserved road bases",cells.all(func(c:Dictionary)->bool:return runtime.world.cell_at(c.x,c.y,c.z)==3) and site.goal_corridor.base_cells.all(func(c:Dictionary)->bool:return runtime.world.cell_at(c.x,c.y,c.z)==4))
	check("stone obstruction cannot report corridor cleared",not Regional.corridor_clear(workforce.context,site))
	var edited:Dictionary={"kind":"terrain","actor_id":"player","payload":{"operation":"dig","cells":[cells[0]]}}
	check("pure work gate protects actual site before risk confirmation",workforce.site_work_permission(edited).get("code")=="SITE_CONFIRMATION_REQUIRED")
	var outside:Dictionary=edited.duplicate(true);outside.payload.cells=[{"x":999,"y":1,"z":999}]
	check("unrelated terrain is not blocked by E site rules",workforce.site_work_permission(outside).ok)
	var level:Dictionary=edited.duplicate(true);level.payload={"operation":"level","area":{"minI":cells[0].x,"maxI":cells[0].x+1,"minK":cells[0].z,"maxK":cells[0].z+1},"height":0}
	check("level rectangle cannot bypass informed site gate",workforce.site_work_permission(level).get("code")=="SITE_CONFIRMATION_REQUIRED")
	check("remote survey cannot fabricate exploration",command("settlement.survey",{"site_id":site.id}).get("code")=="OUT_OF_REACH")
	# Explicit near-point fixture proves terrain and rule semantics, not the
	# normal inventory/route budget. A source supplies the actual tool instance.
	var near:Dictionary=runtime.capture_checkpoint()
	if delivery_case:near=Opening.prepare_opening(near,"normal")
	for a:Dictionary in near.facts.actors:
		if a.id=="player":a.merge(site.survey_point,true);a.intent=null;a.stamina=100.0
	var tool_id:String=""
	for tool:Dictionary in near.world.extensions["r3:production"].tools:
		if tool.kind=="pickaxe":tool.holderId="pack:player";tool_id=tool.id
	check("explicit fixture uses one actual finite pickaxe identity",not tool_id.is_empty())
	if not mount(near):finish();return
	workforce=runtime._services.workforce
	var before:Dictionary=runtime.capture_checkpoint()
	check("begin without real survey refuses even if risk flag true",command("settlement.begin_route_work",{"site_id":site.id,"accept_risk":true}).get("code")=="SITE_CONFIRMATION_REQUIRED")
	check("refused start changes no cells cargo or clock",Data.json_equal(before,runtime.capture_checkpoint()))
	check("actual on-site survey commits known site",command("settlement.survey",{"site_id":site.id}).ok)
	check("survey alone never starts warning or grants permission",runtime.world.extension(Gameplay.KEY).defense.status=="dormant" and workforce.site_work_permission(edited).get("code")=="SITE_CONFIRMATION_REQUIRED")
	check("risk acceptance cannot be omitted",command("settlement.begin_route_work",{"site_id":site.id}).get("code")=="SITE_CONFIRMATION_REQUIRED")
	var started:Dictionary=command("settlement.begin_route_work",{"site_id":site.id,"accept_risk":true})
	check("informed risk commit proves real return path and grants no items",started.ok,started)
	if not started.ok:finish();return
	runtime.tick(0.1)
	var state:Dictionary=runtime.world.extension(Gameplay.KEY)
	check("A committed work-start event starts exactly one regional warning",state.defense.status=="warning" and state.defense.site_id==site.id and float(state.defense.warning_remaining)>=60 and state.event_ids.has(state.defense.cause_event_id),state.defense)
	check("risk warning budget exposes measured path and pending balance status",state.regional_objectives[site.id].warning_basis.route_distance_m>0 and state.regional_objectives[site.id].warning_basis.status=="initial_tuning_pending_normal_route_acceptance")
	var basis:Dictionary=state.regional_objectives[site.id].warning_basis
	check("warning includes real home to combat point route and necessary preparation",basis.defense_route_distance_m>0 and basis.defense_route_seconds>0 and Data.json_equal(basis.defense_position,site.warning_points.approach_after) and basis.interruption_seconds>=1 and basis.preparation_components.necessary_action_seconds>=10 and state.regional_objectives[site.id].warning_seconds>=ceilf((basis.return_seconds+basis.defense_route_seconds+basis.interruption_seconds+basis.preparation_seconds)*basis.margin))
	check("same site cannot restart or reroll its encounter",command("settlement.begin_route_work",{"site_id":site.id,"accept_risk":true}).get("code")=="REGIONAL_EVENT_ALREADY_STARTED")
	check("actual accepted site now permits B terrain while retaining B checks",workforce.site_work_permission(edited).ok)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	check("survey risk and active warning encode as one checkpoint",encoded.ok,encoded.get("reason"))
	if encoded.ok:
		var decoded:Dictionary=Store.decode(encoded.text)
		check("native checkpoint preserves committed region event",decoded.ok,decoded.get("reason"))
		if decoded.ok:mount(decoded.capture);workforce=runtime._services.workforce
	# Execute actual terrain in contact order from the true survey shoulder.
	var remaining:Array=cells.duplicate(true);var dig_count:int=0;var terrain_failure:Dictionary={};var switched_side:=false
	while not remaining.is_empty():
		var progress:bool=false
		for cell:Dictionary in remaining.duplicate(true):
			var payload:Dictionary={"operation":"dig","cells":[{"x":cell.x,"y":cell.y,"z":cell.z}],"tool_id":tool_id}
			var ready:Dictionary=runtime.availability({"kind":"terrain","actor_id":"player","payload":payload})
			if not ready.ok:terrain_failure=ready;continue
			var dig:Dictionary=command("terrain",payload)
			if not dig.ok:terrain_failure=dig;continue
			if not settle():terrain_failure={"code":"TERRAIN_DID_NOT_FINISH"};break
			if runtime.world.cell_at(cell.x,cell.y,cell.z)==0:remaining.erase(cell);dig_count+=1;progress=true
		if not progress:
			if switched_side:break
			switched_side=true
			var walking:Dictionary=command("walk",{"destination":site.goal_corridor.approach_after})
			check("remaining far-side stones require actual B bypass walk",walking.ok and settle(),walking)
			if not walking.ok:break
	check("real B terrain clears all C stone cells without fake button completion",remaining.is_empty() and dig_count==cells.size(),{"remaining":remaining.size(),"cleared":dig_count,"failure":terrain_failure})
	check("actual corridor proof preserves road and supports a B route",Regional.corridor_clear(workforce.context,site))
	runtime.tick(0.1)
	state=runtime.world.extension(Gameplay.KEY)
	check("clear terrain alone does not claim unresolved defense complete",state.regional_objectives[site.id].corridor_clear and not state.regional_objectives[site.id].get("completed",false))
	var warning_limit:int=ceili(float(state.defense.warning_remaining)*10)+5
	var warning_started:float=runtime.clock()
	for i in warning_limit:
		runtime.tick(0.1)
		if runtime.world.extension(Gameplay.KEY).defense.status!="warning":break
	state=runtime.world.extension(Gameplay.KEY)
	var warning_sample:Dictionary={"state":state.defense,"clock_elapsed":runtime.clock()-warning_started,"status":runtime.facts().status,"player_hp":runtime.actor("player").hp,"site_detailed":runtime.region_is_detailed(site.region_id)}
	if state.defense.status=="warning":
		var probe:Dictionary=workforce.advance(.1)
		warning_sample.preview={"ok":probe.ok,"code":probe.get("code"),"reason":probe.get("reason"),"world_changes":probe.get("world_changes",[]).size()}
	check("warning spawns finite real enemies while player remains outside home",state.defense.status=="active" and state.defense.actors.size()==3 and runtime.actor("player").regionId==site.region_id,warning_sample)
	var visible_ids:Array=runtime.actor_presentation().visible_actor_ids
	var public_view:Dictionary=runtime._services.workforce.projection("*")
	check("public event and map reuse A actual visibility without leaking future encounter positions",not public_view.regional_event.defense.has("encounter_positions") and public_view.regional_event.defense.actors.all(func(id:String)->bool:return visible_ids.has(id)) and public_view.map_markers.filter(func(marker:Dictionary)->bool:return marker.kind=="hostile").all(func(marker:Dictionary)->bool:return visible_ids.has(marker.id)))
	if state.defense.status=="active":
		var roster:Array=state.defense.actors.duplicate(true)
		var fighting:Dictionary=Store.encode(runtime.capture_checkpoint())
		check("active encounter persists exactly three real enemy identities",fighting.ok)
		if fighting.ok:
			var restored:Dictionary=Store.decode(fighting.text)
			if restored.ok:mount(restored.capture);workforce=runtime._services.workforce
		for i in 3:runtime.tick(0.1)
		check("revisit cannot respawn or clear live encounter",runtime.world.extension(Gameplay.KEY).defense.status=="active" and runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.get("encounter_id")=="r34:first-defense").size()==3 and not runtime.world.extension(Gameplay.KEY).regional_objectives[site.id].get("completed",false))
		if delivery_case:
			# The loss case above remains realistic. This branch bounds combat to
			# isolate post-victory delivery; actual attacks still settle all deaths.
			var victory_setup:Dictionary=runtime.capture_checkpoint()
			for actor:Dictionary in victory_setup.facts.actors:
				if roster.has(actor.id):actor.hp=1.0
			check("delivery fixture uses a legal wounded hostile roster",mount(victory_setup))
		var approach:Dictionary=site.goal_corridor.approach_after.duplicate(true)
		var target:Dictionary=runtime.actor(str(roster[0]));var direction:Vector3=(G.point(target)-G.point(approach)).normalized()
		approach.x+=direction.x*1.0;approach.z+=direction.z*1.0
		var walked:Dictionary=command("walk",{"destination":approach})
		check("player reaches combat using existing B walk",walked.ok and settle(),walked)
		var attacks:int=0
		for round_index in 25:
			var alive:Array=roster.filter(func(id:String)->bool:return float(runtime.actor(id).hp)>0)
			if alive.is_empty() or runtime.actor("player").hp<=0:break
			var strike:Dictionary={}
			for id:String in alive:
				strike=command("attack",{"tool_id":tool_id},id)
				if strike.ok or not delivery_case:break
			if strike.ok:attacks+=1
			for i in 7:runtime.tick(0.1)
		state=runtime.world.extension(Gameplay.KEY)
		var live:int=roster.filter(func(id:String)->bool:return float(runtime.actor(id).hp)>0).size()
		check("existing paid combat produces real damage and survival outcome",attacks>0 and roster.any(func(id:String)->bool:return float(runtime.actor(id).hp)<48) and (live==0 or runtime.actor("player").hp<=0),{"status":state.defense.status,"attacks":attacks,"player_hp":runtime.actor("player").hp,"player_stamina":runtime.actor("player").stamina,"enemies":roster.map(func(id:String)->Dictionary:return {"id":id,"hp":runtime.actor(id).hp})})
		check("regional completion requires both real clear corridor and resolved encounter",state.regional_objectives[site.id].corridor_clear and bool(state.regional_objectives[site.id].get("completed",false))==(live==0) and state.defense.status==("cleared" if live==0 else "active"))
		var outcome:Dictionary=Store.encode(runtime.capture_checkpoint())
		check("partial defeat and cleared road persist without respawn or free victory",outcome.ok)
		if outcome.ok:
			var decoded_outcome:Dictionary=Store.decode(outcome.text)
			if decoded_outcome.ok:
				var final_facts:Dictionary=runtime.facts()
				mount(decoded_outcome.capture)
				check("restored combat outcome preserves exact discrete enemy hp and event stage",runtime.world.extension(Gameplay.KEY).defense.status==state.defense.status and roster.all(func(id:String)->bool:return runtime.actor(id).hp==final_facts.actors.filter(func(a:Dictionary)->bool:return a.id==id)[0].hp))
		if delivery_case:check("resolved regional route supports an actual NPC trip and paid production",live==0 and delivery_and_work(site),runtime.world.extension(Gameplay.KEY).flags)
	var old_contract:Dictionary=Contract.fresh(profiles.profiles,1)
	var old:Dictionary=Assembly.prepare(Generator.generate(713,profiles.profiles,old_contract.contract))
	check("historical v1 opening remains without injected obstruction",old.ok and old.layout.get("regional_sites",[]).is_empty())
	finish()

func reach_stock(id:String,operation:String)->bool:
	var a:Dictionary=runtime.actor("player")
	var actions:RefCounted=runtime._services.actions
	var p:=StockRoute.stock_path(actions,Draft.new(actions.context),a,runtime.stock(id),operation)
	if not p.ok:return false
	if not p.steps.is_empty():
		var goal:Dictionary=p.steps[-1].get("to",{})
		if goal.is_empty() or not command("walk",{"destination":goal}).ok or not settle():return false
	return runtime._services.production.reach("player",id,runtime.stock(id),operation)==null

func delivery_and_work(site:Dictionary)->bool:
	var modules:RefCounted=runtime._services.modules
	var source:Dictionary=modules.instance(REMOTE_STORE)
	var workshop:Dictionary=modules.instance(HOME_WORKSHOP)
	if source.is_empty() or workshop.is_empty():return false
	var from:String=str(source.stock_refs.supplies);var to:String=str(workshop.stock_refs.tools)
	if not reach_stock(from,"search") or not command("search",{},from).ok or not settle():return false
	var shown:bool=Factory.endpoint_visible(runtime._services.production,runtime.actor("player"),runtime.stock(from)) and Factory.endpoint_visible(runtime._services.production,runtime.actor("player"),runtime.stock(to))
	check("on-site search reveals a usable finite exterior store and home receiver",shown,[from,to])
	if not shown:return false
	var before_from:float=item_count(from,"scrap");var before_to:float=item_count(to,"scrap")
	var queued:=command("logistics.create",{"source_id":from,"destination_id":to,"items":{"scrap":1},"priority":10})
	check("player queues the known physical endpoints without awarding progress",queued.ok and not runtime.world.extension(Gameplay.KEY).flags.get("chapter_route_delivered",false),queued.get("code"))
	if not queued.ok:return false
	var task:Dictionary=runtime.world.extension("r34:logistics").tasks.back()
	if not reach_stock(to,"stock"):return false
	for i:int in 2000:
		runtime.tick(.1)
		task=Draft.find(runtime.world.extension("r34:logistics").tasks,str(task.id))
		if task.get("trips",0)==1:break
	var settled:bool=task.get("trips",0)==1 and item_count(from,"scrap")==before_from-1 and item_count(to,"scrap")==before_to+1
	check("NPC logistics removes and delivers the same finite scrap",settled,task)
	if not settled:return false
	var arrivals:Array=runtime.facts().ledger.filter(func(e:Dictionary)->bool:return e.kind=="logistics-delivery-completed" and e.get("task_id")==task.id)
	# Workforce reads the canonical ledger before actions append this delivery.
	runtime.tick(.1)
	var game:Dictionary=runtime.world.extension(Gameplay.KEY)
	var verified:bool=arrivals.size()==1 and str(arrivals[0].id).begins_with("event:") and game.event_ids.has(arrivals[0].id) and arrivals[0].source_id==from and arrivals[0].destination_id==to and arrivals[0].actor_id in ["village-resident","repair-resident"] and game.defense.site_id==site.id and game.flags.get("chapter_route_delivered",false)
	check("regional objective observes exactly one committed real delivery event",verified,{"events":arrivals,"observed":arrivals.size()==1 and game.event_ids.has(arrivals[0].id),"flag":game.flags.get("chapter_route_delivered",false),"site_region":site.region_id,"source_region":runtime.stock(from).location.regionId,"destination_region":runtime.stock(to).location.regionId})
	if not verified:return false
	return paid_workshop_batch(to)

func item_count(stock_id:String,item:String)->float:
	return float(runtime.stock(stock_id).get("items",{}).get(item,0))

func paid_workshop_batch(to:String)->bool:
	var saw:String=HOME_WORKSHOP+":tool:hand_saw"
	var axe:String=HOME_WORKSHOP+":tool:salvaged_axe"
	if not reach_stock(to,"stock") or not command("take",{"items":{"book_woodwork":1},"tool_ids":[saw]},to).ok:return false
	if not command("study",{"direct":false},HOME_WORKSHOP+":record:book_woodwork").ok or not settle():return false
	if not command("rest").ok or not settle():return false
	var origin:=G.point(runtime.actor("player"))
	var trees:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return origin.distance_squared_to(G.point(a.position))<origin.distance_squared_to(G.point(b.position)))
	var acquired:bool=false
	for tree:Dictionary in trees:
		if not command("harvest",{"direct":false,"tool_ids":[axe]},tree.id).ok:continue
		if not settle():return false
		var drop:String=str(tree.data.outputId)
		if item_count(drop,"log")<1 or not reach_stock(drop,"stock"):continue
		acquired=command("take",{"items":{"log":1}},drop).ok
		if acquired:break
	check("post-encounter local felling supplies a real log",acquired)
	if not acquired:return false
	var log_before:float=item_count("pack:player","log");var boards_before:float=item_count("pack:player","timber")
	var done:=command("craft",{"direct":false,"recipe_id":"r34:saw_timber_v2","source_id":"pack:player","output_id":"pack:player","tool_ids":[saw]},HOME_WORKSHOP)
	var finished:bool=done.ok and settle() and item_count("pack:player","log")==log_before-1 and item_count("pack:player","timber")==boards_before+4
	check("the real workshop consumes one log and outputs four boards after the encounter",finished,done.get("code"))
	return finished
func finish()->void:
	var scope:String="actual C v2 stone/corridor and A layout, E survey-risk/event, B terrain; near-survey/tool-holder are explicit fixtures; not normal solo full journey PCK OS VA acceptance"
	if delivery_case:scope+="; --delivery also pre-wounds the live enemy roster, then uses actual attacks, NPC logistics, harvesting and paid sawing without adding cargo or production inputs"
	var report:Dictionary={"scope":scope,"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));runtime=null;host.free();quit(1 if report.failed else 0)
