extends "res://tests/buildings/candidate_tokens_suite.gd"
## Original exact voxel/entity predicate retained as a read-only test oracle.
class OriginalVoxelSpace extends "res://scripts/buildings/building_space.gd":
	func terrain_clear_uncached(region:String,volume:AABB,exclude_id:String)->bool:
		var lo:=Vector3i(floor((volume.position.x+0.00001)/cell_size),floor((volume.position.y+0.00001)/cell_size),floor((volume.position.z+0.00001)/cell_size))
		var hi:=Vector3i(ceil((volume.end.x-0.00001)/cell_size),ceil((volume.end.y-0.00001)/cell_size),ceil((volume.end.z-0.00001)/cell_size))
		if (hi.x-lo.x)*(hi.y-lo.y)*(hi.z-lo.z)>65536:return false
		for x in range(lo.x,hi.x):
			for y in range(lo.y,hi.y):
				for z in range(lo.z,hi.z):
					if cell_material(Vector3i(x,y,z))!=0:return false
		for x in range(floori(volume.position.x/2),floori(volume.end.x/2)+1):
			for z in range(floori(volume.position.z/2),floori(volume.end.z/2)+1):
				for e in entity_buckets.get(region,{}).get(Vector2i(x,z),[]):
					if e.id!=exclude_id and Geometry.overlap(Geometry.aabb(e.bounds),volume):return false
		return true

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:=Codec.decode_checkpoint(raw)
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var world:=World.new();world.load_snapshot(imported.world)
	var runtime:=Runtime.new();var building:=Building.new()
	expect("actual source configures unchanged",runtime.configure({"world":world,"facts":imported.facts,"services":{"buildings":building}}).ok)
	var before:=world.snapshot();var rows:Array=[]
	for n in 3:
		var variants:Dictionary={}
		for name in (["original","interval"] if n%2==0 else ["interval","original"]):
			var query:RefCounted=OriginalVoxelSpace.new() if name=="original" else Space.new()
			query.configure(world,building.structures(),building.geometry,building.permission)
			variants[name]=measured(query,building,world,imported.facts)
			variants[name].voxel_intervals=query.voxel_clear_cache.size()
		expect("exact full route proof unchanged pass "+str(n),variants.original.routes==variants.interval.routes)
		expect("all four residents retain source exits pass "+str(n),variants.interval.rows.size()==4 and variants.interval.rows.all(func(r:Dictionary)->bool:return r.ok))
		rows.append({"pass":n,"order":"original-first" if n%2==0 else "interval-first","before":variants.original.rows,"after":variants.interval.rows,"cached_intervals":variants.interval.voxel_intervals})
	var old_query:=OriginalVoxelSpace.new();old_query.configure(world,building.structures(),building.geometry,building.permission)
	var new_query:=Space.new();new_query.configure(world,building.structures(),building.geometry,building.permission)
	var mismatches:Array=[];var count:=0
	for piece:Dictionary in new_query.pieces:
		for offset in [Vector3.ZERO,Vector3(0.24999,-0.01001,0.25001),Vector3(-0.25001,0.49999,-0.24999)]:
			for size in [Vector3(0.02,0.01,0.02),Vector3(0.52,1.76,0.52),Vector3.ZERO]:
				var volume:=AABB(Geometry.point(piece.position)+offset,size);count+=1
				if old_query.terrain_clear_uncached(piece.regionId,volume,"")!=new_query.terrain_clear_uncached(piece.regionId,volume,"") and mismatches.size()<20:mismatches.append({"piece":piece.id,"volume":str(volume)})
	expect("all exact epsilon/voxel boundaries and body volumes agree",count>8000 and mismatches.is_empty(),{"samples":count,"mismatches":mismatches})
	# Same voxel interval, different precise overlap: sharing the entity result
	# would falsely reject the second box and break its exclude-id behavior.
	var entity:Dictionary={"id":"fixture:precise-obstacle","regionId":"city","bounds":Geometry.json_box(AABB(Vector3(0.15,19.10,0.15),Vector3(0.1,0.1,0.1)))}
	var region:="fixture:precise-region"
	new_query.entity_buckets[region]={Vector2i.ZERO:[entity]}
	old_query.entity_buckets[region]={Vector2i.ZERO:[entity]}
	var hit:=AABB(Vector3(0.16,19.12,0.16),Vector3(0.03,0.03,0.03))
	var clear:=AABB(Vector3(0.31,19.12,0.31),Vector3(0.03,0.03,0.03))
	expect("entity-separation fixture lies in generated air not outside world",new_query.cell_material(Vector3i(0,38,0))==0)
	expect("same voxel interval never shares continuous entity overlap",not new_query.terrain_clear_uncached(region,hit,"") and new_query.terrain_clear_uncached(region,clear,"") and not old_query.terrain_clear_uncached(region,hit,"") and old_query.terrain_clear_uncached(region,clear,""))
	expect("exclude-id never poisons the shared voxel proof",new_query.terrain_clear_uncached(region,hit,entity.id) and not new_query.terrain_clear_uncached(region,hit,""))
	expect("all diagnostics preserve sole authoritative world and actors",world.snapshot()==before and runtime.facts()==imported.facts)
	print(JSON.stringify({"scope":"B exact geometry comparison and alternating headless CPU diagnostic; not FPS or official budget","ok":not failed,"checks":checks,"measurements":rows}))
	quit(1 if failed else 0)
