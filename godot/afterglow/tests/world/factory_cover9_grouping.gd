extends "res://tests/world/environment_mount.gd"
## Actual25 normal9 outputs, decoded into an isolated C consumer. Edits below
## are explicit support/blocker fixtures, never normal play or authority saves.
const PreviousCover=preload("res://tests/world/fixtures/cover_before_grouping.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Raster=preload("res://scripts/world/settlement_generator.gd")

func cover_ids(view:Node3D)->Array:
	var result:Array=[]
	for node:Node3D in view._ecology.values():result.append_array(node.get_meta("presentation_patch_ids",[]))
	result.sort();return result

func persistent_ids(view:Node3D)->Array:
	var result:Array=[]
	for node:Node3D in view._ecology.values():result.append_array(node.get_meta("persistent_patch_ids",[]))
	result.sort();return result

func fixed_geometry(view:Node3D)->String:
	var result:Array=[]
	for collection:Dictionary in [view._roots,view._ground,view._contacts,view._fields]:
		var keys:Array=collection.keys();keys.sort()
		for key:String in keys:result.append([key,node_data(collection[key])])
	return digest(result)

func change(ops:Array,view:Node3D)->Dictionary:
	var tx:Dictionary=world.prepare_changes(ops,world.get_revision())
	var done:Dictionary=world.commit_prepared(tx.capability) if tx.ok else tx
	if done.ok:view.on_world_changed(done.changes)
	return done

func residency(region:String,resident:bool,view:Node3D)->Dictionary:
	var request:Dictionary=world.prepare_region_residency(region,resident,world.get_revision())
	return change(request.world_changes,view) if request.ok else request

func run()->void:
	var args:=OS.get_cmdline_user_args();var output:String=args[0]
	var profiles:Array=Modules.generation_profiles(true)
	for version:int in range(1,9):
		var lock:Dictionary=Contract.fresh(profiles,version,0 if version<3 else 1)
		var old_exact:bool=lock.ok
		for seed:int in [713,2026]:
			var planned:Dictionary=Factory.plan_region(seed,Vector2i.ZERO,profiles,lock.contract) if lock.ok else lock
			old_exact=old_exact and planned.ok and PreviousCover.patches(planned.plan)==Cover.patches(planned.plan)
		check("actual historical%d plans preserve old cover byte-values for both seeds"%version,old_exact)
	for index:int in range(1,args.size()):
		var input:String=args[index];var input_sha:String=FileAccess.get_sha256(input)
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input))
		world=State.new();var loaded:Dictionary=world.load_snapshot(decoded.capture.world) if decoded.get("ok",false) else decoded
		check("actual25 normal9 save decodes without regenerating "+str(index),loaded.ok,loaded.get("reason"))
		if not loaded.ok:continue
		var region:String="RH-HOME";var warm_ok:bool=true
		for id:String in ["RH-HOME","RH-VILLAGE"]:
			var request:Dictionary=world.prepare_region_residency(id,true,world.get_revision())
			var tx:Dictionary=world.prepare_changes(request.world_changes,world.get_revision()) if request.ok else request
			warm_ok=warm_ok and tx.ok and world.commit_prepared(tx.capability).ok
		check("isolated decoded home/village warm by original residency transactions "+str(index),warm_ok)
		if not warm_ok:continue
		var authority:Dictionary=world.snapshot();var plans:Dictionary={};var rows:Array=[];var summary:Array=[]
		for id:String in ["RH-HOME","RH-VILLAGE"]:
			var plan:Dictionary=world.extension("generation:"+id);plans[id]=plan
			var old:Array=PreviousCover.patches(plan);var next:Array=Cover.patches(plan)
			var skirts:Array=next.filter(func(p:Dictionary)->bool:return p.get("presentation_group")=="vegetation-skirt")
			var uses:Dictionary={};var unique:Dictionary={};var valid:bool=true
			var roads:Dictionary=Raster._road_index(plan)
			for patch:Dictionary in next:
				if unique.has(patch.id):valid=false
				unique[patch.id]=true
				valid=valid and patch.presentation_only and not patch.blocking and not patch.harvestable and patch.material==1 and patch.model in ["quality:v01_fresh_grass","quality:v02_dry_grass"] and Cover.clear(plan,roads,patch.position.x,patch.position.z,patch.footprint[0]*patch.scale*sqrt(2.0)*0.5)
			for patch:Dictionary in skirts:uses[patch.anchor_use]=int(uses.get(patch.anchor_use,0))+1
			check("saved9 "+id+" divides unchanged384 budget into real skirt groups and road fringe "+str(index),next.size()<=384 and not skirts.is_empty() and skirts.size()<=96 and next.size()-skirts.size()>0 and uses.has("forest-understorey") and uses.size()>=3,{"old":old.size(),"new":next.size(),"skirts":skirts.size(),"uses":uses})
			check("saved9 "+id+" unique IDs/only existing images/full plan clearances and repeatability "+str(index),valid and next==Cover.patches(plan))
			var old_times:Array=[];var new_times:Array=[]
			for sample:int in 8:
				for newer:bool in ([false,true] if sample%2==0 else [true,false]):
					var started:int=Time.get_ticks_usec()
					if newer:Cover.patches(plan)
					else:PreviousCover.patches(plan)
					if sample>1:
						if newer:new_times.append(Time.get_ticks_usec()-started)
						else:old_times.append(Time.get_ticks_usec()-started)
			old_times.sort();new_times.sort();rows.append_array(next)
			summary.append({"region":id,"skirts":skirts.size(),"uses":uses,"old_usec":old_times,"new_usec":new_times,"before_median_usec":(old_times[2]+old_times[3])/2.0,"after_median_usec":(new_times[2]+new_times[3])/2.0})
		var view:=EnvironmentView.new();root.add_child(view);view.configure({"world":world})
		var previous:=EnvironmentView.new();root.add_child(previous);previous.configure({"world":world,"materials":view.materials})
		# Disposable layout substitution is explicit test-only, never world data.
		for id:String in plans:previous._presentation_layouts[id]=PreviousCover.patches(plans[id])
		previous._ecology_layout_dirty=true;previous.sync()
		var ids_before:Array=cover_ids(view);var current:String=signature(view)
		var fixed:String=fixed_geometry(view);var visible_skirts:Array=rows.filter(func(p:Dictionary)->bool:return p.get("presentation_group")=="vegetation-skirt" and p.id in ids_before)
		check("real MultiMesh submits supported grouped skirts "+str(index),visible_skirts.size()>0 and view.statistics().missing_quality_images.is_empty(),{"visible_skirts":visible_skirts.size(),"stats":view.statistics()})
		check("persistent vegetation IDs and tree/root/ground/contact/field geometry/material/collision remain exact "+str(index),persistent_ids(previous)==persistent_ids(view) and fixed_geometry(previous)==fixed and Data.json_equal(authority,world.snapshot()))
		previous.free()
		var safe:bool=true;var blockers:Array=world.entities().filter(func(e:Dictionary)->bool:return e.get("data",{}).get("solid",false) or e.get("blocksTerrain",false))
		for patch:Dictionary in rows:
			if patch.id not in ids_before:continue
			var p:Vector3=Vector3(patch.position.x,patch.position.y,patch.position.z);var width:float=patch.footprint[0]*patch.scale*sqrt(2.0)
			var bounds:Dictionary={"min":{"x":p.x-width/2,"y":p.y+0.01,"z":p.z-width/2},"max":{"x":p.x+width/2,"y":p.y+1.6,"z":p.z+width/2}}
			safe=safe and view._grounded(p,Vector2.ONE*width,1) and not blockers.any(func(e:Dictionary)->bool:return Data.intersects(e.bounds,bounds))
		check("every visible disposable patch has full current support and real blocker clearance "+str(index),safe)
		if visible_skirts.is_empty():view.free();continue
		var chosen:Dictionary=visible_skirts.filter(func(p:Dictionary)->bool:return p.id.begins_with("render:fringe-v1:RH-HOME:"))[0]
		var cell:Dictionary={"x":floori(chosen.position.x*2),"y":roundi(chosen.position.y*2)-1,"z":floori(chosen.position.z*2)}
		var dug:Dictionary=change([{"op":"voxel.set","cell":cell,"before":1,"after":0}],view)
		check("isolated support dig immediately removes actual skirt "+str(index),dug.ok and chosen.id not in cover_ids(view))
		var filled:Dictionary=change([{"op":"voxel.set","cell":cell,"before":0,"after":1}],view)
		check("exact support fill restores actual mesh UV material transforms and identities "+str(index),filled.ok and signature(view)==current)
		var p:Dictionary=chosen.position
		var blocker:Dictionary={"id":"r34:c:cover9:blocker","kind":"object","position":p.duplicate(true),"regionId":region,"revision":0,"bounds":{"min":{"x":p.x-0.5,"y":p.y,"z":p.z-0.5},"max":{"x":p.x+0.5,"y":p.y+1.8,"z":p.z+0.5}},"data":{"solid":true}}
		var added:Dictionary=change([{"op":"entity.put","id":blocker.id,"before_exists":false,"before":null,"after":blocker}],view)
		check("explicit live blocker suppresses grouped skirt immediately "+str(index),added.ok and chosen.id not in cover_ids(view),added.get("reason"))
		var removed:Dictionary=change([{"op":"entity.remove","id":blocker.id,"before":world.entity(blocker.id)}],view)
		check("blocker deletion restores same native output "+str(index),removed.ok and signature(view)==current,removed.get("reason"))
		view.on_world_changed({"operations":[{"op":"extension.set","id":"generation:"+region}],"chunks":[],"entities":[]})
		check("plan invalidation derives exact same groups and bindings "+str(index),signature(view)==current)
		var cold:Dictionary=residency(region,false,view)
		check("lossless cold retires home skirt and roots "+str(index),cold.ok and chosen.id not in cover_ids(view) and world.region_residency_state(region).paged)
		var warm:Dictionary=residency(region,true,view)
		check("lossless warm restores complete exact consumer "+str(index),warm.ok and signature(view)==current)
		# Save after a real isolated support edit, not after refilling it.
		dug=change([{"op":"voxel.set","cell":cell,"before":1,"after":0}],view)
		var edited:String=signature(view);var saved:Dictionary=world.snapshot()
		var encoded:Dictionary=Codec.encode_checkpoint(saved,{},"r34:c:cover9:"+str(index));var readback:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
		var restored:=State.new();var loaded_back:Dictionary=restored.load_snapshot(readback.state) if readback.ok else readback
		var recovered:=EnvironmentView.new();root.add_child(recovered);recovered.configure({"world":restored,"materials":view.materials})
		var cold_starts:bool=cover_ids(recovered).is_empty()
		var original_world:RefCounted=world;world=restored
		var restored_ok:bool=loaded_back.ok
		for id:String in ["RH-HOME","RH-VILLAGE"]:restored_ok=restored_ok and residency(id,true,recovered).ok
		check("codec cold starts empty then same original warm restores edited complete consumer "+str(index),cold_starts and restored_ok and signature(recovered)==edited and chosen.id not in cover_ids(recovered) and restored.cell_at(cell.x,cell.y,cell.z)==0)
		check("original plans/entities untouched and no new persisted cover fields "+str(index),plans[region]==restored.extension("generation:"+region) and Data.json_equal(saved,original_world.snapshot()) and Data.json_equal(authority.entities,restored.snapshot().entities))
		check("normal25 direct input remains byte exact "+str(index),FileAccess.get_sha256(input)==input_sha)
		costs["input%d"%index]={"path":input,"sha256":input_sha,"rows":summary,"visible_skirts":visible_skirts.size(),"scope":"Same saved9 plans, two warmups plus six alternating old/new CPU observations per region; scoped C consumer fixtures, no renderer/OS/FPS/VA or normal gameplay qualification."}
		view.free();recovered.free();await process_frame
	finish(output)
