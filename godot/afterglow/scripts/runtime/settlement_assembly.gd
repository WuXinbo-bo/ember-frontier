extends RefCounted
## A's one-time composition of C's persisted terrain and B's real buildings.
## The worker sees value DTOs only. Never pass a live WorldState/scene to it.
const Rural=preload("res://scripts/world/rural_generator.gd")
const World=preload("res://scripts/world/world_state.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")

static func generate(seed:int,profiles:Array)->Dictionary:
	return Rural.generate_settlement(seed,profiles)

static func prepare(snapshot:Dictionary)->Dictionary:
	var world:=World.new()
	var loaded:Dictionary=world.load_snapshot(snapshot)
	if not loaded.ok:return loaded
	var building:=Buildings.new();var temporary:=Runtime.new()
	building.configure({"world":world,"runtime":temporary})
	var seeded:Dictionary=building.prepare_generation(world)
	if not seeded.ok:return seeded
	for id:String in ["player","village-resident","repair-resident"]:
		if not seeded.get("spawn_points",{}).has(id):return {"ok":false,"code":"MISSING_SPAWN","reason":"真实生成未提供人物站位："+id}
	var structures:Dictionary=building.structures(world)
	for change:Dictionary in seeded.world_changes:
		if change.get("id")==building.EXTENSION:structures=change.after
	var query:RefCounted=building.space(world,structures)
	var layout:Dictionary=_layout(world,query)
	if not layout.ok:return layout
	seeded.home=layout.home
	var neighbor:Dictionary=_opening_neighbor(world,query,seeded,layout)
	if not neighbor.ok:return neighbor
	seeded.spawn_points["village-resident"]=neighbor.location
	seeded.initial_stocks.append_array(Rural.empty_resource_stocks(world))
	var facts:Dictionary=Initial.facts(seeded)
	var changes:Array=seeded.world_changes.duplicate(true)
	changes.append_array([
		{"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":Initial.production(seeded)},
		{"op":"extension.set","id":Gameplay.KEY,"before_exists":false,"before":null,"after":Gameplay.initial(layout)},
		{"op":"extension.set","id":"r3:structure-orders","before_exists":false,"before":null,"after":{"version":1,"orders":[]}}])
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	if not draft.ok:return draft
	var safety:Dictionary=building.validate_world_draft(draft.view,facts,changes)
	if not safety.ok:world.discard_prepared(draft.capability);return safety
	var committed:Dictionary=world.commit_prepared(draft.capability)
	if not committed.ok:return committed
	return {"ok":true,"code":"OK","capture":{"world":world.snapshot(),"facts":facts,"source":{"scenario":"rural-home-r33","generator":world.identity().generatorVersion,"initial_parameters":"finite generated settlement; independent native save namespace"},"command_revision":0},"layout":layout}

static func _opening_neighbor(world:RefCounted,query:RefCounted,seeded:Dictionary,layout:Dictionary)->Dictionary:
	# New-world composition only. Restores retain the exact saved positions,
	# consent, resources and membership; no actor is teleported on load.
	var player:Dictionary=seeded.spawn_points.player
	var plan:Dictionary=world.extension("generation:RH-HOME")
	var arrival:Dictionary=plan.anchors.arrival
	var candidates:Array=[]
	for path:Dictionary in plan.get("paths",[]):
		for point:Dictionary in path.get("points",[]):candidates.append(point)
	for offset:Vector2 in [Vector2(2.2,0),Vector2(-2.2,0),Vector2(0,2.2),Vector2(0,-2.2),Vector2(3.2,0),Vector2(-3.2,0)]:
		var point:=arrival.duplicate();point.x=float(point.x)+offset.x;point.z=float(point.z)+offset.y;candidates.append(point)
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a).distance_squared_to(Geometry.point(player))<Geometry.point(b).distance_squared_to(Geometry.point(player)))
	for point:Dictionary in candidates:
		var at:=Geometry.location(point);at.regionId="RH-HOME"
		var feet:Dictionary=query.standing_point(at)
		if feet.is_empty() or feet.get("buildingId")!=null:continue
		var distance:float=Geometry.point(feet).distance_to(Geometry.point(player))
		if distance<2.2 or distance>14:continue
		if not query.line_clear(player,feet,"village-resident"):continue
		var route:Dictionary=query.route("village-resident",feet,layout.defense_position)
		if route.ok:return {"ok":true,"location":feet}
	return {"ok":false,"code":"NO_OPENING_NEIGHBOR","reason":"生成村路未提供可见且连通的熟人站位，保留原世界"}

static func _street(query:RefCounted,plan:Dictionary,preferred:Vector3)->Dictionary:
	var candidates:Array=[]
	for path:Dictionary in plan.get("paths",[]):
		for p:Dictionary in path.get("points",[]):
			var at:=Geometry.location(p);at.regionId=plan.region_id
			var feet:Dictionary=query.standing_point(at)
			if feet.is_empty() or feet.get("buildingId")!=null:continue
			candidates.append(feet)
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a).distance_squared_to(preferred)<Geometry.point(b).distance_squared_to(preferred))
	return candidates[0].duplicate(true) if not candidates.is_empty() else {}

static func _layout(world:RefCounted,query:RefCounted)->Dictionary:
	var home:Dictionary=world.extension("generation:RH-HOME")
	var village:Dictionary=world.extension("generation:RH-VILLAGE")
	var parcels:Dictionary={}
	for plan:Dictionary in [home,village]:
		for p:Dictionary in plan.get("parcels",[]):parcels[p.site_id]=p
	for id:String in ["home","shed","store","repair","neighbor"]:
		if not parcels.has(id):return {"ok":false,"code":"MISSING_LAYOUT","reason":"聚落缺少必要真实地块："+id}
	var p:Dictionary=parcels.home
	var r:Array=p.pad.xz
	var home_at:Dictionary={"x":(float(r[0])+float(r[2]))*0.5,"y":float(p.origin.y),"z":(float(r[1])+float(r[3]))*0.5,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var home_street:Dictionary=_street(query,home,Geometry.point(home.anchors.arrival))
	var store_street:Dictionary=_street(query,village,Geometry.point(village.anchors.store))
	var repair_street:Dictionary=_street(query,village,Geometry.point(village.anchors.repair))
	if [home_street,store_street,repair_street].any(func(at:Dictionary)->bool:return at.is_empty()):return {"ok":false,"code":"NO_ENCOUNTER_GROUND","reason":"真实街道未提供安全遭遇站位"}
	return {"ok":true,"version":1,"generator":world.identity().generatorVersion,"home":home_at,"home_radius":18.0,"home_region":"RH-HOME","home_building":p.id,"gate_id":str(p.id)+":yard-gate","store_prefix":str(parcels.store.id)+":","defense_position":home_street,"encounter_positions":[store_street,repair_street]}
