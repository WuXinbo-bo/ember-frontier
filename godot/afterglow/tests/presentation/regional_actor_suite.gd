extends "res://tests/buildings/domain_suite.gd"
## Explicit owner DTO over actual runtime/original rigs; not B work settlement.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
const WorkingItem=preload("res://scripts/presentation/regional_work_item.gd")
class PresentedRuntime extends "res://scripts/runtime/game_runtime.gd":
	var fixture:Dictionary={}
	var fixture_intent:Variant=null
	var moving:bool=false
	func actor_presentation()->Dictionary:
		var result:Dictionary=super.actor_presentation()
		result.actors[0].intent=fixture_intent
		result.work={"player":fixture.duplicate(true)}
		if moving:result.movement={"player":{"moving":true,"speed":1.0,"mode":"walk"}}
		return result
func run()->void:
	runtime=PresentedRuntime.new()
	expect("real source world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var tools:Dictionary=Production.empty_state();tools.tools=[{"id":"fixture:shovel","kind":"shovel","holderId":"pack:player","durability":1.0,"qualities":{}}]
	var prepared:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,tools)],world.get_revision())
	expect("finite owned original shovel registers",prepared.ok and world.commit_prepared(prepared.capability).ok)
	var finite:Dictionary=runtime.facts();finite.actors[0].pack["r34:water_bucket"]=1;finite.actors[0].pack["r34:raw_water"]=1
	expect("finite reusable bucket fixture registers actual pack",runtime.configure({"world":world,"facts":finite,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var before:Dictionary=runtime.capture_checkpoint()
	var view:=Actors.new();root.add_child(view);view.set_process(false)
	runtime.fixture_intent={"owner":"zonework","kind":"zonework","held":true}
	runtime.fixture={"owner":"zonework","kind":"zonework","operation":"till","tool_id":"fixture:shovel","progress_seconds":.2,"duration_seconds":8.0,"effective_work":true,"paused_reason":"","contact":{"position":[30.0,.03,43.8],"normal":[0.0,1.0,0.0]}}
	view.configure(runtime)
	expect("zonework displays actual tool from owner DTO despite no intent tool field",view._states.player=="Use" and view._held_ids.player=="fixture:shovel" and view._props.player.get_meta("tool_kind")=="shovel")
	for operation:String in ["sow","water","compost","harvest_crop","collect_seed","nursery","draw_raw_water","cook"]:
		runtime.fixture.operation=operation;runtime.fixture.tool_id="";runtime.fixture.progress_seconds=.2
		runtime.fixture.source_id="pack:player";runtime.fixture.cost={"r34:raw_water":1} if operation=="water" else {}
		view.sync(0)
		expect("real empty-hand operation has no phantom tool "+operation,not view._props.has("player") and view._states.player=="Use" and view.statistics().work.player.get("posture",{}).get("operation")==operation)
		var arm:Transform3D=view._arms.player.transform
		var body:Transform3D=view._arms.player.get_parent().transform
		view.sync(.8)
		expect("render delta cannot advance accepted operation "+operation,view._arms.player.transform.is_equal_approx(arm) and view._arms.player.get_parent().transform.is_equal_approx(body))
		runtime.fixture.progress_seconds=.7;view.sync(0)
		expect("owner seconds drive distinct hand action "+operation,not view._arms.player.transform.is_equal_approx(arm))
		runtime.set_paused(true);view.sync(.1)
		arm=view._arms.player.transform;body=view._arms.player.get_parent().transform
		view.sync(1.0)
		expect("global pause freezes original joints "+operation,view._arms.player.transform.is_equal_approx(arm) and view._arms.player.get_parent().transform.is_equal_approx(body))
		runtime.set_paused(false)
	runtime.fixture.operation="draw_raw_water";runtime.fixture.tool_id="";runtime.fixture.progress_seconds=.2;view.sync(0)
	expect("actual reusable bucket appears only for accepted drawing",view._work_items.has("player") and view._work_items.player.get_meta("actual_pack_quantity")==1)
	var attachment:Node3D=view._work_items.player
	expect("real handle follows animated palm without moving actor",attachment.global_position.distance_to(view._arms.player.to_global(Vector3(0,-.51,.06)))<.00001 and attachment.global_basis.is_equal_approx(Basis.IDENTITY))
	view.sync(.3)
	expect("unchanged work reuses exact bucket node",view._work_items.player==attachment)
	runtime.set_paused(true);runtime.fixture.effective_work=false;view.sync(.1);var frozen:Transform3D=attachment.global_transform
	view.sync(1)
	expect("global pause freezes attached container",view._work_items.player==attachment and attachment.global_transform.is_equal_approx(frozen))
	runtime.set_paused(false);runtime.fixture.effective_work=true
	runtime.fixture.operation="sow";view.sync(0)
	expect("different real operation cannot retain water bucket",not view._work_items.has("player"))
	var drawing:Dictionary={"owner":"zonework","kind":"zonework","operation":"draw_raw_water","available":true,"active":true}
	expect("promised bucket cannot substitute actual pack item",WorkingItem.item_for({"pack":{},"pending_delivery":{"items":{"r34:water_bucket":1}}},drawing).is_empty())
	expect("absent invalid or partial tool quantities never invent bucket",[null,0,-1,.5,NAN,INF,"1"].all(func(q:Variant)->bool:return WorkingItem.item_for({"pack":{"r34:water_bucket":q}},drawing).is_empty()))
	runtime.fixture.operation="water";runtime.fixture.source_id="pack:player";runtime.fixture.cost={"r34:raw_water":1};view.sync(0)
	expect("actual owner pack cost displays raw-water can and never free bucket",view._work_items.has("player") and view._work_items.player.get_meta("item_id")=="r34:raw_water" and view._work_items.player.get_meta("actual_pack_quantity")==1)
	attachment=view._work_items.get("player")
	expect("raw water handle stays on original palm",is_instance_valid(attachment) and attachment.global_position.distance_to(view._arms.player.to_global(Vector3(0,-.51,.06)))<.00001)
	runtime.fixture.source_id="fixture:remote-stock";view.sync(0)
	expect("remote stock cost cannot borrow personal pack water-can image",not view._work_items.has("player"))
	runtime.fixture.source_id="pack:player";runtime.fixture.erase("cost");view.sync(0)
	expect("missing exact owner cost fails closed instead of guessing water use",not view._work_items.has("player"))
	var pouring:Dictionary={"owner":"zonework","kind":"zonework","operation":"water","available":true,"active":true,"source_id":"pack:player","cost":{"r34:raw_water":1}}
	expect("actual water quantity must be finite and at least accepted cost",[null,0,-1,.5,NAN,INF,"1"].all(func(q:Variant)->bool:return WorkingItem.item_for({"id":"player","pack":{"r34:raw_water":q}},pouring).is_empty()))
	runtime.fixture.cost={"r34:raw_water":1};view.sync(0)
	expect("restored exact pack source reuses correct physical representation",view._work_items.has("player") and view._work_items.player.get_meta("item_id")=="r34:raw_water")
	runtime.fixture.effective_work=false;runtime.fixture.paused_reason="missing_input";view.sync(0)
	expect("blocked regional work exits Use and restores original joints",view._states.player=="Idle" and not view._work_postures.has("player"))
	runtime.fixture.effective_work=true;runtime.fixture.paused_reason="";runtime.moving=true;view.sync(0)
	expect("real route motion cannot prematurely sow or harvest",view._states.player=="Walk")
	runtime.fixture_intent.steps=[{"kind":"move"}];runtime.fixture_intent.step=0.0;view.sync(0)
	expect("integer-valued JSON route cursor cannot work before last segment",view._states.player=="Walk")
	runtime.fixture_intent.step=1.0;view.sync(0)
	expect("completed JSON route plus actual effective work supersedes historical moving",view._states.player=="Use")
	runtime.fixture.effective_work=false;view.sync(0)
	expect("completed route without effective labor cannot invent Use",view._states.player=="Walk")
	runtime.fixture.effective_work=true
	runtime.moving=false;runtime.fixture_intent=null;view.sync(0)
	expect("cancel drops stale regional progress",view._states.player=="Idle" and not view._manual_work.has("player"))
	expect("all display operations preserve world tools stock and accepted intent",Data.json_equal(before,runtime.capture_checkpoint()))
	view.free();await process_frame
	var result:Dictionary={"scope":"finite public DTO consumer over actual runtime and original GLBs; not real B jobs, native PCK, renderer/OS/VA/FPS","checks":checks,"failures":failures}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DDD_REGIONAL_ACTOR ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
