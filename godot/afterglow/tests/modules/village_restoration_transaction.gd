extends SceneTree
## Explicit funded/contact fixture tests settlement, not the natural acquisition journey.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func run()->void:
	var profiles:=Assembly.generation_profiles(13)
	var generated:=Assembly.generate(713,profiles.get("profiles",[]),13) if profiles.get("ok",false) else profiles
	var prepared:=Assembly.prepare(generated) if generated.get("ok",true) else generated
	check("new opening composes before funded fixture",prepared.get("ok",false),prepared if not prepared.get("ok",false) else null)
	if not prepared.get("ok",false):return finish()
	var capture:Dictionary=prepared.capture;var modules:Dictionary=capture.world.extensions["r34:modules"]
	var warehouse:Dictionary=modules.instances.filter(func(v:Dictionary)->bool:return v.definition_id=="r35.module.village_warehouse")[0]
	var port:Dictionary=Shape.ports(warehouse,Catalog.definition(warehouse.definition_id)).filter(func(p:Dictionary)->bool:return p.purpose=="repair")[0].location
	var player:Dictionary=Draft.find(capture.facts.actors,"player");player.merge(port,true);player.pack={"timber":22,"scrap":11,"cloth":3,"food":4,"water":4}
	var hammer:String=""
	for tool:Dictionary in capture.world.extensions["r3:production"].tools:
		if tool.kind=="hammer":tool.holderId="pack:player";hammer=tool.id;break
	var host:=Native.new();var built:=host._assemble(capture);host.free()
	check("funded contact fixture assembles through actual authority",built.get("ok",false),built.get("code"))
	if not built.get("ok",false):return finish()
	var rt:RefCounted=built.runtime;var service:RefCounted=built.services.modules
	var before:int=warehouse.members.size();var stock_id:String=warehouse.stock_refs.storage
	check("damaged warehouse refuses inventory before repair",not built.services.production.capacity_check(stock_id,{"timber":1}).ok)
	var command:Dictionary={"kind":"module.restore","actor_id":"player","command_id":"village-test:restore","target_id":warehouse.id,"payload":{"source_id":"pack:player","tool_id":hammer}}
	var started:Dictionary=rt.command(command)
	check("actual restore command starts",started.get("ok",false),started.get("code"))
	if started.get("ok",false):
		for i:int in 245:rt.tick(.1)
		var restored:Dictionary=service.instance(warehouse.id);var project:Dictionary=Draft.find(service.state().projects,str(restored.project_id))
		check("actual labor settles single completed restoration",restored.restoration.completed and restored.status=="operational" and project.get("status")=="completed",project)
		check("real materials deducted once",rt.actor("player").pack.get("timber")==14 and rt.actor("player").pack.get("scrap")==9 and rt.actor("player").pack.get("cloth")==2,rt.actor("player").pack)
		check("repair changes actual geometry and capacity",restored.members.size()>before and built.services.production.capacity_check(stock_id,{"timber":1}).ok)
		var again:Dictionary=rt.command(command.merged({"command_id":"village-test:duplicate"},true))
		check("second restoration cannot settle again",not again.ok)
		var home:Dictionary=modules.instances.filter(func(v:Dictionary)->bool:return v.definition_id=="r35.module.village_home")[0]
		var home_contact:=hostile_contact(rt,built.services,service.instance(home.id))
		check("unrestored old home has a real shell that can be hit",not home_contact.is_empty())
		check("restored shed can be damaged and repaired again",verify_hostile_repair(rt,built.services,restored,stock_id))
		var rebuilt_stock_id:=verify_ruin_rebuild(rt,built.services,service.instance(warehouse.id))
		check("ruined shed rebuilds on its original site with usable storage",not rebuilt_stock_id.is_empty())
		var upgrade:Dictionary=rt.command({"kind":"module.upgrade","actor_id":"player","command_id":"village-test:upgrade","target_id":warehouse.id,"payload":{"source_id":"pack:player","tool_id":hammer,"definition_id":"r35.module.village_warehouse_expanded"}})
		check("restored heritage enters existing paid upgrade project",upgrade.get("ok",false),upgrade.get("code"))
		if upgrade.get("ok",false):
			for i:int in 215:rt.tick(.1)
			var expanded:Dictionary=service.instance(warehouse.id)
			check("upgrade settles to expanded warehouse without duplicate material credit",expanded.definition_id=="r35.module.village_warehouse_expanded" and expanded.get("upgrades",[]).size()==1 and rt.actor("player").pack.get("timber",0)==0 and rt.actor("player").pack.get("scrap")==4,expanded)
			check("upgrade keeps the rebuilt storage endpoint",expanded.stock_refs.storage==rebuilt_stock_id,expanded.stock_refs)
		var candidate:Dictionary=preload("res://scripts/modules/module_projects.gd").plan_instance(service,{"target_id":"village-test:style","payload":{"definition_id":"r34.module.sawmill_mid_v1.mechanism-v2","position":rt.actor("player").duplicate(true),"quarter_turn":0}})
		check("new13 construction pins explicit original-tier geometry style",candidate.get("config",{}).get("village_style_v1")==1)
		var home_rebuild:=verify_ruined_opening_home(rt,built.services,service.instance(home.id))
		check("an unrepaired starting home can rebuild directly from rubble",home_rebuild.ok,home_rebuild)
		var encoded:=Store.encode(rt.capture_checkpoint());var decoded:=Store.decode(encoded.get("text",""));var cold:=Native.new();var restored_capture:Dictionary=cold._assemble(decoded.capture) if decoded.ok else decoded;cold.free()
		check("reconstructed village and paid history survive canonical save/load",restored_capture.get("ok",false),restored_capture.get("code"))
		if restored_capture.get("ok",false):restored_capture.runtime.retire()
	rt.retire();finish()

