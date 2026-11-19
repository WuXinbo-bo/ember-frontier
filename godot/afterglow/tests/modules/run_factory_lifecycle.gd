extends SceneTree
## Explicit isolated fixture resources. Exercises formal Runtime commands/CAS,
## never writes user saves or opens a renderer; not a normal economy/VA claim.
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Projects=preload("res://scripts/modules/module_projects.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	if detail is Dictionary:detail={"code":detail.get("code"),"reason":detail.get("reason")}
	checks.append({"name":name,"ok":ok,"detail":detail});if not ok:print("FAIL "+name+" "+str(detail))
func command(rt:RefCounted,id:String,kind:String,target:String="",payload:Dictionary={},actor_id:String="player")->Dictionary:return rt.command({"command_id":id,"actor_id":actor_id,"kind":kind,"target_id":target,"payload":payload})
func commit(rt:RefCounted,prepared:Dictionary)->Dictionary:return rt._commit(prepared)
func advance(rt:RefCounted,services:Dictionary,steps:int,domain:String)->void:
	for i:int in steps:
		var result:Dictionary=services[domain].advance(0.1)
		if not result.ok:check(domain+" prepares actual advance",false,result);return
		var committed:Dictionary=commit(rt,result)
		if not committed.ok:check(domain+" commits actual advance",false,committed);return
func run()->void:
	var opening:Dictionary=Assembly.prepare(Generator.generate(713,Modules.generation_profiles()))
	check("real C/B/E/A opening assembly",opening.ok,opening)
	if not opening.ok:finish();return
	var capture:Dictionary=opening.capture.duplicate(true);var state:Dictionary=capture.world.extensions[Modules.KEY]
	var home:Dictionary=state.instances.filter(func(v:Dictionary)->bool:return v.definition_id=="r34.module.home_service" and v.region=="RH-HOME")[0]
	var position:Dictionary=home.position.duplicate(true);position.regionId=home.region
	# Vacate the existing large graded home pad in this isolated fixture only.
	# Test keeps real generated voxels, collision and actor safety validators.
	for member:Dictionary in home.members:capture.world.entities.erase(member.id)
	state.instances.erase(home)
	for key:String in state.source_receipts.keys():
		if state.source_receipts[key].module_id==home.id:state.source_receipts.erase(key)
	capture.facts.stocks=capture.facts.stocks.filter(func(s:Dictionary)->bool:return s.get("module_id")!=home.id)
	var actor:=Draft.find(capture.facts.actors,"player");actor.pack={"timber":64,"scrap":32,"r34:salvaged_drive_unit":1,"log":20,"food":1,"water":1}
	actor.x=position.x;actor.y=position.y;actor.z=position.z-3.1;actor.regionId=home.region
	var legacy:Dictionary=capture.world.extensions["r3:production"];var hammer:Dictionary=legacy.tools.filter(func(t:Dictionary)->bool:return t.kind=="hammer")[0];hammer.holderId="pack:player"
	var host:=Native.new();var assembled:Dictionary=host._assemble(capture)
	check("fixture passes formal Native restore and domain schemas",assembled.ok,assembled)
	if not assembled.ok:host.free();finish();return
	var rt:RefCounted=assembled.runtime;var services:Dictionary=assembled.services
	var module_id:String="r34:test-built-woodshop"
	var definition_id:String="r34.module.woodshop_long_v2" if OS.get_cmdline_user_args().has("new-design") else "r34.module.fuel_woodshop"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("quality-definition="):definition_id=arg.trim_prefix("quality-definition=")
	var payload:Dictionary={"definition_id":definition_id,"position":position,"quarter_turn":0,"source_id":"pack:player","tool_id":hammer.id}
	var request:Dictionary={"command_id":"real-plan","actor_id":"player","target_id":module_id,"kind":"module.plan","payload":payload}
	var before:Dictionary=rt.capture_checkpoint();var preview:Dictionary=services.modules.preview(request)
	check("pure placement preview checks real generated graded pad",preview.ok,preview)
	check("preview never reserves or commits",Data.json_equal(before,rt.capture_checkpoint()))
	var invalid:Dictionary=request.duplicate(true);invalid.payload.position.y+=0.5
	check("floating foundation rejected",not services.modules.preview(invalid).ok)
	var planned:Dictionary=rt.command(request)
	check("module.plan goes through formal Runtime once",planned.ok,planned)
	if not planned.ok:host.free();finish();return
	check("planned site is an actual selectable entity",assembled.world.entity(module_id).get("data",{}).get("module_target",false))
	check("project creates empty buffers without generated rewards",rt.facts().stocks.filter(func(s:Dictionary)->bool:return s.get("module_id")==module_id).all(func(s:Dictionary)->bool:return s.items.is_empty()))
	check("planning holds costs but does not consume them",float(rt.actor("player").pack.timber)==64 and services.production.reserved("pack:player","timber")==20)
	check("duplicate command cannot add second project",rt.command(request).ok and services.modules.state().projects.size()==1)
	advance(rt,services,15,"modules")
	var p:Dictionary=services.modules.state().projects[0]
	check("real on-site hammer labor advances unique project",float(p.progress_seconds)>1.0,p)
	var paused:Dictionary=command(rt,"release-build","module.held",module_id,{"held":false});var old_work:float=p.progress_seconds
	advance(rt,services,5,"modules")
	check("released hold stops effective labor and preserves costs",paused.ok and float(services.modules.state().projects[0].progress_seconds)==old_work)
	check("module labor projection is real and paused",services.modules.actor_work_projection("player").get("effective_work")==false)
	command(rt,"hold-build","module.held",module_id,{"held":true})
	advance(rt,services,410,"modules")
	var module:Dictionary=services.modules.instance(module_id)
	check("complete module builds physical members and becomes usable",module.status=="operational" and module.members.size()>10,module)
	if module.status!="operational":print(JSON.stringify(services.modules.state().projects));host.free();finish();return
	check("construction settles costs exactly once",float(rt.actor("player").pack.timber)==44 and float(rt.actor("player").pack.scrap)==24 and float(rt.actor("player").pack["r34:salvaged_drive_unit"])==0)
	advance(rt,services,3,"modules")
	check("completed construction cannot pay or gift twice",float(rt.actor("player").pack.timber)==44 and rt.facts().stocks.filter(func(s:Dictionary)->bool:return s.get("module_id")==module_id).all(func(s:Dictionary)->bool:return s.items.is_empty()))
	# Put the player at each real service point through fixture capture restore;
	# all subsequent inventory commands still use real reach/filter/CAS checks.
	var saved:Dictionary=rt.capture_checkpoint();var player:=Draft.find(saved.facts.actors,"player");var port:Dictionary=Draft.find(Shape.ports(module,Modules.definition(module.definition_id)),"log-input")
	player.x=port.location.x;player.y=port.location.y;player.z=port.location.z
	var host2:=Native.new();var resumed:Dictionary=host2._assemble(saved);check("built module survives exact cold restore",resumed.ok,resumed)
	if not resumed.ok:host.free();host2.free();finish();return
	rt=resumed.runtime;services=resumed.services
	check("old transfer entrance enforces module item filter",not command(rt,"bad-filter","deposit",module.stock_refs.input,{"items":{"food":1}}).ok)
	check("input capacity exact boundary rejects excess",not command(rt,"too-much","deposit",module.stock_refs.input,{"items":{"log":13}}).ok)
	check("real near-surface transfer fills input",command(rt,"load-logs","deposit",module.stock_refs.input,{"items":{"log":4}}).ok)
	# Move fixture actor to fuel service, then use the same true inventory path.
	saved=rt.capture_checkpoint();player=Draft.find(saved.facts.actors,"player");port=Draft.find(Shape.ports(module,Modules.definition(module.definition_id)),"fuel-input");player.x=port.location.x;player.y=port.location.y;player.z=port.location.z
	var host3:=Native.new();resumed=host3._assemble(saved);check("fuel port restore is spatially safe",resumed.ok,resumed)
	if not resumed.ok:host.free();host2.free();host3.free();finish();return
	rt=resumed.runtime;services=resumed.services
	check("fuel is actual competing log stock",command(rt,"load-fuel","deposit",module.stock_refs.fuel,{"items":{"log":2}}).ok)
	check("machine configure uses adopted real recipe",command(rt,"configure","factory.configure",module_id,{"recipe_id":"saw_timber","batches":2}).ok)
	advance(rt,services,1,"production")
	var machine:Dictionary=services.production.factory_projection().orders[0];var batch:Dictionary=services.production.factory_projection().batches[0]
	check("one start moves material to WIP and promises output",float(rt.stock(module.stock_refs.input).items.log)==3 and batch.wip=={"log":1.0} and services.production.capacity_reserved(module.stock_refs.output,"timber")==4)
	check("energy deducted only by actual machine work",is_equal_approx(float(machine.energy_seconds),19.9) and float(rt.stock(module.stock_refs.fuel).items.log)==1)
	var freeze:Dictionary=rt.capture_checkpoint();command(rt,"pause","factory.pause",module_id);advance(rt,services,10,"production")
	check("pause preserves WIP progress and energy",is_equal_approx(float(services.production.factory_projection().batches[0].elapsed),0.1) and is_equal_approx(float(services.production.factory_projection().orders[0].energy_seconds),19.9))
	var alert_before:Dictionary=rt.capture_checkpoint();var alerts:Array=services.production.factory_projection().alerts
	check("actual pause exposes stable same-reason alert and real batch episode",alerts.size()==1 and alerts[0].key==module_id+":paused" and alerts[0].reason_code=="paused" and alerts[0].episode_id==services.production.factory_projection().batches[0].id and alerts==services.production.factory_projection().alerts)
	check("alerts neither mutate authority nor expose unknown actor production",Data.json_equal(alert_before,rt.capture_checkpoint()) and services.production.factory_projection("unknown-person").alerts.is_empty())
	command(rt,"resume","factory.resume",module_id);advance(rt,services,199,"production")
	var result:Dictionary=services.production.factory_projection();var completed:Array=result.batches.filter(func(b:Dictionary)->bool:return b.status=="completed")
	check("two real single batches yield once each",completed.size()==2 and float(rt.stock(module.stock_refs.output).items.timber)==8,result)
	check("durable settlement and event identities exactly once",services.production.context.world.extension(Factory.KEY).settlements.size()==2 and rt.facts().ledger.filter(func(e:Dictionary)->bool:return e.kind=="factory-batch-completed").size()==2)
	check("20 effective machine seconds use one fuel log",is_zero_approx(float(result.orders[0].energy_seconds)) and float(rt.stock(module.stock_refs.fuel).items.log)==1)
	advance(rt,services,3,"production");check("target met does not start third batch",services.production.factory_projection().batches.size()==2)
	command(rt,"third","factory.configure",module_id,{"batches":1});advance(rt,services,15,"production")
	check("RC01 stop keeps irreversible WIP and does not return whole log",command(rt,"cancel","factory.cancel",module_id).ok and float(rt.stock(module.stock_refs.input).items.log)==1 and services.production.factory_projection().batches[-1].status=="blocked" and services.production.factory_projection().batches[-1].wip=={"log":1.0} and float(services.production.factory_projection().orders[0].energy_seconds)<20)
	var stop_snapshot:Dictionary=rt.capture_checkpoint()
	check("discard requires explicit confirmation and leaves facts unchanged",not command(rt,"unconfirmed-discard","factory.discard",module_id).ok and Data.json_equal(stop_snapshot,rt.capture_checkpoint()))
	check("explicit irreversible discard settles zero recovery once",command(rt,"discard","factory.discard",module_id,{"confirm_discard":true}).ok and services.production.factory_projection().batches[-1].status=="discarded" and float(rt.stock(module.stock_refs.input).items.log)==1 and float(rt.stock(module.stock_refs.output).items.timber)==8)
	check("discard replay cannot settle twice",command(rt,"discard","factory.discard",module_id,{"confirm_discard":true}).ok and services.production.context.world.extension(Factory.KEY).settlements.size()==3)
	var restored_host:=Native.new();var cold:Dictionary=restored_host._assemble(rt.capture_checkpoint());check("batches settlements energy and empty holds cold restore",cold.ok,cold)
	if cold.ok:
		var bad:Dictionary=cold.world.extension(Factory.KEY);bad.settlements.append(bad.settlements[0].duplicate(true))
		check("duplicate durable settlement rejects on restore validation",not cold.services.production.validate_extensions(cold.runtime.facts(),{Factory.KEY:bad}).ok)
	# Controlled dismantle and damage use sibling isolated captures so neither
	# can borrow the other branch's salvage or reconstruct paid cost from price.
	var base:Dictionary=rt.capture_checkpoint()
	var repair_port:Dictionary=Draft.find(Shape.ports(module,Modules.definition(module.definition_id)),"repair")
	var repair_source:Dictionary=base.duplicate(true);var repair_actor:=Draft.find(repair_source.facts.actors,"player");repair_actor.x=repair_port.location.x;repair_actor.y=repair_port.location.y;repair_actor.z=repair_port.location.z
	var repair_host:=Native.new();var repaired:Dictionary=repair_host._assemble(repair_source)
	check("repair fixture restores real body and paid structure",repaired.ok,repaired)
	if repaired.ok:
		var rr:RefCounted=repaired.runtime;var rs:Dictionary=repaired.services
		check("partial combat damage commits before repair",commit(rr,rs.modules.prepare_damage(module_id,60,"repair:damage")).ok)
		var condition_alerts:Array=rs.modules.projection().alerts
		check("committed HP damage is immediately projected without a later tick",condition_alerts.any(func(row:Dictionary)->bool:return row.key==module_id+":damaged" and row.severity=="danger") and rs.modules.projection("unknown-person").alerts.is_empty())
		var before_paid:Dictionary=rs.modules.instance(module_id).paid_cost.duplicate(true);var before_pack:Dictionary=rr.actor("player").pack.duplicate(true)
		check("repair starts with same physical hammer and actual materials",command(rr,"repair","module.repair",module_id,{"source_id":"pack:player","tool_id":hammer.id}).ok)
		advance(rr,rs,85,"modules")
		var fixed:Dictionary=rs.modules.instance(module_id)
		check("repair consumes materials without increasing paid salvage basis",float(fixed.hp)==300 and fixed.status=="operational" and fixed.paid_cost==before_paid and float(before_pack.timber)-float(rr.actor("player").pack.timber)==2 and float(before_pack.scrap)-float(rr.actor("player").pack.scrap)==1)
		check("real repair resolves condition alert at the fact source",not rs.modules.projection().alerts.any(func(row:Dictionary)->bool:return row.key==module_id+":damaged"))
		var bad:Dictionary=rs.modules.state();Draft.find(bad.instances,module_id).paid_cost.timber+=2
		check("forged repair cost cannot inflate original paid basis",not rs.modules.validate_extensions(rr.facts(),{Modules.KEY:bad}).ok)
		check("old damage replay after repair remains idempotent",commit(rr,rs.modules.prepare_damage(module_id,60,"repair:damage")).ok and float(rs.modules.instance(module_id).hp)==300)
	repair_host.free()
	var dismantle_source:Dictionary=base.duplicate(true);var da:=Draft.find(dismantle_source.facts.actors,"player");da.x=repair_port.location.x;da.y=repair_port.location.y;da.z=repair_port.location.z
	for stock:Dictionary in dismantle_source.facts.stocks:
		if stock.get("module_id")==module_id:
			for item:String in stock.items:da.pack[item]=float(da.pack.get(item,0))+float(stock.items[item])
			stock.items={}
	var dismantle_host:=Native.new();var dismantled:Dictionary=dismantle_host._assemble(dismantle_source);check("controlled dismantle fixture restores actual paid materials",dismantled.ok,dismantled)
	if dismantled.ok:
		var dr:RefCounted=dismantled.runtime;var ds:Dictionary=dismantled.services;var prior:Dictionary=dr.actor("player").pack.duplicate(true)
		check("stopped empty machine accepts actual dismantle project",command(dr,"dismantle","module.dismantle",module_id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer.id}).ok)
		advance(dr,ds,125,"modules")
		check("RC01 controlled 75 percent and whole drive recovered once",ds.modules.instance(module_id).status=="dismantled" and float(dr.actor("player").pack.timber)-float(prior.timber)==15 and float(dr.actor("player").pack.scrap)-float(prior.scrap)==6 and float(dr.actor("player").pack["r34:salvaged_drive_unit"])==1)
		check("dismantled fixed device has no live geometry or energy",dismantled.world.entity(module_id).is_empty() and float(ds.production.factory_projection().orders[0].energy_seconds)==0)
		check("same dismantle replay cannot create second drive",command(dr,"dismantle","module.dismantle",module_id,{"source_id":"pack:player","tool_id":hammer.id}).ok and float(dr.actor("player").pack["r34:salvaged_drive_unit"])==1)
		var bad:Dictionary=ds.modules.state();Draft.find(bad.instances,module_id).recovery_settlement.items.timber+=1
		check("forged controlled salvage settlement rejects",not ds.modules.validate_extensions(dr.facts(),{Modules.KEY:bad}).ok)
	var damage_host:=Native.new();var damaged:Dictionary=damage_host._assemble(base);check("independent damage branch cold restores",damaged.ok,damaged)
	if damaged.ok:
		var rr:RefCounted=damaged.runtime;var rs:Dictionary=damaged.services
		var damage:Dictionary=rs.modules.prepare_damage(module_id,60,"actual-combat:first");check("damage prepared through same domain transaction",damage.ok and commit(rr,damage).ok)
		check("same damage cause cannot apply twice",commit(rr,rs.modules.prepare_damage(module_id,60,"actual-combat:first")).ok and float(rs.modules.instance(module_id).hp)==240)
		var destroy:Dictionary=rs.modules.prepare_damage(module_id,1000,"actual-combat:destroy");var destroyed:Dictionary=commit(rr,destroy)
		check("ruin freezes one recovery ledger and real local caches",destroyed.ok,destroyed)
		if destroyed.ok:
			var ruin:Dictionary=rs.modules.instance(module_id)
			check("RC01 ruin preserves 50 percent and original drive identity",ruin.status=="ruined" and ruin.recovery.items=={"timber":10.0,"scrap":4.0,"r34:salvaged_drive_unit":1.0} and not ruin.recovery.claimed)
			check("ruin cached products keep actual stock identity and quantities",ruin.stock_refs.output.contains(":ruin:1:cache:") and float(rr.stock(ruin.stock_refs.output).items.timber)==8 and float(rr.stock(ruin.stock_refs.input).items.log)==1)
			var ruin_before:Dictionary=rr.capture_checkpoint();check("repeat attack cannot re-freeze or duplicate salvage",commit(rr,rs.modules.prepare_damage(module_id,1000,"other-attack")).ok and Data.json_equal(ruin_before.world,rr.capture_checkpoint().world))
			var ruin_restore_host:=Native.new();var ruin_restore:Dictionary=ruin_restore_host._assemble(rr.capture_checkpoint());check("actual ruin cache references and ledger cold restore",ruin_restore.ok,ruin_restore);ruin_restore_host.free()
			check("uncleared real caches prevent ruin salvage",not command(rr,"blocked-clear","module.clear_ruin",module_id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer.id}).ok)
			var bad:Dictionary=rs.modules.state();Draft.find(bad.instances,module_id).recovery.claimed=true
			check("claimed flag cannot consume a standing ruin without settlement",not rs.modules.validate_extensions(rr.facts(),{Modules.KEY:bad}).ok)
			bad=rs.modules.state();Draft.find(bad.instances,module_id).recovery.items.timber+=1
			check("forged frozen recovery quantity rejects",not rs.modules.validate_extensions(rr.facts(),{Modules.KEY:bad}).ok)
			# Isolated cache-vacating capture; no claim that this fixture is the
			# player's normal looting or physical mouse route.
			var empty_source:Dictionary=rr.capture_checkpoint();var ca:=Draft.find(empty_source.facts.actors,"player");ca.x=repair_port.location.x;ca.y=repair_port.location.y;ca.z=repair_port.location.z
			for stock:Dictionary in empty_source.facts.stocks:
				if stock.get("ruin_id")==ruin.ruin_id:
					for item:String in stock.items:ca.pack[item]=float(ca.pack.get(item,0))+float(stock.items[item])
					stock.items={}
			var clear_host:=Native.new();var cleared:Dictionary=clear_host._assemble(empty_source);check("emptied ruin restores with real safe clearance position",cleared.ok,cleared)
			if cleared.ok:
				var cr:RefCounted=cleared.runtime;var cs:Dictionary=cleared.services;var prior:Dictionary=cr.actor("player").pack.duplicate(true)
				check("on-site clear starts one project",command(cr,"clear","module.clear_ruin",module_id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer.id}).ok)
				advance(cr,cs,125,"modules")
				var cleared_module:Dictionary=cs.modules.instance(module_id)
				check("clear pays frozen 50 percent and original drive exactly once",cleared_module.status=="dismantled" and cleared_module.recovery.claimed and float(cr.actor("player").pack.timber)-float(prior.timber)==10 and float(cr.actor("player").pack.scrap)-float(prior.scrap)==4 and float(cr.actor("player").pack["r34:salvaged_drive_unit"])==1)
				check("removed rubble cannot start another clear project",not command(cr,"clear-again","module.clear_ruin",module_id,{"source_id":"pack:player","tool_id":hammer.id}).ok and cleared.world.entity(module_id).is_empty())
				var clear_restore_host:=Native.new();var clear_restore:Dictionary=clear_restore_host._assemble(cr.capture_checkpoint());check("claimed ruin settlement survives exact cold restore",clear_restore.ok,clear_restore);clear_restore_host.free()
			clear_host.free()
	dismantle_host.free();damage_host.free()
	host.free();host2.free();host3.free();restored_host.free();finish()
func finish()->void:
	var report:Dictionary={"ok":checks.all(func(c:Dictionary)->bool:return c.ok),"scope":"BBB isolated real Runtime construction/inventory/machine/cold-restore source checks; explicit fixture supplies; no official package/OS/economy/VA/performance acceptance","checks":checks}
	print(JSON.stringify(report));quit(0 if report.ok else 1)
