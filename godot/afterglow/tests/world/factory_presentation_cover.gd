extends "res://tests/world/factory_environment.gd"
const Cover=preload("res://scripts/environment/land_use_cover.gd")
const EnvironmentView=preload("res://scripts/environment/environment_view.gd")
const BeforeView=preload("res://tests/world/fixtures/environment_before_fringe.gd")

func visible(view:Node3D)->Array:
	var result:Array=[]
	for node:Node3D in view._ecology.values():result.append_array(node.get_meta("presentation_patch_ids",[]))
	result.sort();return result

func collision_count(node:Node)->int:
	var count:int=1 if node is CollisionObject3D else 0
	for child:Node in node.get_children():count+=collision_count(child)
	return count

func notify(view:Node3D,ops:Array,baseline:Node3D=null)->Dictionary:
	var started:int=Time.get_ticks_usec()
	var tx:Dictionary=world.prepare_changes(ops,world.get_revision())
	var result:Dictionary=world.commit_prepared(tx.capability) if tx.ok else tx
	var transaction_ms:float=(Time.get_ticks_usec()-started)/1000.0
	if result.ok:
		var old_ms:float=0.0
		if baseline!=null:
			started=Time.get_ticks_usec();baseline.on_world_changed(result.changes);old_ms=(Time.get_ticks_usec()-started)/1000.0
		started=Time.get_ticks_usec();view.on_world_changed(result.changes)
		if baseline!=null:result.test_timing={"world_transaction_ms":transaction_ms,"before_environment_notify_ms":old_ms,"after_environment_notify_ms":(Time.get_ticks_usec()-started)/1000.0}
	return result

func rebuild_cost(view:Node3D)->float:
	view._ecology_signatures.clear()
	var started:int=Time.get_ticks_usec();view._sync_ecology(view._derived_entities,[],true)
	return (Time.get_ticks_usec()-started)/1000.0

