extends "res://tests/buildings/family_generation_suite.gd"
## Original A clock/commit and all six services, with a frozen B service oracle.
## CPU hook timings only; never an app, FPS/GPU or quiet-window qualification.
const Reference=preload("res://tests/buildings/metadata_reference.gd")
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const Life=preload("res://scripts/runtime/resident_life.gd")

class MeterRuntime extends "res://scripts/runtime/game_runtime.gd":
	var rows:Array=[]
	func _commit(plan:Dictionary)->Dictionary:
		var started:=Time.get_ticks_usec();var result:Dictionary=super._commit(plan)
		var elapsed:=Time.get_ticks_usec()-started
		var ids:Array=[]
		for op:Dictionary in plan.get("world_changes",[]):ids.append(str(op.get("op"))+":"+str(op.get("id","")))
		rows.append({"ids":ids,"us":elapsed,"ok":result.ok,"code":result.get("code")})
		return result

func create_runtime(capture:Dictionary,reference:bool)->Dictionary:
	var w:=World.new();var loaded:Dictionary=w.load_snapshot(capture.world)
	if not loaded.ok:return loaded
	var b:RefCounted=Reference.new() if reference else Building.new()
	var services:Dictionary={"buildings":b,"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"gameplay":Gameplay.new(),"residents":Life.new()}
	var r:=MeterRuntime.new()
	var configured:Dictionary=r.configure({"world":w,"services":services,"facts":capture.facts,"source":capture.get("source",{}),"command_revision":capture.get("command_revision",0),"receipts":capture.get("receipts",{}),"definitions":JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))})
	return {"ok":configured.ok,"reason":configured.get("reason"),"world":w,"runtime":r,"building":b,"services":services}

func costs(rows:Array,controlled_metadata:bool)->Dictionary:
	var values:Array=[];var failures:Array=[]
	for row:Dictionary in rows:
		if not row.ok:failures.append(row)
		if row.ids==["extension.set:"+("fixture:metadata-cost" if controlled_metadata else "r33:gameplay")]:values.append(float(row.us)/1000)
	var sorted:=values.duplicate();sorted.sort();var total:=0.0
	for value:float in values:total+=value
	return {"count":values.size(),"first_ms":values[0] if not values.is_empty() else 0,"median_ms":sorted[sorted.size()/2] if not sorted.is_empty() else 0,"mean_ms":total/maxi(1,values.size()),"total_ms":total,"failures":failures,"samples_ms":values}

func actual_ticks(built:Dictionary,moving:bool,controlled_metadata:bool)->Dictionary:
	var r:RefCounted=built.runtime;r.rows.clear()
	var accepted:=0;var denied:=0;var query:RefCounted=built.building.current_space();var direction:=Vector2.ZERO
	var p:=Geometry.location(r.actor("player"))
	for d:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		var candidate:=p.duplicate(true);candidate.x+=d.x*0.04;candidate.z+=d.y*0.04
		if query.direct_move("player",p,candidate).ok:direction=d;break
	var start:=Time.get_ticks_usec()
	for tick:int in 40:
		if moving:
			var at:=Geometry.location(r.actor("player"));var sign:float=1 if tick%2==0 else -1
			at.x+=direction.x*0.04*sign;at.z+=direction.y*0.04*sign
			var result:Dictionary=r.command({"command_id":"metadata:move:"+str(tick),"actor_id":"player","kind":"direct_move","destination":at,"payload":{"movement_dt":0.1,"movement_mode":"walk"},"expected_revision":r.get_revision()})
			if result.ok:accepted+=1
			else:denied+=1
		r.tick(0.1)
		if controlled_metadata:
			# Deliberate metadata workload through the actual original transaction,
			# independently of E's reduced observer cursor frequency. No rewritten
			# validator or executor and no synthetic accepted gameplay events.
			r._commit({"world_changes":[built.building.extension_change("fixture:metadata-cost",{"tick":tick,"moving":moving})],"fact_changes":[]})
	var elapsed:float=float(Time.get_ticks_usec()-start)/1000
	return {"moving":moving,"controlled_metadata":controlled_metadata,"ticks":40,"accepted_moves":accepted,"denied_moves":denied,"wall_ms":elapsed,"metadata_commits":costs(r.rows,controlled_metadata),"capture":r.capture_checkpoint()}

func stage_actor(built:Dictionary,id:String,y_offset:float,revive:bool=false)->Dictionary:
	var before:Dictionary=built.runtime.actor(id);var after:=before.duplicate(true)
	after.y=float(after.y)+y_offset
	if revive:after.hp=100.0
	var op:Dictionary=built.building.extension_change("fixture:metadata",{"value":built.runtime.get_revision()})
	return {"ok":true,"world_changes":[op],"fact_changes":[{"collection":"actors","id":id,"before":before,"after":after}]}

