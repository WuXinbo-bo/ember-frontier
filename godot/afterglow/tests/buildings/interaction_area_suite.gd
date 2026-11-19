extends "res://tests/buildings/family_generation_suite.gd"
## Actual generated worlds; explicit reach fixtures and all-real command routes.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Contact=preload("res://scripts/buildings/interaction_contact.gd")
var probe_rows:Array=[]

func staged_at(at:Dictionary)->Dictionary:
	var staged:=runtime.facts()
	for a:Dictionary in staged.actors:
		if a.id=="player":a.merge(at,true);a.intent=null
	return staged

func old_socket_reachable(from:Dictionary,target:Dictionary)->bool:
	var query:RefCounted=building.current_space()
	for at:Dictionary in query.use_points(target):
		var feet:Dictionary=query.standing_point(at)
		if not feet.is_empty() and from.regionId==feet.regionId and from.get("storeyId")==feet.get("storeyId") and Geometry.point(from).distance_to(Geometry.point(feet))<=1.3 and query.line_clear(from,feet,str(target.id)):return true
	return false

func door_areas(seed_value:int)->void:
	var query:RefCounted=building.current_space()
	var checked:=0;var improved:=0;var rejected:Array=[]
	for suffix:String in ["front-door","rear-door","living-kitchen-door","living-sleep-door"]:
		var target:Dictionary=building.instance("RH-HOME:home:"+suffix)
		if target.is_empty():continue
		for x:float in [-0.6,0.0,0.6]:
			for z:float in [-1.25,1.25]:
				var at:=Geometry.location(target);at.merge(Geometry.json_point(Geometry.transform(Vector3(x,0,z),target)),true)
				var feet:Dictionary=query.standing_point(at)
				if feet.is_empty() or absf(float(feet.y)-float(target.position.y))>0.025:continue
				var before:bool=old_socket_reachable(feet,target)
				var after:Variant=building.can_use("player",target,{},staged_at(feet))
				checked+=1
				if not before and after==null:improved+=1
				if after!=null:rejected.append({"id":target.id,"local":[x,z],"feet":feet,"reason":after})
				probe_rows.append({"seed":seed_value,"kind":"door_area","id":target.id,"feet":feet,"old_socket":before,"accepted":after==null})
	expect("seed%d full same-side clear door areas are usable"%seed_value,checked>=12 and rejected.is_empty(),{"checked":checked,"rejected":rejected})
	expect("seed%d real portal fixtures reproduce and fix exact-handle failures"%seed_value,improved>0,{"improved":improved})
	var door:Dictionary=building.instance("RH-HOME:home:front-door")
	var at:=Geometry.location(door);at.merge(Geometry.json_point(Geometry.transform(Vector3(0,0,1.25),door)),true)
	var wrong:=at.duplicate(true);wrong.y+=3.4;wrong.storeyId="other-real-level"
	expect("seed%d door area never reaches another elevation or storey"%seed_value,building.can_use("player",door,{},staged_at(wrong))!=null)
	var dead:=staged_at(at)
	for a:Dictionary in dead.actors:
		if a.id=="player":a.hp=0
	expect("seed%d area reach cannot authorize an incapacitated actor"%seed_value,building.can_use("player",door,{},dead)!=null)
	var forbidden:=door.duplicate(true);forbidden.owner="other-household";forbidden.door.locked=true
	expect("seed%d a reachable door never removes ownership/lock permission"%seed_value,building.permission("player",forbidden.id,"open",forbidden,staged_at(at))!=null)

func tree_areas(seed_value:int)->void:
	var query:RefCounted=building.current_space();var found:=0;var wrong_floor:=0
	for tree:Dictionary in world.entities("RH-HOME"):
		if tree.get("kind")!="tree":continue
		for offset:Vector3 in [Vector3(2.5,0,0),Vector3(-2.5,0,0),Vector3(0,0,2.5),Vector3(0,0,-2.5)]:
			var at:=Geometry.location(tree);at.merge(Geometry.json_point(Geometry.point(tree.position)+offset),true)
			var feet:Dictionary=query.standing_point(at)
			if feet.is_empty() or feet.get("buildingId")!=null or absf(float(feet.y)-float(tree.position.y))>0.55 or not Contact.entity(query,feet,tree):continue
			var tx:=preload("res://scripts/actions/domain_draft.gd").new(production.context)
			for a:Dictionary in tx.staged.actors:
				if a.id=="player":a.merge(feet,true)
			var reason:Variant=production.reach("player",tree.id,Geometry.location(tree),"tree",tx)
			expect("seed%d actual trunk surface is usable around its whole perimeter %d"%[seed_value,found],reason==null,{"tree":tree.id,"at":feet,"origin_distance":Geometry.point(feet).distance_to(Geometry.point(tree.position)),"reason":reason})
			var a:Dictionary=tx.actor("player");a.y+=3.4;a.storeyId="upper-floor"
			if production.reach("player",tree.id,Geometry.location(tree),"tree",tx)!=null:wrong_floor+=1
			found+=1
			if found>=4:break
		if found>=4:break
	expect("seed%d real tree probes include four wider contacts and reject upper floor"%seed_value,found==4 and wrong_floor==found,{"found":found,"wrong_floor":wrong_floor})