func hostile_contact(rt:RefCounted,services:Dictionary,module:Dictionary,stock_id:String="")->Dictionary:
	var query:RefCounted=services.buildings.current_space()
	for member:Dictionary in module.members:
		var entity:Dictionary=rt.world.entity(member.id)
		if not entity.get("data",{}).get("solid",false):continue
		var shell:AABB=Geometry.aabb(entity.bounds)
		for normal:Vector3 in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
			var face:Vector3=shell.get_center()+shell.size*normal/2.0+normal*0.66
			face.y=module.position.y
			var stance:Dictionary=query.standing_point(Geometry.json_point(face).merged({"regionId":module.region,"buildingId":null,"storeyId":null}))
			if stance.is_empty():continue
			var tx:=Draft.new(services.modules.context)
			if not stock_id.is_empty() and not tx.stock_delta(stock_id,{"log":2}):return {}
			var walker:Dictionary=rt.actor("player").merged(stance,true)
			walker.merge({"id":"village-test:infected","faction":"infected","cooldown":0.0,"hp":48.0,"stunned_until":0.0,"pack":{},"intent":null},true)
			tx.staged.actors.append(walker)
			var hit:Dictionary=services.modules.strike_hostile(tx,walker.id,module.id)
			if hit.get("ok",false):return {"draft":tx,"hit":hit}
	return {}

func verify_hostile_repair(rt:RefCounted,services:Dictionary,warehouse:Dictionary,stock_id:String)->bool:
	var contact:=hostile_contact(rt,services,warehouse,stock_id)
	if contact.is_empty():return false
	var tx:RefCounted=contact.draft
	var hit:Dictionary=contact.hit
	var enemy:Dictionary=tx.actor("village-test:infected")
	enemy.cooldown=0.0
	var replay:Dictionary=services.modules.strike_hostile(tx,enemy.id,warehouse.id)
	check("same-time replay cannot apply damage twice",not replay.ok and replay.code=="NO_CHANGE",replay)
	# Drop the injected fixture enemy before advancing the real repair simulation.
	tx.staged.actors.erase(enemy)
	var commit:Dictionary=rt._commit(tx.result())
	if not commit.get("ok",false):return false
	var stocked:Dictionary=rt.stock(stock_id).items.duplicate(true)
	var row:Dictionary=services.modules.projection("player",warehouse.id).instances[0]
	check("true contact damage keeps the same warehouse stock and exposes repair",row.structural_integrity.hp==warehouse.hp-12 and row.structural_integrity.state_code=="damaged" and row.damage_receipts.get(hit.cause_id)==12 and row.stock_refs.storage==stock_id and float(stocked.get("log",0))>=2 and row.repair_action.available,row.structural_integrity)
	var encoded:=Store.encode(rt.capture_checkpoint())
	var decoded:=Store.decode(encoded.get("text",""))
	var host:=Native.new()
	var cold:Dictionary=host._assemble(decoded.capture) if decoded.ok else decoded
	host.free()
	check("damage and stock survive cold validation",cold.ok and cold.services.modules.instance(warehouse.id).hp==row.hp and cold.runtime.stock(stock_id).items==stocked,cold.get("code"))
	if cold.ok:cold.runtime.retire()
	var repair:Dictionary=rt.command(row.repair_action.command.merged({"actor_id":"player","command_id":"village-test:repair-from-status"}))
	if not repair.ok:return false
	for i:int in 105:rt.tick(.1)
	var after:Dictionary=services.modules.instance(warehouse.id)
	var pack:Dictionary=rt.actor("player").pack
	var repaired:bool=after.status=="operational" and after.hp==warehouse.hp and after.stock_refs.storage==stock_id and rt.stock(stock_id).items==stocked and pack.get("timber")==12 and pack.get("scrap")==8
	# Isolate the fixture from the existing empty-stock upgrade scenario.
	var cleanup:=Draft.new(services.modules.context)
	if not cleanup.stock_delta(stock_id,{"log":2},-1.0):return false
	var emptied:Dictionary=rt._commit(cleanup.result())
	return repaired and emptied.ok

