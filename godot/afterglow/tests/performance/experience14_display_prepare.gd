extends SceneTree
## Exact transaction/dependency probes; real owner and B safety, no rendering/FPS claim.
const Data=preload("res://scripts/world/world_data.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Display=preload("res://scripts/runtime/factory_display.gd")
class WorldProbe extends "res://scripts/world/world_state.gd":
	var exported:int=0
	var unexported:int=0
	func prepare_changes(changes:Array,revision:int)->Dictionary:
		exported+=1
		return super.prepare_changes(changes,revision)
	func prepare_changes_without_view(changes:Array,revision:int)->Dictionary:
		unexported+=1
		return super.prepare_changes_without_view(changes,revision)
class BuildingProbe extends "res://scripts/buildings/building_service.gd":
	var calls:int=0
	var full_calls:int=0
	var current:bool=false
	func validate_world_draft(view:RefCounted,observed:Dictionary,changes:Array)->Dictionary:
		calls+=1;current=view==context.world
		return super.validate_world_draft(view,observed,changes)
	func validate_structures(view:RefCounted,data:Dictionary,staged:Dictionary,removed:Array=[],added:Array=[])->Dictionary:
		full_calls+=1
		return super.validate_structures(view,data,staged,removed,added)
class DisplayProbe extends "res://scripts/runtime/factory_display.gd":
	var calls:int=0
	func validate_extensions(observed:Dictionary,overrides:Dictionary={})->Dictionary:
		calls+=1
		return super.validate_extensions(observed,overrides)
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func source()->Dictionary:
	var floor_cells:=PackedInt32Array();floor_cells.resize(64);floor_cells.fill(1)
	var air_cells:=PackedInt32Array();air_cells.resize(64);air_cells.fill(0)
	return {"schemaVersion":1,"worldId":"test:display-prepare","seed":713,"generatorVersion":"rural-1","revision":0,"config":{"cellSize":0.5,"chunkCells":4,"minCellY":-8,"maxCellY":40,"maxEditCells":256,"maxReach":2.5},"regions":{"r":{"id":"r","bounds":{"min":{"x":-4,"y":-4,"z":-4},"max":{"x":4,"y":8,"z":4}},"exits":[],"editAreas":[],"generated":true}},"entities":{},"extensions":{"r34:display":Display.initial()},"receipts":{},"retiredEntityIds":[],"chunks":{"0,-1,0":{"key":"0,-1,0","coord":{"x":0,"y":-1,"z":0},"cells":floor_cells,"revision":0,"resident":true,"generated":true,"generatorVersion":"rural-1"},"0,0,0":{"key":"0,0,0","coord":{"x":0,"y":0,"z":0},"cells":air_cells,"revision":0,"resident":true,"generated":true,"generatorVersion":"rural-1"}}}
func display_op(world:RefCounted,x:int=0)->Dictionary:
	var after:Dictionary=world.extension(Display.KEY)
	after.explored_tiles.append({"region_id":"r","x":x,"z":0})
	return {"op":"extension.set","id":Display.KEY,"before_exists":true,"before":world.extension(Display.KEY),"after":after}
func actor(id:String,x:float,z:float)->Dictionary:
	return {"id":id,"x":x,"y":0.0,"z":z,"regionId":"r","buildingId":null,"storeyId":null,"hp":100.0,"hunger":0.0,"thirst":0.0,"fatigue":0.0,"stamina":100.0,"pack":{},"intent":null,"skills":{},"relationship":{"member":true,"consent":true}}
func assembled()->Dictionary:
	var snapshot:Dictionary=source()
	# Both complete vertical chunks are authored; unknown sky must still reject.
	snapshot.config.minCellY=-4;snapshot.config.maxCellY=4
	var world:=WorldProbe.new();var loaded:Dictionary=world.load_snapshot(snapshot)
	if not loaded.ok:return loaded
	var runtime:=Runtime.new();var building:=BuildingProbe.new();var display:=DisplayProbe.new()
	var configured:Dictionary=runtime.configure({"world":world,"facts":{"actors":[actor("player",0.75,0.75),actor("helper",1.4,1.4)],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing","ledger":[]},"content":Content.content_lock(),"services":{"buildings":building,"display":display},"definitions":JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))})
	if not configured.ok:return configured
	display.calls=0
	return {"ok":true,"world":world,"runtime":runtime,"building":building,"display":display}
func plan(built:Dictionary)->Dictionary:
	return built.display._plan(display_op(built.world).after)
func run()->void:
	var world:=WorldProbe.new();var original:Dictionary=source()
	check("fixture passes unchanged world schema",world.load_snapshot(original).ok)
	var operations:Array=[display_op(world)]
	var standard:Dictionary=world.prepare_changes(operations,0)
	check("ordinary prepare retains public isolated view",standard.ok and standard.has("view"))
	var expected:Dictionary=standard.view.snapshot();var expected_receipt:Dictionary=standard.changes.duplicate(true)
	standard.view._state.extensions[Display.KEY].explored_tiles[0].x=999
	standard.view._state.chunks["0,-1,0"].cells.fill(0)
	world.discard_prepared(standard.capability)
	var fast:Dictionary=world.prepare_changes_without_view(operations,0)
	check("no-view prepare exposes no authority or draft view",fast.ok and not fast.has("view") and not fast.has("draft") and not fast.has("world"))
	operations[0].after.explored_tiles[0].x=777
	fast.changes.operations[0].after.explored_tiles[0].x=555
	fast.changes.operations.clear()
	check("input and public receipt edits cannot reach committed base",Data.json_equal(world.snapshot(),original))
	var committed:Dictionary=world.commit_prepared(fast.capability)
	check("private no-view capability matches untouched standard draft",committed.ok and Data.json_equal(world.snapshot(),expected) and Data.json_equal(committed.changes,expected_receipt))
	committed.changes.operations[0].after.explored_tiles[0].x=333
	check("no-view commit receipt is detached",world.extension(Display.KEY).explored_tiles[0].x==0)
	check("no-view capability remains single-use",world.commit_prepared(fast.capability).code=="PREPARED_CLOSED")
	check("no-view stale prepare still rejects",world.prepare_changes_without_view([],0).code=="STALE_WORLD_REVISION")
	var wrong:Dictionary=display_op(world,1);wrong.before={}
	check("no-view exact extension CAS still rejects",world.prepare_changes_without_view([wrong],world.get_revision()).code=="CAS_MISMATCH")
	var invalid:Dictionary=display_op(world,1);invalid.after.bad=NAN
	check("no-view extension JSON schema still rejects",world.prepare_changes_without_view([invalid],world.get_revision()).code=="INVALID_JSON_FACT")
	var one:Dictionary=world.prepare_changes_without_view([display_op(world,1)],world.get_revision())
	var two:Dictionary=world.prepare_changes_without_view([display_op(world,2)],world.get_revision())
	world.commit_prepared(one.capability)
	check("parallel no-view prepared capability stays revision fenced",world.commit_prepared(two.capability).code=="STALE_WORLD_REVISION")
	var epoch:Dictionary=world.prepare_changes_without_view([],world.get_revision())
	world.load_snapshot(original)
	check("reload epoch invalidates no-view capability",not world.commit_prepared(epoch.capability).ok)
	var tokens:Array=[]
	for i:int in 32:tokens.append(world.prepare_changes_without_view([],0).capability)
	check("no-view shares original bounded capability pool",world.prepare_changes_without_view([],0).code=="TOO_MANY_PREPARED")
	world.discard_prepared(tokens.pop_back())
	var reclaimed:Dictionary=world.prepare_changes_without_view([],0)
	check("no-view discard reclaims its original slot",reclaimed.ok)
	world.discard_prepared(reclaimed.capability);tokens.clear()
	var built:Dictionary=assembled();var baseline:Dictionary=assembled()
	check("real runtime display owner and B services configure",built.ok and baseline.ok,{"fast":built.get("code"),"baseline":baseline.get("code")})
	if not built.ok or not baseline.ok:return finish()
	var prepared:Dictionary=plan(built);var baseline_plan:Dictionary=plan(baseline)
	var old:Dictionary=baseline.world.prepare_changes(baseline_plan.world_changes,baseline.world.get_revision())
	var old_safety:Dictionary=baseline.building.validate_world_draft(old.view,baseline.runtime.facts(),baseline_plan.world_changes)
	check("original detached-view full B validation succeeds",old_safety.ok,old_safety)
	if not old_safety.ok:return finish()
	baseline.world.commit_prepared(old.capability)
	var notifications:Array=[]
	built.runtime.changed.connect(func(changes:Dictionary)->void:notifications.append(changes.duplicate(true)))
	var before_facts:Dictionary=built.runtime.facts()
	var result:Dictionary=built.runtime._commit(prepared)
	check("pure display uses only no-view prepare and current-world B",result.ok and built.world.unexported==1 and built.world.exported==0 and built.building.current,result)
	check("pure display still invokes actual owner and full B safety",built.display.calls==1 and built.building.calls==1 and built.building.full_calls==1)
	check("pure display equals original complete committed world and receipt",Data.json_equal(built.world.snapshot(),baseline.world.snapshot()) and result.get("changes",{}).get("world")==baseline_plan.world_changes)
	check("facts clock actor state and notifications retain exact semantics",Data.json_equal(before_facts,built.runtime.facts()) and notifications==[{"world":prepared.world_changes,"facts":[],"events":[],"revision":1,"actor_transitions":[]}])
	for mode:String in ["facts","events","unknown_extension","actor_release"]:
		var mixed:Dictionary=assembled();var request:Dictionary=plan(mixed)
		if mode=="facts":request.fact_changes=[{"collection":"quests","id":"test:quest","before":null,"after":{"id":"test:quest"}}]
		elif mode=="events":request.events=[{"kind":"test:display-event"}]
		elif mode=="unknown_extension":request.world_changes.append({"op":"extension.set","id":"test:unknown","before_exists":false,"before":null,"after":{"value":1}})
		else:
			var before:Dictionary=mixed.runtime.actor("helper");var after:Dictionary=before.duplicate(true);after.hp=0.0
			request.fact_changes=[{"collection":"actors","id":"helper","before":before,"after":after}]
		var receipt:Dictionary=mixed.runtime._commit(request)
		check("mixed "+mode+" returns to original detached-view full validation",receipt.ok and mixed.world.exported==1 and mixed.world.unexported==0 and mixed.building.calls==1 and mixed.building.full_calls==1 and not mixed.building.current,receipt)
	var unsafe:Dictionary=assembled()
	unsafe.runtime._facts.actors[0].y=1.0
	var unsafe_world:Dictionary=unsafe.world.snapshot();var unsafe_facts:Dictionary=unsafe.runtime.facts()
	var unsafe_result:Dictionary=unsafe.runtime._commit(plan(unsafe))
	check("pure display still rejects unsupported living body and discards capability",not unsafe_result.ok and unsafe_result.code=="SPATIAL_REJECTED" and unsafe.world.unexported==1 and unsafe.building.full_calls==1 and unsafe.world._prepared.is_empty() and Data.json_equal(unsafe_world,unsafe.world.snapshot()) and Data.json_equal(unsafe_facts,unsafe.runtime.facts()),unsafe_result)
	var geometry:Dictionary=assembled();var geometry_plan:Dictionary=plan(geometry)
	geometry_plan.world_changes.append({"op":"voxel.set","cell":{"x":1,"y":0,"z":1},"before":0,"after":2})
	var geometry_world:Dictionary=geometry.world.snapshot()
	var geometry_result:Dictionary=geometry.runtime._commit(geometry_plan)
	check("display plus real geometry uses isolated draft and rejects body collision atomically",not geometry_result.ok and geometry_result.code=="SPATIAL_REJECTED" and geometry.world.exported==1 and geometry.world.unexported==0 and not geometry.building.current and geometry.world._prepared.is_empty() and Data.json_equal(geometry_world,geometry.world.snapshot()),geometry_result)
	var rejected:Dictionary=assembled();var bad_plan:Dictionary=plan(rejected)
	bad_plan.world_changes[0].before={}
	var bad_receipt:Dictionary=rejected.runtime._commit(bad_plan)
	check("runtime pure display cannot bypass exact CAS",not bad_receipt.ok and bad_receipt.code=="CAS_MISMATCH" and rejected.world.get_revision()==0 and rejected.building.calls==0,bad_receipt)
	var malformed:Dictionary=assembled();bad_plan=plan(malformed);bad_plan.world_changes[0].after.explored_tiles=[{"region_id":"r","x":0.5,"z":0}]
	bad_receipt=malformed.runtime._commit(bad_plan)
	check("real display owner rejects malformed state before either prepare",not bad_receipt.ok and bad_receipt.code=="INVALID_DISPLAY_STATE" and malformed.world.exported==0 and malformed.world.unexported==0,bad_receipt)
	var unsupported:Dictionary=assembled();bad_plan=plan(unsupported)
	bad_plan.world_changes.append({"op":"extension.set","id":"r34:unknown","before_exists":false,"before":null,"after":{"version":1}})
	bad_receipt=unsupported.runtime._commit(bad_plan)
	check("unknown factory owner remains rejected",not bad_receipt.ok and bad_receipt.code=="UNSUPPORTED_FACTORY_EXTENSION" and unsupported.world.exported==0 and unsupported.world.unexported==0,bad_receipt)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"scope":"Exact no-view capability isolation/CAS/epoch/capacity; real runtime display owner and full B body safety; standard-view differential; mixed transaction fallback. No graphics or FPS measurement."}
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print("DISPLAY_PREPARE "+JSON.stringify(result));quit(1 if failed else 0)
