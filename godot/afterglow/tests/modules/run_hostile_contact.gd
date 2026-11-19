extends SceneTree
## Isolated counterexamples on a READ-ONLY actual19 normal save. Enemy poses,
## HP/cooldown, blockers and ruin adversity below are EXPLICIT test fixtures.
## These direct service tests NEVER qualify a natural AI/economy journey.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var rt:RefCounted
var services:Dictionary
var target:Dictionary
var stance:Dictionary
var contact:Dictionary
var output:String
var original_sha:String
var source_path:String

func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func snap(tx:RefCounted)->Dictionary:return {"initial":tx.initial.duplicate(true),"staged":tx.staged.duplicate(true),"extensions":tx.extensions.duplicate(true),"extra":tx.extra.duplicate(true),"events":tx.events.duplicate(true)}
func enemy(id:String,at:Dictionary)->Dictionary:
	var a:Dictionary=rt.actor("player");a.id=id;a.name=id;a.pack={};a.faction="infected";a.hp=48.0;a.max_hp=48.0;a.intent=null;a.cooldown=0.0;a.wounds=[];a.erase("pending_delivery");a.merge(at,true)
	return a
func draft()->RefCounted:
	var tx:=Draft.new(services.modules.context)
	tx.staged.actors.append(enemy("B:hostile:one",stance));tx.staged.actors.append(enemy("B:hostile:two",stance))
	return tx
func reject(label:String,tx:RefCounted,actor_id:String="B:hostile:one",id:String="",expected:String="")->void:
	var before:Dictionary=snap(tx);var result:Dictionary=services.modules.strike_hostile(tx,actor_id,id)
	check(label,not result.ok and (expected.is_empty() or result.code==expected),result)
	check(label+" preserves complete caller Draft",Data.json_equal(before,snap(tx)))
func module_in(tx:RefCounted)->Dictionary:return Draft.find(tx.extension(Modules.KEY).instances,str(target.id))
func block(tx:RefCounted,solid:bool,opaque:bool,other_module:bool=false)->void:
	var a:Vector3=G.point(stance)+Vector3(0,1.2,0);var p:Vector3=G.point(contact.point);var center:Vector3=a.lerp(p,0.52)
	var size:=Vector3(0.04,2.0,0.7) if absf(p.x-a.x)>absf(p.z-a.z) else Vector3(0.7,2.0,0.04)
	var bounds:=AABB(Vector3(center.x,stance.y,center.z)-Vector3(size.x/2,0,size.z/2),size)
	var e:Dictionary={"id":"B:contact:blocker","kind":"prop","regionId":stance.regionId,"position":G.json_point(bounds.position),"bounds":G.json_box(bounds),"revision":0,"blocksTerrain":true,"supportBounds":[],"data":{"solid":solid,"opaque":opaque}}
	if other_module:e.data.module_id="r34:normal-built-warehouse"
	tx.extra.append({"op":"entity.put","id":e.id,"before_exists":false,"before":null,"after":e})
func find_stance()->bool:
	var query:RefCounted=services.buildings.current_space()
	for member:Dictionary in target.members:
		var e:Dictionary=rt.world.entity(member.id)
		if e.is_empty() or not e.data.get("solid",false):continue
		var box:AABB=G.aabb(e.bounds)
		for normal:Vector3 in [Vector3.BACK,Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT]:
			var surface:Vector3=box.get_center()
			if normal.x!=0:surface.x=box.end.x if normal.x>0 else box.position.x
			else:surface.z=box.end.z if normal.z>0 else box.position.z
			var point:Vector3=surface+normal*0.78
			var feet:Dictionary={"x":point.x,"y":target.position.y,"z":point.z,"regionId":target.region,"buildingId":null,"storeyId":null}
			feet=query.standing_point(feet)
			if feet.is_empty():continue
			var chest:Vector3=G.point(feet)+Vector3(0,1.2,0);var hit:Vector3=chest.max(box.position).min(box.end)
			var to:Dictionary=feet.merged(G.json_point(hit-Vector3(0,1.2,0)),true)
			if chest.distance_to(hit)>0.9 or not query.contact_clear(feet,to,e.id) or not query.line_clear(feet,to,e.id):continue
			stance=feet;contact={"member_id":e.id,"point":G.json_point(hit)};return true
	return false
