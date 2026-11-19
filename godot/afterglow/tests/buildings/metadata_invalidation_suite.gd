extends "res://tests/buildings/metadata_reuse_suite.gd"
## Real C capabilities and A commits after warmed metadata certificates.
## Rejections preserve the full authority; accepted physical edits invalidate.

func prime(built:Dictionary)->void:
	for n:int in 2:
		var result:Dictionary=built.runtime._commit({"world_changes":[built.building.extension_change("fixture:prime",n)],"fact_changes":[]})
		expect("metadata projection priming is a real accepted transaction",result.ok,result.get("reason"))
	built.building.current_space()

func voxel_op(built:Dictionary,at:Vector3,material:int)->Dictionary:
	var size:float=built.world.config().cellSize
	var cell:=Vector3i(floori(at.x/size),floori(at.y/size),floori(at.z/size))
	return {"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":built.world.cell_at(cell.x,cell.y,cell.z),"after":material}

func unsafe_plan(built:Dictionary,kind:String)->Dictionary:
	var p:=Geometry.location(built.runtime.actor("player"))
	var changes:Array=[built.building.extension_change("fixture:unsafe",kind)]
	if kind=="head voxel":changes.append(voxel_op(built,Geometry.point(p)+Vector3(0,0.9,0),3))
	elif kind=="resident exit":
		for a:Dictionary in built.runtime.facts().actors:
			if float(a.hp)<=0 or a.get("buildingId")==null:continue
			var key:="generation:"+str(a.regionId);var plan:Dictionary=built.world.extension(key)
			var found:=false
			for slot:Dictionary in plan.get("slots",[]):
				if slot.get("kind")=="entrance" and slot.get("buildingId")==a.buildingId:
					slot.x+=10000
					# Canonical location() prioritizes nested position over legacy x.
					slot.position.x+=10000
					found=true
			if found:changes.append(built.building.extension_change(key,plan));break
	return {"world_changes":changes,"fact_changes":[]}

func rejection_cases(capture:Dictionary)->void:
	for kind:String in ["head voxel","resident exit"]:
		var results:Dictionary={}
		for name:String in ["reference","production"]:
			var built:=create_runtime(capture,name=="reference");expect("real rejection runtime configures "+kind+name,built.ok)
			if not built.ok:continue
			prime(built)
			var before:Dictionary=built.runtime.capture_checkpoint();var plan:=unsafe_plan(built,kind)
			expect("counterexample contains a real physical change "+kind+name,plan.world_changes.size()==2 and not Building.metadata_preserves_geometry(plan.world_changes))
			results[name]=built.runtime._commit(plan)
			expect("unsafe edit preserves full authority "+kind+name,Data.json_equal(before,built.runtime.capture_checkpoint()))
		expect("warmed metadata proof cannot hide real unsafe "+kind,results.has_all(["reference","production"]) and not results.production.ok and results.production.get("code")=="SPATIAL_REJECTED" and results.reference==results.production,results)

func safe_changes(built:Dictionary,kind:String)->Array:
	var p:=Geometry.location(built.runtime.actor("player"))
	if kind=="region":
		var region:Dictionary=built.world.region(p.regionId);var after:=region.duplicate(true);after.fixture_label="changed"
		return [{"op":"region.put","id":region.id,"before_exists":true,"before":region,"after":after}]
	if kind=="generation":
		var key:="generation:"+str(p.regionId);var plan:Dictionary=built.world.extension(key);plan.fixture_label="changed"
		return [built.building.extension_change(key,plan)]
	if kind=="entity":
		var entity:Dictionary={"id":"fixture:non-solid","kind":"prop","regionId":p.regionId,"position":Geometry.json_point(Geometry.point(p)),"bounds":Geometry.json_box(AABB(Geometry.point(p),Vector3.ONE)),"revision":0,"data":{"solid":false}}
		return [{"op":"entity.put","id":entity.id,"before_exists":false,"before":null,"after":entity}]
	if kind=="residency":
		# Existing B standing semantics read known geometry; C separately gates
		# streamed actions by residency. Preserve the original accepted result,
		# but prove the projection really invalidates and sees the new flag.
		var cfg:Dictionary=built.world.config();var width:float=cfg.cellSize*cfg.chunkCells
		var key:=Data.key(Vector3i(floori(float(p.x)/width),floori(float(p.y)/width),floori(float(p.z)/width)))
		return [{"op":"chunk.residency","id":key,"before":built.world.chunk(key).resident,"after":false}]
	if kind=="chunk replacement":
		var cfg:Dictionary=built.world.config();var width:float=cfg.cellSize*cfg.chunkCells
		var key:=Data.key(Vector3i(floori(float(p.x)/width),floori(float(p.y)/width),floori(float(p.z)/width)))
		var chunk:Dictionary=built.world.chunk(key);var after:=chunk.duplicate(true);after.revision=int(chunk.revision)+1
		return [{"op":"chunk.put","id":key,"before_exists":true,"before":chunk,"after":after}]
	if kind=="deep voxel":
		var at:=Geometry.point(p);at.y=(int(built.world.config().minCellY)+1)*float(built.world.config().cellSize)
		var op:=voxel_op(built,at,1);op.after=2 if op.before==1 else 1
		return [op]
	if kind=="structure HP":
		var data:Dictionary=built.building.structures();var piece:Dictionary=data.instances[0];piece.hp-=1;piece.version+=1
		return built.building.changes_for(data,[piece],[])
	return []