func verify_ruin_rebuild(rt:RefCounted,services:Dictionary,warehouse:Dictionary)->String:
	var d:=Catalog.definition(warehouse.definition_id)
	var tx:=Draft.new(services.modules.context)
	if not tx.stock_delta("pack:player",d.build_cost) or not tx.stock_delta(warehouse.stock_refs.storage,{"log":2}):return ""
	var lethal:Dictionary=services.modules.damage_in(tx,warehouse.id,warehouse.hp,"village-test:lethal-shed")
	if not lethal.ok:return ""
	var committed:Dictionary=rt._commit(tx.result())
	if not committed.ok:return ""
	var row:Dictionary=services.modules.projection("player",warehouse.id).instances[0]
	var cache_id:String=row.stock_refs.storage
	check("lethal damage retains actual goods and exposes the rebuild command",row.hp==0 and row.repair_action.rebuild and rt.stock(cache_id).items.log==2,row.get("repair_action"))
	var started:Dictionary=rt.command(row.repair_action.command.merged({"actor_id":"player","command_id":"village-test:rebuild-shed"}))
	if not started.ok:return ""
	verify_rebuild_workforce(services.modules,warehouse.id)
	for i:int in ceili(float(d.build_seconds)*10.0)+40:rt.tick(.1)
	var rebuilt:Dictionary=services.modules.instance(warehouse.id)
	var stock:Dictionary=rt.stock(cache_id)
	var pack:Dictionary=rt.actor("player").pack
	check("rebuild consumes real materials and keeps the goods in the same cache",rebuilt.get("rebuild_count")==1 and rebuilt.stock_refs.storage==cache_id and stock.get("module_id")==rebuilt.id and stock.items.log==2 and pack.timber==12 and pack.scrap==8,stock)
	var live_members:Array=rebuilt.members.filter(func(member:Dictionary)->bool:return member.id!=rebuilt.id and str(member.id).ends_with(":rebuild:1") and not rt.world.entity(member.id).is_empty())
	check("restored shell has newly registered physical members on original site",rebuilt.position==warehouse.position and rebuilt.quarter_turn==warehouse.quarter_turn and not live_members.is_empty() and not rebuilt.has("recovery"),rebuilt.get("status"))
	var replay:Dictionary=rt.command(row.repair_action.command.merged({"actor_id":"player","command_id":"village-test:rebuild-replay"}))
	check("rebuilding a settled shell cannot claim the same ruin twice",not replay.ok and replay.code=="MODULE_INTACT",replay)
	var cleanup:=Draft.new(services.modules.context)
	if not cleanup.stock_delta(cache_id,{"log":2},-1):return ""
	var emptied:Dictionary=rt._commit(cleanup.result())
	return cache_id if emptied.ok and rebuilt.status=="operational" and rebuilt.hp==warehouse.hp else ""

