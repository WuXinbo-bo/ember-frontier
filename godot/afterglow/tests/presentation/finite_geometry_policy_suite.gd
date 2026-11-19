extends "res://tests/buildings/domain_suite.gd"
## Real generated/assembled finite rural data; isolated observation/residency
## fixtures only. No formal application, player route, pixel or VA evidence.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const Data=preload("res://scripts/world/world_data.gd")

func commit(changes:Array,label:String)->bool:
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	var ok:bool=draft.ok and world.commit_prepared(draft.capability).ok
	expect(label,ok,draft.get("code"))
	return ok

func find_pair(offset:float=3.0,require_sight:bool=true)->Dictionary:
	var edge:float=world.region("RH-HOME").bounds.min.z
	var q:RefCounted=building.current_space()
	for x:int in range(3,61):
		var points:Array=[]
		for side:float in [1.0,-1.0]:
			var z:float=edge+side*offset
			var y:Variant=world.surface_height(x,z)
			if y==null:continue
			var at:Dictionary=q.standing_point({"x":float(x),"y":float(y),"z":z,"regionId":"RH-HOME" if side>0 else "RH-VILLAGE","buildingId":null,"storeyId":null})
			if not at.is_empty() and at.get("buildingId")==null:points.append(at)
		if points.size()==2 and (not require_sight or q.line_clear(points[0],points[1])) and world.continuous_outdoor_segment(points[0],points[1],256.0,true).ok:return {"from":points[0],"to":points[1]}
	return {}

func shell(at:Dictionary)->Dictionary:
	return {"id":"ddd:finite-geometry-fixture","position":Geometry.json_point(Geometry.point(at)),"regionId":at.regionId,"buildingId":at.get("buildingId"),"storeyId":at.get("storeyId")}

func rebind(policy:RefCounted,at:Dictionary)->void:
	policy.configure(building.current_space());policy.sample(at,0)

