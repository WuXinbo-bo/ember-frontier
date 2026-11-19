extends SceneTree
## Targeted new-input regression: A's actual brush payload/router/runtime and
## B's validator/actions/production. No formal app, save slot or controls write.
const State = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Codec = preload("res://scripts/world/world_codec.gd")
const Queries = preload("res://scripts/terrain/terrain_queries.gd")
const Terrain = preload("res://scripts/terrain/terrain_service.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Router = preload("res://scripts/input/input_router.gd")
const Direct = preload("res://scripts/input/direct_interaction.gd")
var checks: Array = []
var shared_gaps: Array = []
var world := State.new()
var runtime := Runtime.new()
var router := Router.new()
var direct := Direct.new()
var production := Production.new()
var buildings := Building.new()

class Feedback extends Control:
	var receipt: Dictionary = {}
	func report_action(value: Dictionary) -> void: receipt = value

func check(label: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok: push_error("FAIL "+label+" "+str(detail))

func setup(changes: Array) -> bool:
	var p: Dictionary = world.prepare_changes(changes,world.get_revision())
	if not p.ok: check("fixture transaction prepared",false,p);return false
	var c: Dictionary = world.commit_prepared(p.capability)
	return c.ok

func extension(id: String,value: Dictionary) -> void:
	setup([{"op":"extension.set","id":id,"before_exists":world.has_extension(id),"before":world.extension(id),"after":value}])

func steps(count: int) -> void:
	for i in count: runtime.tick(0.1)

func payload(cell: Dictionary,operation: String,normal: Vector3=Vector3.UP,width: int=1,height: float=0.0) -> Dictionary:
	router.set_terrain_brush(operation,2,height,width)
	var p: Dictionary = Direct.terrain_payload({"cell":cell,"normal":normal},router.state().terrain,operation,0.5)
	p.merge({"tool_id":"fixture:shovel","held":true,"requires_hold":operation!="fill"},true)
	return p

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var loaded := world.load_snapshot(Generator.generate(713))
	check("current finite rural world loaded",loaded.ok)
	var p := Production.empty_state()
	p.tools=[{"id":"fixture:shovel","kind":"shovel","holderId":"pack:player","durability":90.0,"qualities":{"shovel":1}}]
	extension("r3:production",p)
	var actor := {"id":"player","name":"test","x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{"soil_m3":2.0},"intent":null,"relationship":{"consent":true}}
	var ready: Dictionary = runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":{"terrain":Terrain.new(),"buildings":buildings,"actions":Actions.new(),"production":production}})
	check("actual A router/runtime plus B/C modules configured",ready.ok,ready)
	root.add_child(router);router.configure(runtime);router.set_physics_process(false)
	# Wire the same production signal handlers while excluding cursor/camera/UI
	# rendering. Actual physical aiming remains A's formal-app acceptance item.
	direct.runtime=runtime;direct.world=world;direct.router=router
	direct.ui=Feedback.new();direct._ghost=MeshInstance3D.new()
	router.primary_requested.connect(direct._primary)
	router.cancel_requested.connect(direct._cancel)
	check("half-metre brush height accepted",router.set_terrain_brush("level",2,-0.5,2).ok)
	check("quarter-metre and unsupported width rejected",not router.set_terrain_brush("level",2,-0.25,2).ok and not router.set_terrain_brush("dig",2,0,3).ok)
	var cell := {"x":59,"y":-1,"z":60}
	var hit := Queries.raycast(world,Vector3(29.75,2,30.25),Vector3(29.75,-2,30.25))
	check("stable cell target carries actual world revision",hit.get("target_id")=="terrain:59:-1:60" and hit.cell==cell and hit.world_revision==world.get_revision(),hit)
	# Ray enters X/Y simultaneously: normal must describe one actual face.
	var corner := Queries.raycast(world,Vector3(29.5,0.5,30.25),Vector3(30.5,-0.5,30.25))
	check("edge tie returns one face rather than a diagonal fill offset",corner.has("normal") and is_equal_approx(corner.normal.length(),1.0),corner)
	var fill_adjacent := payload(cell,"fill",Vector3.RIGHT)
	check("real A payload fills face-adjacent cell",fill_adjacent.edit.cells==[{"x":60,"y":-1,"z":60}],fill_adjacent)
	for operation in ["dig","fill"]:
		var wide := payload(cell,operation,Vector3.UP,2)
		check("real A "+operation+" two-cell payload expands four face cells",wide.edit.cells.size()==4,wide)
		if wide.edit.cells.size()!=4:
			shared_gaps.append({"owner":"A input/direct_interaction.gd","case":"2-cell "+operation,"api":"set_terrain_brush","brush":router.state().terrain,"actual_payload":wide,"expected":"four cells on selected face; dig/fill currently ignore brush_cells"})
	var dig := payload(cell,"dig")
	var started: Dictionary = router.request("terrain",hit.target_id,dig)
	check("actual router starts dig without early terrain/material change",started.ok and world.cell_at(59,-1,60)==1 and runtime.actor("player").pack.soil_m3==2.0,started)
	steps(5)
	var elapsed: float = runtime.actor("player").intent.elapsed
	router.set_modal(true)
	var paused_clock := runtime.clock()
	steps(30)
	check("modal releases held and freezes sole clock/progress",runtime.clock()==paused_clock and runtime.actor("player").intent.elapsed==elapsed and not runtime.actor("player").intent.held)
	router.set_modal(false);steps(5)
	check("closing modal does not silently resume held labor",runtime.actor("player").intent.elapsed==elapsed)
	router.request("held","",{"held":true});steps(10)
	check("dig commits exact half-metre cell, material and .1 tool wear",world.cell_at(59,-1,60)==0 and is_equal_approx(runtime.actor("player").pack.soil_m3,2.125) and is_equal_approx(runtime.tool("fixture:shovel").durability,89.9),runtime.actor("player"))
	var fill := payload({"x":59,"y":-2,"z":60},"fill")
	var filled: Dictionary = router.request("terrain","terrain:59:-2:60",fill)
	router.primary_requested.emit(false);steps(15)
	check("right-click fill continues across left release and spends once",filled.ok and world.cell_at(59,-1,60)==2 and is_equal_approx(runtime.actor("player").pack.soil_m3,2.0),filled)
	var level := payload(cell,"level",Vector3.UP,2,-1.0)
	check("real A two-cell level expands exact 1m square",level.edit.area=={"minI":59,"maxI":61,"minK":60,"maxK":62} and level.edit.height==-1.0,level)
	var road_tool: Dictionary = runtime.availability({"actor_id":"player","kind":"terrain","payload":level})
	check("a shovel alone cannot excavate road inside level selection",not road_tool.ok and road_tool.code=="MISSING_TOOL",road_tool)
	# Explicit dual-quality fixture exercises this mixed soil/road selection;
	# production tool definitions and original tool wear are not relaxed/reset.
	var mixed_tool: Dictionary = world.extension("r3:production")
	mixed_tool.tools[0].qualities.pickaxe=1
	extension("r3:production",mixed_tool)
	var leveling: Dictionary = router.request("terrain",hit.target_id,level)
	check("multi-layer downward level is not blocked by its own selected top layer",leveling.ok,leveling)
	if leveling.ok:
		steps(5);router.cancel()
		check("actual router/direct cancel leaves selected ground and materials unchanged",runtime.actor("player").intent==null and world.cell_at(59,-1,60)==2 and runtime.actor("player").pack.soil_m3==2.0)
		var again: Dictionary = router.request("terrain",hit.target_id,level)
		steps(120)
		var level_ok: bool = again.ok and runtime.actor("player").intent==null
		for z in range(60,62):
			for x in range(59,61): level_ok=level_ok and world.surface_height((x+0.5)*0.5,(z+0.5)*0.5)==-1.0
		check("full two-cell by two-layer level completes through real A clock",level_ok,runtime.actor("player"))
	# Real production reservation queries, explicit inactive-world fixture only;
	# no fake gameplay rewards or direct runtime-private commit calls.
	# Full structure-order DTO, matching Actions.start_structure. Its explicit
	# synthetic soil cost isolates cross-provider reservation without creating
	# a building or changing any production catalogue/cost. targetId must remain
	# present: the standard hold also reports the actual use-target identity.
	var held_instance:Dictionary=buildings.make_instance("floor","fixture:reserved-floor",{"x":40.0,"y":0.0,"z":40.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	extension("r3:structure-orders",{"version":1,"orders":[{"id":"fixture:reservation","kind":"place","actorId":"player","targetId":held_instance.id,"instance":held_instance,"destination":null,"sourceId":"pack:player","outputId":null,"targetVersion":null,"cost":{"soil_m3":float(runtime.actor("player").pack.soil_m3)},"toolId":null,"seconds":10.0,"elapsed":0.0,"status":"active","reason":null}]})
	var reserved: Dictionary = router.request("terrain","terrain:59:-3:60",payload({"x":59,"y":-3,"z":60},"fill"))
	check("existing material reservations cannot be spent by terrain",not reserved.ok and reserved.code=="MATERIAL_RESERVED",reserved)
	extension("r3:structure-orders",{"version":1,"orders":[]})
	var tool_state: Dictionary = world.extension("r3:production")
	tool_state.orders=[{"id":"fixture:tool-order","kind":"harvest","actorId":"player","targetId":"rural:v1:RH-HOME:tree:02","status":"active","duration":24.0,"elapsed":0.0,"sourceId":"pack:player","outputId":"pack:player","toolIds":["fixture:shovel"]}]
	extension("r3:production",tool_state)
	var tool_denied: Dictionary = router.request("terrain","terrain:59:-3:60",payload({"x":59,"y":-3,"z":60},"fill"))
	check("production-reserved tool denied before work",not tool_denied.ok and tool_denied.code=="TOOL_RESERVED",tool_denied)
	tool_state.orders=[];extension("r3:production",tool_state)
	var missing_tool := payload({"x":59,"y":-3,"z":60},"fill");missing_tool.tool_id="fixture:missing"
	check("missing tool cannot start or award material",not router.request("terrain","",missing_tool).ok)
	# This 1m brush crosses z=32m (cell 63/64, adjacent chunks) and stays clear
	# of the actor's actual support footprint. All requests use A's new payload.
	var wide_cell := {"x":57,"y":-1,"z":63}
	var wide_dig := payload(wide_cell,"dig",Vector3.UP,2)
	setup([{"op":"voxel.set","cell":{"x":58,"y":0,"z":62},"before":0,"after":2}])
	var obstructed: Dictionary = runtime.availability({"actor_id":"player","kind":"terrain","payload":wide_dig})
	check("batch visibility never ignores an unselected intervening solid",not obstructed.ok and obstructed.code=="OCCLUDED",obstructed)
	setup([{"op":"voxel.set","cell":{"x":58,"y":0,"z":62},"before":2,"after":0}])
	var obstacle := {"id":"fixture:solid-obstacle","kind":"object","regionId":"RH-HOME","position":{"x":29.25,"y":0,"z":31.25},"bounds":{"min":{"x":28.5,"y":0,"z":31.0},"max":{"x":29.75,"y":1.5,"z":31.5}},"revision":0,"blocksTerrain":true,"data":{"solid":true,"opaque":true}}
	setup([{"op":"entity.put","id":obstacle.id,"before_exists":false,"before":null,"after":obstacle}])
	var entity_blocked: Dictionary = runtime.availability({"actor_id":"player","kind":"terrain","payload":wide_dig})
	check("batch ray retains real intervening non-structure entity obstruction",not entity_blocked.ok and entity_blocked.code=="OCCLUDED",entity_blocked)
	setup([{"op":"entity.remove","id":obstacle.id,"before":world.entity(obstacle.id)}])
	var wall: Dictionary = buildings.make_instance("wall","fixture:sight-wall",{"x":29.0,"y":0,"z":31.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var wall_plan: Dictionary = buildings.prepare_edit([],[wall])
	check("actual B wall fixture validates on original ground",wall_plan.ok,wall_plan.get("reason"))
	if wall_plan.ok:
		setup(wall_plan.world_changes)
		var wall_blocked: Dictionary = runtime.availability({"actor_id":"player","kind":"terrain","payload":wide_dig})
		check("actual B sight geometry still blocks terrain work through wall",not wall_blocked.ok and wall_blocked.code=="OCCLUDED",wall_blocked)
		var remove_wall: Dictionary = buildings.prepare_edit([wall.id],[])
		if remove_wall.ok: setup(remove_wall.world_changes)
	var wide_started: Dictionary = router.request("terrain","terrain:57:-1:63",wide_dig)
	check("two-cell dig crossing adjacent chunks starts through actual router",wide_started.ok,wide_started)
	if wide_started.ok: steps(60)
	var dug_all := true
	for c in wide_dig.edit.cells: dug_all=dug_all and world.cell_at(c.x,c.y,c.z)==0
	check("all four brush cells actually commit across neighbour boundary",dug_all)
	if dug_all:
		var wide_fill := payload({"x":57,"y":-2,"z":63},"fill",Vector3.UP,2)
		var refill: Dictionary = router.request("terrain","terrain:57:-2:63",wide_fill)
		check("two-cell face-adjacent fill starts through actual router",refill.ok,refill)
		if refill.ok: steps(60)
		var filled_all := true
		for c in wide_fill.edit.cells: filled_all=filled_all and world.cell_at(c.x,c.y,c.z)==2
		check("all four real fill cells commit and release intent",filled_all and runtime.actor("player").intent==null)
	var encoded: Dictionary = Codec.encode_checkpoint(world.snapshot(),{"runtime":runtime.facts()},"section8:revisit")
	var decoded: Dictionary = Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var revisit := State.new()
	var restored: Dictionary = revisit.load_snapshot(decoded.state) if decoded.ok else decoded
	check("edit survives codec restore and stable target identity on revisit",restored.ok and revisit.surface_height(29.75,30.25)==-1.0 and Queries.raycast(revisit,Vector3(29.75,2,30.25),Vector3(29.75,-2,30.25)).get("target_id")=="terrain:59:-3:60",restored)
	var failed := checks.filter(func(c: Dictionary)->bool:return not c.ok).size()
	var result := {"scope":"section8 real A payload/router/runtime + B/C domain checks; no physical cursor/app acceptance","checks":checks,"failed":failed,"shared_input_gaps":shared_gaps}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify(result))
	direct._ghost.free();direct.ui.free();direct.free();router.free()
	quit(1 if failed else 0)
