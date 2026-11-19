extends "res://tests/buildings/domain_suite.gd"
## Same-process alternating exact old predicate vs immutable candidate reuse.
const Codec=preload("res://scripts/world/world_codec.gd")
class Reference extends "res://scripts/buildings/building_service.gd":
	func supported_uncached(query:RefCounted,v:Dictionary,visited:Dictionary,terrain_proofs:Dictionary)->bool:
		# Frozen pre-change predicate, including caller-specific ancestry/cycle
		# rejection and three-slab count. Not a second runtime or production path.
		if float(v.get("hp",0))<=0:return true
		if visited.has(v.id):return false
		var ancestry:=visited.duplicate();ancestry[v.id]=true
		var d:Dictionary=geometry.definition(v);var b:AABB=query.bounds(v)
		if d.support=="terrain":
			if not terrain_proofs.has(v.id):terrain_proofs[v.id]=query.terrain_supports(str(v.regionId),AABB(b.position,Vector3(b.size.x,0,b.size.z)))
			return terrain_proofs[v.id]
		if d.support=="wall-top":
			var neighbors:Dictionary=query.support_neighbors(v)
			for other:Dictionary in neighbors.wall:
				if supported(query,other,ancestry,terrain_proofs):return true
			var slabs:=0
			for id in ancestry:
				if query.by_id.has(id) and geometry.definition(query.by_id[id]).kind in ["floor","roof"]:slabs+=1
			if slabs>=3:return false
			for other:Dictionary in neighbors.slab:
				if supported(query,other,ancestry,terrain_proofs):return true
			return false
		var footprint:=b
		if d.has("stairs"):footprint=Geometry.transformed_box(AABB(Vector3(-float(d.size.x)/2.0,0,0),Vector3(float(d.size.x),0,0.4)),v)
		for x in samples(footprint.position.x,footprint.end.x):
			for z in samples(footprint.position.z,footprint.end.z):
				var found:=false
				for floor_piece:Dictionary in query.nearby_pieces(str(v.regionId),AABB(Vector3(x,v.position.y,z),Vector3.ZERO),true):
					if floor_piece.id==v.id or floor_piece.regionId!=v.regionId or absf(float(floor_piece.position.y)-float(v.position.y))>=Geometry.EPS:continue
					var floor_box:AABB=query.bounds(floor_piece)
					if x>=floor_box.position.x-0.005 and x<=floor_box.end.x+0.005 and z>=floor_box.position.z-0.005 and z<=floor_box.end.z+0.005 and supported(query,floor_piece,ancestry,terrain_proofs):found=true;break
				if not found and not (v.get("storeyId")==null and query.terrain_supports(str(v.regionId),AABB(Vector3(x,v.position.y,z),Vector3.ZERO))):return false
		return true

func measure(service:RefCounted,query:RefCounted,order:Array)->Dictionary:
	var values:Dictionary={};var terrain:Dictionary={}
	var started:=Time.get_ticks_usec()
	for v:Dictionary in order:values[v.id]=service.supported(query,v,{},terrain)
	return {"values":values,"ms":float(Time.get_ticks_usec()-started)/1000,"projected_samples":query.surface_support_neighbors.size()}

func run()->void:
	var started:=Time.get_ticks_msec()
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():expect("actual ordinary source path supplied",false);finish(started);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	expect("actual immutable ordinary v5 source loads",world.load_snapshot(imported.world).ok)
	expect("actual runtime facts configure",runtime.configure({"world":world,"facts":imported.facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var original:=world.snapshot();var reference:=Reference.new();reference.configure(building.context)
	var rows:Array=[]
	for n in 3:
		var old_query:RefCounted=reference.space();var new_query:RefCounted=building.space()
		var old:Dictionary;var candidate:Dictionary
		if n%2==0:old=measure(reference,old_query,old_query.pieces);candidate=measure(building,new_query,new_query.pieces)
		else:candidate=measure(building,new_query,new_query.pieces);old=measure(reference,old_query,old_query.pieces)
		expect("all 971 cold support results equal original predicate pass "+str(n),old.values==candidate.values and old.values.size()==971)
		# Reuse candidates under distinct recursion ancestry. Never reuse truth
		# whose result depends on a visited ancestor or slab budget.
		var mismatches:Array=[]
		for i in range(0,new_query.pieces.size(),7):
			var v:Dictionary=new_query.pieces[i]
			for visited in [{v.id:true},{new_query.pieces[(i+1)%new_query.pieces.size()].id:true},{}]:
				if reference.supported(old_query,v,visited,{})!=building.supported(new_query,v,visited,{}):mismatches.append({"id":v.id,"visited":visited})
		expect("cached candidates preserve independent recursion ancestry pass "+str(n),mismatches.is_empty(),mismatches)
		rows.append({"pass":n,"order":"old-first" if n%2==0 else "candidate-first","before_ms":old.ms,"after_ms":candidate.ms,"candidate_footprints":candidate.projected_samples})
	expect("all support diagnostics leave original world and facts unchanged",world.snapshot()==original and runtime.facts()==imported.facts)
	print("SUPPORT_PROJECTION_COMPARISON "+JSON.stringify({"rows":rows,"scope":"same-process alternating headless CPU diagnostic, not FPS or official quiet-window acceptance"}))
	finish(started)
