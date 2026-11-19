extends "res://tests/world/local_hills_candidate.gd"
const Scheduler=preload("res://scripts/runtime/region_scheduler.gd")

func run()->void:
	var args:=OS.get_cmdline_user_args();var folder:String=args[0].get_base_dir()
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	check("v6 true opening native capture assembles all production services",built.ok,built.get("reason"))
	if not built.ok:return finish()
	var world:RefCounted=built.world;var runtime:RefCounted=built.runtime
	var original:Dictionary=world.snapshot();var original_facts:Dictionary=runtime.facts()
	var jobs:=Scheduler.new();jobs.attach(runtime,built.services.buildings,6)
	for coord:Vector2i in [Vector2i(1,0),Vector2i(-1,0)]:
		var requested:Dictionary=jobs.request(coord);var result:Dictionary={};var deadline:int=Time.get_ticks_msec()+10000
		while requested.ok and result.is_empty() and Time.get_ticks_msec()<deadline:
			await process_frame;result=jobs.poll(0,true)
		check("v6 actual threaded scheduler C B A atomic integration "+str(coord),requested.ok and result.get("ok",false),result)
	jobs.shutdown()
	var unchanged:=true
	for key:String in original.chunks:unchanged=unchanged and Data.json_equal(original.chunks[key],world.chunk(key))
	check("new region worker leaves original cells actors and clock exact",unchanged and Data.json_equal(runtime.facts().actors,original_facts.actors) and runtime.clock()==original_facts.time)
	check("both true-coordinate persistent v6 regions exist",world.region("R2:1:0").get("bounds",{}).get("min",{}).get("x")==64 and world.extension("generation:R2:-1:0").get("landscape_model")==Hills.MODEL)
	if world.region("R2:1:0").is_empty():return finish()
	# Test-only relocation and two marked tools isolate new-terrain labor. This
	# is not the natural survival route or an addition to the delivered capture.
	var trees:Array=world.entities("R2:1:0").filter(func(e:Dictionary)->bool:return e.kind=="tree")
	check("new peripheral real resource trees exist",not trees.is_empty())
	if trees.is_empty():return finish()
	var tree:Dictionary=trees[0];var p:Dictionary=tree.position
	var building:=Building.new();var facts:Dictionary=runtime.facts()
	runtime=Runtime.new()
	check("isolated labor runtime reuses sole actual expanded world",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"terrain":Terrain.new(),"actions":Actions.new(),"production":Production.new()}}).ok)
	var at:Dictionary=actor_at({"x":p.x+1.75,"y":world.surface_height(p.x+1.75,p.z),"z":p.z});at.regionId=tree.regionId
	var feet:Dictionary=building.current_space().standing_point(at)
	check("real tree work position satisfies final nine-probe support",not feet.is_empty(),feet)
	if feet.is_empty():return finish()
	var before:Dictionary=runtime.actor("player");var after:Dictionary=before.duplicate(true);after.merge(feet,true);after.intent=null
	var prod:Dictionary=world.extension("r3:production");var next:Dictionary=prod.duplicate(true)
	next.tools.append_array([{"id":"v6:test:axe","kind":"salvaged_axe","holderId":"pack:player","durability":100.0},{"id":"v6:test:shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1}}])
	var fixture:Dictionary=runtime._commit({"world_changes":[{"op":"extension.set","id":"r3:production","before_exists":true,"before":prod,"after":next}],"fact_changes":[{"collection":"actors","id":"player","before":before,"after":after}]})
	check("explicit labor fixture commits via unchanged formal safety",fixture.ok,fixture)
	if not fixture.ok:return finish()
	var harvested:Dictionary=runtime.command({"command_id":"v6:harvest","actor_id":"player","kind":"harvest","target_id":tree.id,"payload":{"tree_id":tree.id,"output_id":tree.data.outputId,"tool_ids":["v6:test:axe"],"held":true}})
	if harvested.ok:
		for i in 280:runtime.tick(0.1)
	check("real harvest commits stump and finite original log yield",harvested.ok and world.entity(tree.id).data.harvest.phase=="stump" and runtime.stock(tree.data.outputId).items.get("log",0)==3,harvested)
	var actor:Dictionary=runtime.actor("player");var cx:int=floori((actor.x+0.5)*2);var cz:int=floori((actor.z+0.5)*2)
	var cy:int=roundi(world.surface_height((cx+0.5)*0.5,(cz+0.5)*0.5)*2)-1;var cell:Dictionary={"x":cx,"y":cy,"z":cz}
	var hit:Dictionary=Queries.pick(world,Vector3((cx+0.5)*0.5,15,(cz+0.5)*0.5),Vector3((cx+0.5)*0.5,-3,(cz+0.5)*0.5))
	check("selection target remains one authoritative stable cell ID",hit.get("target_id")=="terrain:%d:%d:%d"%[cx,cy,cz],hit)
	var view:=TerrainView.new();root.add_child(view);view.configure({"world":world});view.set_process(false)
	var key:String=Data.key(Data.cell_chunk(Vector3i(cx,cy,cz),16))
	await collider_agrees(view,world,key,cx,cz,"before work")
	var soil_before:float=actor.pack.get("soil_m3",0)
	var dig:Dictionary=runtime.command({"command_id":"v6:dig","actor_id":"player","kind":"terrain","payload":{"edit":{"operation":"dig","cells":[cell]},"tool_id":"v6:test:shovel"}})
	if dig.ok:
		for i in 100:runtime.tick(0.1)
	check("actual dig updates only authority and conserves real soil",dig.ok and world.cell_at(cx,cy,cz)==0 and runtime.actor("player").pack.get("soil_m3",0)==soil_before+0.125,dig)
	await collider_agrees(view,world,key,cx,cz,"after real dig")
	var fill:Dictionary=runtime.command({"command_id":"v6:fill","actor_id":"player","kind":"terrain","payload":{"edit":{"operation":"fill","material":2,"cells":[cell]},"tool_id":"v6:test:shovel"}})
	if fill.ok:
		for i in 100:runtime.tick(0.1)
	check("actual fill returns same soil with changed persisted material",fill.ok and world.cell_at(cx,cy,cz)==2 and runtime.actor("player").pack.get("soil_m3",0)==soil_before,fill)
	await collider_agrees(view,world,key,cx,cz,"after real fill");view.free()
	var saved:Dictionary=Store.encode(runtime.capture_checkpoint());var restored_input:Dictionary=Store.decode(saved.text) if saved.ok else saved
	check("whole edited world native encode and cold decode",restored_input.ok,restored_input.get("reason"))
	if not restored_input.ok:return finish()
	FileAccess.open(folder+"/modified-four-region-v6.native.json",FileAccess.WRITE).store_string(saved.text)
	var cold:=State.new();cold.load_snapshot(restored_input.capture.world)
	var again:Dictionary=Rural.prepare_region(cold,Vector2i(1,0),Building.generation_profiles())
	check("cold revisit cannot redraw edit stump or create new resources",again.ok and again.already_generated and again.world_changes.is_empty() and again.initial_stocks.is_empty() and not cold.is_cell_resident(cx,cy,cz) and cold.cell_at(cx,cy,cz)==2 and cold.entity(tree.id).data.harvest.phase=="stump")
	native=Native.new();var restored:Dictionary=native._assemble(restored_input.capture);native.free()
	check("actual Native full cold reassembly retains standing support egress and stocks",restored.ok,restored.get("reason"))
	if restored.ok:
		check("native reassembly exact cells and native JSON world plan",raster_digest(restored.world.snapshot())==raster_digest(world.snapshot()) and Data.json_equal(restored.world.extension("generation:R2:1:0"),JSON.parse_string(JSON.stringify(world.extension("generation:R2:1:0"),"",true,true))))
		check("restored finite harvest output and soil stock remain exact",restored.runtime.stock(tree.data.outputId).items.get("log",0)==3 and restored.runtime.actor("player").pack.get("soil_m3",0)==soil_before)
	costs.scheduler=jobs.status();costs.scope="v6 actual A Thread scheduler/B family/stock/A atomic commit, three native collision phases, marked isolated labor fixtures and whole Native cold reassembly. No OS/app/export/user slot/Metal or natural survival/performance qualification."
	finish()

func collider_agrees(view:Node,world:RefCounted,key:String,cx:int,cz:int,label:String)->void:
	view._rebuild(key);await physics_frame;await process_frame
	var x:float=(cx+0.5)*0.5;var z:float=(cz+0.5)*0.5
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(x,15,z),Vector3(x,-3,z))
	var hit:Dictionary=view.get_world_3d().direct_space_state.intersect_ray(ray)
	check("actual native mesh collider agrees "+label,not hit.is_empty() and absf(hit.position.y-float(world.surface_height(x,z)))<0.001,{"authority":world.surface_height(x,z),"collision":str(hit.get("position"))})
