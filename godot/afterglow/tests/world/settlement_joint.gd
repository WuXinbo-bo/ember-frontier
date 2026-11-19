extends SceneTree
const Generator=preload("res://scripts/world/settlement_generator.gd")
const OldGenerator=preload("res://scripts/world/rural_generator.gd")
const State=preload("res://scripts/world/world_state.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Actions=preload("res://scripts/actions/action_service.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var checks: Array=[]
var costs: Dictionary={}
func _initialize() -> void: call_deferred("run")
func check(label: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok: push_error("FAIL "+label+" "+str(detail))
func actor_at(p: Dictionary) -> Dictionary:
	return {"id":"player","x":p.x,"y":p.y,"z":p.z,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"skills":{},"pack":{},"intent":null,"relationship":{"consent":true}}
func run() -> void:
	for coord in [Vector2i.ZERO,Vector2i(0,-1)]:
		var planned: Dictionary=Generator.plan_region(713,coord,Building.generation_profiles())
		check("current B contract produces terrain plan "+str(coord),planned.ok,{"code":planned.get("code"),"reason":planned.get("reason")})
		if not planned.ok:return finish()
	var world:=State.new();var result: Dictionary=world.load_snapshot(Generator.generate(713,Building.generation_profiles()))
	check("actual generated settlement world loaded",result.ok,result)
	if not result.ok: return finish()
	var building:=Building.new();var runtime:=Runtime.new()
	var facts: Dictionary={"actors":[actor_at(world.extension("generation:RH-HOME").anchors.arrival)],"stocks":OldGenerator.empty_resource_stocks(world),"actions":[],"quests":[],"time":0.0,"status":"playing"}
	runtime.configure({"world":world,"facts":facts,"services":{"buildings":building}})
	walk_paths(world,building,"terrain before B construction")
	var query: RefCounted=building.current_space()
	var home: Dictionary=world.extension("generation:RH-HOME")
	var from: Dictionary=home.anchors.arrival.duplicate();from.merge({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var to: Dictionary=home.anchors.home.duplicate();to.merge({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var long_route: Dictionary=query.route("player",from,to)
	check("B automatic full-route planning follows real graded access",long_route.ok,{"from":from,"to":to,"result":long_route})
	var second_world:=State.new();second_world.load_snapshot(Generator.generate(2026,Building.generation_profiles()))
	var second_runtime:=Runtime.new();var second_building:=Building.new()
	var second_facts: Dictionary={"actors":[actor_at(second_world.extension("generation:RH-HOME").anchors.arrival)],"stocks":OldGenerator.empty_resource_stocks(second_world),"actions":[],"quests":[],"time":0.0,"status":"playing"}
	second_runtime.configure({"world":second_world,"facts":second_facts,"services":{"buildings":second_building}})
	walk_paths(second_world,second_building,"seed2026 terrain before B construction")
	var second_proposal: Dictionary=second_building.prepare_generation(second_world)
	check("seed2026 real B family producer resolves same persistent plan",second_proposal.ok,second_proposal.get("reason"))
	if second_proposal.ok:
		second_facts.stocks.append_array(second_proposal.initial_stocks)
		var second_prod:=Production.empty_state();second_prod.tools=second_proposal.initial_tools;second_prod.records=second_proposal.initial_records
		var second_changes: Array=second_proposal.world_changes.duplicate(true)
		second_changes.append({"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":second_prod})
		var second_draft: Dictionary=second_world.prepare_changes(second_changes,second_world.get_revision())
		var second_safe: Dictionary=second_building.validate_world_draft(second_draft.view,second_facts,second_changes) if second_draft.ok else second_draft
		check("seed2026 actual complete family draft passes same C/B safety",second_safe.ok,second_safe)
		if second_safe.ok:
			second_world.commit_prepared(second_draft.capability)
			second_runtime.configure({"world":second_world,"facts":second_facts,"services":{"buildings":second_building,"production":Production.new()}})
			walk_paths(second_world,second_building,"seed2026 complete B family graph")
		elif second_draft.ok:second_world.discard_prepared(second_draft.capability)
	var start:=Time.get_ticks_usec()
	var proposal: Dictionary=building.prepare_generation(world)
	costs.b_preparation_ms=(Time.get_ticks_usec()-start)/1000.0
	check("actual B family producer consumes C persistent parcels",proposal.ok and proposal.get("assembled_parcels",[]).size()==5,{"ok":proposal.ok,"reason":proposal.get("reason"),"assembled":proposal.get("assembled_parcels"),"spawn_points":proposal.get("spawn_points")})
	if not proposal.ok: return finish()
	facts.stocks.append_array(proposal.initial_stocks)
	var prod:=Production.empty_state();prod.tools=proposal.initial_tools;prod.records=proposal.initial_records
	var changes: Array=proposal.world_changes.duplicate(true)
	changes.append({"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":prod})
	var draft: Dictionary=world.prepare_changes(changes,world.get_revision())
	check("C full isolated capability accepts real B family graph/production",draft.ok,{"operations":changes.size(),"reason":draft.get("reason")})
	if not draft.ok: return finish()
	start=Time.get_ticks_usec()
	var safety: Dictionary=building.validate_world_draft(draft.view,facts,changes)
	costs.b_final_draft_validation_ms=(Time.get_ticks_usec()-start)/1000.0
	check("real B final-draft support/body/egress on actual nonflat C cells",safety.ok,safety)
	if not safety.ok:
		var data: Dictionary=building.structures(draft.view)
		var draft_query: RefCounted=building.space(draft.view,data,facts)
		var terrain_conflicts: Array=[]
		for v in data.instances:
			if building.geometry.definition(v).kind=="foundation":continue
			for part in building.geometry.boxes(v):
				if draft_query.terrain_clear(v.regionId,part):continue
				var cells: Array=[];var entities: Array=[]
				var lo:=Vector3i(floori((part.position.x+0.00001)/0.5),floori((part.position.y+0.00001)/0.5),floori((part.position.z+0.00001)/0.5))
				var hi:=Vector3i(ceili((part.end.x-0.00001)/0.5),ceili((part.end.y-0.00001)/0.5),ceili((part.end.z-0.00001)/0.5))
				for x in range(lo.x,hi.x):
					for y in range(lo.y,hi.y):
						for z in range(lo.z,hi.z):
							var material: int=draft.view.cell_at(x,y,z)
							if material!=0 and cells.size()<6:cells.append({"cell":[x,y,z],"material":material})
				for entity in draft.view.entities():
					if entity.regionId==v.regionId and entity.get("data",{}).get("solid",false) and Geometry.overlap(Geometry.aabb(entity.bounds),part):entities.append(entity.id)
				terrain_conflicts.append({"source_id":v.id,"definition":v.definitionId,"box":Geometry.json_box(part),"cells":cells,"entities":entities})
				if terrain_conflicts.size()>=8:break
			if terrain_conflicts.size()>=8:break
		costs.rejected_terrain_conflicts=terrain_conflicts
		world.discard_prepared(draft.capability)
		return finish()
	check("single world commit installs complete family facts",world.commit_prepared(draft.capability).ok)
	check("sole actual runtime adopts B initial stocks and same clock",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"production":Production.new(),"actions":Actions.new()}}).ok)
	check("repeat building preparation does not redraw saved parcels",building.prepare_generation(world).code=="ALREADY_SEEDED")
	walk_paths(world,building,"complete B family graph")
	write_navigation_handoff(world,building)
	var direct_route:=walk_home_to_village(runtime,world)
	check("same actual runtime direct commands traverse home road and village boundary",direct_route.ok,direct_route)
	var saved:=Codec.encode_checkpoint(world.snapshot(),{"runtime":runtime.facts()},"test:rural2:families")
	var decoded:=Codec.decode_checkpoint(saved.envelope) if saved.ok else saved
	var restored:=State.new()
	var restore: Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
	check("whole real family graph native checkpoint restores",restore.ok,restore)
	if restore.ok:
		var restored_runtime:=Runtime.new();var restored_building:=Building.new()
		var ready: Dictionary=restored_runtime.configure({"world":restored,"facts":decoded.extensions.runtime,"services":{"buildings":restored_building,"production":Production.new()}})
		check("restored B marker prevents duplicate building/stock/record creation",ready.ok and restored_building.prepare_generation(restored).code=="ALREADY_SEEDED")
	finish()

func write_navigation_handoff(world: RefCounted,building: RefCounted) -> void:
	# Export actual immutable-plan roads and B standing points for its owner.
	# This is diagnostic data, not another production actor navigator.
	var query: RefCounted=building.current_space()
	var paths: Array=[]
	for region in world.regions():
		var plan: Dictionary=world.extension("generation:"+region.id)
		for path in plan.paths:
			var feet: Array=[]
			for index in path.points.size()-1:
				var a: Dictionary=path.points[index];var b: Dictionary=path.points[index+1]
				var count:=maxi(1,ceili(Vector2(b.x-a.x,b.z-a.z).length()/0.5))
				for step in count+1:
					var t:=float(step)/count;var x:=lerpf(a.x,b.x,t);var z:=lerpf(a.z,b.z,t)
					if x<region.bounds.min.x+0.5 or x>region.bounds.max.x-0.5 or z<region.bounds.min.z+0.5 or z>region.bounds.max.z-0.5:continue
					var point: Dictionary={"x":x,"y":world.surface_height(x,z),"z":z,"regionId":region.id,"buildingId":null,"storeyId":null}
					var standing: Dictionary=query.standing_point(point)
					if feet.is_empty() or feet[-1].get("standing")!=standing:feet.append({"sample":point,"standing":standing})
			paths.append({"id":path.id,"region_id":region.id,"width":path.width,"plan_points":path.points,"actual_standing_samples":feet})
	var home: Dictionary=world.extension("generation:RH-HOME")
	var from: Dictionary=home.anchors.arrival.duplicate();from.merge({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var to: Dictionary=home.anchors.home.duplicate();to.merge({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var result: Dictionary={"scope":"actual C roads/heights and B standing samples after real five-family commit; diagnostic handoff only, not replacement navigator or formal NPC acceptance","world":world.identity(),"revision":world.get_revision(),"configuration":world.extension("generation:rural2"),"failure_input":{"actor_id":"player","from":from,"to":to,"from_standing":query.standing_point(from),"to_standing":query.standing_point(to),"route":query.route("player",from,to)},"paths":paths}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0]+".navigation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"",true,true)+"\n")

func walk_home_to_village(runtime: RefCounted,world: RefCounted) -> Dictionary:
	var home: Dictionary=world.extension("generation:RH-HOME")
	var village: Dictionary=world.extension("generation:RH-VILLAGE")
	var south: Dictionary=home.paths.filter(func(p: Dictionary)->bool:return p.id=="RH-HOME:south")[0]
	var north: Dictionary=home.paths.filter(func(p: Dictionary)->bool:return p.id=="RH-HOME:north")[0]
	var village_south: Dictionary=village.paths.filter(func(p: Dictionary)->bool:return p.id=="RH-VILLAGE:south")[0]
	var points: Array=south.points.slice(south.points.size()-4)
	var reversed: Array=north.points.duplicate(true);reversed.reverse()
	for p in reversed:
		if p.z>=0.5:points.append(p)
	for region_id in ["RH-HOME","RH-VILLAGE"]:
		var to_id: String="RH-VILLAGE" if region_id=="RH-HOME" else "RH-HOME"
		for exit in world.region(region_id).exits:
			if exit.toRegionId==to_id:points.append(exit.position);break
	for p in village_south.points:
		if p.z<=-0.5:points.append(p)
	var commands:=0
	for target in points:
		while true:
			var from:Dictionary=runtime.actor("player")
			var remaining:=Vector2(target.x-from.x,target.z-from.z)
			if remaining.length()<0.00001:break
			if commands>=4096:return {"ok":false,"reason":"bounded route command limit","commands":commands}
			# Consume the new shared logical movement budget and measure actual
			# progress. Legacy commands may now be clamped; a fixed old waypoint
			# loop could accumulate unwalked distance and falsely test a >1m jump.
			var budget:Dictionary=runtime.movement_budget("player",0.1,"walk")
			if not budget.ok:return {"ok":false,"reason":"movement budget","result":budget,"commands":commands}
			var step:float=minf(remaining.length(),minf(0.25,float(budget.max_distance)))
			if step<=0.000001:return {"ok":false,"reason":"no actual movement budget","result":budget,"commands":commands}
			var delta:Vector2=remaining.normalized()*step
			var x:float=float(from.x)+delta.x;var z:float=float(from.z)+delta.y
			var y: Variant=world.surface_height(x,z)
			if y==null:return {"ok":false,"reason":"unknown actual ground","x":x,"z":z,"commands":commands}
			var to: Dictionary={"x":x,"y":y,"z":z,"regionId":world.region_at({"x":x,"y":y,"z":z}).get("id"),"buildingId":null,"storeyId":null}
			var result: Dictionary=runtime.command({"command_id":"r2:walk:%d"%commands,"actor_id":"player","kind":"direct_move","destination":to,"payload":{"movement_dt":0.1,"movement_mode":"walk"}})
			commands+=1
			if not result.ok:return {"ok":false,"from":runtime.actor("player"),"to":to,"result":result,"commands":commands}
			var after:Dictionary=runtime.actor("player")
			if Vector2(after.x-from.x,after.z-from.z).length()<0.000001:return {"ok":false,"reason":"no actual progress","commands":commands}
			runtime.tick(0.1)
	return {"ok":runtime.actor("player").regionId=="RH-VILLAGE","commands":commands,"actor":runtime.actor("player"),"time":runtime.facts().time}

func walk_paths(world: RefCounted,building: RefCounted,stage: String) -> void:
	# Prove the paths with B's exact body/terrain walk, not just centre heights.
	var query: RefCounted=building.current_space()
	for region in world.regions():
		var plan: Dictionary=world.extension("generation:"+region.id)
		var failures: Array=[];var segments:=0
		for path in plan.paths:
			var current: Dictionary={}
			for i in path.points.size()-1:
				var a: Dictionary=path.points[i];var b: Dictionary=path.points[i+1]
				var length:=Vector2(b.x-a.x,b.z-a.z).length()
				var steps:=maxi(1,ceili(length/0.5))
				for step in steps+1:
					var t:=float(step)/steps
					var x:=lerpf(a.x,b.x,t);var z:=lerpf(a.z,b.z,t)
					# A finite exterior ends at half-open boundary; leave radius
					# margin here. A owns safe cross-region transition testing.
					if x<region.bounds.min.x+0.5 or x>region.bounds.max.x-0.5 or z<region.bounds.min.z+0.5 or z>region.bounds.max.z-0.5: current={};continue
					var point: Dictionary={"x":x,"y":world.surface_height(x,z),"z":z,"regionId":region.id,"buildingId":null,"storeyId":null}
					var feet: Dictionary=query.standing_point(point)
					if feet.is_empty():
						if failures.size()<8:failures.append({"path":path.id,"point":point,"reason":"no standing body"})
						current={};continue
					if not current.is_empty():
						var walk: Dictionary=query.walk("player",current,feet,true)
						if not walk.ok and failures.size()<8: failures.append({"path":path.id,"from":current,"to":feet,"result":walk})
						segments+=1
					current=feet
		check(stage+" "+region.id+" road/access obey existing B body/collision walk",failures.is_empty(),{"segments":segments,"failures":failures})
func finish() -> void:
	var failed:=checks.filter(func(c: Dictionary)->bool:return not c.ok).size()
	var result: Dictionary={"scope":"C/B actual shared settlement graph and existing navigation rules in isolated headless domain test; no app/export/VA qualification","checks":checks,"costs":costs,"failed":failed}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"costs":costs}));quit(1 if failed else 0)
