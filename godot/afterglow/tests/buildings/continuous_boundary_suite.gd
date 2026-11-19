extends "res://tests/buildings/family_generation_suite.gd"
## Real generated/assembled regions. Explicit actor/contact fixtures are marked;
## all movement, occupancy, ownership, transfer and codec use production paths.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var host:Node3D

func place_fixture(at:Dictionary,stocks:Variant=null)->void:
	var capture:=runtime.capture_checkpoint()
	for actor:Dictionary in capture.facts.actors:
		if actor.id=="player":actor.merge(at,true);actor.intent=null
	if stocks is Array:capture.facts.stocks=stocks
	expect("explicit boundary fixture preserves all source metadata",runtime.configure({"world":world,"facts":capture.facts,"source":capture.get("source",{}),"command_revision":capture.get("command_revision",0),"receipts":capture.get("receipts",{}),"services":host_services}).ok)

var host_services:Dictionary={}

func shared_candidates(a:Dictionary,b:Dictionary)->Array:
	var candidates:Array=[];var axis:="";var boundary:=0.0;var sign:=1.0;var low:=0.0;var high:=0.0
	if is_equal_approx(float(a.bounds.max.x),float(b.bounds.min.x)):
		axis="x";boundary=float(a.bounds.max.x);low=maxf(a.bounds.min.z,b.bounds.min.z);high=minf(a.bounds.max.z,b.bounds.max.z)
	elif is_equal_approx(float(a.bounds.max.z),float(b.bounds.min.z)):
		axis="z";boundary=float(a.bounds.max.z);low=maxf(a.bounds.min.x,b.bounds.min.x);high=minf(a.bounds.max.x,b.bounds.max.x)
	elif is_equal_approx(float(a.bounds.min.x),float(b.bounds.max.x)):
		axis="x";boundary=float(a.bounds.min.x);sign=-1.0;low=maxf(a.bounds.min.z,b.bounds.min.z);high=minf(a.bounds.max.z,b.bounds.max.z)
	elif is_equal_approx(float(a.bounds.min.z),float(b.bounds.max.z)):
		axis="z";boundary=float(a.bounds.min.z);sign=-1.0;low=maxf(a.bounds.min.x,b.bounds.min.x);high=minf(a.bounds.max.x,b.bounds.max.x)
	if axis.is_empty():return candidates
	var query:RefCounted=building.current_space()
	for i in range(ceili(low)+2,floori(high)-2,2):
		var from:Dictionary={"x":float(i) if axis=="z" else boundary-sign*0.12,"z":float(i) if axis=="x" else boundary-sign*0.12,"y":0.0,"regionId":a.id,"buildingId":null,"storeyId":null}
		var to:=from.duplicate(true);to[axis]=boundary+sign*0.12;to.regionId=b.id
		var ground:Variant=world.surface_height(from.x,from.z)
		if ground==null:continue
		from.y=float(ground);to.y=float(ground)
		var feet:Dictionary=query.standing_point(from)
		if feet.is_empty() or feet.get("buildingId")!=null:continue
		from=feet
		var distant:=true
		for exit:Dictionary in a.get("exits",[]):
			if Vector2(float(from.x)-float(exit.position.x),float(from.z)-float(exit.position.z)).length()<float(exit.get("width",2))+1:distant=false
		if not distant:continue
		var actual:Dictionary=actions.move_step("player",from,to)
		if actual.ok:candidates.append({"from":from,"to":actual.location,"axis":axis})
		if candidates.size()==3:break
	return candidates

