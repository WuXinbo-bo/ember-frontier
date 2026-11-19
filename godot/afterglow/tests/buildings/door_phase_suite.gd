extends "res://tests/buildings/door_cost_suite.gd"
## Inclusive hook costs are CPU diagnostics, not additive phases or FPS.
class MeteredBuilding extends "res://scripts/buildings/building_service.gd":
	var meters:Dictionary={}
	var support_depth:=0
	func record(label:String,started:int)->void:
		if not meters.has(label):meters[label]={"calls":0,"usec":0}
		meters[label].calls+=1;meters[label].usec+=Time.get_ticks_usec()-started
	func prepare_door(request:Dictionary,proposed:Dictionary={},staged:Dictionary={})->Dictionary:
		var t:=Time.get_ticks_usec();var value:=super.prepare_door(request,proposed,staged);record("prepare_door",t);return value
	func space(view:RefCounted=null,proposed:Dictionary={},staged:Dictionary={})->RefCounted:
		var t:=Time.get_ticks_usec();var value:=super.space(view,proposed,staged);record("space_projection",t);return value
	func current_space()->RefCounted:
		var t:=Time.get_ticks_usec();var value:=super.current_space();record("current_space",t);return value
	func validation_space(view:RefCounted,data:Dictionary,staged:Dictionary)->RefCounted:
		var t:=Time.get_ticks_usec();var value:=super.validation_space(view,data,staged);record("validation_space",t);return value
	func supported(query:RefCounted,v:Dictionary,visited:Dictionary={},terrain_proofs:Dictionary={})->bool:
		var outer:=support_depth==0;support_depth+=1
		var t:=Time.get_ticks_usec();var value:=super.supported(query,v,visited,terrain_proofs)
		support_depth-=1
		if outer:
			record("root_support",t)
			record("support_kind:"+str(geometry.definition(v).get("kind")),t)
		return value
	func surface_support_samples(query:RefCounted,v:Dictionary,b:AABB)->Array:
		var t:=Time.get_ticks_usec();var value:=super.surface_support_samples(query,v,b);record("surface_support_samples",t);return value
	func exit_reachable(query:RefCounted,id:String,from:Dictionary,to:Dictionary)->bool:
		var t:=Time.get_ticks_usec();var value:=super.exit_reachable(query,id,from,to);record("resident_exit:"+id,t);return value
	func validate_structures(view:RefCounted,data:Dictionary,staged:Dictionary,removed:Array=[],added:Array=[])->Dictionary:
		var t:=Time.get_ticks_usec();var value:=super.validate_structures(view,data,staged,removed,added);record("validate_structures",t);return value
	func can_use(id:String,target:Dictionary,at:Dictionary={},staged:Dictionary={})->Variant:
		var t:=Time.get_ticks_usec();var value:Variant=super.can_use(id,target,at,staged);record("can_use",t);return value
	func changes_for(data:Dictionary,added:Array,removed:Array)->Array:
		var t:=Time.get_ticks_usec();var value:=super.changes_for(data,added,removed);record("changes_for",t);return value

func new_building()->RefCounted:return MeteredBuilding.new()
func sample_metrics(building:RefCounted)->Dictionary:
	var result:Dictionary=building.meters.duplicate(true)
	building.meters.clear()
	return {"scope":"inclusive native CPU hooks, do not add nested rows; timer overhead present","meters":result}
