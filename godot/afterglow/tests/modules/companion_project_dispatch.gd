extends SceneTree
## Synthetic delivery isolates queue, real movement and paid settlement.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Recovery=preload("res://scripts/modules/module_recovery.gd")
const RebuildGeometry=preload("res://scripts/buildings/building_geometry.gd")
const WORKER="village-resident"
var failures:int=0
var checks:int=0

func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->bool:
	checks+=1
	if not ok:failures+=1;print("FAIL ",label," ",detail)
	return ok
func finish()->void:
	print("COMPANION_PROJECT ", checks-failures,"/",checks)
	quit(0 if failures==0 else 1)
func run()->void:
	var profiles:=Assembly.generation_profiles()
	var opening:=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	if not check("prepare",opening.ok,opening.get("code")):return finish()
	var capture:Dictionary=opening.capture
	var warehouse:Dictionary=capture.world.extensions["r34:modules"].instances.filter(func(v:Dictionary)->bool:return v.id=="r34:generated:RH-HOME:village-warehouse")[0]
	var worker:=Draft.find(capture.facts.actors,WORKER)
	worker.pack.erase("timber");worker.pack.erase("scrap");worker.pack.erase("cloth")
	for stock:Dictionary in capture.facts.stocks:
		for item:String in warehouse.restoration.cost:stock.items.erase(item)
	for tool:Dictionary in capture.world.extensions["r3:production"].tools:
		if tool.kind=="hammer":tool.holderId="pack:"+WORKER;break
	var host:=Native.new();var built:=host._assemble(capture)
	if not check("assemble",built.ok,built.get("code")):host.free();return finish()
	var rt:RefCounted=built.runtime
	var request:Dictionary={"kind":"workforce.queue_building","actor_id":"player","command_id":"test:warehouse-order","target_id":warehouse.id,"payload":{}}
	var placed:Dictionary=rt.command(request)
	if not check("missing stock does not reject the work order",placed.ok,placed):rt.retire();host.free();return finish()
	var duplicate:=request.duplicate(true)
	duplicate.command_id="test:duplicate-warehouse-order"
	check("the same building cannot be queued twice",not rt.command(duplicate).ok)
	var queued_save:=Store.encode(rt.capture_checkpoint())
	var queued_decoded:=Store.decode(queued_save.get("text",""))
	if not check("unassigned order survives serializing",queued_decoded.ok and queued_decoded.capture.world.extensions["r34:workforce"].get("building_queue",[])==[warehouse.id],queued_decoded.get("code")):
		rt.retire();host.free();return finish()
	for i:int in 40:rt.tick(.1)
	var row:Dictionary=built.world.extension("r34:workforce").assignments[0]
	check("waiting work names actual blocker without creating project",row.get("building_phase")=="blocked" and not str(row.get("building_reason","")).is_empty() and built.services.modules.instance(warehouse.id).project_id=="",row)
	var saved:=Store.encode(rt.capture_checkpoint());var decoded:=Store.decode(saved.get("text",""))
	if not check("pending order is serializable",decoded.ok,decoded.get("code")):rt.retire();host.free();return finish()
	var source:=Draft.find(decoded.capture.facts.actors,str(row.actor_id))
	for item:String in warehouse.restoration.cost:source.pack[item]=warehouse.restoration.cost[item]
	for tool:Dictionary in decoded.capture.world.extensions["r3:production"].tools:
		if tool.kind=="hammer":tool.holderId="pack:"+str(row.actor_id);break
	rt.retire();built=host._assemble(decoded.capture)
	if not check("pending order reloads after isolated supply fixture",built.ok,built.get("code")):host.free();return finish()
	rt=built.runtime
	var started:=false
	for i:int in 480:
		rt.tick(.1)
		var instance:Dictionary=built.services.modules.instance(warehouse.id)
		if not str(instance.project_id).is_empty():started=true
		if instance.status=="operational":break
	var result:Dictionary=built.services.modules.instance(warehouse.id)
	check("same queued order starts and restores actual warehouse",started and result.status=="operational" and result.restoration.completed,[rt.actor(str(row.actor_id)).activity,built.world.extension("r34:workforce").assignments])
	var paid:=true
	for item:String in warehouse.restoration.cost:paid=paid and float(rt.actor(str(row.actor_id)).pack.get(item,0))==0
	check("construction uses finite real resources",paid,rt.actor(str(row.actor_id)).pack)
	for i:int in 20:rt.tick(.1)
	row=built.world.extension("r34:workforce").assignments[0]
	check("completion tracks one project",row.get("building_phase")=="completed" and row.get("project_id")==result.project_id,row)
	var content:int=int(built.world.extension("r34:gameplay").get("layout",{}).get("content_version",0))
	if content>=20:
		var skill:int=int(rt.actor(str(row.actor_id)).get("skills",{}).get("village_building",0))
		check("completed warehouse restoration awards construction experience once",skill==2,skill)
	if result.status=="operational":verify_rebuild(rt,built,result,str(row.actor_id))
	rt.retire();host.free();finish()

