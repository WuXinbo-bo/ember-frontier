extends SceneTree
const Codec=preload("res://scripts/world/world_codec.gd")
const World=preload("res://scripts/world/world_state.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:Dictionary=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:Dictionary=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var world:=World.new();world.load_snapshot(imported.world)
	var runtime:=Runtime.new();var building:=Building.new()
	runtime.configure({"world":world,"facts":imported.facts,"services":{"buildings":building}})
	var rows:Array=[]
	var start:=Time.get_ticks_usec();var query:RefCounted=building.current_space()
	rows.append({"phase":"space projection","ms":float(Time.get_ticks_usec()-start)/1000})
	start=Time.get_ticks_usec();var proofs:Dictionary={}
	for v in query.pieces:building.supported(query,v,{},proofs)
	rows.append({"phase":"cold support all","ms":float(Time.get_ticks_usec()-start)/1000})
	for stair in query.pieces.filter(func(v:Dictionary)->bool:return v.has("stairs")):
		start=Time.get_ticks_usec();var ok:bool=query.stair_clear(stair)
		rows.append({"phase":"stair clearance","id":stair.id,"ok":ok,"ms":float(Time.get_ticks_usec()-start)/1000})
	for actor in imported.facts.actors:
		var p:=Geometry.location(actor)
		if p.buildingId==null:continue
		for slot in world.extension("generation:"+str(p.regionId)).get("slots",[]):
			if slot.get("kind")!="entrance" or slot.get("buildingId")!=p.buildingId:continue
			var to:=Geometry.location(slot);to.buildingId=null;to.storeyId=null
			var ground:Variant=world.surface_height(to.x,to.z)
			if ground!=null:to.y=float(ground)
			start=Time.get_ticks_usec();var route:Dictionary=query.route(actor.id,p,to)
			rows.append({"phase":"cold resident exit","actor":actor.id,"ok":route.ok,"visited":route.get("visited"),"steps":route.get("steps",[]).size(),"ms":float(Time.get_ticks_usec()-start)/1000})
	print(JSON.stringify({"scope":"BBB headless native cold-phase CPU diagnostic; no FPS claim","ok":rows.all(func(v:Dictionary)->bool:return v.get("ok",true)),"rows":rows}))
	quit()
