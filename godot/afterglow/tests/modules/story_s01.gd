extends "res://tests/modules/factory_boundary_fixture.gd"
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Restoration=preload("res://scripts/modules/module_restoration.gd")
const Recovery=preload("res://scripts/modules/module_recovery.gd")
const Projects=preload("res://scripts/modules/module_projects.gd")
var hammer_id:String=""
func step_project(rt:RefCounted,id:String,limit:int)->Dictionary:
	for i:int in limit:
		rt.tick(.1)
		var p:=Draft.find(rt.world.extension(Modules.KEY).projects,id)
		if p.get("status")=="completed":return p
	return Draft.find(rt.world.extension(Modules.KEY).projects,id)
func walk_to(rt:RefCounted,at:Dictionary,label:String)->bool:
	serial+=1;var begun:Dictionary=rt.command({"command_id":"B:S01:walk:"+str(serial),"actor_id":"player","kind":"walk","target_id":"","payload":{},"destination":at})
	if begun.ok:
		for i:int in 600:
			rt.tick(.1)
			if rt.actor("player").intent==null:break
	var arrived:bool=begun.ok and G.point(G.location(rt.actor("player"))).distance_to(G.point(at))<.1
	check(label,arrived,begun);return arrived
func run()->void:
	var profiles:Array=Modules.generation_profiles();var fresh:Dictionary=Contract.fresh(profiles,7,1)
	var prepared:Dictionary=Assembly.prepare(Generator.generate(713,profiles,fresh.contract))
	check("actual content7 generation and B source registration",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish();return
	var base:Dictionary=prepared.capture;var state:Dictionary=base.world.extensions[Modules.KEY]
	var frames:Array=state.instances.filter(func(v:Dictionary)->bool:return v.has("restoration"))
	check("one actual old framework without replacing manual",frames.size()==1 and state.instances.any(func(v:Dictionary)->bool:return v.region=="RH-HOME" and Modules.definition(v.definition_id).shape=="manual"))
	if frames.size()!=1:finish();return
	var frame:Dictionary=frames[0];var id:String=frame.id
	check("old frame is damaged120, historical12/4 not player-paid",frame.status=="damaged" and frame.hp==120 and not frame.player_built and frame.restoration.historical_cost==Restoration.HISTORY and frame.get("paid_cost",{}).is_empty())
	check("frame creates no drive stock fuel output or installed power housing",frame.stock_refs.values().all(func(s:String)->bool:return Draft.find(base.facts.stocks,s).items.is_empty()) and not base.world.entities.has(id+":part:fixed-power-housing"))
	check("unrestored controlled and battle recovery both six/two",Recovery.recovery_items(frame,.75)=={"timber":6.0,"scrap":2.0} and Recovery.recovery_items(frame,.5)=={"timber":6.0,"scrap":2.0})
	var store:Dictionary=state.instances.filter(func(v:Dictionary)->bool:return v.definition_id=="r34.module.supply_rear_v3")[0]
	var service:Dictionary=port(store,"service");var front:Array=Modules.definition(store.definition_id).story_front_point
	check("new store has one actual rear supplies buffer",store.stock_refs.size()==1 and Draft.find(base.facts.stocks,str(store.stock_refs.supplies)).location==service and service==Shape.at(store,Vector3(-.7,0,2.9)))
	check("front shelf clue has no second stock",base.world.entities[store.id].data.has("story_front_point") and base.facts.stocks.filter(func(s:Dictionary)->bool:return s.get("module_id")==store.id).size()==1 and is_equal_approx(front[0],-.7) and front[1]==0 and is_equal_approx(front[2],-2.9),{"data":base.world.entities[store.id].data,"front":front})
	put_actor(base,port(frame,"work"));var player:=Draft.find(base.facts.actors,"player");player.pack=Restoration.COST.duplicate(true);player.pack["log"]=2
	for tool:Dictionary in base.world.extensions["r3:production"].tools:
		if tool.kind=="hammer":tool.holderId="pack:player";hammer_id=tool.id;break
	var mounted:=mount(base,"explicit finite restoration costs/logs/hammer at original use point");if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var svc:RefCounted=mounted.services.modules
	check("actual standing discovery succeeds",command(rt,"module.discover",id).ok)
	var before:Dictionary=rt.capture_checkpoint();var simple:=command(rt,"module.repair",id,{"source_id":"pack:player","tool_id":hammer_id})
	check("two/one generic repair cannot bypass missing drive",not simple.ok and simple.code=="MODULE_RESTORATION_REQUIRED" and Data.json_equal(before,rt.capture_checkpoint()),simple)
	var machine:=command(rt,"factory.configure",id,{"batches":1})
	check("old frame cannot configure or fuel a working machine",not machine.ok and machine.code=="MODULE_RESTORATION_REQUIRED" and Data.json_equal(before,rt.capture_checkpoint()))
	var row:Dictionary=svc.projection("player",id).instances[0]
	check("real DTO exposes restore cost and hides generic repair",row.state_code=="needs_restoration" and row.allowed_actions.has("module.restore") and not row.allowed_actions.has("module.repair") and row.restoration_requirements.cost==Restoration.COST)
	check("restore starts original project with real single hammer",command(rt,"module.restore",id,{"source_id":"pack:player","tool_ids":[hammer_id]}).ok)
	var pid:String=svc.instance(id).project_id;tick(rt,10)
	var partial:Dictionary=rt.capture_checkpoint();var paid_pack:Dictionary=rt.actor("player").pack
	check("partial labor does not debit construction supplies early",paid_pack==player.pack and not svc.instance(id).restoration.completed)
	check("same hold reserves the one real drive",svc.hold_descriptors(rt.facts()).any(func(h:Dictionary)->bool:return h.intent_id==pid and h.cost==Restoration.COST))
	check("held pause uses existing project",command(rt,"module.held",id,{"held":false}).ok)
	var seconds:float=Draft.find(svc.state().projects,pid).progress_seconds;tick(rt,10)
	check("paused frame neither progresses nor claims drive",Draft.find(svc.state().projects,pid).progress_seconds==seconds and rt.actor("player").pack==paid_pack)
	var cold:=mount(rt.capture_checkpoint(),"paused restoration cold")
	check("original old frame and hold survive cold",cold.ok and Data.json_equal(svc.state(),cold.services.modules.state()))
	if cold.ok:rt=cold.runtime;svc=cold.services.modules
	check("cancel returns only unused reservation and keeps history",command(rt,"module.cancel",id).ok and rt.actor("player").pack==paid_pack and not svc.instance(id).restoration.completed)
	var branch:Dictionary=rt.capture_checkpoint()
	check("restart restore accepts original pending instance",command(rt,"module.restore",id,{"source_id":"pack:player","tool_id":hammer_id}).ok)
	pid=svc.instance(id).project_id;var done:=step_project(rt,pid,430)
	check("forty effective seconds restore same instance",done.status=="completed" and is_equal_approx(done.progress_seconds,40) and svc.instance(id).restoration.completed and svc.instance(id).hp==300 and svc.instance(id).status=="operational",done)
	check("exact8/4/drive debited once and historical cost remains separate",rt.actor("player").pack.get("timber",0)==0 and rt.actor("player").pack.get("scrap",0)==0 and rt.actor("player").pack.get("r34:salvaged_drive_unit",0)==0 and svc.instance(id).get("paid_cost",{}).is_empty())
	check("physical original missing motor fitted on completion",not rt.world.entity(id+":part:fixed-power-housing").is_empty())
	check("restored recovery bases actual20/8/1 composition",Recovery.recovery_items(svc.instance(id),.75)=={"timber":15.0,"scrap":6.0,"r34:salvaged_drive_unit":1.0} and Recovery.recovery_items(svc.instance(id),.5)=={"timber":10.0,"scrap":4.0,"r34:salvaged_drive_unit":1.0})
	before=rt.capture_checkpoint();check("repeat restoration cannot charge or multiply drive",not command(rt,"module.restore",id,{"source_id":"pack:player","tool_id":hammer_id}).ok and Data.json_equal(before,rt.capture_checkpoint()))
	var restored:=mount(before,"same restored original cold")
	check("restoration ledger and exact geometry survive cold",restored.ok and Data.json_equal(svc.state(),restored.services.modules.state()))
	if restored.ok:
		var rr:RefCounted=restored.runtime;var rs:RefCounted=restored.services.modules;var tx:=Draft.new(rs.context)
		var damaged:Dictionary=rs.damage_in(tx,id,300,"B:S01:explicit-ruin-fixture")
		check("explicit damage fixture uses original damage_in transaction",damaged.ok and rr._commit(tx.result()).ok)
		check("restored ruin freezes actual10/4 and one installed drive",rs.instance(id).recovery.items=={"timber":10.0,"scrap":4.0,"r34:salvaged_drive_unit":1.0} and rr.actor("player").pack.get("r34:salvaged_drive_unit",0)==0)
		var ruin_cold:=mount(rr.capture_checkpoint(),"restored damaged original cold")
		check("ruin and restoration histories coexist across cold",ruin_cold.ok and Data.json_equal(rs.state(),ruin_cold.services.modules.state()))
		var forged:Dictionary=before.duplicate(true);Draft.find(forged.world.extensions[Modules.KEY].instances,id).restoration.historical_cost.timber=20
		var host:=Native.new();hosts.append(host);check("forged historical free composition rejected",not host._assemble(forged).ok)
	var regenerated:Dictionary=svc.prepare_generation(rt.world,["RH-HOME"],rt.facts())
	check("repeat generation cannot resurrect old source or refill stocks",regenerated.ok and regenerated.world_changes.is_empty() and regenerated.initial_stocks.is_empty())
	var active:Dictionary=svc.instance(id)
	if not walk_to(rt,port(active,"log-input"),"real walk to original input"):finish();return
	check("one actual carried log loaded into restored input",command(rt,"deposit",str(active.stock_refs.input),{"items":{"log":1}}).ok)
	if not walk_to(rt,port(active,"fuel-input"),"real walk to original fuel"):finish();return
	check("last carried log fuels recovered machine",command(rt,"deposit",str(active.stock_refs.fuel),{"items":{"log":1}}).ok)
	check("recovered original machine configures actual one batch",command(rt,"factory.configure",id,{"batches":1}).ok)
	tick(rt,120)
	check("restoration route produces four actual boards at original module",rt.stock(str(active.stock_refs.output)).items.get("timber",0)==4,rt.stock(str(active.stock_refs.output)))
	if not walk_to(rt,port(active,"board-output"),"walk to take original real output"):finish();return
	var taken_boards:=command(rt,"take",str(active.stock_refs.output),{"items":{"timber":4}})
	check("actual four boards withdrawn before controlled teardown",taken_boards.ok,taken_boards)
	check("original machine must really stop before teardown",command(rt,"factory.pause",id).ok)
	if not walk_to(rt,port(active,"work"),"walk back for controlled teardown"):finish();return
	check("completed restoration starts controlled teardown",command(rt,"module.dismantle",id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer_id}).ok)
	var paid_salvage:=step_project(rt,svc.instance(id).project_id,150)
	check("controlled teardown returns15/6 and original drive once",paid_salvage.status=="completed" and rt.actor("player").pack.get("timber",0)==19 and rt.actor("player").pack.get("scrap",0)==6 and rt.actor("player").pack.get("r34:salvaged_drive_unit",0)==1,paid_salvage)
	# Independent alternative from the exact cancelled branch: no restore cost
	# was paid, and the drive is still the one carried original fixture item.
	var bm:=mount(branch,"mutually exclusive teardown branch");if not bm.ok:finish();return
	var br:RefCounted=bm.runtime;var bs:RefCounted=bm.services.modules
	check("unrestored alternate branch starts real dismantle",command(br,"module.dismantle",id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer_id}).ok)
	var dismantled:=step_project(br,bs.instance(id).project_id,150)
	check("unrestored teardown yields only6/2 no drive grant",dismantled.status=="completed" and br.actor("player").pack.get("timber",0)==14 and br.actor("player").pack.get("scrap",0)==6 and br.actor("player").pack.get("r34:salvaged_drive_unit",0)==1 and bs.instance(id).status=="dismantled",dismantled)
	regenerated=bs.prepare_generation(br.world,["RH-HOME"],br.facts())
	check("retired original frame stays dismantled on revisit",regenerated.ok and regenerated.world_changes.is_empty() and regenerated.initial_stocks.is_empty())
	var end:=mount(br.capture_checkpoint(),"dismantled source cold")
	check("alternative ledger and carried original drive survive cold",end.ok and Data.json_equal(bs.state(),end.services.modules.state()))
	var manual:Dictionary=bs.state().instances.filter(func(v:Dictionary)->bool:return v.region=="RH-HOME" and Modules.definition(v.definition_id).shape=="manual")[0]
	var supplies:String=manual.stock_refs.tools
	if not walk_to(br,port(manual,"work"),"alternate route really carries salvage to manual supplies"):finish();return
	check("original finite manual container is actually searched",command(br,"search",supplies).ok);tick(br,50)
	var taken_difference:=command(br,"take",supplies,{"items":{"timber":6,"scrap":2}})
	check("new build difference is actually withdrawn, not discounted",taken_difference.ok and br.actor("player").pack.get("timber")==20 and br.actor("player").pack.get("scrap")==8,taken_difference)
	var spot:Dictionary={};var q:RefCounted=bm.services.buildings.current_space()
	for x:int in range(4,58,3):
		for z:int in range(4,58,3):
			if Vector2(x,z).distance_to(Vector2(frame.position.x,frame.position.z))<8:continue
			var h:Variant=q.ground_height(x,z);if h==null:continue
			var candidate:Dictionary=Modules.record_for({"id":"B:S01:new-site","definition_id":Restoration.DEFINITION,"region":"RH-HOME","position":{"x":float(x),"y":float(h),"z":float(z)},"quarter_turn":0})
			if Projects.footprint_check(bs,candidate,br.facts()).ok:spot=candidate;break
		if not spot.is_empty():break
	check("naturally supported different legal new site exists",not spot.is_empty())
	if spot.is_empty():finish();return
	if not walk_to(br,port(spot,"work"),"carry all real20/8/drive to different site"):finish();return
	var at:Dictionary=G.location(spot.position.merged({"regionId":spot.region}));var planned:=command(br,"module.plan",spot.id,{"definition_id":spot.definition_id,"position":at,"quarter_turn":0,"source_id":"pack:player","tool_id":hammer_id})
	check("alternative new construction pays full original price",planned.ok,planned)
	if not planned.ok:finish();return
	var built_project:=step_project(br,bs.instance(spot.id).project_id,450)
	var relocated:Dictionary=bs.instance(spot.id)
	check("real carried salvage plus paid difference constructs new identity",built_project.status=="completed" and relocated.player_built and Data.json_equal(relocated.paid_cost,Restoration.TOTAL) and br.actor("player").pack.get("r34:salvaged_drive_unit",0)==0 and bs.instance(id).status=="dismantled",{"project":built_project,"paid_cost":relocated.get("paid_cost"),"player_built":relocated.player_built,"pack":br.actor("player").pack,"old_status":bs.instance(id).status})
	if not walk_to(br,port(relocated,"log-input"),"new site real input walk"):finish();return
	check("new site receives original carried log",command(br,"deposit",str(relocated.stock_refs.input),{"items":{"log":1}}).ok)
	if not walk_to(br,port(relocated,"fuel-input"),"new site real fuel walk"):finish();return
	check("new site receives last carried fuel log",command(br,"deposit",str(relocated.stock_refs.fuel),{"items":{"log":1}}).ok)
	check("alternative configures only actually completed new machine",command(br,"factory.configure",relocated.id,{"batches":1}).ok);tick(br,120)
	check("alternative actually produces four boards at different site",br.stock(str(relocated.stock_refs.output)).items.get("timber",0)==4)
	var migrated:=mount(br.capture_checkpoint(),"alternative paid relocation production cold")
	check("new paid module and old retired source survive cold",migrated.ok and Data.json_equal(bs.state(),migrated.services.modules.state()))
	evidence.append({"scope":"Actual C7 sites and B original geometry, explicit finite initial8/4/drive/log2/hammer plus fixture placement. Following costs/ticks/walk/deposit/batch/recovery are real. Damage uses explicitly isolated damage_in, not natural attack. Normal acquisition/social/OS still E/A.","original_id":id,"restoration_project":pid,"new_site":relocated.id,"new_boards":br.stock(str(relocated.stock_refs.output)).items.get("timber",0)})
	finish()