func safety_pair(capture:Dictionary)->void:
	var old:=create_runtime(capture,true);var current:=create_runtime(capture,false)
	expect("paired exact safety runtimes configure",old.ok and current.ok)
	if not old.ok or not current.ok:return
	for built:Dictionary in [old,current]:
		for n:int in 2:
			var result:Dictionary=built.runtime._commit({"world_changes":[built.building.extension_change("fixture:metadata",{"value":n})],"fact_changes":[]})
			expect("metadata still passes complete original structure/actor safety",result.ok,result.get("reason"))
	var base:RefCounted=current.building.current_space();var validation:RefCounted=current.building._validation_space
	for built:Dictionary in [old,current]:
		var op:Dictionary=built.building.extension_change("fixture:metadata",{"value":3})
		var result:Dictionary=built.runtime._commit({"world_changes":[op],"fact_changes":[]})
		expect("another arbitrary metadata extension remains safe",result.ok)
	expect("same immutable current and staged projections retained after proven metadata commit",base==current.building.current_space() and validation==current.building._validation_space and base.world==current.world and validation.world==current.world and base.world.get_revision()==current.world.get_revision())
	for id:String in current.runtime.facts().actors.map(func(a:Dictionary)->String:return a.id):
		var before_old:Dictionary=old.runtime.capture_checkpoint();var before_current:Dictionary=current.runtime.capture_checkpoint()
		var rejected_old:Dictionary=old.runtime._commit(stage_actor(old,id,5.0))
		var rejected_new:Dictionary=current.runtime._commit(stage_actor(current,id,5.0))
		expect("cached metadata still rejects each living actor's unsupported staged feet "+id,not rejected_new.ok and rejected_new.get("code")=="SPATIAL_REJECTED" and rejected_old==rejected_new and Data.json_equal(before_old,old.runtime.capture_checkpoint()) and Data.json_equal(before_current,current.runtime.capture_checkpoint()),{"reference":rejected_old,"current":rejected_new})
	# Same immutable geometry, different final permissions: staged binding must
	# change even when every geometry cache and world revision is retained.
	var target:Dictionary=current.building.instance("RH-VILLAGE:neighbor:storage")
	for allowed:bool in [true,false,true]:
		var staged:Dictionary=current.runtime.facts()
		for a:Dictionary in staged.actors:
			if a.id=="player":a.householdId=target.owner if allowed else "fixture:other-household"
		var op:Dictionary=current.building.extension_change("fixture:permissions",{"allowed":allowed})
		var draft:Dictionary=current.world.prepare_changes([op],current.world.get_revision())
		var valid:Dictionary=current.building.validate_world_draft(draft.view,staged,[op])
		var reason:Variant=current.building._validation_space.permission.call("player",target.id,"remove",target)
		expect("retained query rebinds current staged permissions "+str(allowed),valid.ok and (reason==null)==allowed)
		current.world.discard_prepared(draft.capability)
	# A real solid entity mutation must rebuild the draft, not borrow a former
	# metadata certificate. It is rejected without changing either authority.
	var results:Dictionary={}
	for name:String in ["reference","current"]:
		var built:Dictionary=old if name=="reference" else current
		var at:=Geometry.location(built.runtime.actor("player"));var lo:=Geometry.point(at)+Vector3(-0.25,0.02,-0.25)
		var entity:Dictionary={"id":"fixture:metadata-obstacle","kind":"prop","regionId":at.regionId,"position":Geometry.json_point(Geometry.point(at)),"bounds":Geometry.json_box(AABB(lo,Vector3(0.5,1.76,0.5))),"revision":0,"data":{"solid":true,"opaque":true}}
		var before:Dictionary=built.runtime.capture_checkpoint()
		results[name]=built.runtime._commit({"world_changes":[built.building.extension_change("fixture:metadata",{"value":4}),{"op":"entity.put","id":entity.id,"before_exists":false,"before":null,"after":entity}],"fact_changes":[]})
		expect(name+" mixed actual obstruction leaves authority unchanged",Data.json_equal(before,built.runtime.capture_checkpoint()))
	expect("mixed entity change cannot reuse metadata proof",not results.current.ok and results.current.get("code")=="SPATIAL_REJECTED" and results.reference==results.current,results)
	# The dependency classifier is fail closed for all actual spatial mutation
	# operations and all generation plans, not keyed to a gameplay extension.
	for op:Dictionary in [{"op":"voxel.set"},{"op":"chunk.put"},{"op":"chunk.residency"},{"op":"region.put"},{"op":"entity.remove"},{"op":"extension.set","id":"r3:structures","before_exists":false,"before":null,"after":{}},{"op":"extension.set","id":"generation:RH-HOME","before_exists":false,"before":null,"after":{}},{"op":"unknown"}]:
		expect("spatial or incomplete mutation invalidates retained projection "+str(op),not Building.metadata_preserves_geometry([op]))

func run()->void:
	var started:=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(973339546,Building.generation_profiles()))
	expect("actual eighth seed prepares using original settlement composition",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish(started);return
	var rows:Array=[]
	for controlled_metadata:bool in [false,true]:
		for pass_index:int in 2:
			var samples:Dictionary={}
			for name:String in (["reference","production"] if pass_index==0 else ["production","reference"]):
				var built:=create_runtime(prepared.capture,name=="reference")
				expect("all six actual services configure "+name+str(pass_index)+str(controlled_metadata),built.ok,built.get("reason"))
				if not built.ok:continue
				var idle:=actual_ticks(built,false,controlled_metadata);var moving:=actual_ticks(built,true,controlled_metadata)
				samples[name]={"idle":idle,"moving":moving}
				for row:Dictionary in [idle,moving]:expect("actual original runtime ticks remain accepted "+name+str(pass_index)+str(row.moving)+str(controlled_metadata),(not controlled_metadata or row.metadata_commits.count==40) and row.metadata_commits.failures.is_empty() and row.denied_moves==0 and (not row.moving or row.accepted_moves==40),{"cost":row.metadata_commits,"moves":row.accepted_moves})
			for stage:String in ["idle","moving"]:
				if not samples.has_all(["reference","production"]):continue
				expect("complete original world facts events and time remain identical "+stage+str(pass_index)+str(controlled_metadata),Data.json_equal(samples.reference[stage].capture,samples.production[stage].capture))
				for name:String in ["reference","production"]:samples[name][stage].erase("capture")
			rows.append({"controlled_metadata":controlled_metadata,"pass":pass_index,"order":"old-first" if pass_index==0 else "new-first","samples":samples})
	safety_pair(prepared.capture)
	print("METADATA_RUNTIME_COST "+JSON.stringify(rows))
	finish(started)
