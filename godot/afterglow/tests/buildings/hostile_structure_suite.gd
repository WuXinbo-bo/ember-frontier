extends "res://tests/buildings/domain_suite.gd"
## Explicit hostile/contact fixtures; actual B safety, C world and A Draft/commit.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
var baseline_world:Dictionary
var baseline_facts:Dictionary
const GATE:="rural:v1:RH-HOME:old-house:yard-gate"

func reset()->void:
	world.load_snapshot(baseline_world)
	runtime.configure({"world":world,"facts":baseline_facts,"services":{"buildings":building,"actions":actions,"production":production}})

func unchanged_failure(label:String,tx:RefCounted,actor_id:String,target:String=GATE)->void:
	var before:Dictionary=tx.result()
	var result:Dictionary=building.strike_structure(tx,actor_id,target)
	expect(label,not result.ok and tx.result()==before,result.get("reason"))

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("actual C rural world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":29.2,"y":0,"z":40.2,"regionId":"RH-HOME"})
	var seeded:=building.seed_rural(world)
	var prepared:=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("actual B structures seed",prepared.ok and world.commit_prepared(prepared.capability).ok)
	var enemy:=resident("infected:bbb:one",{"x":27.2,"y":0,"z":40.2,"regionId":"RH-HOME"})
	enemy.faction="infected";enemy.cooldown=0.0;enemy.wounds=[]
	var second:=enemy.duplicate(true);second.id="infected:bbb:two";second.z=39.8
	initialize_at({"x":29.2,"y":0,"z":40.2,"regionId":"RH-HOME"},[enemy,second],seeded.initial_stocks)
	var p:=Production.empty_state();p.tools=seeded.initial_tools;p.records=seeded.initial_records
	# Match native_client._new_world: gameplay reads the canonical orders
	# extension even before the first construction. An absent fixture extension
	# otherwise stages an invalid fallback during its first quest update.
	prepared=world.prepare_changes([building.extension_change(Production.KEY,p),building.extension_change("r3:structure-orders",{"version":1,"orders":[]})],world.get_revision())
	expect("finite original stocks and tool durability installed",prepared.ok and world.commit_prepared(prepared.capability).ok)
	expect("canonical empty structure orders match formal native initialization",world.extension("r3:structure-orders")=={"version":1,"orders":[]})
	baseline_world=world.snapshot();baseline_facts=runtime.facts()
	var live_view:Node3D=building.create_view({"runtime":runtime})
	var static_ids:Dictionary={};var object_ids:Dictionary={}
	for key in live_view.static_nodes:static_ids[key]=live_view.static_nodes[key].get_instance_id()
	for id in live_view.objects:object_ids[id]=live_view.objects[id].get_instance_id()
	var tx:=Draft.new(building.context)
	var first:=building.strike_structure(tx,enemy.id,GATE)
	expect("real touching hostile hit stages inside same draft",first.ok,first.get("reason"))
	expect("preparing hostile hit never mutates live HP or facts",world.snapshot()==baseline_world and runtime.facts()==baseline_facts)
	var view_started:=Time.get_ticks_usec()
	var committed:=runtime._commit(tx.result()) if first.ok else first
	var view_commit_ms:=float(Time.get_ticks_usec()-view_started)/1000
	var replaced:=0
	for key in static_ids:
		if not live_view.static_nodes.has(key) or live_view.static_nodes[key].get_instance_id()!=static_ids[key]:replaced+=1
	var furniture_replaced:=0
	for id in object_ids:
		if not live_view.objects.has(id) or live_view.objects[id].get_instance_id()!=object_ids[id]:furniture_replaced+=1
	print("HOSTILE_VIEW_SAMPLE "+JSON.stringify({"commit_cpu_ms":view_commit_ms,"static_batches":static_ids.size(),"recreated_batches":replaced,"furniture":object_ids.size(),"recreated_furniture":furniture_replaced,"scope":"headless native commit including safety and live presentation; no GPU/FPS or official app claim"}))
	expect("nonlethal door HP update preserves all static batches and furniture",replaced==0 and furniture_replaced==0 and live_view.doors[GATE].piece.hp==48)
	expect("A commits hostile HP and cooldown atomically",committed.ok and building.instance(GATE).hp==48 and runtime.actor(enemy.id).cooldown==1.3,committed.get("reason"))
	expect("same authoritative entity matches damaged extension",world.entity(GATE).data.structure==building.instance(GATE))
	expect("hostile damage spends no player stock or tool durability",runtime.actor("player").pack==baseline_facts.actors[0].pack and production.state()==p)
	expect("actual structure hit event carries target and damage",runtime.facts().get("ledger",[]).any(func(e:Dictionary)->bool:return e.kind=="structure-damaged" and e.target_id==GATE and e.damage==12 and e.hostile))
	live_view.free()
	unchanged_failure("same hostile cannot hit twice during A cooldown",Draft.new(building.context),enemy.id)
	reset();tx=Draft.new(building.context);tx.actor(enemy.id).hp=0
	unchanged_failure("dead hostile rejected without staging side effects",tx,enemy.id)
	reset();tx=Draft.new(building.context);tx.actor(enemy.id).stunned_until=runtime.clock()+0.5
	unchanged_failure("stunned hostile rejected without staging side effects",tx,enemy.id)
	reset();tx=Draft.new(building.context);tx.actor(enemy.id).x=25
	unchanged_failure("remote hostile rejected without staging side effects",tx,enemy.id)
	reset();unchanged_failure("player cannot bypass tools and ownership through hostile API",Draft.new(building.context),"player")
	reset();tx=Draft.new(building.context);tx.actor(enemy.id).regionId="RH-VILLAGE"
	unchanged_failure("other region cannot damage a nearby coordinate",tx,enemy.id)
	reset();tx=Draft.new(building.context);tx.extension(Building.EXTENSION).instances.filter(func(v:Dictionary)->bool:return v.id==GATE)[0].protected=true
	unchanged_failure("protected gate rejected without staging side effects",tx,enemy.id)
	reset();tx=Draft.new(building.context)
	var one:=building.strike_structure(tx,enemy.id,GATE)
	var two:=building.strike_structure(tx,second.id,GATE)
	var operations:Array=tx.result().world_changes.filter(func(op:Dictionary)->bool:return op.op=="entity.put" and op.id==GATE)
	committed=runtime._commit(tx.result()) if one.ok and two.ok else {"ok":false,"reason":[one.get("reason"),two.get("reason")]}
	expect("two same-step enemies merge original CAS and final HP",committed.ok and operations.size()==1 and building.instance(GATE).hp==36,committed.get("reason"))
	reset()
	var occluder:Dictionary={"id":"bbb:hostile-occluder","kind":"prop","regionId":"RH-HOME","position":{"x":27.8,"y":0,"z":40.2},"bounds":{"min":{"x":27.75,"y":0,"z":39.5},"max":{"x":27.85,"y":2,"z":40.5}},"revision":0,"blocksTerrain":true,"supportBounds":[],"data":{"solid":true,"opaque":true}}
	prepared=world.prepare_changes([{"op":"entity.put","id":occluder.id,"before_exists":false,"before":null,"after":occluder}],world.get_revision())
	expect("explicit real occluding prop fixture installs",prepared.ok and world.commit_prepared(prepared.capability).ok)
	unchanged_failure("closer solid occludes hostile contact line",Draft.new(building.context),enemy.id)
	reset()
	var destroyed_view:Node3D=building.create_view({"runtime":runtime})
	for i in 5:
		tx=Draft.new(building.context);tx.actor(enemy.id).cooldown=0.0
		var hit:=building.strike_structure(tx,enemy.id,GATE)
		var result:=runtime._commit(tx.result()) if hit.ok else hit
		expect("real repeated separate contact transaction "+str(i),result.ok,result.get("reason"))
	expect("zero HP door loses collision and releases locked blocked flags",building.instance(GATE).hp==0 and building.instance(GATE).door.open and not building.instance(GATE).door.locked and not building.instance(GATE).door.blocked and building.geometry.boxes(building.instance(GATE)).is_empty())
	expect("fatal hit removes the real gate from the same live view",not destroyed_view.doors.has(GATE))
	tx=Draft.new(building.context);tx.actor(enemy.id).cooldown=0.0
	unchanged_failure("destroyed door cannot receive phantom damage even after cooldown",tx,enemy.id)
	var save:=world.snapshot();var saved_facts:=runtime.facts()
	expect("destroyed door and hostile facts restore validly",world.load_snapshot(save).ok and runtime.configure({"world":world,"facts":saved_facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok and building.validate_snapshot(world,runtime.facts()).ok and building.instance(GATE).hp==0)
	var restored_view:Node3D=building.create_view({"runtime":runtime})
	expect("restored real destruction derives matching geometry and contents",not restored_view.doors.has(GATE) and restored_view.static_nodes.size()==destroyed_view.static_nodes.size() and restored_view.objects.keys()==destroyed_view.objects.keys() and restored_view.get_node("Contents").get_child_count()==destroyed_view.get_node("Contents").get_child_count())
	destroyed_view.free();restored_view.free()
	support_case(enemy)
	ai_case(enemy)
	finish(started)

func support_case(enemy:Dictionary)->void:
	reset()
	var wall:Dictionary=building.make_instance("wall","bbb:single-bearing-wall",{"x":42,"y":0,"z":45,"regionId":"RH-HOME"})
	wall.hp=12
	var roof:Dictionary=building.make_instance("roof","bbb:single-supported-roof",{"x":42,"y":3.4,"z":45,"regionId":"RH-HOME"})
	var edit:=building.prepare_edit([],[wall,roof])
	var committed:Dictionary=runtime._commit(edit) if edit.ok else edit
	expect("isolated real single support fixture installs",committed.ok,committed.get("reason"))
	if not committed.ok:return
	var tx:=Draft.new(building.context);tx.actor(enemy.id).merge({"x":42,"z":44.3},true)
	unchanged_failure("lethal bearing-wall hit retains complete support safety",tx,enemy.id,wall.id)
	# The final staged resident positions and HP remain part of the same proof.
	tx=Draft.new(building.context);tx.actor("player").merge({"x":42,"y":4,"z":45},true)
	unchanged_failure("unsafe final staged resident support blocks any edit",tx,enemy.id)

func ai_case(enemy:Dictionary)->void:
	reset()
	var facts:=runtime.facts();facts.scenario="rural-home-r33";facts.actors.remove_at(2)
	# The hostile starts in real contact range behind the rotated closed gate;
	# A's public gameplay step must choose B, not this test invoking B directly.
	facts.actors[1].x=27.60;facts.actors[1].wounds=[];facts.actors[0].wounds=[]
	var gameplay:=Gameplay.new()
	var configured:=runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production,"gameplay":gameplay}})
	expect("same A runtime configures real hostile gameplay service",configured.ok)
	var old_hp:float=building.instance(GATE).hp
	for n in 8:runtime.tick(0.1)
	expect("actual A fixed-step enemy AI hits the real obstructing gate",building.instance(GATE).hp<old_hp and runtime.facts().get("ledger",[]).any(func(e:Dictionary)->bool:return e.kind=="structure-damaged" and e.target_id==GATE),{"gate_hp":building.instance(GATE).hp,"enemy":runtime.actor(enemy.id)})
	expect("AI does not attack player through closed gate",runtime.actor("player").hp==100)