func verify_rebuild(rt:RefCounted,built:Dictionary,warehouse:Dictionary,worker_id:String)->void:
	var modules:RefCounted=built.services.modules
	var cost:=Recovery.rebuild_cost(warehouse,modules.definition(str(warehouse.definition_id)))
	var depot_id:="test:rebuild-depot"
	var hammer_id:="test:rebuild-hammer"
	var tx:=Draft.new(modules.context)
	var worker:=tx.actor(worker_id)
	worker.merge({"thirst":100.0,"hunger":100.0,"fatigue":0.0,"stamina":100.0},true)
	tx.writable_collection("stocks").append({"id":depot_id,"items":cost.duplicate(true),"owner":warehouse.owner,"searched":true,"location":RebuildGeometry.location(worker)})
	tx.extension("r3:production").tools.append({"id":hammer_id,"kind":"hammer","holderId":depot_id,"durability":100.0})
	var destroyed:Dictionary=modules.damage_in(tx,warehouse.id,warehouse.hp,"test:lethal-warehouse")
	if not check("warehouse enters actual ruined state",destroyed.ok and rt._commit(tx.result()).ok,destroyed):return
	var request:Dictionary={"kind":"workforce.queue_building","actor_id":"player","command_id":"test:rebuild-warehouse","target_id":warehouse.id,"payload":{}}
	var issued:Dictionary=rt.command(request)
	if not check("village accepts ruined warehouse with no materials taken yet",issued.ok and rt.stock(depot_id).items==cost and rt.tool(hammer_id).get("holderId")==depot_id and modules.instance(warehouse.id).status=="ruined",issued):return
	var observed_rebuild:=false
	for i:int in 900:
		rt.tick(.1)
		var current:Dictionary=modules.instance(warehouse.id)
		var project:=Draft.find(modules.state().projects,str(current.get("project_id","")))
		if project.has("rebuild_ruin_id") and rt.tool(hammer_id).get("holderId")=="pack:"+str(project.actor_id):observed_rebuild=true
		if current.status=="operational":break
	for i:int in 12:rt.tick(.1)
	var rebuilt:Dictionary=modules.instance(warehouse.id)
	var final_order:Dictionary=built.world.extension("r34:workforce").assignments.filter(func(entry:Dictionary)->bool:return entry.get("module_id")==warehouse.id).back()
	check("automatic dispatch funds and completes the real rebuild",observed_rebuild and int(rebuilt.get("rebuild_count",0))==1 and rebuilt.status=="operational" and final_order.get("building_phase")=="completed" and final_order.get("project_id")==rebuilt.project_id,[observed_rebuild,rebuilt.get("status"),rebuilt.get("rebuild_count"),final_order,rt.tool(hammer_id)])
	for item:String in cost:
		check("finite rebuild material consumed once: "+item,rt.stock(depot_id).items.get(item,0)==0 and rt.actor(str(final_order.actor_id)).pack.get(item,0)==0)