func verify_rebuild_workforce(modules:RefCounted,module_id:String)->void:
	var tx:=Draft.new(modules.context)
	var state:Dictionary=tx.extension("r34:modules")
	var ruin:Dictionary=Draft.find(state.instances,module_id)
	var project:Dictionary=Draft.find(state.projects,str(ruin.project_id))
	var candidate_id:String="module-project:"+str(project.id)
	var offer:Dictionary=Draft.find(modules.workforce_candidates("player",tx.staged,tx.extensions),candidate_id)
	check("current unclaimed ruin remains a valid funded work candidate",offer.get("valid",false),offer)
	tx.stock("pack:player").items.timber=0
	offer=Draft.find(modules.workforce_candidates("player",tx.staged,tx.extensions),candidate_id)
	check("rebuild candidate still requires actual reserved materials",offer.get("reason")=="missing_input",offer)
	# The direct-arrival branch already owns a reservation and bypasses offer
	# selection. It must still reject a stale ruin before changing intent.
	var actor:Dictionary=tx.actor("player")
	var approach:Dictionary={"owner":"actions","workforce_candidate_id":candidate_id}
	actor.intent=approach
	project.auto_approach=true
	project.rebuild_ruin_id="village-test:previous-ruin"
	offer=Draft.find(modules.workforce_candidates("player",tx.staged,tx.extensions),candidate_id)
	var arrived:Dictionary=modules.claim_workforce_in(tx,"player",candidate_id,"village-test:stale-arrival",true)
	check("stale ruin fails both candidate and reserved direct arrival",offer.get("reason")=="target_unavailable" and arrived.get("reason")=="target_unavailable" and tx.actor("player").intent==approach,arrived)

func verify_ruined_opening_home(rt:RefCounted,services:Dictionary,home:Dictionary)->Dictionary:
	var definition:=Catalog.definition(home.definition_id)
	var port:Dictionary=Shape.ports(home,definition).filter(func(p:Dictionary)->bool:return p.purpose=="repair")[0].location
	# This case follows four real construction jobs. Wait for natural idle
	# recovery before adding another 18 seconds of paid hammering.
	var required_stamina:float=float(home.restoration.seconds)*1.2+2.0
	for i:int in 150:
		if float(rt.actor("player").stamina)>=required_stamina:break
		rt.tick(.1)
	var stamina:float=float(rt.actor("player").stamina)
	if stamina<required_stamina:return {"ok":false,"stage":"rest before rebuild","stamina":stamina,"required_stamina":required_stamina}
	var tx:=Draft.new(services.modules.context)
	tx.actor("player").merge(port,true)
	if not tx.stock_delta("pack:player",home.restoration.cost):return {"ok":false,"stage":"funding"}
	var ruined:Dictionary=services.modules.damage_in(tx,home.id,home.hp,"village-test:lethal-home")
	if not ruined.ok:return {"ok":false,"stage":"damage","detail":ruined}
	var commit:Dictionary=rt._commit(tx.result())
	if not commit.ok:return {"ok":false,"stage":"damage commit","detail":commit}
	# The domain command accepts the same action even when the early legacy
	# fixture did not discover this house through the ordinary world prompt.
	var started:Dictionary=rt.command({"kind":"module.repair","actor_id":"player","command_id":"village-test:rebuild-home","target_id":home.id,"payload":{}})
	if not started.ok:return {"ok":false,"stage":"start rebuild","detail":started}
	for i:int in ceili(float(home.restoration.seconds)*10.0)+40:rt.tick(.1)
	var rebuilt:Dictionary=services.modules.instance(home.id)
	var project:Dictionary=Draft.find(services.modules.state().projects,str(rebuilt.project_id))
	var ok:bool=rebuilt.get("rebuild_count")==1 and rebuilt.status=="operational" and rebuilt.hp==definition.hp and rebuilt.position==home.position and rebuilt.restoration.completed and rebuilt.paid_cost==home.restoration.cost
	return {"ok":ok,"stage":"settlement","status":rebuilt.status,"project":project,"paid_cost":rebuilt.paid_cost,"restoration":rebuilt.restoration,"player_activity":rt.actor("player").get("activity"),"stamina_before":stamina,"stamina_after":rt.actor("player").stamina}

func finish()->void:
	var result:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"scope":"Synthetic funded contact fixture; real command/labor/material settlement/capacity/geometry/canonical cold restore. Does not claim natural gathering/hauling or graphical quality."}
	print(JSON.stringify(result))
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():DirAccess.make_dir_recursive_absolute(args[0]);FileAccess.open(args[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	quit(0 if result.failed==0 else 1)