func run()->void:
	var profiles:Array=Modules.generation_profiles()
	var legacy:Dictionary=Factory.plan_region(713,Vector2i.ZERO,profiles,Contract.fresh(profiles,2).contract)
	check("historical content2 visual plan keeps no new derived fringe",legacy.ok and Cover.patches(legacy.plan).is_empty())
	for seed:int in [713,2026]:
		var opening:Dictionary=Assembly.prepare(Factory.generate(seed,profiles,Contract.fresh(profiles,3).contract))
		check("actual module-aware content3 world assembles "+str(seed),opening.ok,opening.get("reason"))
		if not opening.ok:return finish()
		world=State.new();var loaded:Dictionary=world.load_snapshot(opening.capture.world)
		check("derived cover uses sole real authority "+str(seed),loaded.ok)
		if not loaded.ok:return finish()
		var facts:Dictionary=world.snapshot();var raster:String=raster_digest(facts)
		var rows:Array=[];var by_region:Dictionary={};var valid:bool=true;var repeated:bool=true
		for id:String in ["RH-HOME","RH-VILLAGE"]:
			var plan:Dictionary=world.extension("generation:"+id)
			var patches:Array=Cover.patches(plan);var roads:Dictionary=Raster._road_index(plan)
			by_region[id]=patches.size();repeated=repeated and patches==Cover.patches(plan)
			for patch:Dictionary in patches:
				valid=valid and patch.presentation_only and not patch.blocking and not patch.harvestable and patch.material==1 and patch.model in ["quality:v01_fresh_grass","quality:v02_dry_grass"] and Cover.clear(plan,roads,patch.position.x,patch.position.z,patch.footprint[0]*patch.scale*sqrt(2.0)*0.5)
			rows.append_array(patches)
		check("bounded repeatable real land-use fringe excludes roads pads buildable land "+str(seed),valid and repeated and by_region.values().all(func(n:int)->bool:return n>0 and n<=Cover.LIMIT),by_region)
		var before:=BeforeView.new();var next:=EnvironmentView.new()
		root.add_child(before);root.add_child(next)
		var started:int=Time.get_ticks_usec();before.configure({"world":world})
		var before_init_ms:float=(Time.get_ticks_usec()-started)/1000.0
		started=Time.get_ticks_usec();next.configure({"world":world,"materials":before.materials})
		var next_init_ms:float=(Time.get_ticks_usec()-started)/1000.0
		var old_stats:Dictionary=before.statistics();var stats:Dictionary=next.statistics()
		check("initial fringe layouts are cached once per saved region "+str(seed),next.presentation_layout_builds==2 and next._presentation_layouts.size()==2)
		var ids:Array=visible(next);var supported:bool=true;var safe:bool=true;var exact_blockers:bool=true
		var blockers:Array=world.entities().filter(func(e:Dictionary)->bool:return e.get("data",{}).get("solid",false) or e.get("blocksTerrain",false))
		for patch:Dictionary in rows:
			var p:=Vector3(patch.position.x,patch.position.y,patch.position.z)
			var width:float=patch.footprint[0]*patch.scale*sqrt(2.0)
			var bounds:Dictionary={"min":{"x":p.x-width/2,"y":p.y+0.01,"z":p.z-width/2},"max":{"x":p.x+width/2,"y":p.y+1.6,"z":p.z+width/2}}
			var blocked:bool=blockers.any(func(e:Dictionary)->bool:return Data.intersects(e.bounds,bounds))
			exact_blockers=exact_blockers and next._ecology_blocked(bounds)==blocked
			if patch.id not in ids:continue
			supported=supported and next._grounded(p,Vector2.ONE*width,1)
			safe=safe and not blocked
		check("spatial candidate bins equal full actual blocker AABB scan "+str(seed),exact_blockers)
		check("actual native MultiMesh submits supported grass without obstacle overlap "+str(seed),ids.size()>80 and supported and safe and stats.presentation_cover_patches==ids.size(),stats)
		check("visual enrichment adds no collision tree stock or persistent patch "+str(seed),collision_count(before)==collision_count(next) and stats.tree_roots==old_stats.tree_roots and stats.ecology_patches<=old_stats.ecology_patches and Data.json_equal(world.snapshot(),facts),{"before":old_stats,"after":stats,"collision_nodes":collision_count(next)})
		check("existing images alpha and model bindings resolve "+str(seed),stats.missing_materials.is_empty() and stats.missing_models.is_empty() and stats.missing_quality_images.is_empty())
		var old_ms:Array=[];var new_ms:Array=[]
		for i:int in 5:
			if i%2==0:old_ms.append(rebuild_cost(before));new_ms.append(rebuild_cost(next))
			else:new_ms.append(rebuild_cost(next));old_ms.append(rebuild_cost(before))
			await process_frame
		old_ms.sort();new_ms.sort()
		var chosen:Dictionary={}
		for patch:Dictionary in rows:
			if patch.id in ids:chosen=patch;break
		if chosen.is_empty():before.free();next.free();return finish()
		var cell:Dictionary={"x":floori(chosen.position.x*2),"y":roundi(chosen.position.y*2)-1,"z":floori(chosen.position.z*2)}
		started=Time.get_ticks_usec();var dug:Dictionary=notify(next,[{"op":"voxel.set","cell":cell,"before":1,"after":0}],before)
		var edit_ms:float=(Time.get_ticks_usec()-started)/1000.0
		check("real dig immediately removes only supported derived cover "+str(seed),dug.ok and chosen.id not in visible(next) and visible(next).size()<ids.size())
		var filled:Dictionary=notify(next,[{"op":"voxel.set","cell":cell,"before":0,"after":1}])
		check("exact grass restoration brings same IDs without reroll "+str(seed),filled.ok and visible(next)==ids and raster_digest(world.snapshot())==raster)
		check("voxel and repeated consumer work do not regenerate plan layouts "+str(seed),next.presentation_layout_builds==2)
		next.on_world_changed({"operations":[{"op":"extension.set","id":"generation:RH-HOME"}],"entities":[],"chunks":[]})
		check("explicit plan invalidation rebuilds only the affected region "+str(seed),next.presentation_layout_builds==3 and visible(next)==ids)
		var region:String="RH-VILLAGE";var plan:Dictionary=world.extension("generation:"+region)
		var cold:Dictionary=world.prepare_region_residency(region,false,world.get_revision())
		var cooled:Dictionary=notify(next,cold.world_changes) if cold.ok else cold
		check("cold region retires all its derived cover immediately "+str(seed),cooled.ok and visible(next).all(func(id:String)->bool:return not id.begins_with("render:fringe-v1:RH-VILLAGE:")))
		var encoded:Dictionary=Codec.encode_checkpoint(world.snapshot(),{},"fringe-check:"+str(seed));var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
		var restored:=State.new();var recovered:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
		check("save stores only unchanged original plan and actual modified facts "+str(seed),recovered.ok and Data.json_equal(restored.extension("generation:"+region),plan) and not restored.extension("generation:"+region).has("presentation_cover"))
		var warm:Dictionary=world.prepare_region_residency(region,true,world.get_revision())
		var warmed:Dictionary=notify(next,warm.world_changes) if warm.ok else warm
		check("warm reload restores exact fringe IDs from same original facts "+str(seed),warmed.ok and visible(next)==ids and raster_digest(world.snapshot())==raster)
		var recovered_view:=EnvironmentView.new();root.add_child(recovered_view);recovered_view.configure({"world":restored,"materials":next.materials})
		# WorldCodec intentionally restores ALL chunks nonresident. Warm both
		# actual regions before comparing against the original two-region view.
		var rc:Dictionary={"ok":true}
		for id:String in ["RH-HOME","RH-VILLAGE"]:
			var rw:Dictionary=restored.prepare_region_residency(id,true,restored.get_revision());var rt:Dictionary=restored.prepare_changes(rw.world_changes,restored.get_revision()) if rw.ok else rw
			rc=restored.commit_prepared(rt.capability) if rt.ok else rt
			if rc.ok:recovered_view.on_world_changed(rc.changes)
			else:break
		var recovered_ids:Array=visible(recovered_view)
		var original_candidates:Array=Cover.patches(plan);var recovered_candidates:Array=Cover.patches(restored.extension("generation:"+region))
		check("candidate identities ignore JSON integer float representation "+str(seed),original_candidates==recovered_candidates)
		check("cold save new consumer reproduces same full visible IDs after warm "+str(seed),rc.ok and recovered_ids==ids,{"warm":rc.get("code"),"reason":rc.get("reason"),"expected":ids.size(),"actual":recovered_ids.size(),"missing":ids.filter(func(id:String)->bool:return id not in recovered_ids).slice(0,8),"added":recovered_ids.filter(func(id:String)->bool:return id not in ids).slice(0,8),"candidates_equal":original_candidates==recovered_candidates,"original_first":original_candidates.slice(0,1),"recovered_first":recovered_candidates.slice(0,1)})
		costs[str(seed)]={"candidates_by_region":by_region,"before":old_stats,"after":stats,"before_init_ms":before_init_ms,"after_init_ms":next_init_ms,"before_warm_full_rebuild_ms":old_ms,"after_warm_full_rebuild_ms":new_ms,"before_median_ms":old_ms[2],"after_median_ms":new_ms[2],"single_support_edit_both_consumers_ms":edit_ms,"same_commit_environment_timing":dug.get("test_timing",{}),"scope":"Headless actual submitted native instances/support/invalidation only. More foliage is a disclosed visual workload increase, not a CPU/FPS improvement or renderer/VA pass."}
		before.free();next.free();recovered_view.free();await process_frame
	finish()
