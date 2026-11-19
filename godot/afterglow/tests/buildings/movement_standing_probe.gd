extends "res://tests/buildings/family_generation_suite.gd"
## Read-only contract probe: every accepted movement endpoint must remain an
## exact standing point in an independent projection of the same real world.
## These are explicit isolated actor samples, never live save/player edits.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")

func run()->void:
	var started:=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(973339546,Building.generation_profiles()))
	expect("exact eighth-package seed prepares actual retained settlement",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(started);return
	var host:=Client.new();var assembled:Dictionary=host._assemble(prepared.capture)
	expect("same formal assembler restores exact seed in isolation",assembled.ok,assembled.get("reason"))
	if not assembled.ok:host.free();finish(started);return
	world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions
	var query:RefCounted=building.current_space();var independent:RefCounted=building.space()
	var original_facts:=runtime.facts();var original_revision:int=world.get_revision()
	var samples:Dictionary={}
	for piece:Dictionary in query.surfaces:
		if building.geometry.definition(piece).kind=="roof" or float(piece.hp)<=0:continue
		var box:AABB=query.bounds(piece)
		for x:float in [box.position.x-0.261,box.position.x-0.259,box.get_center().x,box.end.x+0.259,box.end.x+0.261]:
			for z:float in [box.position.z-0.261,box.get_center().z,box.end.z+0.261]:
				var point:Dictionary={"regionId":piece.regionId,"buildingId":piece.get("buildingId"),"storeyId":piece.get("storeyId"),"x":x,"y":piece.position.y,"z":z}
				samples[str([point.regionId,x,point.y,z])]=point
	# Sample real varied terrain as well as the house/foundation edges.
	for region:Dictionary in world.regions():
		for x in range(ceili(region.bounds.min.x)+2,floori(region.bounds.max.x)-2,5):
			for z in range(ceili(region.bounds.min.z)+2,floori(region.bounds.max.z)-2,5):
				var ground:Variant=world.surface_height(x+0.249,z+0.251)
				if ground!=null:samples[str([region.id,x,z])] = {"regionId":region.id,"buildingId":null,"storeyId":null,"x":x+0.249,"y":float(ground),"z":z+0.251}
	var bad:Array=[];var accepted:=0;var valid_origins:=0;var denied:=0
	for point:Dictionary in samples.values():
		var from:Dictionary=query.standing_point(point)
		if from.is_empty():continue
		valid_origins+=1
		for direction:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1).normalized(),Vector2(-1,-1).normalized()]:
			for distance:float in [0.073,0.28,0.46]:
				var to:=from.duplicate(true);to.x+=direction.x*distance;to.z+=direction.y*distance
				if world.region_at(Geometry.json_point(Geometry.point(to))).get("id")!=from.regionId:continue
				var moved:Dictionary=query.direct_move("player",from,to)
				if not moved.ok:denied+=1;continue
				accepted+=1
				var feet:Dictionary=independent.standing_point(moved.location)
				if feet.is_empty() or Geometry.point(feet).distance_to(Geometry.point(moved.location))>0.025:
					bad.append({"from":from,"requested":to,"accepted":moved,"independent_feet":feet})
					if bad.size()>=8:break
			if bad.size()>=8:break
		if bad.size()>=8:break
	expect("accepted endpoints retain exact independent standing proof",bad.is_empty() and accepted>100, {"samples":samples.size(),"valid_origins":valid_origins,"accepted":accepted,"denied":denied,"failures":bad})
	expect("probe preserves every fact and authoritative world revision",runtime.facts()==original_facts and world.get_revision()==original_revision)
	print("MOVEMENT_STANDING_PROBE "+JSON.stringify({"seed":973339546,"sampled":samples.size(),"valid_origins":valid_origins,"accepted":accepted,"denied":denied,"failures":bad}))
	host.free();finish(started)