func run()->void:
	var started:=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(713,Building.generation_profiles()))
	expect("actual rural-3 world and buildings prepare",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(started);return
	host=Client.new()
	var assembled:Dictionary=host._assemble(prepared.capture)
	expect("one formal assembler warms actual generated chunks",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;host_services=assembled.services
	building=host_services.buildings;actions=host_services.actions;production=host_services.production
	var a:=world.region("RH-HOME");var b:=world.region("RH-VILLAGE")
	var candidates:=shared_candidates(a,b)
	expect("three real supported seam points exist outside every old exit radius",candidates.size()==3,candidates)
	for pair:Dictionary in candidates:
		place_fixture(pair.from)
		var first:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"walk"},pair.to)
		expect("actual command crosses continuous terrain away from a portal",first.ok and runtime.actor("player").regionId==b.id,first)
		runtime.tick(0.1)
		var back:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"walk"},pair.from)
		expect("same real body crosses back without an invisible exit",back.ok and runtime.actor("player").regionId==a.id,back)
	if candidates.is_empty():host.free();finish(started);return
	var pair:Dictionary=candidates[0]
	place_fixture(pair.from)
	# Withdraw a real chunk residency token: geometry still exists, but the
	# shared C proof must refuse cold space before B can move or consume time.
	var cfg:=world.config();var width:=float(cfg.cellSize)*int(cfg.chunkCells)
	var coord:=Vector3i(floori(float(pair.to.x)/width),floori((float(pair.to.y)+1.2)/width),floori(float(pair.to.z)/width))
	var key:="%d,%d,%d"%[coord.x,coord.y,coord.z]
	var residency:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":key,"before":true,"after":false}],world.get_revision())
	expect("explicit real cold-chunk fixture commits",residency.ok and world.commit_prepared(residency.capability).ok,residency.get("reason"))
	var before:=runtime.capture_checkpoint()
	var cold:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"walk"},pair.to)
	expect("cold known geometry cannot bypass continuous residency or charge movement",not cold.ok and cold.code=="UNLOADED_CELL" and runtime.capture_checkpoint()==before,cold)
	residency=world.prepare_changes([{"op":"chunk.residency","id":key,"before":false,"after":true}],world.get_revision())
	expect("normal C residency restoration preserves same geometry",residency.ok and world.commit_prepared(residency.capability).ok)

	var at:Dictionary=pair.to.duplicate(true)
	var box:=AABB(Geometry.point(at)+Vector3(-0.10,0,-0.10),Vector3(0.20,1.8,0.20))
	var entity:Dictionary={"id":"fixture:boundary-container","kind":"container","regionId":b.id,"position":Geometry.json_point(Geometry.point(at)),"bounds":Geometry.json_box(box),"revision":0,"data":{"solid":true,"opaque":true}}
	var obstruction:=world.prepare_changes([{"op":"entity.put","id":entity.id,"before_exists":false,"before":null,"after":entity}],world.get_revision())
	expect("explicit solid container fixture uses sole C capability",obstruction.ok and world.commit_prepared(obstruction.capability).ok,obstruction.get("reason"))
	before=runtime.capture_checkpoint()
	var blocked:=command("direct_move","",{"movement_dt":0.1,"movement_mode":"walk"},pair.to)
	expect("destination-region collider blocks crossing and cannot spend movement",not blocked.ok and runtime.capture_checkpoint()==before,blocked)
	var query:RefCounted=building.current_space()
	expect("cross-region line still sees destination-region opaque body",not query.line_clear(pair.from,pair.to))
	var stocks:Array=runtime.facts().stocks
	stocks.append({"id":entity.id,"location":at,"items":{"water":1},"owner":"other-household","searched":true})
	place_fixture(pair.from,stocks)
	before=runtime.capture_checkpoint()
	var forbidden:=command("take",entity.id,{"items":{"water":1}})
	expect("physical surface reach never grants another household's contents",not forbidden.ok and runtime.capture_checkpoint()==before,forbidden)
	stocks=runtime.facts().stocks
	for stock:Dictionary in stocks:
		if stock.id==entity.id:stock.owner="player"
	place_fixture(pair.from,stocks)
	var water_before:=float(runtime.actor("player").pack.get("water",0))
	var take:=command("take",entity.id,{"items":{"water":1}})
	expect("real nearest surface crosses continuous outdoor partition with ownership",take.ok and float(runtime.actor("player").pack.get("water",0))==water_before+1 and float(runtime.stock(entity.id).items.water)==0,take)
	var capture:=runtime.capture_checkpoint()
	var encoded:=Store.encode(capture)
	var decoded:=Store.decode(encoded.get("text",""))
	var restored:Dictionary=host._assemble(decoded.capture) if encoded.ok and decoded.ok else {"ok":false}
	expect("boundary movement transfer survives real native codec and formal reassembly",restored.ok,restored.get("reason"))
	if restored.ok:
		# Check the exact canonical facts actually persisted, rather than JSON
		# object key insertion order or the pre-encoding float representation.
		var saved_actor:=Draft.find(decoded.capture.facts.actors,"player")
		var actual_actor:Dictionary=restored.runtime.actor("player")
		expect("restored exact persisted position and transfer do not redraw or duplicate stock",Data.json_equal(actual_actor.pack,saved_actor.pack) and restored.runtime.stock(entity.id).items.water==0 and Data.json_equal(Geometry.location(actual_actor),Geometry.location(saved_actor)),{"actual":Geometry.location(actual_actor),"persisted":Geometry.location(saved_actor),"pre_encode":Geometry.location(runtime.actor("player")),"actual_pack":actual_actor.pack,"persisted_pack":saved_actor.pack})
		var forged:Dictionary=saved_actor.pack.duplicate(true);forged.water=float(forged.get("water",0))+1
		expect("canonical inventory comparison still rejects one extra water",not Data.json_equal(actual_actor.pack,forged))
	host.free();host=null
	finish(started)
