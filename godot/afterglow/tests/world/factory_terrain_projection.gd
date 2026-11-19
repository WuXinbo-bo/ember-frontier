extends "res://tests/world/factory_normal_path.gd"
## Same normal tools and Runtime public presentation; explicit cold probe is a
## C failure fixture, not a claim A may unload an active player's region.

func public_work(runtime:RefCounted)->Dictionary:
	return runtime.actor_presentation().work.get("player",{})

func run()->void:
	var opening:Dictionary=normal_tools(Contract.fresh(Modules.generation_profiles(),3).contract)
	if not opening.ok:return finish()
	var runtime:RefCounted=opening.runtime;var world:RefCounted=opening.world
	var service:RefCounted=opening.built.services.terrain;var rows:Array=[]
	for mode:String in ["pickaxe","shovel"]:
		var at:Dictionary=_location(world,55.0,15.0) if mode=="pickaxe" else _location(world,41.5,20.25)
		at=opening.built.services.buildings.current_space().standing_point(at)
		var walked:Dictionary=walk(runtime,at) if not at.is_empty() else {"ok":false}
		check("normal actor reaches actual projection work site "+mode,walked.get("ok",false),walked)
		if not walked.get("ok",false):return finish()
		var cell:Dictionary={"x":111,"y":roundi(world.surface_height(55.75,15.75)*2)-1,"z":31} if mode=="pickaxe" else {"x":84,"y":roundi(world.surface_height(42.25,20.25)*2)-1,"z":40}
		var tool:String=opening[mode]
		var operation:String="dig" if mode=="pickaxe" else "level"
		var payload:Dictionary=brush(cell,operation,tool,1 if mode=="pickaxe" else 2,float(cell.y)*0.5,3 if mode=="pickaxe" else 2)
		var started:Dictionary=send(runtime,"terrain","",payload)
		check("real held terrain command starts "+mode,started.ok,started)
		if not started.ok:return finish()
		var initial:Dictionary=public_work(runtime)
		check("new command has no fabricated effective work "+mode,initial.get("owner")=="terrain" and not initial.effective_work and initial.progress_seconds==0)
		runtime.tick(0.1)
		var fact:Dictionary=runtime.actor("player");var projection:Dictionary=public_work(runtime)
		check("public projection reads exact sole elapsed and duration "+mode,projection.get("owner")=="terrain" and projection.kind=="terrain" and projection.effective_work and projection.progress_seconds==fact.intent.elapsed and projection.duration_seconds==fact.intent.duration,projection)
		var actual:Dictionary={}
		if projection.get("contact") is Dictionary:
			actual=service._cell_contact(world,Geometry.point(fact)+Vector3(0,1.2,0),Vector3i(projection.cell.x,projection.cell.y,projection.cell.z),true,fact,str(world.region_at({"x":(projection.cell.x+0.5)*0.5,"y":(projection.cell.y+0.5)*0.5,"z":(projection.cell.z+0.5)*0.5}).id))
		check("tool contact is actual original-world exposed face "+mode,actual.get("ok",false) and projection.contact.position==[actual.point.x,actual.point.y,actual.point.z] and projection.contact.normal==[actual.normal.x,actual.normal.y,actual.normal.z] and projection.world_revision==world.get_revision(),projection)
		var snapshot:Dictionary=runtime.capture_checkpoint();var samples:Array=[];var refresh_samples:Array=[];var equivalent:bool=true
		for i:int in 11:
			service._work_projection_revisions.clear()
			var begin:int=Time.get_ticks_usec();var refreshed:Dictionary=public_work(runtime);refresh_samples.append((Time.get_ticks_usec()-begin)/1000.0)
			begin=Time.get_ticks_usec();var cached:Dictionary=public_work(runtime);samples.append((Time.get_ticks_usec()-begin)/1000.0)
			equivalent=equivalent and Data.json_equal(refreshed,cached) and Data.json_equal(cached,projection)
		check("same-revision reuse exactly equals fresh legal contact and progress "+mode,equivalent)
		var external:Dictionary=public_work(runtime);external.contact.position[0]+=10
		check("caller cannot mutate cached work projection "+mode,Data.json_equal(public_work(runtime),projection))
		check("repeated public read never advances reserves settles or changes authority "+mode,Data.json_equal(snapshot,runtime.capture_checkpoint()))
		runtime.set_paused(true);runtime.tick(1.0)
		check("global pause stops displayed work and sole elapsed "+mode,not public_work(runtime).effective_work and public_work(runtime).paused_reason=="paused" and runtime.actor("player").intent.elapsed==fact.intent.elapsed)
		runtime.set_paused(false);send(runtime,"held","",{"held":false});runtime.tick(0.1)
		var held:Dictionary=public_work(runtime)
		check("held release stops displayed work without invented progress "+mode,not held.effective_work and held.paused_reason=="held" and held.progress_seconds==fact.intent.elapsed)
		send(runtime,"held","",{"held":true});runtime.tick(0.1)
		check("held resume uses next actual fixed-step progress "+mode,public_work(runtime).effective_work and public_work(runtime).progress_seconds>fact.intent.elapsed)
		# Validate an unknown/cold actual target cannot retain an old contact.
		var key:String=Data.key(Data.cell_chunk(Vector3i(cell.x,cell.y,cell.z),16))
		var off:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":key,"before":true,"after":false}],world.get_revision())
		if off.ok:world.commit_prepared(off.capability)
		var blocked:Dictionary=public_work(runtime)
		check("cold target safely stops work and omits stale contact "+mode,off.ok and not blocked.effective_work and not blocked.has("contact"),blocked)
		var on:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":key,"before":false,"after":true}],world.get_revision())
		if on.ok:world.commit_prepared(on.capability)
		check("warm original facts restore same legal work contact "+mode,on.ok and public_work(runtime).effective_work and public_work(runtime).has("contact"))
		var cancelled:Dictionary=send(runtime,"cancel")
		check("cancel removes projection without committing terrain "+mode,cancelled.ok and public_work(runtime).is_empty())
		samples.sort();refresh_samples.sort();rows.append({"tool":mode,"projection_ms":samples,"median_ms":samples[5],"max_ms":samples[-1],"refresh_ms":refresh_samples,"refresh_median_ms":refresh_samples[5],"scope":"read-only actual public projection, interleaved same-input fresh and same-revision reuse CPU; not frame time"})
	costs={"samples":rows,"scope":"actual normal content3 tool commands and same Runtime actor_presentation; no app/renderer, dynamic tool mesh or normal-camera contact/VA qualification"};finish()