func all_boundaries(seed_value:int)->void:
	# Actual bedroom/kitchen partition remains opaque despite same building.
	var query:RefCounted=building.current_space()
	var kitchen:Dictionary=building.instance("RH-HOME:home:kitchen")
	var bed:Dictionary=world.entity("RH-HOME:home:sleeping-place")
	var from:=Geometry.location(bed);from.x+=1.1
	var feet:Dictionary=query.standing_point(from)
	if not feet.is_empty():
		expect("seed%d same-floor closed partitions still block remote objects"%seed_value,building.can_use("player",kitchen,{},staged_at(feet))!=null)
	var stock:Dictionary=runtime.stock("RH-HOME:home:storage")
	var tx:=preload("res://scripts/actions/domain_draft.gd").new(production.context)
	for a:Dictionary in tx.staged.actors:
		if a.id=="player":a.merge(Geometry.location(stock),true)
	var prior:Dictionary=stock.duplicate(true);prior.owner="private-owner"
	expect("seed%d actual-surface stock reach preserves private ownership"%seed_value,production.reach("player",prior.id,prior,"stock",tx)!=null)
	prior=stock.duplicate(true);prior.searched=false
	expect("seed%d actual-surface reach preserves unsearched contents"%seed_value,production.reach("player",prior.id,prior,"stock",tx)!=null)
	var actor:Dictionary=tx.actor("player");actor.hp=0
	expect("seed%d surface production never works after incapacitation"%seed_value,production.reach("player",stock.id,stock,"stock",tx)!=null)

func furniture_areas(seed_value:int)->void:
	var query:RefCounted=building.current_space();var checked:=0;var improved:=0;var edges:Dictionary={};var rejected:Array=[]
	for target:Dictionary in building.structures().instances:
		var definition:Dictionary=building.geometry.definition(target)
		if definition.kind not in ["cabinet","workbench"] or float(target.hp)<=0:continue
		var box:=AABB()
		for raw:Dictionary in definition.solids:
			var part:=Geometry.aabb(raw);box=part if not box.has_volume() else box.merge(part)
		var center:=box.get_center()
		var approaches:Dictionary={
			"left":Vector3(box.position.x-1.4,0,center.z),"right":Vector3(box.end.x+1.4,0,center.z),
			"back":Vector3(center.x,0,box.end.z+1.4),"front":Vector3(center.x,0,box.position.z-1.4)}
		for edge:String in approaches:
			var at:=Geometry.location(target);at.merge(Geometry.json_point(Geometry.transform(approaches[edge],target)),true)
			var feet:Dictionary=query.standing_point(at)
			if feet.is_empty() or feet.buildingId!=target.buildingId or feet.storeyId!=target.storeyId or not Contact.structure(query,feet,target):continue
			var before:bool=old_socket_reachable(feet,target)
			var reason:Variant=building.can_use("player",target,{},staged_at(feet))
			checked+=1;edges[edge]=int(edges.get(edge,0))+1
			if not before and reason==null:improved+=1
			if reason!=null:rejected.append({"id":target.id,"edge":edge,"reason":reason})
			probe_rows.append({"seed":seed_value,"kind":"actual_furniture_surface","id":target.id,"edge":edge,"feet":feet,"origin_distance":Geometry.point(feet).distance_to(Geometry.point(target.position)),"old_socket":before,"accepted":reason==null})
	expect("seed%d real furniture offers supported endpoint side and back contact"%seed_value,checked>=12 and edges.has_all(["left","right","front","back"]) and rejected.is_empty(),{"checked":checked,"edges":edges,"rejected":rejected})
	expect("seed%d furniture surfaces fix old precise-socket failures"%seed_value,improved>0,improved)

func run()->void:
	var started:=Time.get_ticks_msec()
	for seed_value:int in [713,2026]:
		var host:=Client.new();var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(seed_value,Building.generation_profiles()))
		expect("real finite generated world prepares "+str(seed_value),prepared.ok,prepared.get("reason"))
		if not prepared.ok:host.free();continue
		var assembled:Dictionary=host._assemble(prepared.capture)
		expect("real formal assembler configures "+str(seed_value),assembled.ok,assembled.get("reason"))
		if not assembled.ok:host.free();continue
		world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
		var before:=runtime.capture_checkpoint()
		door_areas(seed_value);tree_areas(seed_value);furniture_areas(seed_value);all_boundaries(seed_value)
		expect("seed%d interaction previews preserve all real inventory time actors and world"%seed_value,preload("res://scripts/world/world_data.gd").json_equal(before,runtime.capture_checkpoint()))
		host.free()
	print("ACTUAL_INTERACTION_AREAS "+JSON.stringify(probe_rows))
	finish(started)
