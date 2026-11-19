extends "res://tests/buildings/domain_suite.gd"
## Real runtime projection and original delivered rigs; explicit in-memory facts.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var view:Node3D
func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("same C fixture world loads",world.load_snapshot(Generator.generate(713)).ok)
	var outside:Dictionary={"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(outside)
	var seeded:Dictionary=building.seed_rural(world)
	expect("existing B seed supplies real finite tool definitions",seeded.ok)
	if not seeded.ok:finish(started);return
	var seed_draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("same C world accepts actual B seed",seed_draft.ok and world.commit_prepared(seed_draft.capability).ok)
	initialize_at(outside,[],seeded.initial_stocks)
	var state:Dictionary=Production.empty_state()
	state.tools=seeded.initial_tools;state.records=seeded.initial_records
	for tool:Dictionary in state.tools:tool.holderId="pack:player"
	var prepared:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,state)],world.get_revision())
	expect("finite actual tool records registered",prepared.ok and world.commit_prepared(prepared.capability).ok)
	view=Actors.new();root.add_child(view);view.configure(runtime)
	expect("delivered rig and expected anchors are bound",view._animations.has("player") and is_instance_valid(view._arms.get("player")) and is_instance_valid(view._carry_anchors.get("player")))
	select_tool("rural:v1:RH-HOME:shed:salvaged_axe")
	expect("held prop follows actual selected owned durable tool",view._props.has("player") and view._props.player.get_meta("tool_id")=="rural:v1:RH-HOME:shed:salvaged_axe")
	var before:Dictionary=runtime.capture_checkpoint()
	view.set_player_occluded(true)
	for i:int in 24:
		select_tool("rural:v1:RH-HOME:shed:hammer" if i%2==0 else "rural:v1:RH-HOME:shed:salvaged_axe")
		view.set_player_occluded(true)
		await process_frame
	var live:Array=view.roots.player.find_children("*","MeshInstance3D",true,false)
	expect("equipping while occluded keeps overlay cache bounded to live meshes",view._old_overlays.size()<=live.size(),{"cached":view._old_overlays.size(),"live_meshes":live.size()})
	view.set_player_occluded(false)
	expect("occlusion exit restores original skin and held prop overlays",live.all(func(m:Node)->bool:return m.material_overlay==null))
	expect("tool display and repeated occlusion cannot mutate authority",Data.json_equal(before,runtime.capture_checkpoint()))
	var facts:Dictionary=runtime.facts();facts.actors[0].pending_delivery={"phase":"deliver","items":{"log":1.0}};facts.actors[0].pack={}
	reconfigure(facts)
	expect("pending delivery without actual carried item produces no fake bundle",not view._carried.has("player") or not view._carried.player.visible)
	facts=runtime.facts();facts.actors[0].pack={"log":1.0};reconfigure(facts)
	expect("actual pending delivery binds original bundle and Carry action",view._carried.has("player") and view._carried.player.visible and view._states.get("player")=="Carry")
	expect("actual carry hides held tool",not view._props.has("player"))
	facts=runtime.facts();facts.actors[0].pending_delivery={};facts.actors[0].pack={};reconfigure(facts)
	expect("completed delivery hides bundle without respawning inventory",not view._carried.player.visible and runtime.actor("player").pack.is_empty())
	expect("rest starts through current public runtime schema",command("rest").ok);view.sync(0)
	expect("actual rest selects original RestLying and no tool",view._states.get("player")=="RestLying" and not view._props.has("player"))
	facts=runtime.facts();facts.actors[0].intent=null;facts.actors[0].hit_until=runtime.clock()+1.0;reconfigure(facts)
	expect("actual hit timestamp selects original Hit action",view._states.get("player")=="Hit")
	facts=runtime.facts();facts.actors[0].hit_until=0.0;reconfigure(facts)
	expect("hit expiry recovers original Idle and scale",view._states.get("player")=="Idle" and view.roots.player.scale.is_equal_approx(Vector3.ONE))
	var tool_state:Dictionary=production.state()
	var unsupported:Dictionary=tool_state.duplicate(true)
	var selected:String=view._held_ids.player
	for tool:Dictionary in unsupported.tools:
		if tool.id==selected:tool.kind="explicit-unimplemented-tool"
	var tool_draft:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,unsupported)],world.get_revision())
	expect("explicit unsupported held definition fixture commits in isolation",tool_draft.ok and world.commit_prepared(tool_draft.capability).ok)
	view.sync(0)
	var report:Dictionary=view.assembly_report()
	expect("same held ID with changed definition cannot keep old prop silently",not view._props.has("player") and not report.ok and report.required_errors.any(func(x:Dictionary)->bool:return x.actor_id=="player" and x.code=="TOOL_VIEW_UNSUPPORTED"),report)
	tool_draft=world.prepare_changes([building.extension_change(Production.KEY,tool_state)],world.get_revision())
	expect("actual tool definition restoration commits once",tool_draft.ok and world.commit_prepared(tool_draft.capability).ok)
	view.sync(0)
	expect("same ID restored supported definition recovers prop and clears error",view._props.has("player") and view.assembly_report().ok,view.assembly_report())
	before=runtime.capture_checkpoint();view.sync(0.016)
	expect("all visual state changes preserve checkpoint facts",Data.json_equal(before,runtime.capture_checkpoint()))
	view.free();finish(started)
func reconfigure(facts:Dictionary)->void:
	var receipt:Dictionary=runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}})
	if not receipt.ok:expect("state fixture accepted by real runtime",false,receipt)
	view.sync(0)
func select_tool(id:String)->void:
	runtime.set_hand({"slots":[{"kind":"tool","id":id}],"selected":0})
	view.sync(0)
func finish(started:int)->void:
	print("DDD_ACTOR "+JSON.stringify({"scope":"DDD delivered rig/actual runtime projection; no OS route or VA","ok":failures.is_empty(),"checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}))
	quit(0 if failures.is_empty() else 1)
