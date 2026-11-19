extends SceneTree
## Exercises A's actual transaction coordinator + B's actual final-draft safety.
## Uses A's actual fixed-step loop; no harness call to terrain.advance/_commit.
const State = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Terrain = preload("res://scripts/terrain/terrain_service.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
var checks: Array = []

func test(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok: push_error("FAIL "+label+" "+str(detail))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var world := State.new()
	world.load_snapshot(Generator.generate())
	var runtime := Runtime.new()
	var terrain := Terrain.new()
	var building := Building.new()
	var actor := {"id":"player","x":28.5,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{},"intent":null,"relationship":{"consent":true}}
	# The official composition root installs the complete B seed once. These
	# pre-seed terrain checks need no stocks; do not combine two initializers.
	var configured: Dictionary = runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":{"terrain":terrain,"buildings":building}})
	test("A runtime configured with real B/C modules",configured.ok,configured)
	var malformed_ok := true
	for payload in ["bad",{"edit":"bad"},{"edit":{"cells":"bad"}},{"edit":{"material":2.5,"cells":[]}},{"edit":{"operation":"level","area":"bad"}}]:
		var invalid: Dictionary = runtime.availability({"actor_id":"player","kind":"terrain","payload":payload})
		malformed_ok = malformed_ok and not invalid.get("ok",false)
	test("malformed terrain payloads rejected without script errors",malformed_ok)
	var old_bed := {"id":"test:legacy-bed","kind":"bed","regionId":"RH-HOME","position":{"x":29.75,"y":0,"z":30.25},"bounds":{"min":{"x":29.5,"y":0,"z":30},"max":{"x":30,"y":0.6,"z":30.5}},"revision":0,"blocksTerrain":true,"data":{"sleeping":true}}
	var bed_draft: Dictionary = world.prepare_changes([{"op":"entity.put","id":old_bed.id,"before_exists":false,"before":null,"after":old_bed}],world.get_revision())
	test("legacy object fixture has no explicit supportBounds",bed_draft.ok and not old_bed.has("supportBounds"))
	if bed_draft.ok:
		world.commit_prepared(bed_draft.capability)
		var dig_bed: Dictionary = runtime.availability({"actor_id":"player","kind":"terrain","payload":{"edit":{"operation":"dig","cells":[{"x":59,"y":-1,"z":60}]}}})
		test("legacy bed foot support refused before labor/material changes",not dig_bed.ok and dig_bed.code=="ENTITY_SUPPORT",dig_bed)
		var remove_bed: Dictionary = world.prepare_changes([{"op":"entity.remove","id":old_bed.id,"before":world.entity(old_bed.id)}],world.get_revision())
		world.commit_prepared(remove_bed.capability)
	var request := {"command_id":"native-terrain-test:dig","actor_id":"player","kind":"terrain","expected_revision":runtime.get_revision(),"payload":{"edit":{"operation":"dig","cells":[{"x":59,"y":-1,"z":60}]}}}
	var start: Dictionary = runtime.command(request)
	test("real runtime command starts C labor without changing terrain/reward",start.ok and world.cell_at(59,-1,60)==1 and runtime.actor("player").pack.is_empty(),start)
	if start.ok:
		for i in 10: runtime.tick(0.1)
		var released: Dictionary = runtime.command({"command_id":"terrain:release","actor_id":"player","kind":"held","payload":{"held":false}})
		var labor_elapsed: float = runtime.actor("player").intent.elapsed
		for i in 20: runtime.tick(0.1)
		test("A held route pauses C labor without releasing facts or rewarding",released.ok and runtime.actor("player").intent.elapsed==labor_elapsed and world.cell_at(59,-1,60)==1 and runtime.actor("player").pack.is_empty(),released)
		var resumed: Dictionary = runtime.command({"command_id":"terrain:resume","actor_id":"player","kind":"held","payload":{"held":true}})
		test("A held route resumes same C intent",resumed.ok and runtime.actor("player").intent.elapsed==labor_elapsed,resumed)
		for i in 29:
			runtime.tick(0.1)
		test("A sole clock has no early reward before 4 labor seconds",world.cell_at(59,-1,60)==1 and runtime.actor("player").pack.is_empty())
		runtime.tick(0.1)
		test("world + true pack + stamina committed atomically after 4s",world.cell_at(59,-1,60)==0 and runtime.actor("player").pack.get("soil_m3")==0.125 and runtime.actor("player").intent==null,{"actor":runtime.actor("player"),"cell":world.cell_at(59,-1,60),"time":runtime.clock()})
		var before: Dictionary = runtime.facts()
		var invalid := {"command_id":"native-terrain-test:unsupported-fill","actor_id":"player","kind":"terrain","expected_revision":runtime.get_revision(),"payload":{"edit":{"operation":"fill","cells":[{"x":59,"y":2,"z":60}],"material":2}}}
		var denied: Dictionary = runtime.command(invalid)
		test("unsupported fill refused without spending",not denied.ok and runtime.facts()==before,denied)
	# The centre ray reaches this empty supported cell only through a solid cell.
	# This fixture is prepared before asking the real service; it is not gameplay.
	var barrier: Dictionary = world.prepare_changes([{"op":"voxel.set","cell":{"x":58,"y":0,"z":60},"before":0,"after":2},{"op":"voxel.set","cell":{"x":58,"y":1,"z":60},"before":0,"after":2}],world.get_revision())
	if barrier.ok:
		world.commit_prepared(barrier.capability)
		var occluded: Dictionary = runtime.availability({"actor_id":"player","kind":"terrain","payload":{"edit":{"operation":"fill","cells":[{"x":59,"y":0,"z":60}],"material":2}}})
		test("fill cannot reach through intervening solid terrain",not occluded.ok and occluded.code=="OCCLUDED",occluded)
		var remove_barrier: Dictionary = world.prepare_changes([{"op":"voxel.set","cell":{"x":58,"y":0,"z":60},"before":2,"after":0},{"op":"voxel.set","cell":{"x":58,"y":1,"z":60},"before":2,"after":0}],world.get_revision())
		world.commit_prepared(remove_barrier.capability)
	var rural: Dictionary = building.seed_rural(world)
	test("B actual complete rural proposal available",rural.get("ok",false),rural.get("reason"))
	if rural.get("ok",false):
		var draft: Dictionary = world.prepare_changes(rural.world_changes,world.get_revision())
		test("C accepts complete B rural buildings transaction",draft.get("ok",false),{"operations":rural.world_changes.size(),"reason":draft.get("reason")})
		if draft.get("ok",false):
			var facts: Dictionary = runtime.facts()
			# Match native_client._new_rural/Initial.facts: take B's complete
			# initial_stocks as the sole source, retaining all metadata verbatim.
			# Reject duplicates rather than deduplicating conflicting DTOs.
			var stock_ids := {}
			for stock in facts.stocks: stock_ids[stock.id]=stock
			var consistent := true
			for stock in rural.get("initial_stocks",[]):
				if stock_ids.has(stock.id): consistent=false
				else: facts.stocks.append(stock);stock_ids[stock.id]=stock
			test("complete seed installs exactly one unmodified fact per stock ID",consistent and facts.stocks==rural.initial_stocks)
			var safety: Dictionary = building.validate_world_draft(draft.view,facts,rural.world_changes)
			test("B verifies full C terrain + B buildings final support/body/egress",safety.get("ok",false),safety)
			world.discard_prepared(draft.capability)
	var failures := checks.filter(func(c: Dictionary)->bool:return not c.ok).size()
	terrain.configure({})
	var result := {"scope":"A/B/C actual runtime fixed step and transaction coordinator in headless domain test; not exported app acceptance","checks":checks,"failed":failures}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0],FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify(result))
	quit(1 if failures else 0)
