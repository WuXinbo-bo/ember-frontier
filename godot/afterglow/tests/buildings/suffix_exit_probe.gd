extends "res://tests/buildings/door_transaction_suite.gd"
## Test-only reuse experiment. Production remains unchanged until measured.
class SuffixBuilding extends "res://scripts/buildings/building_service.gd":
	var observed_query:WeakRef
	var shared:Dictionary={}
	var metrics:Dictionary={"joined":0,"candidates":0}
	func configure(value:Dictionary)->void:
		super.configure(value);observed_query=null;shared.clear()
	func exit_reachable(query:RefCounted,id:String,from:Dictionary,to:Dictionary)->bool:
		if observed_query==null or observed_query.get_ref()!=query:
			observed_query=weakref(query);shared.clear()
		var goal:Array=[to.duplicate(true)]
		var actor_key:=id+"|"+str([to.regionId,to.x,to.y,to.z])
		if _exit_hints.get(actor_key,[]).is_empty():
			var candidates:Array=[]
			for route:Dictionary in shared.get(goal,[]):
				var at:Dictionary=route.from
				for index:int in range(route.steps.size()+1):
					if at.regionId==from.regionId and at.get("buildingId")==from.get("buildingId") and at.get("storeyId")==from.get("storeyId") and absf(float(at.y)-float(from.y))<=query.agent.max_step:
						var distance:float=Geometry.point(from).distance_squared_to(Geometry.point(at))
						if distance<=64.0:candidates.append({"at":at,"steps":route.steps,"index":index,"distance":distance})
					if index<route.steps.size() and route.steps[index].kind in ["move","stairs"]:at=route.steps[index].to
			candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.distance<b.distance)
			for candidate:Dictionary in candidates.slice(0,4):
				metrics.candidates+=1
				var bridge:Dictionary=query.walk(id,from,candidate.at,true)
				if not bridge.ok or Geometry.point(bridge.location).distance_to(Geometry.point(candidate.at))>0.025:continue
				var steps:Array=[{"kind":"move","to":candidate.at.duplicate(true)}]
				steps.append_array(candidate.steps.slice(candidate.index))
				_exit_hints[actor_key]=steps
				metrics.joined+=1;break
		var result:bool=super.exit_reachable(query,id,from,to)
		if result and not _exit_hints.get(actor_key,[]).is_empty():
			if shared.size()>=16:shared.clear()
			if not shared.has(goal):shared[goal]=[]
			if shared[goal].size()<4:shared[goal].append({"from":from.duplicate(true),"steps":_exit_hints[actor_key].duplicate(true)})
		return result

var last_model:RefCounted

func hint(c:Dictionary,request:Dictionary,_reference:bool)->Dictionary:
	return c.building.door_preview(request)

func configure_case(imported:Dictionary,side:int,reference:bool)->Dictionary:
	var w:=World.new();w.load_snapshot(imported.world)
	var b:RefCounted=Building.new() if reference else SuffixBuilding.new();last_model=b
	var r:=Runtime.new();var services:Dictionary={"buildings":b,"actions":Actions.new(),"production":Production.new()}
	var configured:Dictionary=r.configure({"world":w,"facts":imported.facts,"services":services})
	expect("same actual baseline runtime configures",configured.ok,configured)
	var fixture:RefCounted=b.space();var door:Dictionary=fixture.by_id[DOOR]
	var stance:Dictionary=fixture.standing_point(fixture.use_points(door)[side])
	var f:=r.facts()
	for a:Dictionary in f.actors:
		if a.id=="player":a.merge(stance,true);a.intent=null
	configured=r.configure({"world":w,"facts":f,"services":services})
	expect("same explicit supported stance and five original actors",not stance.is_empty() and configured.ok and r.facts().actors.size()==5)
	return {"world":w,"building":b,"runtime":r,"services":services,"fixture":fixture}

func phase_case(imported:Dictionary,side:int,index:int,reference:bool)->Dictionary:
	var result:Dictionary=super.phase_case(imported,side,index,reference)
	if not reference:result.suffix_metrics=last_model.metrics.duplicate(true)
	return result
