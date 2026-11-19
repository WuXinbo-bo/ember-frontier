extends SceneTree
## Real production input/ray/command checks with explicitly arranged fixtures.
## No OS input, live user saves, controls write or formal preview.
const Direct=preload("res://scripts/input/direct_interaction.gd")
const Router=preload("res://scripts/input/input_router.gd")
const State=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Actions=preload("res://scripts/actions/action_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Client=preload("res://scripts/runtime/native_client.gd")
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
class TestRouter extends Router:
	func _persist_bindings()->bool:return true
class Probe extends Direct:
	var cursor:=Vector2.ZERO
	func _refresh()->void:_refresh_at(cursor)
class Ground extends Node3D:
	var world:RefCounted
	func pick(a:Vector3,b:Vector3)->Dictionary:return Queries.raycast(world,a,b)
class Feedback extends Control:
	var receipts:Array=[]
	var panels:Array=[]
	func report_action(value:Dictionary)->void:receipts.append(value)
	func open_panel(page:String,id:String="")->void:panels.append([page,id])
	func notify(_text:String,_bad:bool=false)->void:pass
var checks:Array=[]
var world:=State.new()
var runtime:=Runtime.new()
var building:=Building.new()
var router:=TestRouter.new()
var direct:=Probe.new()
var scene:=Node3D.new()
var camera:=Camera3D.new()
var ground:=Ground.new()
var feedback:=Feedback.new()
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+name+" "+str(detail))
func edit(changes:Array)->bool:
	var prepared:Dictionary=world.prepare_changes(changes,world.get_revision())
	return prepared.ok and world.commit_prepared(prepared.capability).ok
func aim(at:Vector3)->void:
	camera.position=at+Vector3(12,18,14);camera.look_at(at)
	direct.cursor=camera.unproject_position(at)
	direct._refresh()
func ticks(count:int)->void:
	for i:int in count:runtime.tick(0.1);direct._process(0.1)