func run()->void:
	var args:Array=OS.get_cmdline_user_args();output=args[0];source_path=args[1];DirAccess.make_dir_recursive_absolute(output)
	original_sha=FileAccess.get_sha256(source_path)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source_path))
	check("read-only actual19 normal source decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("source passes current formal Native and owner validators",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	rt=built.runtime;services=built.services;target=services.modules.instance("r34:normal-built-woodshop")
	check("real paid original machine exposes a supported external member",not target.is_empty() and find_stance(),{"target":target.id,"stance":stance,"contact":contact})
	if stance.is_empty():return finish()
	var live:Dictionary=rt.capture_checkpoint();var tx:RefCounted=draft()
	var actor_ref:Dictionary=tx.actor("B:hostile:one");var state_ref:Dictionary=tx.extension(Modules.KEY);var target_ref:Dictionary=Draft.find(state_ref.instances,str(target.id))
	var hit:Dictionary=services.modules.strike_hostile(tx,actor_ref.id)
	check("empty target selects physically contacted registered shell",hit.get("ok",false) and hit.module_id==target.id and hit.damage==12,hit)
	if not hit.get("ok",false):return finish()
	check("prepared hit never mutates live world or facts",Data.json_equal(live,rt.capture_checkpoint()))
	check("same Draft references receive exactly one original hit and cooldown",target_ref.hp==target.hp-12 and actor_ref.cooldown==1.3 and is_equal_approx(actor_ref.attack_until,rt.clock()+0.28))
	check("hit reuses original unique damage receipt and both event facts",target_ref.damage_receipts.get(hit.cause_id)==12 and tx.events.any(func(e:Dictionary)->bool:return e.kind=="module-damaged") and tx.events.any(func(e:Dictionary)->bool:return e.kind=="module-hostile-hit" and e.cause_id==hit.cause_id and e.member_id==hit.member_id))
	reject("same hostile cannot hit again during original cooldown",tx,"B:hostile:one","","COOLDOWN")
	tx.actor("B:hostile:one").cooldown=0.0
	reject("same simulation-fact cause replay rejects zero change",tx,"B:hostile:one","","NO_CHANGE")
	var again:RefCounted=draft();var repeated:Dictionary=services.modules.strike_hostile(again,"B:hostile:one",target.id)
	check("same actor module world and time derive stable cause identity",repeated.get("cause_id")==hit.cause_id)
	check("explicit valid module still requires same real registered contact",repeated.get("ok",false) and repeated.member_id==hit.member_id)
	reject("player cannot bypass owner tools via hostile API",draft(),"player","","FORBIDDEN")
	tx=draft();tx.actor("B:hostile:one").hp=0;reject("dead infected",tx)
	tx=draft();tx.actor("B:hostile:one").stunned_until=rt.clock()+1;reject("stunned infected",tx,"B:hostile:one","","COOLDOWN")
	tx=draft();tx.actor("B:hostile:one").y+=4;reject("floating unsupported body",tx,"B:hostile:one","","INVALID_ATTACK_STANCE")
	tx=draft();tx.actor("B:hostile:one").merge({"x":10.9,"y":0.5,"z":25.8},true);reject("remote module cannot be hit by explicit ID",tx,"B:hostile:one",target.id)
	tx=draft();tx.actor("B:hostile:one").regionId="RH-VILLAGE";reject("wrong detailed-space ownership cannot hit home module",tx)
	var original_detailed:Callable=services.modules.context.region_is_detailed
	services.modules.context.region_is_detailed=func(_id:String)->bool:return false
	reject("cold region cannot simulate a module attack",draft(),"B:hostile:one","","REGION_PAUSED")
	services.modules.context.region_is_detailed=original_detailed
	reject("another module cannot be reached through module selection",draft(),"B:hostile:one","r34:normal-built-warehouse","OUT_OF_REACH")
	tx=draft();tx.staged.scenario="rural-home-r33";reject("legacy cannot acquire new hostile module rule",tx,"B:hostile:one","","FORBIDDEN")
	tx=draft();module_in(tx).protected=true;reject("protected module",tx)
	for status:String in ["planned","constructing","ruined","dismantled"]:
		tx=draft();module_in(tx).status=status;reject("non damageable "+status,tx)
	tx=draft();module_in(tx).members=[{"id":target.id,"kind":"entity"}];reject("aggregate target bounds cannot replace physical registered members",tx)
	tx=draft();module_in(tx).owner="other-owner";reject("mismatched member owner cannot authorize hostile shell mapping",tx)
	tx=draft();module_in(tx).geometry_version="B:stale-version";reject("stale member geometry version",tx)
	tx=draft();block(tx,true,false);reject("transparent solid blocks tool contact",tx)
	tx=draft();block(tx,false,true);reject("non-solid opaque curtain blocks sight",tx)
	tx=draft();block(tx,true,true,true);reject("another module member blocks attack rather than being ignored",tx,"B:hostile:one",target.id)
	var from:Vector3=G.point(stance);var towards:Vector3=G.point(contact.point)-Vector3(0,1.2,0);var midpoint:Vector3=from.lerp(towards,0.52)
	var wall_at:Dictionary=stance.merged(G.json_point(midpoint),true)
	var wall:Dictionary=services.buildings.make_instance("wall","B:hostile:intervening-wall",wall_at,1 if absf(towards.x-from.x)>absf(towards.z-from.z) else 0)
	tx=draft();tx.extension("r3:structures").instances.append(wall)
	tx.extra.append({"op":"entity.put","id":wall.id,"before_exists":false,"before":null,"after":services.buildings.geometry.entity(wall)})
	reject("same Draft actual wall member blocks module contact",tx,"B:hostile:one",target.id,"OUT_OF_REACH")
	var fallback:Dictionary=services.buildings.strike_structure(tx,"B:hostile:one",wall.id)
	check("rejected module attack leaves original real wall fallback usable",fallback.ok and tx.actor("B:hostile:one").cooldown==1.3,fallback.get("reason"))
	manual_member_case()
	tx=draft();var box:Dictionary=module_in(tx);box.hp=12
	var conflict_stock:Dictionary=rt.stock(str(target.stock_refs.input));conflict_stock.id=str(target.id)+":ruin:1:cache:input";tx.staged.stocks.append(conflict_stock)
	reject("late original ruin cache conflict rolls back all staging",tx,"B:hostile:one",target.id,"RUIN_STOCK_CONFLICT")
	tx=draft();module_in(tx).damage_receipts={}
	for i:int in 8192:module_in(tx).damage_receipts["B:full:"+str(i)]=1.0
	reject("original damage receipt bound rejects without charging cooldown",tx,"B:hostile:one",target.id,"MODULE_DAMAGE_LEDGER_LIMIT")
	var one:RefCounted=draft();var first:Dictionary=services.modules.strike_hostile(one,"B:hostile:one");var second:Dictionary=services.modules.strike_hostile(one,"B:hostile:two")
	check("two same-tick enemies each hit once with separate stable causes",first.ok and second.ok and first.cause_id!=second.cause_id and module_in(one).hp==target.hp-24)
	var committed:Dictionary=rt._commit(one.result())
	check("single authoritative commit accepts merged multi-enemy HP cooldown and owners",committed.ok and services.modules.instance(target.id).hp==target.hp-24 and rt.actor("B:hostile:one").cooldown==1.3 and rt.actor("B:hostile:two").cooldown==1.3,committed.get("reason"))
	if committed.ok:lethal_case()
	check("actual19 original source bytes unchanged",FileAccess.get_sha256(source_path)==original_sha)
	finish()
func manual_member_case()->void:
	var manual:Dictionary=services.modules.state().instances.filter(func(v:Dictionary)->bool:return v.members.any(func(m:Dictionary)->bool:return m.kind=="structure"))[0]
	var piece_id:String=manual.members.filter(func(m:Dictionary)->bool:return m.kind=="structure")[0].id
	var piece:Dictionary=services.buildings.instance(piece_id);var query:RefCounted=services.buildings.current_space();var chosen:Dictionary={}
	for box:AABB in services.buildings.geometry.boxes(piece):
		for normal:Vector3 in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
			var surface:Vector3=box.get_center()
			if normal.x!=0:surface.x=box.end.x if normal.x>0 else box.position.x
			else:surface.z=box.end.z if normal.z>0 else box.position.z
			var feet:Dictionary={"x":surface.x+normal.x*0.5,"y":manual.position.y,"z":surface.z+normal.z*0.5,"regionId":manual.region,"buildingId":null,"storeyId":null}
			feet=query.standing_point(feet)
			if feet.is_empty():continue
			var tx:RefCounted=draft();tx.actor("B:hostile:one").merge(feet,true)
			var result:Dictionary=services.modules.strike_hostile(tx,"B:hostile:one",manual.id)
			if result.ok and result.member_id==piece_id:chosen=result;break
		if not chosen.is_empty():break
	check("real manual workbench structure member maps to whole module damage",not chosen.is_empty(),chosen)
func lethal_case()->void:
	# Explicit adversity setup: restore module HP, seed only a bounded log
	# cache/fuel, then use the ORIGINAL machine configure/advance for live WIP.
	# This is a domain fixture, never a finite normal-economy recovery claim.
	var setup:=Draft.new(services.modules.context);var original_module:Dictionary=module_in(setup)
	original_module.hp=target.hp;original_module.status="operational"
	setup.stock(str(target.stock_refs.input)).items.log=2.0;setup.stock(str(target.stock_refs.fuel)).items.log=1.0
	var seeded:Dictionary=rt._commit(setup.result())
	var configured:Dictionary=rt.command({"kind":"factory.configure","actor_id":"player","command_id":"B:hostile:live-wip","target_id":target.id,"payload":{"batches":2,"recipe_id":"saw_timber"}}) if seeded.ok else seeded
	var advanced:Dictionary=rt._commit(services.production.advance(0.1)) if configured.ok else configured
	var production:Dictionary=rt.world.extension("r34:production");var batch:Dictionary=production.batches[-1]
	check("bounded fixture feeds original machine into real active WIP",seeded.ok and configured.ok and advanced.ok and batch.status=="active" and batch.elapsed>0 and batch.wip=={"log":1.0},advanced.get("reason"))
	if not advanced.ok or batch.status!="active":return
	var tx:=Draft.new(services.modules.context);var v:Dictionary=module_in(tx);v.hp=24.0
	tx.actor("B:hostile:one").cooldown=0.0;tx.actor("B:hostile:two").cooldown=0.0;tx.staged.time+=0.1
	# An explicit preexisting root update in the same Draft exercises original
	# CAS coalescing when the second enemy destroys the module shell.
	var root:Dictionary=rt.world.entity(str(target.id));var changed:Dictionary=root.duplicate(true);changed.revision+=1
	tx.extra.append({"op":"entity.put","id":root.id,"before_exists":true,"before":root,"after":changed})
	var legacy:Dictionary=tx.extension("r3:production");var hammer:Dictionary=Draft.find(legacy.tools,"r34:generated:RH-HOME:woodwork:tool:hammer");hammer.holderId=target.stock_refs.input
	# Explicit carried-task fixture conserves the original warehouse board:
	# source8->7/pack0->1, retains an existing task ID and ordinary haul intent.
	var logistics:Dictionary=tx.extension("r34:logistics");var task:Dictionary=logistics.tasks[0]
	task.source_id="r34:normal-built-warehouse:stock:storage";task.destination_id=target.stock_refs.output;task.items={"timber":1.0};task.phase="deliver";task.status="delivering";task.actor_id="village-resident"
	tx.stock(task.source_id).items.timber-=1;tx.actor(task.actor_id).pack.timber=1.0
	tx.actor(task.actor_id).intent={"schema_version":1,"owner":"actions","kind":"haul","id":"B:hostile:cargo","steps":[],"step":0,"held":true,"logistics_task_id":task.id}
	Factory.sync_logistics(logistics)
	var state_ref:Dictionary=tx.extension(Modules.KEY);var actor_ref:Dictionary=tx.actor("B:hostile:two")
	var a:Dictionary=services.modules.strike_hostile(tx,"B:hostile:one",target.id)
	var intermediate:Dictionary=tx.extensions.get("r34:production",production)
	check("nonlethal contact retains active WIP and original damaged-machine blocker",a.ok and Data.json_equal(intermediate,production) and Factory.blockers(services.production,tx,module_in(tx),production.orders[0],batch).has("damaged"))
	var b:Dictionary=services.modules.strike_hostile(tx,"B:hostile:two",target.id)
	check("second same-tick legal contact invokes original lethal recovery",a.ok and b.ok and Draft.find(state_ref.instances,str(target.id)).status=="ruined" and actor_ref.cooldown==1.3,{"one":a,"two":b})
	if not a.ok or not b.ok:return
	var ruined:Dictionary=module_in(tx)
	check("original frozen 50 percent materials and unique drive remain exact",ruined.recovery.items=={"timber":10.0,"scrap":4.0,"r34:salvaged_drive_unit":1.0} and not ruined.recovery.claimed)
	check("ruin preserves unconsumed cache and tool identity at same service",tx.stock(str(ruined.stock_refs.input)).items.log==1 and Draft.find(tx.extensions["r3:production"].tools,hammer.id).holderId==ruined.stock_refs.input and ruined.stock_refs.input!=target.stock_refs.input)
	var after_production:Dictionary=tx.extensions["r34:production"];var destroyed:Dictionary=Draft.find(after_production.batches,str(batch.id))
	check("started WIP and spent energy settle once without output or refund",destroyed.status=="destroyed" and destroyed.wip.is_empty() and destroyed.settlement_id==str(batch.id)+":destroyed" and after_production.settlements.size()==production.settlements.size()+1 and after_production.settlements[-1].outputs.is_empty() and after_production.orders[0].energy_seconds==0 and after_production.orders[0].remaining==0 and tx.stock(str(ruined.stock_refs.output)).items.get("timber",0)==0)
	check("carried responsibility preserves exact original pack and task with no remote delivery",task.status=="cargo_held" and task.reason=="target_ruined" and task.phase=="deliver" and task.actor_id=="village-resident" and tx.actor(task.actor_id).pack.timber==1 and tx.actor(task.actor_id).intent==null and tx.stock(task.source_id).items.timber==7 and logistics.reservations.is_empty())
	check("uncarried collection cancels and releases original endpoint promises",logistics.tasks[1].status=="cancelled" and logistics.tasks[1].reason=="target_ruined")
	var root_ops:Array=tx.extra.filter(func(op:Dictionary)->bool:return op.id==target.id and op.op in ["entity.put","entity.remove"])
	check("same-tick ruin coalesces root to one original-before final-after CAS",root_ops.size()==1 and Data.json_equal(root_ops[0].before,root) and root_ops[0].after.data.ruin_id==ruined.ruin_id)
	tx.actor("B:hostile:one").cooldown=0.0
	reject("third hit on same-tick ruin cannot charge or create another ledger",tx,"B:hostile:one",target.id,"OUT_OF_REACH")
	var result:Dictionary=rt._commit(tx.result())
	check("original owner lifecycle and storage validators accept complete lethal transaction",result.ok,result.get("reason"))
	if not result.ok:return
	var encoded:Dictionary=Store.encode(rt.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var host:=Native.new();var restored:Dictionary=host._assemble(decoded.capture) if decoded.ok else decoded;host.free()
	check("native canonical cold restore retains ruin receipt goods tools and cooldown",restored.get("ok",false) and Data.json_equal(restored.runtime.facts(),decoded.capture.facts) and Data.json_equal(restored.world.snapshot().extensions,decoded.capture.world.extensions),restored.get("reason"))
	if encoded.ok:FileAccess.open(output+"/explicit-fixture-lethal.native.json",FileAccess.WRITE).store_string(encoded.text)
	var before_owner:Dictionary=rt.capture_checkpoint();var bad:=Draft.new(services.modules.context);bad.stock(str(ruined.stock_refs.input)).owner="B:forged-owner"
	var rejected:Dictionary=rt._commit(bad.result())
	check("same final Runtime owner validator still rejects forged ruin cache owner atomically",not rejected.ok and Data.json_equal(before_owner,rt.capture_checkpoint()),rejected.get("code"))
func finish()->void:
	var result:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"source_sha256":original_sha,"stance":stance,"contact":contact,"scope":"B isolated contact/atomicity fixtures only; original19 normal save read-only. Enemy poses, body/HP/status/cooldown, blocker entities, cold hook, root pending edit, restored module HP, bounded log/fuel cache, HP24 lethal adversity, hammer holder, conserved warehouse-to-pack1/carrying task and forged cache owner are explicit fixtures. Live WIP uses original configure/advance; NOT natural enemy/economy/OS/VA/performance/new-PCK qualification."}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print(JSON.stringify(result,"",false,true));quit(1 if result.failed else 0)