func run()->void:
	var started:int=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	expect("actual generated rural-3 composition prepares",prepared.ok,prepared.get("code"))
	if not prepared.ok:finish_local(started);return
	expect("sole world loads actual finite composition",world.load_snapshot(prepared.capture.world).ok)
	expect("actual A/B services accept generated facts",runtime.configure({"world":world,"facts":prepared.capture.facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var warm:Array=[]
	for id:String in world.chunk_keys():
		if not world.chunk(id).resident:warm.append({"op":"chunk.residency","id":id,"before":false,"after":true})
	if not warm.is_empty():commit(warm,"explicit observation fixture warms existing generated data")
	var pair:Dictionary=find_pair()
	expect("real clear supported seam spans six metres",not pair.is_empty(),pair)
	if pair.is_empty():finish_local(started);return
	var policy:=Policy.new();rebind(policy,pair.from)
	var target:Dictionary=shell(pair.to)
	var before:Dictionary=runtime.capture_checkpoint()
	expect("outdoor geometry crosses management labels beyond hand reach",policy.base_visible(target,"floor") and policy.can_observe_geometry(target,pair.from) and not world.continuous_outdoor_contact(pair.from,pair.to).ok)
	var foreign_shell:Dictionary=target.duplicate(true);foreign_shell.buildingId="fixture:external-building";foreign_shell.storeyId="fixture:external-storey"
	expect("external wall and roof retain actual spatial metadata across seam",policy.base_visible(foreign_shell,"wall") and policy.base_visible(foreign_shell,"roof"))
	expect("foreign interior furniture never borrows exterior eligibility",not policy.can_observe_geometry(foreign_shell,pair.from))
	expect("hidden caps remain unpickable across region seam",not policy.base_visible(target,"cap"))
	var queries:int=policy.statistics().coverage_queries
	for i:int in 4:policy.base_visible(target,"floor");policy.can_observe_geometry(target,pair.from)
	expect("same exact geometry anchor reuses C proof across view consumers",policy.statistics().coverage_queries==queries and policy.statistics().coverage_hits>=8,policy.statistics())
	var moved_target:Dictionary=target.duplicate(true);moved_target.position.x+=0.01
	policy.base_visible(moved_target,"floor")
	expect("moving target within one cell still invalidates its exact proof",policy.statistics().coverage_queries==queries+1)
	var moved_observer:Dictionary=pair.from.duplicate(true);moved_observer.x+=0.01
	policy.sample(moved_observer,0);queries=policy.statistics().coverage_queries;policy.base_visible(target,"floor")
	expect("moving observer within one cell never reuses quantized eligibility",policy.statistics().coverage_queries==queries+1)
	policy.sample(pair.from,0);policy.base_visible(target,"floor")
	var signature:String=policy.signature()
	policy.configure(building.space())
	expect("equal query rebind clears coverage without resetting stable room scope",policy.statistics().coverage_entries==0 and policy.signature()==signature)
	policy.base_visible(target,"floor")
	expect("repeated geometry observations leave all authority unchanged",Data.json_equal(before,runtime.capture_checkpoint()))
	var q:RefCounted=building.current_space();var external:Array=[]
	for piece:Dictionary in q.pieces:
		if piece.regionId!=pair.to.regionId or piece.get("buildingId")==null:continue
		var role:String=q.geometry.definition(piece).kind
		if role not in ["wall","roof"]:continue
		var at:Dictionary=Geometry.location(piece);at.buildingId=null;at.storeyId=null
		if world.continuous_outdoor_segment(pair.from,at,256.0,true).ok:
			external.append(piece.id)
			if not policy.base_visible(piece,role):break
	expect("real generated neighboring building shell uses finite geometry scope",not external.is_empty() and external.all(func(id:String)->bool:return policy.base_visible(q.by_id[id],q.geometry.definition(q.by_id[id]).kind)),{"pieces":external.size()})
	var cfg:Dictionary=world.config();var width:float=float(cfg.cellSize)*int(cfg.chunkCells)
	var long_pair:Dictionary=find_pair(12.0,false)
	expect("actual finite data supplies supported 24-metre geometry segment",not long_pair.is_empty(),long_pair)
	if not long_pair.is_empty():
		var inner:Vector3=Geometry.point(long_pair.from).lerp(Geometry.point(long_pair.to),0.5)
		var inner_key:String="%d,%d,%d"%[floori(inner.x/width),floori(inner.y/width),floori(inner.z/width)]
		var long_target:Dictionary=shell(long_pair.to);policy.sample(long_pair.from,0)
		expect("long resident geometry segment is initially eligible",policy.base_visible(long_target,"wall"))
		if commit([{"op":"chunk.residency","id":inner_key,"before":true,"after":false}],"interior-only chunk becomes cold with both endpoint chunks resident"):
			var from:Vector3=Geometry.point(long_pair.from);var to:Vector3=Geometry.point(long_pair.to)
			expect("fixture retains both actual endpoint residency tokens",world.is_cell_resident(floori(from.x/cfg.cellSize),floori(from.y/cfg.cellSize),floori(from.z/cfg.cellSize)) and world.is_cell_resident(floori(to.x/cfg.cellSize),floori(to.y/cfg.cellSize),floori(to.z/cfg.cellSize)))
			expect("endpoint eligibility cannot bypass a genuinely cold intermediate chunk",not policy.base_visible(long_target,"wall"))
			if commit([{"op":"chunk.residency","id":inner_key,"before":false,"after":true}],"same intermediate generated chunk becomes resident again"):
				expect("long live proof recovers only after actual intermediate residency",policy.base_visible(long_target,"wall"))
		policy.sample(pair.from,0)
	var middle:Vector3=Geometry.point(pair.from).lerp(Geometry.point(pair.to),0.5)
	var key:String="%d,%d,%d"%[floori(middle.x/width),floori(middle.y/width),floori(middle.z/width)]
	var other_key:String=""
	for id:String in world.chunk_keys():
		var chunk:Dictionary=world.chunk(id)
		if id!=key and Vector3(chunk.coord.x,chunk.coord.y,chunk.coord.z).distance_to(middle/width)>5.0:other_key=id;break
	expect("actual world supplies unrelated far-corner chunk",not other_key.is_empty(),other_key)
	if not other_key.is_empty() and commit([{"op":"chunk.residency","id":other_key,"before":true,"after":false}],"unrelated far-corner residency withdrawn in isolated world"):
		rebind(policy,pair.from)
		expect("unrelated cold corner does not hide resident seam geometry",policy.base_visible(target,"floor") and policy.can_observe_geometry(target,pair.from))
	if commit([{"op":"chunk.residency","id":key,"before":true,"after":false}],"actual traversed chunk becomes cold"):
		expect("same query cannot reuse old proof after actual world revision",not policy.base_visible(target,"floor"))
		rebind(policy,pair.from)
		expect("old positive geometry proof cannot survive cold segment",not policy.base_visible(target,"floor") and not policy.can_observe_geometry(target,pair.from))
		if commit([{"op":"chunk.residency","id":key,"before":false,"after":true}],"same real chunk residency restored"):
			rebind(policy,pair.from)
			expect("same live policy restores geometry after residency change",policy.base_visible(target,"floor") and policy.can_observe_geometry(target,pair.from))
	var known:Dictionary=world.chunk(key);var unknown:Dictionary=known.duplicate(true);unknown.generated=false
	if commit([{"op":"chunk.put","id":key,"before_exists":true,"before":known,"after":unknown}],"actual traversed chunk retains identity but becomes ungenerated"):
		rebind(policy,pair.from)
		expect("existing but ungenerated segment cannot show remote geometry",not policy.base_visible(target,"wall") and not policy.can_observe_geometry(target,pair.from))
		unknown=world.chunk(key);known.revision=unknown.revision
		if commit([{"op":"chunk.put","id":key,"before_exists":true,"before":unknown,"after":known}],"original generated chunk restored through C capability"):rebind(policy,pair.from)
	# Re-loading a different valid snapshot into the same WorldState can keep
	# its numeric revision. New immutable query identity must discard coverage.
	var saved:Dictionary=world.snapshot();var rebound_snapshot:Dictionary=saved.duplicate(true)
	rebound_snapshot.chunks[key].resident=false
	expect("explicit same-revision snapshot fixture loads",world.load_snapshot(rebound_snapshot).ok)
	policy.configure(building.space());policy.sample(pair.from,0)
	expect("equal world revision cannot preserve coverage across snapshot rebind",not policy.base_visible(target,"wall"))
	expect("original isolated snapshot restores without reseeding",world.load_snapshot(saved).ok)
	policy.configure(building.space());policy.sample(pair.from,0)
	expect("same policy recovers exact resident snapshot geometry",policy.base_visible(target,"wall"))
	var wrong:Dictionary=target.duplicate(true);wrong.regionId="RH-HOME"
	expect("false region metadata cannot create cross-region eligibility",not policy.can_observe_geometry(wrong,pair.from))
	var missing:Dictionary=target.duplicate(true);missing.position.x=1000.0
	expect("unknown remote space never acquires geometric visibility",not policy.base_visible(missing,"wall") and not policy.can_observe_geometry(missing,pair.from))
	# Real opaque-but-nonsolid object tests B sight, not contact or cutaway.
	var box:=AABB(middle+Vector3(-0.5,-1.0,-0.04),Vector3(1,4,0.08))
	var blocker:Dictionary={"id":"ddd:finite-opaque-fixture","kind":"prop","regionId":pair.from.regionId,"position":Geometry.json_point(middle),"bounds":Geometry.json_box(box),"revision":0,"data":{"solid":false,"opaque":true}}
	if commit([{"op":"entity.put","id":blocker.id,"before_exists":false,"before":null,"after":blocker}],"opaque nonsolid fixture commits through actual authority"):
		rebind(policy,pair.from)
		expect("outdoor fixed shell still respects actual opaque B sight",not policy.can_observe_geometry(target,pair.from))
	var legacy:Dictionary=Generator.generate(713)
	expect("retained rural-1 source loads",world.load_snapshot(legacy).ok)
	initialize_at(pair.from)
	rebind(policy,pair.from)
	expect("old portal-bound rural-1 does not gain cross-region shell visibility",not policy.base_visible(target,"floor") and not policy.can_observe_geometry(target,pair.from))
	finish_local(started)

func finish_local(started:int)->void:
	var result:Dictionary={"scope":"actual generated finite rural-3 policy plus explicit supported poses/residency/opaque fixtures; no OS/VA","checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_FINITE_GEOMETRY "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
