extends "res://tests/modules/normal_module_lifecycle.gd"
## Start ONLY at B's actual paid home04. Two explicitly labelled damage
## injections use B.damage_in + original transaction; no enemy/natural-attack claim.
## Every repair, material reclamation, rebuild and service uses real commands.
const Cold=preload("res://tests/gameplay/factory_route_cold.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var options:Dictionary
var baseline_facts:Dictionary
var injections:Array=[]
var limitations:Array=[]
var baseline_beds:Array=[]
var id:String="B:architecture:normal-home"
var hammer:String="r34:generated:RH-HOME:woodwork:tool:hammer"
func send(rt:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	# B's successful source already contains its command receipts. Never replay
	# inherited B IDs as if they were new actions in this continuation.
	sequence+=1
	var request:Dictionary={"command_id":"E:6.35:housing-recovery:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=rt.command(request)
	commands.append({"clock":rt.clock(),"request":request.duplicate(true),"code":result.get("code"),"ok":result.get("ok",false),"reason":result.get("reason")})
	return result
func home_row()->Dictionary:
	var housing:Dictionary=live.services.residents.housing_projection("player")
	for row:Dictionary in housing.homes:
		if row.id==id:return row
	return {}
func cold(label:String)->bool:
	var packed:Dictionary=Store.encode(live.runtime.capture_checkpoint())
	check(label+" actual native save",packed.get("ok",false))
	if not packed.get("ok",false):return false
	FileAccess.open(outdir+"/"+label+".native.json",FileAccess.WRITE).store_string(packed.text)
	var decoded:Dictionary=Store.decode(packed.text);var host:=Native.new()
	var result:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	var compared:Dictionary=Cold.compare(decoded.capture,result.runtime,int(options.native_residency_batch)) if result.get("ok",false) else result
	check(label+" full persisted capture/chunks/revision exact residency oracle",compared.get("ok",false),compared)
	if not compared.get("ok",false):return false
	live.runtime.retire();live=result;return true
func inject_damage(amount:float,label:String)->bool:
	var rt:RefCounted=live.runtime;var before:Dictionary=rt.capture_checkpoint()
	var tx:=Draft.new(live.services.modules.context)
	var damaged:Dictionary=live.services.modules.damage_in(tx,id,amount,"E:housing:fixture:"+label)
	var committed:Dictionary=rt._commit(tx.result()) if damaged.get("ok",false) else damaged
	injections.append({"label":label,"kind":"B.damage_in explicit fixture; not hostile attack","amount":amount,"module_id":id,"result":committed,"before_hp":Draft.find(before.world.extensions[Modules.KEY].instances,id).hp,"after_hp":live.services.modules.instance(id).hp})
	check(label+" explicit damage only through B transaction authority",committed.get("ok",false),committed.get("reason"))
	return committed.get("ok",false)
func service_cycle(label:String)->bool:
	var rt:RefCounted=live.runtime;var home:Dictionary=live.services.modules.instance(id)
	var port:Dictionary=Draft.find(ModuleShape.ports(home,Modules.definition(home.definition_id)),"service")
	var walked:Dictionary=walk(rt,port.location)
	var stock:String=home.stock_refs.supplies;var before:float=float(rt.actor("player").pack.get("water",0))
	var put:Dictionary=send(rt,"deposit",stock,{"items":{"water":1}}) if walked.get("ok",false) else walked
	var take:Dictionary=send(rt,"take",stock,{"items":{"water":1}}) if put.get("ok",false) else put
	check(label+" original finite water transports through exact service face",take.get("ok",false) and float(rt.actor("player").pack.get("water",0))==before and float(rt.stock(stock).items.get("water",0))==0 and home_row().get("usable",false),{"walk":walked.get("ok",false),"put":put.get("code"),"take":take.get("code")})
	return take.get("ok",false)
func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];source_path=args[1];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source_path));var host:=Native.new()
	live=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	check("exact B normal04 paid-home success mounts without capture edits",FileAccess.get_sha256(source_path)==options.input_sha256 and live.get("ok",false),live.get("reason"))
	if not live.get("ok",false):return finish()
	var rt:RefCounted=live.runtime;baseline_facts=rt.facts()
	baseline_beds=rt.world.entities().filter(func(e:Dictionary)->bool:return e.get("data",{}).get("sleeping",false) or e.get("kind")=="bed").duplicate(true)
	var original:Dictionary=live.services.modules.instance(id)
	check("real paid home design2 populated by original three actors only",original.status=="operational" and float(original.paid_cost.timber)==24 and float(original.paid_cost.scrap)==8 and home_row().capacity==2 and home_row().usable and rt.facts().actors.size()==3)
	check("consumer reaches housing through original public factory snapshot",rt.factory_snapshot().workforce.housing==live.services.residents.housing_projection("player"))
	if not service_cycle("initial paid home"):return finish()
	# Finite repair resources: dismantle the already-paid, now empty warehouse.
	# This is a deliberate economic sacrifice, not a material gift.
	if not dismantle("r34:normal-built-warehouse",hammer,"finite empty warehouse reclamation"):return finish()
	if not inject_damage(12,"partial"):return finish()
	check("damaged home loses usable service but retains design capacity",home_row().capacity==2 and not home_row().usable and home_row().status=="damaged")
	var tx:=Draft.new(live.services.modules.context);var pack:Dictionary=rt.actor("player").pack.duplicate(true)
	var denied:Dictionary=live.services.residents._take_supply(tx,"player",original.stock_refs.supplies,"water")
	check("E arrival refuses damaged home without changing goods",not denied.ok and denied.code=="HOUSING_SERVICE_UNAVAILABLE" and Data.json_equal(tx.staged,rt.facts()) and Data.json_equal(pack,rt.actor("player").pack))
	if not cold("actual-explicit-partial-damage"):return finish()
	rt=live.runtime
	var port:Dictionary=work_port(rt,live.services.modules.instance(id))
	var walked:Dictionary=walk(rt,port) if not port.is_empty() else {"ok":false}
	check("repairer follows actual supported route",walked.get("ok",false))
	if not walked.get("ok",false):return finish()
	var before_pack:Dictionary=rt.actor("player").pack.duplicate(true);var before_tool:float=rt.tool(hammer).durability
	var repair:Dictionary=send(rt,"module.repair",id,{"source_id":"pack:player","tool_id":hammer})
	var done:Dictionary=progress(rt,140) if repair.get("ok",false) else repair
	check("original paid eight-second hammer repair restores service",repair.get("ok",false) and done.get("finished",false) and home_row().usable and live.services.modules.instance(id).hp==Modules.definition(original.definition_id).hp,{"repair":repair,"done":done})
	check("repair charges exactly two finite boards one scrap and real tool wear",float(before_pack.timber)-float(rt.actor("player").pack.timber)==2 and float(before_pack.scrap)-float(rt.actor("player").pack.scrap)==1 and is_equal_approx(before_tool-float(rt.tool(hammer).durability),1.2))
	if not home_row().usable:return finish()
	if not service_cycle("actually repaired home") or not cold("actual-paid-repaired-home"):return finish()
	rt=live.runtime
	if not inject_damage(300,"ruin"):return finish()
	check("ruined home design persists without live service",home_row().capacity==2 and not home_row().usable and home_row().status=="ruined")
	if not cold("actual-explicit-ruin"):return finish()
	rt=live.runtime
	if not care(rt,70):return finish()
	var ruin:Dictionary=live.services.modules.instance(id);var feet:Dictionary=work_port(rt,ruin)
	walked=walk(rt,feet) if not feet.is_empty() else {"ok":false}
	var clear:Dictionary=send(rt,"module.clear_ruin",id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer}) if walked.get("ok",false) else walked
	done=progress(rt,200) if clear.get("ok",false) else clear
	check("actual ruin clearing returns only original50percent paid materials",clear.get("ok",false) and done.get("finished",false) and live.services.modules.instance(id).status=="dismantled" and float(live.services.modules.instance(id).recovery_settlement.items.get("timber",0))==12 and float(live.services.modules.instance(id).recovery_settlement.items.get("scrap",0))==4,clear)
	if live.services.modules.instance(id).status!="dismantled":return finish()
	# Honest failed full-ruin branch: even all currently known scrap is short.
	var rebuild_payload:Dictionary={"definition_id":original.definition_id,"position":original.position.merged({"regionId":original.region}),"quarter_turn":original.quarter_turn,"source_id":"pack:player","tool_id":hammer}
	var before_denial:Dictionary=rt.capture_checkpoint()
	var rebuild_denial:Dictionary=send(rt,"module.plan","E:architecture:unfunded-ruin-rebuild",rebuild_payload)
	check("full-ruin rebuild honestly refuses missing finite materials atomically",not rebuild_denial.get("ok",false) and rebuild_denial.get("code")=="MODULE_MATERIALS" and Data.json_equal(before_denial.facts,rt.facts()) and Data.json_equal(before_denial.world,rt.capture_checkpoint().world),rebuild_denial)
	limitations.append({"branch":"full ruin; NOT recovered","actual_pack":rt.actor("player").pack.duplicate(true),"required":{"timber":24,"scrap":8},"known_shortfall":{"timber":4,"scrap":2},"reachable_source":"one original tree and hand saw can supply4timber, but all searched original scrap stocks exhausted; uncharted regions are not a guaranteed source","code":rebuild_denial.get("code")})
	save_scene(rt,"actual-ruin-rebuild-insufficient")
	# Separate legal alternate branch, loaded from our actual repaired save.
	# Ruin recovery is NOT claimed: controlled dismantling loses less material.
	rt.retire()
	var alternate:Dictionary=Store.decode(FileAccess.get_file_as_string(outdir+"/actual-paid-repaired-home.native.json"))
	host=Native.new();live=host._assemble(alternate.capture) if alternate.get("ok",false) else alternate;host.free()
	check("separate controlled branch restores our exact paid-repaired checkpoint",live.get("ok",false))
	if not live.get("ok",false):return finish()
	rt=live.runtime
	if not dismantle(id,hammer,"controlled alternate original home reclamation"):return finish()
	check("dismantled home retains design but loses live service",home_row().capacity==2 and not home_row().usable and home_row().status=="dismantled")
	if not care(rt,80):return finish()
	# The old ID is a dismantled historical object; new paid build gets a new ID.
	var old_id:String=id;id="E:architecture:rebuilt-home"
	var payload:Dictionary={"definition_id":original.definition_id,"position":original.position.merged({"regionId":original.region}),"quarter_turn":original.quarter_turn,"source_id":"pack:player","tool_id":hammer}
	var preview:Dictionary=live.services.modules.preview({"kind":"module.plan","actor_id":"player","target_id":id,"payload":payload})
	check("original unedited site proves real rebuild support and clearance",preview.get("ok",false),preview.get("code"))
	if not preview.get("ok",false):return finish()
	var service:Dictionary=Draft.find(preview.ports,"service").location
	walked=walk(rt,service);before_pack=rt.actor("player").pack.duplicate(true);before_tool=rt.tool(hammer).durability
	var plan:Dictionary=send(rt,"module.plan",id,payload) if walked.get("ok",false) else walked
	done=progress(rt,600) if plan.get("ok",false) else plan
	check("actual rebuilt home pays24boards8scrap once and exposes design2",plan.get("ok",false) and done.get("finished",false) and home_row().get("usable",false) and home_row().capacity==2 and float(before_pack.timber)-float(rt.actor("player").pack.timber)==24 and float(before_pack.scrap)-float(rt.actor("player").pack.scrap)==8 and is_equal_approx(before_tool-float(rt.tool(hammer).durability),6.0),plan)
	if not home_row().get("usable",false):return finish()
	check("old ruined identity stays dismantled after new paid construction",live.services.modules.instance(old_id).status=="dismantled")
	if not service_cycle("actually rebuilt home") or not cold("actual-paid-rebuilt-home"):return finish()
	rt=live.runtime
	check("original actors HP consent identity and no new beds survive whole branch",rt.facts().actors.size()==baseline_facts.actors.size() and rt.facts().actors.all(func(a:Dictionary)->bool:return a.hp==Draft.find(baseline_facts.actors,a.id).hp and Data.json_equal(a.relationship,Draft.find(baseline_facts.actors,a.id).relationship)) and Data.json_equal(baseline_beds,rt.world.entities().filter(func(e:Dictionary)->bool:return e.get("data",{}).get("sleeping",false) or e.get("kind")=="bed")))
	finish()
func finish()->void:
	if live.get("ok",false):save_scene(live.runtime,"housing-recovery-final")
	var result:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"journey":journey,"commands":commands,"injections":injections,"limitations":limitations,"scope":"B normal04 real finite paid-home continuation. Explicit partial12/ruin300 damage fixtures only; legal finite warehouse reclaim/repair/ruin-clear then honest insufficient-material failure. Separate restored repaired-checkpoint branch uses controlled dismantle/rebuild/service/cold. Full-ruin recovery NOT passed. Not natural enemy attack, NPC occupancy or other eight actual home lifecycle; no OS/VA/FPS/package claim."}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":result.failed}));quit(1 if result.failed else 0)
