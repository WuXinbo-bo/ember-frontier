extends "res://tests/world/environment_mount.gd"
## Same saved world, exact same native mesh/shape/ground work, bounded queue
## comparison. A 60Hz headless pump is a scheduler fixture, not rendered FPS.
const PriorBudget=preload("res://tests/world/fixtures/terrain_before_budget17.gd")
const PriorFields17=preload("res://tests/world/fixtures/field_surfaces_before_projection17.gd")
const CurrentFields17=preload("res://scripts/environment/field_surfaces.gd")
var selected:Array=[]
var rows:Array=[]
var signatures:Array=[]
const OBSERVED16_MAX={"materials":33623,"mesh":27695,"ground":25492,"shape":19693,"ground_materials":19206,"ground_fields":8598,"ground_shoulders":5567}
func seed_history(view:Node3D)->void:
	for stage:String in OBSERVED16_MAX:
		view._stage_costs[stage]={"calls":0,"total_usec":0,"max_usec":OBSERVED16_MAX[stage],"over_4ms":0}
func terrain_signature(view:Node3D)->String:
	var result:Array=[]
	for key:String in selected:
		var row:Array=[key]
		if view._chunks.has(key):row.append(node_data(view._chunks[key].node))
		for collection:String in ["_ground","_contacts","_fields"]:
			var nodes:Dictionary=view.environment.get(collection)
			row.append(node_data(nodes[key]) if nodes.has(key) else [])
		result.append(row)
	return digest(result)
func drain(view:Node3D,budget:int,label:String)->Dictionary:
	view.prioritize(selected)
	var started:int=Time.get_ticks_usec();var frames:int=0;var cpu:int=0;var peak:int=0
	var ready:Dictionary=view.readiness(selected);var next_check:int=0
	while not ready.get("ready",false) and frames<2400:
		var tick:int=Time.get_ticks_usec();view.process_budget(budget)
		var elapsed:int=Time.get_ticks_usec()-tick;cpu+=elapsed;peak=maxi(peak,elapsed)
		frames+=1;await process_frame
		if Time.get_ticks_msec()>=next_check:
			ready=view.readiness(selected);view.prioritize(ready.pending);next_check=Time.get_ticks_msec()+50
	var result:Dictionary={"label":label,"budget_usec":budget,"frames":frames,"wall_ms":(Time.get_ticks_usec()-started)/1000.0,"cpu_usec":cpu,"peak_unit_usec":peak,"ready":ready,"stats":view.statistics()}
	check(label+" retains actual geometry and later-physics gate",ready.ready and ready.geometry_ready and ready.physics_ready,result)
	return result
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var out:String=args[0];var input:String=args[1]
	DirAccess.make_dir_recursive_absolute(out);Engine.max_fps=60
	var loaded:Dictionary=Store.new(input).load_current()
	check("exact real saved content16 decodes",loaded.ok and int(loaded.capture.world.extensions.get("generation:factory-r34",{}).get("content_version",0))==16)
	if not loaded.ok:quit(1);return
	world=State.new();check("complete real world loads",world.load_snapshot(loaded.capture.world).ok)
	var source_sha:String=FileAccess.get_sha256(str(loaded.path))
	var region:String="RH-HOME" if args.size()<3 else args[2]
	var budget:int=4000 if args.size()<4 else int(args[3])
	var count:int=128 if args.size()<5 else int(args[4])
	# Native saves deliberately restore transient residency as cold. Use the
	# ORIGINAL lossless storage conversion before comparing the two consumers;
	# never regenerate or substitute any saved voxel/entity/extension facts.
	var warm:Dictionary=world.prepare_region_residency(region,true,world.get_revision(),256)
	var prepared:Dictionary=world.prepare_changes_without_view(warm.world_changes,world.get_revision()) if warm.ok else warm
	check("original lossless region warm CAS succeeds",prepared.ok and world.commit_prepared(prepared.capability).ok)
	var initial:String=digest(world.snapshot())
	# Include every actual saved farm chunk, then the surrounding ordinary
	# chunk set. An arbitrary first half of a region can contain no crop layer.
	var plan:Variant=world.extension("generation:"+region)
	for key:String in plan.get("field_surfaces",{}).get("chunks",{}):
		if world.chunk_metadata(key).get("resident",false):selected.append(key)
	for key:String in world.region_chunk_keys(region):
		if world.chunk_metadata(key).get("resident",false) and not selected.has(key):selected.append(key)
	selected=selected.slice(0,count)
	check("same finite real resident chunk set available",selected.size()==count)
	if selected.size()!=count:quit(1);return
	var fields_equal:=true;var field_chunks:int=0;var before_fields_usec:int=0;var after_fields_usec:int=0
	for key:String in selected:
		var began:int=Time.get_ticks_usec();var old:Dictionary=PriorFields17.capture(world,key);before_fields_usec+=Time.get_ticks_usec()-began
		began=Time.get_ticks_usec();var current:Dictionary=CurrentFields17.capture(world,key);after_fields_usec+=Time.get_ticks_usec()-began
		fields_equal=fields_equal and old==current
		if not current.groups.is_empty():field_chunks+=1
	check("narrow generation projection preserves actual farm vertices UV textures and support rows",fields_equal and field_chunks>0,{"actual_field_chunks":field_chunks,"old_usec":before_fields_usec,"new_usec":after_fields_usec})
	var shared_materials:RefCounted
	for current:bool in [false,true]:
		var view:Node3D=Terrain.new() if current else PriorBudget.new();root.add_child(view);view.set_process(false)
		var context:Dictionary={"world":world,"stream_updates":true,"budgeted_edits":true}
		if shared_materials!=null:context.materials=shared_materials
		view.configure(context);shared_materials=view.materials
		seed_history(view)
		check(("new" if current else "old")+" starts with mandatory pending geometry",not view.readiness(selected).ready)
		rows.append(await drain(view,budget,"recent-stage-window" if current else "lifetime-max-before"))
		signatures.append(terrain_signature(view))
		if current:
			check("lifetime expensive peaks remain exposed as evidence",view.statistics().stages.materials.max_usec>=OBSERVED16_MAX.materials)
			check("recent estimate window stays bounded",view._recent_stage_costs.values().all(func(v:Array)->bool:return v.size()<=4))
		view.cancel_pending();view.free();await process_frame
	check("exact same real meshes UV normals materials ground and collision faces",signatures[0]==signatures[1],signatures)
	check("complete world and original saved bytes remain unchanged",initial==digest(world.snapshot()) and source_sha==FileAccess.get_sha256(str(loaded.path)))
	check("same work completes with fewer scheduling frames",rows[1].frames<rows[0].frames,{"before":rows[0].frames,"after":rows[1].frames})
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"source_sha256":source_sha,"keys":selected,"stage_history_source":"experience16/packed-graphics/stdout.log actual historical maxima; injected identically into both consumers to reproduce persistent high-water scheduling after a cold upload","scope":"Same saved world and 60Hz paused headless scheduler fixture with original actual mesh/shape/ground publication and readiness. Shared material instance is old-first; wall/CPU values are diagnostic, not GUI/FPS acceptance."},"\t",true,true))
	print(JSON.stringify({"suite":"terrain_budget17","checks":checks.size(),"failed":failed,"before_frames":rows[0].frames,"after_frames":rows[1].frames}));quit(1 if failed else 0)
