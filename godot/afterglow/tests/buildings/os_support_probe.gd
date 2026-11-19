extends "res://tests/buildings/family_generation_suite.gd"
## Read-only restored COPY of A's real candidate10 scene. No live app/saves.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const COPY="/Users/wxbbo/Documents/末日余晖4/work/r3-3/build10-support-scene-20261115-123152/saves/77c9bd2b11934109262bca3b7da15b9c/a.json"

func foot_grid(q:RefCounted,p:Dictionary)->Array:
	var grid:Array=[]
	for dx:float in [-0.26,0.0,0.26]:
		for dz:float in [-0.26,0.0,0.26]:
			grid.append({"dx":dx,"dz":dz,"ground":q.ground_height(float(p.x)+dx,float(p.z)+dz),"sample":q.floor_sample(str(p.regionId),float(p.x)+dx,float(p.z)+dz,float(p.y))})
	return grid

func inspect(label:String,capture:Dictionary)->void:
	var host:=Client.new();var restored:Dictionary=host._assemble(capture)
	# A's post-incident guard must reject the saved invalid stance. Continue
	# diagnosis on a raw, isolated World copy; never repair or mount this state.
	expect(label+" formal offscreen assembly preserves standing safety",not restored.ok and restored.get("code")=="SPATIAL_REJECTED" if label.begins_with("actual saved") else restored.ok,restored.get("reason"))
	if not restored.ok:
		var raw:=World.new();var loaded:Dictionary=raw.load_snapshot(capture.world)
		if not loaded.ok:host.free();return
		var raw_building:=Building.new();raw_building.configure({"world":raw,"runtime":Runtime.new()})
		restored={"world":raw,"services":{"buildings":raw_building}}
	var b:RefCounted=restored.services.buildings;var q:RefCounted=b.current_space()
	var p:Dictionary={"x":40.344171716366,"y":3.0,"z":56.7493890756741,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var saved:Dictionary=Geometry.location(capture.facts.actors.filter(func(a:Dictionary)->bool:return a.id=="player")[0])
	var result:Dictionary={"label":label,"identity":restored.world.identity(),"world_revision":restored.world.get_revision(),"saved":saved,"saved_feet":q.standing_point(saved),"logged":p,"body":q.body_location(p),"standing":q.standing_point(p),"grid":foot_grid(q,p),"movements":[]}
	for delta:Vector2 in [Vector2(0.08,0),Vector2(-0.08,0),Vector2(0,0.08),Vector2(0,-0.08),Vector2(0.08,0.08),Vector2(0,-0.28)]:
		var at:=p.duplicate(true);at.x+=delta.x;at.z+=delta.y
		at.y=2.5
		var resolved:Dictionary=q.standing_point(at)
		if resolved.is_empty():continue
		var moved:Dictionary=q.direct_move("player",resolved,p)
		result.movements.append({"from":resolved,"move":moved,"independent":b.space().standing_point(moved.location) if moved.ok else {}})
	print("OS_SUPPORT_PROBE "+JSON.stringify(result))
	var reference:=p.duplicate(true);reference.y=2.5
	var resolved:Dictionary=q.body_location(reference)
	var origin:=reference.duplicate(true);origin.z+=0.08
	var origin_feet:Dictionary=q.standing_point(origin)
	var edge_move:Dictionary=q.direct_move("player",origin_feet,p) if not origin_feet.is_empty() else {"ok":false}
	print("OS_SUPPORT_ENDPOINT "+JSON.stringify({"label":label,"body_from_lower_reference":resolved,"origin":origin_feet,"origin_independent":b.space().standing_point(origin_feet) if not origin_feet.is_empty() else {},"edge_move":edge_move,"endpoint_independent":b.space().standing_point(edge_move.location) if edge_move.ok else {}}))
	expect(label+" body projection must be a stable supported endpoint",resolved.is_empty() or not b.space().standing_point(resolved).is_empty(),resolved)
	expect(label+" accepted direct movement must retain independent support",not edge_move.ok or not b.space().standing_point(edge_move.location).is_empty(),edge_move)
	host.free()

func run()->void:
	var started:=Time.get_ticks_msec()
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(COPY))
	expect("A isolated real seed12 backup decodes",decoded.ok,decoded.get("reason"))
	if decoded.ok:inspect("actual saved rev"+str(decoded.capture.world.revision),decoded.capture)
	var fresh:Dictionary=Assembly.prepare(Assembly.generate(12,Building.generation_profiles()))
	expect("fresh12 is distinct generated comparison",fresh.ok,fresh.get("reason"))
	if fresh.ok:inspect("fresh12 not actual rev5",fresh.capture)
	finish(started)
