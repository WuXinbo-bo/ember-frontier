extends SceneTree
## Rear-side finite placement fixture reproduces the real16 management problem;
## thereafter actual public DTO/walk/cancel/search authority, no renderer/save IO.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var serial:int=0
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func send(rt:RefCounted,spec:Dictionary)->Dictionary:
	serial+=1;var request:Dictionary=spec.duplicate(true)
	request.merge({"actor_id":"player","command_id":"B:service:"+str(serial)},true)
	return rt.command(request)
func advance(rt:RefCounted,limit:int=500)->void:
	for i:int in limit:
		if rt.actor("player").intent==null:return
		rt.tick(0.1)
func edit(rt:RefCounted,changes:Array)->Dictionary:
	return rt._commit({"ok":true,"world_changes":changes,"fact_changes":[],"events":[]})
func run()->void:
	for seed:int in [713,2026]:
		var made:Dictionary=Assembly.prepare(Assembly.generate(seed,Modules.generation_profiles()))
		check("actual normal source assembles "+str(seed),made.ok)
		if not made.ok:continue
		var capture:Dictionary=made.capture;var module:Dictionary=Draft.find(capture.world.extensions[Modules.KEY].instances,"r34:generated:RH-HOME:woodwork")
		var rear:Dictionary=Shape.at(module,Vector3(0,0,3.0));var player:Dictionary=Draft.find(capture.facts.actors,"player")
		player.merge(rear,true);player.intent=null
		var host:=Native.new();var built:Dictionary=host._assemble(capture)
		check("rear-side supported body fixture restores "+str(seed),built.ok)
		if not built.ok:host.free();continue
		var rt:RefCounted=built.runtime;var services:Dictionary=built.services;var stock_id:String=module.stock_refs.tools
		var stock_before:Dictionary=rt.stock(stock_id);var pack_before:Dictionary=rt.actor("player").pack.duplicate(true);var before:Dictionary=rt.capture_checkpoint()
		check("rear is genuinely out of stock contact "+str(seed),services.production.reach("player",stock_id,stock_before,"search")!=null and not stock_before.searched)
		var guidance:Dictionary=rt.module_service_approaches(module.id)
		check("A facade consumes real B provider "+str(seed),guidance==services.modules.service_approaches("player",module.id) and guidance.available and not guidance.approaches.is_empty(),guidance)
		var tools:Dictionary=Draft.find(guidance.approaches,"tools")
		check("unsearched tools expose only real route not contents "+str(seed),tools.get("available",false) and not tools.at_service and tools.command.kind=="walk" and tools.command.destination==tools.location and tools.stock_ref==stock_id and not tools.has("items") and not tools.has("actual"),tools)
		check("guidance leaves exact authority untouched "+str(seed),Data.json_equal(before,rt.capture_checkpoint()))
		if not tools.get("available",false):host.free();continue
		var port:Dictionary=Draft.find(Shape.ports(module,Modules.definition(module.definition_id)),str(tools.port_id));var normal:Vector3=G.point(port.normal)
		var expected:String="东侧" if normal.x>0.5 else "西侧" if normal.x< -0.5 else "南侧" if normal.z>0.5 else "北侧"
		check("label follows actual rotated normal "+str(seed),tools.direction_label==expected and port.use_points.any(func(p:Dictionary)->bool:return G.point(p).distance_to(G.point(tools.location))<0.01))
		check("unknown and nonmember cannot acquire stock use points "+str(seed),not rt.module_service_approaches(module.id,"unknown-person").available and not rt.module_service_approaches(module.id,"repair-resident").available and not rt.module_service_approaches("B:unknown:module").available)
		var hidden:Array=services.modules.state().instances.filter(func(v:Dictionary)->bool:return not v.get("discovered",false))
		check("undiscovered module does not leak a route "+str(seed),not hidden.is_empty() and not rt.module_service_approaches(hidden[0].id).available)
		var copied:Dictionary=guidance.duplicate(true);guidance.approaches[0].command.destination.x+=200;guidance.approaches.clear()
		check("nested returned command is detached "+str(seed),rt.module_service_approaches(module.id)==copied and Data.json_equal(before,rt.capture_checkpoint()))
		# A real transparent solid arriving after the query invalidates its walk.
		var box:=AABB(G.point(tools.location)+Vector3(-0.38,0,-0.38),Vector3(0.76,1.9,0.76))
		var blocker:Dictionary={"id":"B:service:blocker:"+str(seed),"kind":"prop","regionId":module.region,"position":G.json_point(box.position),"bounds":G.json_box(box),"revision":rt.world.get_revision(),"blocksTerrain":false,"supportBounds":[],"data":{"solid":true,"opaque":false}}
		var added:Dictionary=edit(rt,[{"op":"entity.put","id":blocker.id,"before_exists":false,"before":null,"after":blocker}])
		check("actual obstacle commit preserves safety "+str(seed),added.ok,added.get("code"))
		var rejected:Dictionary=send(rt,tools.command)
		check("stale guidance cannot walk into a new solid "+str(seed),not rejected.ok and rt.actor("player").intent==null,rejected.get("reason"))
		var removed:Dictionary=edit(rt,[{"op":"entity.remove","id":blocker.id,"before_exists":true,"before":rt.world.entity(blocker.id),"after":null}])
		check("real removal restores public supported path "+str(seed),removed.ok and Draft.find(rt.module_service_approaches(module.id).approaches,"tools").available)
		check("original walk accepts real service feet "+str(seed),send(rt,tools.command).ok)
		rt.tick(0.1)
		check("busy guidance requires original cancel "+str(seed),not Draft.find(rt.module_service_approaches(module.id).approaches,"tools").available)
		var cancelled:Dictionary=send(rt,{"kind":"cancel","target_id":"","payload":{}})
		check("original cancel clears walk without searching or moving goods "+str(seed),cancelled.ok and rt.actor("player").intent==null and Data.json_equal(stock_before,rt.stock(stock_id)) and rt.actor("player").pack==pack_before)
		tools=Draft.find(rt.module_service_approaches(module.id).approaches,"tools")
		var walked:Dictionary=send(rt,tools.command);advance(rt)
		check("actual actor walks around shell and reaches stock face "+str(seed),walked.ok and rt.actor("player").intent==null and services.production.reach("player",stock_id,rt.stock(stock_id),"search")==null,{"activity":rt.actor("player").get("activity"),"location":G.location(rt.actor("player"))})
		check("walk alone never searches transfers or gives tools "+str(seed),Data.json_equal(stock_before,rt.stock(stock_id)) and rt.actor("player").pack==pack_before and Draft.find(rt.module_service_approaches(module.id).approaches,"tools").at_service)
		var searched:Dictionary=send(rt,{"kind":"search","target_id":stock_id,"payload":{}});advance(rt)
		check("separate original search succeeds only after actual arrival "+str(seed),searched.ok and rt.stock(stock_id).searched and rt.stock(stock_id).items==stock_before.items and rt.actor("player").pack==pack_before)
		var cold_host:=Native.new();var cold:Dictionary=cold_host._assemble(rt.capture_checkpoint());cold_host.free()
		check("Native restored module recomputes exact public service feet "+str(seed),cold.ok and cold.runtime.module_service_approaches(module.id).available and Draft.find(cold.runtime.module_service_approaches(module.id).approaches,"tools").at_service)
		host.free()
	var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	print(JSON.stringify({"ok":ok,"checks":checks,"scope":"actual A on-demand facade B provider original walk/cancel/search and CAS stale-obstacle/cold restore; explicit rear body fixture only; no OS/package/VA qualification"}));quit(0 if ok else 1)
