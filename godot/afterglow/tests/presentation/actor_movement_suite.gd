extends "res://tests/buildings/domain_suite.gd"
## A actual movement projection + B successful/blocked sweeps + original GLB.
## Explicit carry/hit facts are labelled fixtures, never natural-life/VA proof.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
const ORIGIN={"x":30.0,"y":0.0,"z":43.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
var view:Node3D
var tool_id:String
var origin:Dictionary=ORIGIN.duplicate(true)
var initial_stocks:Array=[]

func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("actual rural source loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at(ORIGIN)
	var seeded:Dictionary=building.seed_rural(world)
	initial_stocks=seeded.initial_stocks.duplicate(true)
	var prepared:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("actual B buildings install",seeded.ok and prepared.ok and world.commit_prepared(prepared.capability).ok)
	var production_state:Dictionary=Production.empty_state();production_state.tools=seeded.initial_tools;production_state.records=seeded.initial_records
	for tool:Dictionary in production_state.tools:tool.holderId="pack:player"
	tool_id=production_state.tools[0].id
	prepared=world.prepare_changes([building.extension_change(Production.KEY,production_state)],world.get_revision())
	expect("actual finite tools install",prepared.ok and world.commit_prepared(prepared.capability).ok)
	var query:RefCounted=building.current_space();var supported:Dictionary={}
	for x:float in [30.0,34.0,38.0,42.0,46.0,50.0,54.0]:
		for z:float in [43.0,47.0,51.0,55.0,59.0]:
			var candidate:Dictionary=ORIGIN.duplicate(true);candidate.x=x;candidate.z=z
			var feet:Dictionary=query.standing_point(candidate)
			if feet.is_empty():continue
			var right:Dictionary=feet.duplicate(true);right.x+=0.5
			var left:Dictionary=feet.duplicate(true);left.x-=0.5
			if query.direct_move("player",feet,right).ok and query.direct_move("player",feet,left).ok:supported=feet;break
		if not supported.is_empty():break
	expect("actual B seeded scene supplies supported clear bidirectional station",not supported.is_empty(),supported)
	if not supported.is_empty():origin=supported
	mount()
	expect("stationary actual projection starts Idle",view._states.player=="Idle")
	expect("real direct run commits",move("player","run",0.46).ok)
	view.sync(0.016)
	var animator:AnimationPlayer=view._animations.player
	expect("successful run selects original Run rather than key-request Walk",view._states.player=="Run",view.statistics())
	expect("normal run uses its original clip rate",is_equal_approx(animator.speed_scale,1.0))
	expect("owned selected tool stays attached while running",view._props.has("player") and view._props.player.get_meta("tool_id")==tool_id)
	animator.advance(0);animator.advance(0.2);var pose:Transform3D=view._arms.player.transform
	animator.advance(0.3)
	expect("actual original run limb pose advances",not view._arms.player.transform.is_equal_approx(pose))
	runtime.tick(0.1)
	expect("actual walk commits after run",move("player","walk",-0.28).ok)
	view.sync(0.016)
	expect("actual walk switches to original Walk",view._states.player=="Walk" and is_equal_approx(animator.speed_scale,1.0))
	runtime.tick(0.2);view.sync(0.016)
	expect("logical movement expiry stops gait without a wall-clock wait",view._states.player=="Idle",view.statistics())
	runtime.set_paused(true);view.sync(0.1)
	expect("paused authority freezes native animation playback",is_zero_approx(animator.speed_scale))
	runtime.set_paused(false);view.sync(0.1)
	expect("unpause has no invented run and restores neutral rate",view._states.player=="Idle" and is_equal_approx(animator.speed_scale,1.0))
	mount({"stamina":9.0})
	expect("low-stamina actual request accepts budgeted walk",move("player","run",0.28).ok)
	view.sync(0.016)
	expect("exhausted run request displays Walk from actual result",view._states.player=="Walk" and runtime.actor_presentation().movement.player.mode=="walk")
	mount({"pack":{"log":1.0},"pending_delivery":{"phase":"deliver","items":{"log":1.0}}})
	expect("actual carry fixture moves through original run budget",move("player","run",0.46).ok)
	view.sync(0.016);animator=view._animations.player
	expect("actual carried stock keeps original CarryWalk and hides tool",view._states.player=="CarryWalk" and view._carried.player.visible and not view._props.has("player"))
	expect("carried gait rate follows actual run metres per second",is_equal_approx(animator.speed_scale,4.6/2.8),animator.speed_scale)
	runtime.tick(0.1);move("player","walk",-0.28);view.sync(0.016)
	expect("same CarryWalk clip changes rate without a state change",view._states.player=="CarryWalk" and is_equal_approx(animator.speed_scale,1.0),animator.speed_scale)
	runtime.tick(0.2);view.sync(0.016)
	expect("stationary real load uses Carry at neutral rate",view._states.player=="Carry" and is_equal_approx(animator.speed_scale,1.0))
	mount({"faction":"infected"})
	expect("infected actual budget preserves original walk",move("player","run",0.22).ok)
	view.sync(0.016)
	expect("infected does not borrow human Run or cadence",view._states.player=="Walk" and is_equal_approx(view._animations.player.speed_scale,1.0))
	blocked_case()
	mount()
	move("player","run",0.46);view.sync(0.016)
	var tx:=Draft.new(actions.context);tx.actor("player").hit_until=runtime.clock()+0.18
	expect("explicit hit fixture uses existing runtime transaction",runtime._commit(tx.result()).ok)
	view.sync(0.016);animator=view._animations.player
	expect("hit interrupts real run with neutral Hit rate",view._states.player=="Hit" and is_equal_approx(animator.speed_scale,1.0))
	animator.advance(0.1)
	tx=Draft.new(actions.context);tx.actor("player").hit_until=runtime.clock()+0.25
	expect("second explicit hit timestamp commits",runtime._commit(tx.result()).ok)
	view.sync(0.016)
	expect("new hit event retriggers same one-shot state",animator.current_animation_position<0.001,animator.current_animation_position)
	runtime.set_paused(true);view.sync(0.016);var frozen:Vector3=view.roots.player.scale
	view.sync(0.2)
	expect("paused hit has neither playback nor independent wall-clock shake",is_zero_approx(animator.speed_scale) and view.roots.player.scale.is_equal_approx(frozen))
	runtime.set_paused(false);runtime.tick(0.3);view.sync(0.016)
	expect("expired real hit returns to stopped stance and neutral scale",view._states.player=="Idle" and view.roots.player.scale.is_equal_approx(Vector3.ONE))
	expect("real rest starts after locomotion expires",command("rest").ok)
	view.sync(0.016)
	expect("rest overrides gait with neutral rate and no held tool",view._states.player=="RestLying" and is_equal_approx(animator.speed_scale,1.0) and not view._props.has("player"))
	expect("real rest cancel succeeds",command("cancel").ok)
	view.sync(0.016)
	expect("rest cancel restores stationary owned tool",view._states.player=="Idle" and view._props.has("player"))
	npc_case()
	var before:Dictionary=runtime.capture_checkpoint()
	for i:int in 12:view.sync(0.016);view._animations.player.advance(0.016)
	expect("motion and interrupt rendering leave complete authority unchanged",Data.json_equal(before,runtime.capture_checkpoint()))
	view.free()
	print("DDD_MOVEMENT "+JSON.stringify({"scope":"real A/B motion + explicit carry/hit fixtures, no OS/VA","checks":checks,"failures":failures,"ok":failures.is_empty(),"elapsed_ms":Time.get_ticks_msec()-started}))
	quit(0 if failures.is_empty() else 1)

func mount(overrides:Dictionary={},at:Dictionary={})->void:
	if is_instance_valid(view):view.free()
	if at.is_empty():at=origin
	var a:Dictionary=resident("player",at.duplicate(true));a.merge(overrides,true)
	var receipt:Dictionary=runtime.configure({"world":world,"services":{"buildings":building,"actions":actions,"production":production},"facts":{"time":0.0,"status":"playing","actors":[a],"stocks":initial_stocks.duplicate(true),"actions":[],"quests":[]}})
	expect("isolated full runtime fixture accepts state",receipt.ok)
	runtime.set_hand({"slots":[{"kind":"tool","id":tool_id}],"selected":0})
	view=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)

func move(id:String,mode:String,dx:float)->Dictionary:
	var to:Dictionary=Geometry.location(runtime.actor(id));to.x+=dx;sequence+=1
	var result:Dictionary=runtime.command({"command_id":"ddd-motion:"+str(sequence),"actor_id":id,"kind":"direct_move","destination":to,"payload":{"movement_mode":mode,"movement_dt":0.1},"expected_revision":runtime.get_revision()})
	if not result.ok:print("DDD_MOVEMENT_COMMAND_REJECTED "+JSON.stringify(result))
	return result

func npc_case()->void:
	if is_instance_valid(view):view.free()
	var player_at:Dictionary=origin.duplicate(true);player_at.z+=4
	var facts:Dictionary={"time":0.0,"status":"playing","actors":[resident("player",player_at),resident("worker",origin)],"stocks":initial_stocks.duplicate(true),"actions":[],"quests":[]}
	expect("explicit two-actor fixture uses the same runtime",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	expect("NPC direct run uses same actual budget",move("worker","run",0.46).ok)
	view.sync(0.016)
	expect("motion lookup is by NPC ID without borrowing player state",view._states.worker=="Run" and view._states.player=="Idle")
	runtime.tick(0.1)
	expect("NPC direct walk commits",move("worker","walk",-0.28).ok)
	view.sync(0.016)
	expect("NPC ordinary gait uses original Walk",view._states.worker=="Walk" and is_equal_approx(view._animations.worker.speed_scale,1.0))
	var visible:Array=runtime.actor_presentation().visible_actor_ids
	expect("movement animation never grants NPC sight",view.roots.worker.visible==visible.has("worker"))

func blocked_case()->void:
	var query:RefCounted=building.current_space();var found:Dictionary={}
	for tree:Dictionary in world.entities("RH-HOME"):
		if tree.kind!="tree":continue
		for direction:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			var at:Dictionary=Geometry.location(tree);at.x+=direction.x*0.65;at.z+=direction.y*0.65
			var feet:Dictionary=query.standing_point(at)
			if feet.is_empty():continue
			var to:Dictionary=feet.duplicate(true);to.x-=direction.x*0.46;to.z-=direction.y*0.46
			if not query.direct_move("player",feet,to).ok:found={"from":feet,"to":to};break
		if not found.is_empty():break
	expect("real tree provides a supported blocked-body station",not found.is_empty())
	if found.is_empty():return
	mount({},found.from)
	var before:Dictionary=runtime.capture_checkpoint()
	expect("real body rejects tree sweep",not command("direct_move","",{"movement_mode":"run","movement_dt":0.1},found.to).ok)
	view.sync(0.016)
	expect("blocked request has no invented running gait or authority change",view._states.player=="Idle" and Data.json_equal(before,runtime.capture_checkpoint()))