func run()->void:
	check("retained finite terrain fixture loads",world.load_snapshot(Rural.generate(713)).ok)
	var p:Dictionary=Production.empty_state()
	p.tools=[{"id":"probe:shovel","kind":"shovel","holderId":"pack:player","durability":90.0,"qualities":{"shovel":1}}]
	check("real production tool state prepared",edit([{"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":p}]))
	var actor:Dictionary={"id":"player","name":"input fixture","x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{"soil_m3":2.0},"intent":null,"relationship":{"consent":true}}
	check("formal runtime with B/C services configures",runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":{"terrain":Terrain.new(),"buildings":building,"actions":Actions.new(),"production":Production.new()}}).ok)
	root.add_child(scene);scene.add_child(camera);scene.add_child(ground);root.add_child(router);root.add_child(feedback);root.add_child(direct)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;camera.current=true
	ground.world=world;router.configure(runtime);router.set_physics_process(false)
	router._slots=[{"kind":"tool","id":"probe:shovel"},{},{},{},{},{},{},{},{}];router._selected=0;router._sync_hand()
	direct.configure({"runtime":runtime,"world":world,"router":router,"camera":camera,"buildings":building,"terrain":ground,"ui":feedback});direct.set_process(false)
	await process_frame
	aim(Vector3(29.75,0,30.25))
	check("real ray selects usable terrain without opening panel",direct._target.get("primary")=="terrain" and direct._target.get("enabled",false) and feedback.panels.is_empty(),direct._target)
	router._primary=true;router.primary_requested.emit(true)
	check("press starts one accepted real dig",runtime.actor("player").get("intent") is Dictionary,runtime.actor("player").get("intent"))
	ticks(40)
	check("holding crosses completed cells without reopening menu",world.cell_at(59,-1,60)==0 and float(runtime.actor("player").pack.get("soil_m3",0))>=2.25 and feedback.panels.is_empty(),{"pack":runtime.actor("player").pack,"panels":feedback.panels,"target":direct._target})
	router._primary=false;router.primary_requested.emit(false)
	var stopped:Dictionary=runtime.actor("player").pack.duplicate(true);var revision:int=world.get_revision();var wear:float=runtime.tool("probe:shovel").durability
	ticks(30)
	check("release pauses labor without more cells materials or wear",runtime.actor("player").pack==stopped and world.get_revision()==revision and is_equal_approx(wear,runtime.tool("probe:shovel").durability))
	router.set_modal(true);router.set_modal(false)
	check("modal closes without silently resuming held input",not direct._holding_primary)
	router.request("cancel")
	# A real B wall fixture blocks diagonal motion; the projected valid axis
	# must advance through the original swept body query, never through wall.
	var wall:Dictionary=building.make_instance("wall_wood","probe:wall",{"regionId":"RH-HOME","x":31.0,"y":0.0,"z":30.25},0)
	if wall.is_empty():
		for definition:Dictionary in building.geometry.definitions.values():
			if definition.get("kind")=="wall":wall=building.make_instance(definition.id,"probe:wall",{"regionId":"RH-HOME","x":31.0,"y":0.0,"z":30.25},1);break
	check("real wall fixture definition exists",not wall.is_empty())
	if not wall.is_empty():test_slide(wall)
	for seed_value:int in [713,2026]:test_opening(seed_value)
	finish()
func test_slide(wall:Dictionary)->void:
	var plan:Dictionary=building.prepare_edit([],[wall])
	check("supported real wall transaction commits",plan.ok and edit(plan.get("world_changes",[])),plan.get("reason"))
	var found:=false;var details:Array=[]
	for x:float in [30.45,30.5,30.55,30.6,30.65]:
		var a:Dictionary=runtime._facts.actors[0];a.x=x;a.y=0.0;a.z=30.1;a.intent=null
		var from:Dictionary=Geometry.location(a);var step:=Vector3(0.12,0,0.12)
		var to:=from.duplicate();to.x+=step.x;to.z+=step.z
		var blocked:Dictionary=runtime._services.actions.move_step("player",from,to)
		if blocked.ok:continue
		var z_only:=from.duplicate();z_only.z+=step.z
		if not runtime._services.actions.move_step("player",from,z_only).ok:continue
		camera.position=Vector3(0,20,20);camera.look_at(Vector3.ZERO)
		direct._move(Vector2.ONE.normalized(),step.length()/2.8)
		var after:Dictionary=runtime.actor("player");found=true
		check("blocked diagonal slides on valid axis without crossing wall",is_equal_approx(after.x,x) and after.z>float(from.z),{"before":from,"after":Geometry.location(after),"blocked":blocked});break
		details.append(blocked)
	check("sliding fixture exercises real blocked swept body",found,details)
func test_opening(seed_value:int)->void:
	var result:Dictionary=Assembly.prepare(Assembly.generate(seed_value,Building.generation_profiles()))
	check("new generated opening prepares "+str(seed_value),result.ok,result.get("reason"))
	if not result.ok:return
	var client:=Client.new();var built:Dictionary=client._assemble(result.capture)
	check("new opening uses formal assembler "+str(seed_value),built.ok,built.get("reason"))
	if built.ok:
		var r:RefCounted=built.runtime;var a:Dictionary=r.actor("village-resident");var player:Dictionary=r.actor("player")
		check("real neighbor visible at spawn without free joining or items "+str(seed_value),"village-resident" in r.actor_presentation().visible_actor_ids and a.get("buildingId")==null and Geometry.point(a).distance_to(Geometry.point(player))>=2.2 and not a.relationship.member and not a.relationship.consent and a.pack.is_empty(),{"player":Geometry.location(player),"neighbor":Geometry.location(a)})
		var scenery:Array=built.world.entities().filter(func(e:Dictionary)->bool:return e.get("data",{}).get("no_interaction",false))
		check("solid generated scenery is not labelled as a usable container "+str(seed_value),not scenery.is_empty() and scenery.all(func(e:Dictionary)->bool:return not direct._scene_entity(e)),scenery.size())
		var policy:=Policy.new();policy.configure(built.services.buildings.current_space());policy.sample(player)
		direct.buildings=built.services.buildings;direct.view_policy=policy
		var home:Dictionary=built.services.buildings.instance("RH-HOME:home:front-door")
		check("input uses the exact shared policy visibility "+str(seed_value),direct._pick_boxes(home).is_empty()==not policy.base_visible(home,"door"))
		test_nearby(built,seed_value)
	client.free()
func test_nearby(built:Dictionary,seed_value:int)->void:
	var r:RefCounted=built.runtime;var w:RefCounted=built.world;var b:RefCounted=built.services.buildings
	direct.runtime=r;direct.world=w;direct.buildings=b;direct._entity_revision=-1;direct._entities=w.entities();ground.world=w;router._runtime=r
	router._mode="tool";direct._holding_primary=false
	var query:RefCounted=b.current_space();var npc:Dictionary=r.actor("village-resident")
	var near:=Geometry.location(npc);near.z+=1.8
	var feet:Dictionary=query.standing_point(near)
	check("explicit nearby resident fixture has real support "+str(seed_value),not feet.is_empty())
	if not feet.is_empty():
		r._find("actors","player").merge(feet,true)
		aim(Geometry.point(feet)+Vector3(8,0,5))
		check("NPC is selectable nearby without hitting its thin body "+str(seed_value),direct._target.get("primary")=="npc" and direct._target.get("id")==npc.id and direct._target.get("enabled",false),direct._target)
	var state:Dictionary=w.extension("r3:production").duplicate(true);var axe:=""
	for t:Dictionary in state.tools:
		if t.get("kind")=="salvaged_axe":t.holderId="pack:player";axe=t.id;break
	var prepared:Dictionary=w.prepare_changes([b.extension_change("r3:production",state)],w.get_revision())
	check("explicit owned axe fixture uses real production definition "+str(seed_value),not axe.is_empty() and prepared.ok and w.commit_prepared(prepared.capability).ok)
	if axe.is_empty():return
	router._slots[0]={"kind":"tool","id":axe};router._selected=0;router._sync_hand()
	var found:=0;var rejected:Array=[]
	for tree:Dictionary in w.entities("RH-HOME"):
		if tree.kind!="tree":continue
		for i:int in 8:
			var angle:float=i*TAU/8.0;var candidate:=Geometry.location(tree)
			candidate.x+=cos(angle)*1.8;candidate.z+=sin(angle)*1.8
			var standing:Dictionary=query.standing_point(candidate)
			if standing.is_empty():continue
			var actor:Dictionary=r._find("actors","player");actor.merge(standing,true);actor.intent=null
			var approved:Dictionary=r.availability({"kind":"harvest","actor_id":"player","target_id":tree.id,"payload":{"tool_id":axe,"direct":true,"held":true}})
			if not approved.ok:continue
			aim(Geometry.point(standing)+Vector3(cos(angle),0,sin(angle))*5)
			if direct._target.get("primary")!="harvest" or not direct._target.get("enabled",false):rejected.append({"at":standing,"target":direct._target})
			found+=1
		if found>=8:break
	check("nearby harvest selection across supported perimeter probes "+str(seed_value),found>=8 and rejected.is_empty(),{"probes":found,"rejected":rejected})
func finish()->void:
	var report:Dictionary={"scope":"production picking/held input/runtime with explicit body fixtures; new untouched generated spawn and formal assembler; not OS/app acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report))
	direct.free();router.free();feedback.free();scene.free();quit(1 if report.failed else 0)
