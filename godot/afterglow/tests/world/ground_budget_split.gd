extends "res://tests/world/ground_cold_layers.gd"
const BeforeTerrain=preload("res://tests/world/fixtures/ground_budget_before_terrain.gd")
const AfterTerrain=preload("res://scripts/terrain/terrain_view.gd")
var samples:Array=[]
func one(world:RefCounted,script:Script,key:String,after:bool)->Dictionary:
	var mats:=Mats.new();var view:Node3D=script.new();root.add_child(view)
	view.configure({"world":world,"materials":mats,"budgeted_edits":true,"stream_updates":true});view.set_process(false)
	view.cancel_pending();view._enqueue(key);mats.loads.clear()
	var rows:Array=[];var single:=true;var no_upload_loads:=true;var no_layer_loads:=true;var steps:=0
	while view.statistics().pending>0 and steps<256:
		var stage:String=view._active.get("stage","capture");var start:=Time.get_ticks_usec()
		var old_loads:int=mats.loads.size();var old_quality:int=mats.quality._materials.size()
		# One actual process_budget unit, so the synchronous native image call is
		# measured without hiding it inside a multi-unit frame.
		view.process_budget(1);steps+=1
		var added:int=mats.loads.size()-old_loads+mats.quality._materials.size()-old_quality
		rows.append({"stage":stage,"usec":Time.get_ticks_usec()-start,"new_dependencies":added})
		if stage=="ground_materials":single=single and added<=1
		if stage=="ground":no_upload_loads=no_upload_loads and added==0
		if stage in ["ground_contacts","ground_fields","ground_shoulders"]:no_layer_loads=no_layer_loads and added==0
	var before_physics:Dictionary=view.readiness([key]);var sig:Array=signature(view.environment,key)
	await physics_frame;await process_frame
	var ready:Dictionary=view.readiness([key]);var stats:Dictionary=view.statistics();var loads:Array=mats.loads.duplicate(true)
	view.free()
	return {"after":after,"rows":rows,"stages":stats.stages,"loads":loads,"single":single,"no_upload_loads":no_upload_loads,"no_layer_loads":no_layer_loads,"geometry_ready":before_physics.geometry_ready,"physics_was_closed":not before_physics.ready,"ready":ready.ready,"signature":sig,"pending":stats.pending}
func advance_until(view:Node3D,stage:String)->bool:
	for i in 256:
		if view._active.get("stage")==stage:return true
		if view.statistics().pending==0:return false
		view.process_budget(1)
	return false
func run()->void:
	var args:=OS.get_cmdline_user_args();var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded;native.free()
	check("actual modified four-region native capture assembles",built.ok,built.get("reason"))
	if not built.ok:return finish_split(args)
	var world:RefCounted=built.world;var snapshot:Dictionary=world.snapshot();var facts:Dictionary=built.runtime.facts();var key:="13,0,0"
	var exact:=true;var singles:=true;var uploads:=true;var layers:=true;var barriers:=true
	for iteration in 4:
		var old:Dictionary;var current:Dictionary
		if iteration%2==0:
			old=await one(world,BeforeTerrain,key,false);current=await one(world,AfterTerrain,key,true)
		else:
			current=await one(world,AfterTerrain,key,true);old=await one(world,BeforeTerrain,key,false)
		exact=exact and old.signature==current.signature
		singles=singles and current.single;uploads=uploads and current.no_upload_loads;layers=layers and current.no_layer_loads
		barriers=barriers and current.geometry_ready and current.physics_was_closed and current.ready and current.pending==0
		old.erase("signature");current.erase("signature");samples.append({"iteration":iteration,"before":old,"after":current})
	check("four alternating fresh-cache builds preserve every overlay array and support metadata",exact)
	check("real queue loads at most one actual ground image dependency per unit",singles)
	check("native ground upload no longer synchronously loads image dependencies",uploads)
	check("pure ground contact field shoulder stages never load images",layers)
	check("split publication preserves physical-frame readiness barrier",barriers)
	check("all measured builds preserve full source facts and residency",Data.json_equal(snapshot,world.snapshot()) and Data.json_equal(facts,built.runtime.facts()))
	var view:=AfterTerrain.new();root.add_child(view);view.configure({"world":world,"budgeted_edits":true,"stream_updates":true});view.set_process(false);view.cancel_pending();view._enqueue(key)
	var waiting:=advance_until(view,"ground_materials");var cancelled:int=view.statistics().cancelled_jobs
	check("real capture reaches staged ground material preparation",waiting)
	if waiting:
		view.environment.contacts._signature+="test-only-foundation-invalidation"
		view.process_budget(1)
		check("foundation layout change cancels pending overlay even without voxel revision",view.statistics().cancelled_jobs==cancelled+1 and not view.environment._ground.has(key) and not view.environment._fields.has(key) and not view.environment._contacts.has(key))
		waiting=advance_until(view,"ground_materials");cancelled=view.statistics().cancelled_jobs
		var p:=Vector3i(222,0,11);var before:int=world.cell_at(p.x,p.y,p.z)
		var prepared:Dictionary=world.prepare_changes([{"op":"voxel.set","cell":{"x":p.x,"y":p.y,"z":p.z},"before":before,"after":0}],world.get_revision())
		var commit:Dictionary=world.commit_prepared(prepared.capability) if prepared.ok else prepared
		check("real authority edit during derivation commits through normal C CAS",waiting and commit.ok,commit.get("code"))
		view.process_budget(1)
		check("voxel revision change cancels stale ground before material or overlay publication",view.statistics().cancelled_jobs==cancelled+1 and not view.environment._ground.has(key))
		waiting=advance_until(view,"ground_materials");var revision:int=world.get_revision();view.cancel_pending()
		check("cancelling staged arrays leaves no overlays and no authority change",waiting and world.get_revision()==revision and view.statistics().pending==0 and not view.environment._ground.has(key))
	view.free();finish_split(args)
func finish_split(args:Array)->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"samples":samples,"scope":"Actual production process_budget(1) and unchanged pre-split snapshot, alternating fresh material caches on identical native input. Readiness, cancellation and CAS staleness checks. No OS/Metal/quiet window or hard 4ms qualification."}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