func accepted_invalidation(capture:Dictionary)->void:
	for kind:String in ["region","generation","entity","residency","chunk replacement","deep voxel","structure HP"]:
		var results:Dictionary={};var captures:Dictionary={}
		for name:String in ["reference","production"]:
			var built:=create_runtime(capture,name=="reference");expect("accepted mutation runtime configures "+kind+name,built.ok)
			if not built.ok:continue
			prime(built)
			var previous:RefCounted=built.building.current_space();var prior_validation:RefCounted=built.building._validation_space
			var changes:=safe_changes(built,kind);changes.append(built.building.extension_change("fixture:mixed",kind))
			results[name]=built.runtime._commit({"world_changes":changes,"fact_changes":[]})
			expect("actual nonmetadata edit remains accepted "+kind+name,results[name].ok,results[name].get("reason"))
			if not results[name].ok:continue
			expect("physical mutation invalidates both exact projections "+kind+name,built.building._space==null and built.building._validation_space==null)
			var check:Dictionary=built.runtime._commit({"world_changes":[built.building.extension_change("fixture:after-edit",kind)],"fact_changes":[]})
			var fresh:RefCounted=built.building.current_space()
			expect("following metadata uses fresh current geometry "+kind+name,check.ok and fresh!=previous and fresh.world==built.world and (name=="reference" or (built.building._validation_space!=prior_validation and built.building._validation_space.world==built.world)))
			if kind=="residency":expect("fresh projection reads actual changed residency "+name,not fresh.world.chunk(str(changes[0].id)).resident)
			captures[name]=built.runtime.capture_checkpoint()
		expect("accepted mutation complete result and authority equal original "+kind,results.has_all(["reference","production"]) and results.reference==results.production and captures.has_all(["reference","production"]) and Data.json_equal(captures.reference,captures.production))

func revival_and_revision(capture:Dictionary)->void:
	var captures:Dictionary={};var results:Dictionary={}
	for name:String in ["reference","production"]:
		var built:=create_runtime(capture,name=="reference");expect("HP and revision runtime configures "+name,built.ok)
		if not built.ok:continue
		prime(built)
		var down:=stage_actor(built,"player",5.0);down.fact_changes[0].after.hp=0.0
		var accepted:Dictionary=built.runtime._commit(down)
		expect("dead staged actor keeps original nonblocking semantics "+name,accepted.ok,accepted.get("reason"))
		var before:Dictionary=built.runtime.capture_checkpoint()
		results[name]=built.runtime._commit(stage_actor(built,"player",0,true))
		expect("revival rechecks staged feet despite same geometry "+name,not results[name].ok and results[name].get("code")=="SPATIAL_REJECTED" and Data.json_equal(before,built.runtime.capture_checkpoint()),results[name])
		var previous:RefCounted=built.building.current_space();var validation:RefCounted=built.building._validation_space
		var bypass:Dictionary=built.world.prepare_changes([built.building.extension_change("fixture:direct-capability",true)],built.world.get_revision())
		expect("isolated direct C capability commits without runtime signal "+name,bypass.ok and built.world.commit_prepared(bypass.capability).ok)
		var check:Dictionary=built.runtime._commit({"world_changes":[built.building.extension_change("fixture:after-gap",true)],"fact_changes":[]})
		expect("skipped revision cannot carry old projections "+name,check.ok and built.building.current_space()!=previous and (name=="reference" or built.building._validation_space!=validation))
		var at_revision:int=built.world.get_revision();var current:RefCounted=built.building.current_space();var valid:RefCounted=built.building._validation_space
		var no_op:Dictionary=built.runtime._commit({"world_changes":[built.building.extension_change("fixture:after-gap",true)],"fact_changes":[]})
		expect("exact no-op retains world revision and valid projection "+name,no_op.ok and built.world.get_revision()==at_revision and (name=="reference" or (built.building.current_space()==current and built.building._validation_space==valid)))
		captures[name]=built.runtime.capture_checkpoint()
	expect("HP rejection agrees with original validator",results.has_all(["reference","production"]) and results.reference==results.production)
	expect("full authority agrees after revival rejection and revision gaps",captures.has_all(["reference","production"]) and Data.json_equal(captures.reference,captures.production))

func run()->void:
	var started:=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(973339546,Building.generation_profiles()))
	expect("real eighth seed prepares for adversarial invalidation",prepared.ok,prepared.get("reason"))
	if prepared.ok:
		rejection_cases(prepared.capture)
		accepted_invalidation(prepared.capture)
		revival_and_revision(prepared.capture)
	finish(started)
