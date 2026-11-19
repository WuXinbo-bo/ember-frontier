extends "res://tests/buildings/legacy_suite.gd"
const Space=preload("res://scripts/buildings/building_space.gd")
class StringCandidates extends "res://scripts/buildings/building_space.gd":
	# Exact previous candidate-loop implementation; the rest of both queries is
	# the same current code/world. Test-only, never an alternate game runtime.
	func candidates(region:String,a:Vector3,b:Vector3,radius:float)->Array:
		var result:Array=[];var seen:Dictionary={}
		for x in range(int(floor((minf(a.x,b.x)-radius)/2.0)),int(floor((maxf(a.x,b.x)+radius)/2.0))+1):
			for z in range(int(floor((minf(a.z,b.z)-radius)/2.0)),int(floor((maxf(a.z,b.z)+radius)/2.0))+1):
				for entry in buckets.get(region,{}).get(Vector2i(x,z),[]):
					var key:=str(entry.instance.id)+"|"+str(entry.bounds)
					if not seen.has(key):seen[key]=true;result.append(entry)
		return result

func measured(query:RefCounted,building:RefCounted,world:RefCounted,facts:Dictionary)->Dictionary:
	var routes:Dictionary={};var rows:Array=[]
	for actor in facts.actors:
		var p:=Geometry.location(actor)
		if p.buildingId==null:continue
		for slot in world.extension("generation:"+str(p.regionId)).get("slots",[]):
			if slot.get("kind")!="entrance" or slot.get("buildingId")!=p.buildingId:continue
			var to:=Geometry.location(slot);to.buildingId=null;to.storeyId=null
			var ground:Variant=world.surface_height(to.x,to.z)
			if ground!=null:to.y=float(ground)
			var start:=Time.get_ticks_usec();var route:Dictionary=query.route(actor.id,p,to)
			rows.append({"actor":actor.id,"ms":float(Time.get_ticks_usec()-start)/1000,"ok":route.ok,"visited":route.get("visited")})
			routes[str(actor.id)+":"+str(slot.id)]=route
	return {"rows":rows,"routes":routes}

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:Dictionary=Codec.decode_checkpoint(raw)
	var imported:Dictionary=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var world:=World.new();world.load_snapshot(imported.world)
	var runtime:=Runtime.new();var building:=Building.new()
	runtime.configure({"world":world,"facts":imported.facts,"services":{"buildings":building}})
	var before:=world.snapshot();var results:Array=[]
	for iteration in 3:
		var variants:Dictionary={}
		for name in (["strings","tokens"] if iteration%2==0 else ["tokens","strings"]):
			var query:RefCounted=StringCandidates.new() if name=="strings" else Space.new()
			query.configure(world,building.structures(),building.geometry,building.permission)
			variants[name]=measured(query,building,world,imported.facts)
		expect("identical complete route proofs iteration "+str(iteration),variants.strings.routes==variants.tokens.routes)
		expect("all real residents retain exits iteration "+str(iteration),variants.tokens.rows.size()==4 and variants.tokens.rows.all(func(v:Dictionary)->bool:return v.ok))
		results.append({"iteration":iteration,"strings":variants.strings.rows,"tokens":variants.tokens.rows})
	expect("comparisons preserve authoritative world and every resident",world.snapshot()==before and runtime.facts()==imported.facts)
	print(JSON.stringify({"scope":"BBB same-process cold candidate-loop comparison; alternating order, identical actual source; CPU diagnostic not FPS/official budget","ok":not failed,"source_sha256":raw.sha256_text(),"checks":checks,"measurements":results}))
	quit(1 if failed else 0)
