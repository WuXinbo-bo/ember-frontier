extends "res://tests/buildings/profile_domain.gd"
## Measure exact successful edge repetition on the SAME immutable space used
## for every current resident, before deciding whether any new cache is useful.
class MeasuredNavigation extends "res://scripts/buildings/building_navigation.gd":
	var seen_success:Dictionary
	var meters:Dictionary
	func straight(a:Dictionary,b:Dictionary)->Dictionary:
		var key:Array=[a,b]
		var repeated:bool=seen_success.has(key)
		var t:=Time.get_ticks_usec();var result:=super.straight(a,b)
		var label:String="repeated_success" if repeated and result.ok else "new_success" if result.ok else "failed_edge"
		if not meters.has(label):meters[label]={"calls":0,"usec":0}
		meters[label].calls+=1;meters[label].usec+=Time.get_ticks_usec()-t
		if result.ok:seen_success[key.duplicate(true)]=result.duplicate(true)
		return result

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var w:=World.new();w.load_snapshot(imported.world)
	var r:=Runtime.new();var b:=Building.new()
	r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b}})
	var query:RefCounted=b.current_space();var seen:Dictionary={};var rows:Array=[]
	for actor:Dictionary in imported.facts.actors:
		var p:=Geometry.location(actor)
		if p.buildingId==null:continue
		for slot:Dictionary in w.extension("generation:"+str(p.regionId)).get("slots",[]):
			if slot.get("kind")!="entrance" or slot.get("buildingId")!=p.buildingId:continue
			var to:=Geometry.location(slot);to.buildingId=null;to.storeyId=null
			var ground:Variant=w.surface_height(to.x,to.z)
			if ground!=null:to.y=float(ground)
			var nav:=MeasuredNavigation.new();nav.seen_success=seen;nav.meters={}
			var t:=Time.get_ticks_usec();var route:Dictionary=nav.plan(query,actor.id,p,to)
			rows.append({"actor":actor.id,"ok":route.ok,"ms":float(Time.get_ticks_usec()-t)/1000,"edge_meters":nav.meters.duplicate(true),"distinct_successes":seen.size()})
	print(JSON.stringify({"ok":rows.size()==4 and rows.all(func(row:Dictionary)->bool:return row.ok),"rows":rows,"scope":"native shared-space edge CPU diagnostic only, exact production predicate, no new production cache"}))
	quit(0 if rows.size()==4 and rows.all(func(row:Dictionary)->bool:return row.ok) else 1)
