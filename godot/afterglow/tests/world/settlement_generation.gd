extends SceneTree
const Generator = preload("res://scripts/world/settlement_generator.gd")
const OldGenerator = preload("res://scripts/world/rural_generator.gd")
const Data = preload("res://scripts/world/world_data.gd")
const State = preload("res://scripts/world/world_state.gd")
const Codec = preload("res://scripts/world/world_codec.gd")
const Mesher = preload("res://scripts/terrain/terrain_mesher.gd")
const Queries = preload("res://scripts/terrain/terrain_queries.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Terrain = preload("res://scripts/terrain/terrain_service.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const EnvironmentView = preload("res://scripts/environment/environment_view.gd")
const TerrainView = preload("res://scripts/terrain/terrain_view.gd")
var checks: Array=[]
var costs: Array=[]
var profiles: Array=[]
class WorkerDraft extends RefCounted:
	var result: Dictionary={}
	func execute(seed: int,coord: Vector2i,input_profiles: Array) -> void:
		result=Generator.draft_region(seed,coord,input_profiles)
func check(label: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok: push_error("FAIL "+label+" "+str(detail))
func _initialize() -> void: call_deferred("run")
func pos(p: Dictionary) -> Vector3: return Vector3(p.x,p.y,p.z)
func mismatch(a: Variant,b: Variant,path: String="") -> Variant:
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): return {"path":path+"/"+str(key),"missing":true}
			var difference: Variant=mismatch(a[key],b[key],path+"/"+str(key))
			if difference!=null: return difference
		if a.size()!=b.size(): return {"path":path,"size_a":a.size(),"size_b":b.size()}
	elif a is Array and b is Array:
		if a.size()!=b.size(): return {"path":path,"size_a":a.size(),"size_b":b.size()}
		for i in a.size():
			var difference: Variant=mismatch(a[i],b[i],path+"/"+str(i))
			if difference!=null: return difference
	elif not Data.json_equal(a,b): return {"path":path,"a":a,"b":b}
	return null
func stock_facts(world: RefCounted) -> Array: return OldGenerator.empty_resource_stocks(world)
func facts_roundtrip(a: Dictionary,b: Dictionary) -> Dictionary:
	# Godot's decimal parser can differ by one ULP on accumulated vitals. Only
	# these continuous scalars allow 1e-10; IDs, items and quantities stay exact.
	var left := a.duplicate(true);var right := b.duplicate(true);var maximum := 0.0
	maximum=maxf(maximum,absf(float(left.time)-float(right.time)));left.time=0;right.time=0
	for i in left.actors.size():
		for key in ["hunger","thirst","fatigue","stamina"]:
			maximum=maxf(maximum,absf(float(left.actors[i][key])-float(right.actors[i][key])))
			left.actors[i][key]=0;right.actors[i][key]=0
	return {"ok":maximum<=0.0000000001 and Data.json_equal(left,right),"max_vital_error":maximum,"other_difference":mismatch(left,right)}
func install(world: RefCounted,coord: Vector2i) -> Dictionary:
	var result := Generator.prepare_region(world,coord,profiles,world.get_revision())
	if not result.ok: return result
	if result.already_generated: return result
	costs.append(result.cost)
	var started := Time.get_ticks_usec()
	var draft: Dictionary=world.prepare_changes(result.world_changes,world.get_revision())
	if not draft.ok: return draft
	result.cost.world_prepare_ms=(Time.get_ticks_usec()-started)/1000.0
	var committed: Dictionary=world.commit_prepared(draft.capability)
	return result if committed.ok else committed
func cell_fingerprint(world: RefCounted) -> String:
	var lines := ""
	var keys: Array=world.chunk_keys();keys.sort()
	for key in keys:
		var c: Dictionary=world.chunk(key)
		lines+=key+PackedInt32Array(c.cells).to_byte_array().hex_encode().sha256_text()
	return lines.sha256_text()
func entity_fingerprint(world: RefCounted) -> String:
	var rows: Array=world.entities()
	rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.id<b.id)
	for row in rows: row.erase("revision")
	return JSON.stringify(rows,"",true,true).sha256_text()
func path_check(world: RefCounted,plan: Dictionary) -> Dictionary:
	var bad: Array=[];var count := 0;var maximum := 0.0
	for path in plan.paths:
		for i in path.points.size()-1:
			var a := pos(path.points[i]);var b := pos(path.points[i+1])
			var steps := maxi(1,ceili(Vector2(b.x-a.x,b.z-a.z).length()/0.25))
			var previous: Variant=null
			for step in steps+1:
				var p := a.lerp(b,float(step)/steps)
				var h: Variant=world.surface_height(p.x,p.z)
				if h==null:
					# The polyline endpoint is a shared half-open boundary.
					p.x=clampf(p.x,plan.region_coord.x*64+0.01,(plan.region_coord.x+1)*64-0.01)
					p.z=clampf(p.z,plan.region_coord.z*64+0.01,(plan.region_coord.z+1)*64-0.01)
					h=world.surface_height(p.x,p.z)
				if h==null: bad.append({"path":path.id,"point":str(p),"unknown":true});continue
				if previous!=null:
					maximum=maxf(maximum,absf(float(h)-float(previous)))
					if absf(float(h)-float(previous))>0.55 and bad.size()<10: bad.append({"path":path.id,"point":str(p),"height":h,"previous":previous})
				previous=h;count+=1
	return {"ok":bad.is_empty(),"samples":count,"max_step":maximum,"bad":bad}
func run() -> void:
	profiles=Building.generation_profiles()
	check("actual B six profiles available, no copied C recipe catalogue",profiles.size()==6)
	var malformed: Array=profiles.duplicate(true);malformed[0].use_reservations[0].rect=[0,0,-1,2]
	check("inverted use rectangle fails closed before mapgen",Generator.plan_region(713,Vector2i.ZERO,malformed).code=="INVALID_PROFILE_RESERVATION")
	malformed=profiles.duplicate(true);malformed[0].foundation.pad_rectangles=[[0,0,NAN,2]]
	check("nonfinite foundation rectangle fails closed before mapgen",Generator.plan_region(713,Vector2i.ZERO,malformed).code=="INVALID_GENERATION_PROFILE")
	malformed=profiles.duplicate(true);malformed[0].entrance_ports[0].position=[1,1,1]
	check("unsupported raised doorway is not silently grounded at wrong level",Generator.plan_region(713,Vector2i.ZERO,malformed).code=="UNSUPPORTED_PROFILE_PORT")
	malformed=profiles.duplicate(true);malformed[0].npc_anchors[0].position=[1,2]
	check("malformed NPC anchor rejected without publishing partial plan",Generator.plan_region(713,Vector2i.ZERO,malformed).code=="INVALID_PROFILE_ANCHOR")
	malformed=profiles.duplicate(true);malformed[0].footprint.max.x=100
	check("oversized physical family contract is rejected rather than cropped",Generator.plan_region(713,Vector2i.ZERO,malformed).code=="PROFILE_EXCEEDS_SITE")
	malformed=profiles.duplicate(true);malformed[2].footprint.max.z=19;malformed[3].footprint.max.z=19
	check("overlapping complete pads rejected before partial cell output",Generator.plan_region(713,Vector2i.ZERO,malformed).code=="OVERLAPPING_PADS")
	var started := Time.get_ticks_usec()
	var snapshot := Generator.generate(713,profiles)
	costs.append({"dual_region_generate_ms":(Time.get_ticks_usec()-started)/1000.0})
	var world := State.new()
	var loaded: Dictionary=world.load_snapshot(snapshot)
	check("real new-version dual-region world validates",loaded.ok,loaded)
	if not loaded.ok: return finish()
	check("explicit new identity; rural-1 generator defaults preserved",world.identity().generatorVersion=="rural-2" and world.identity().worldId=="rural:v2:713" and OldGenerator.generate(713).generatorVersion=="rural-1")
	check("two persistent regions have 512 real chunks / 2097152 cells",world.regions().size()==2 and world.chunk_keys().size()==512)
	var plans: Array=[]
	for region in world.regions():
		var plan: Dictionary=world.extension("generation:"+region.id);plans.append(plan)
		check(region.id+" one JSON-safe persisted settlement plan",plan.schema==Generator.SCHEMA and Data.json_value(plan))
		check(region.id+" actual height span rather than y0 shader",region.data.heightMax-region.data.heightMin>=2.0,region.data)
		var pads := true;var use_faces := true
		for parcel in plan.parcels:
			pads=pads and parcel.profile_resolved and parcel.quarter_turn==0
			for z in range(ceili(parcel.pad.xz[1]*2),floori(parcel.pad.xz[3]*2)):
				for x in range(ceili(parcel.pad.xz[0]*2),floori(parcel.pad.xz[2]*2)):
					pads=pads and world.surface_height((x+0.5)*0.5,(z+0.5)*0.5)==parcel.origin.y
			for port in parcel.entrance_ports: use_faces=use_faces and world.surface_height(port.position.x,port.position.z)==port.position.y
			for reservation in parcel.use_reservations:
				var b: Dictionary=reservation.bounds
				for z in range(floori(b.min.z*2),ceili(b.max.z*2)):
					for x in range(floori(b.min.x*2),ceili(b.max.x*2)):
						use_faces=use_faces and world.surface_height((x+0.5)*0.5,(z+0.5)*0.5)==parcel.origin.y
		check(region.id+" B footprint and full pad use actual height",pads)
		check(region.id+" every entrance and door sweep supported at pad height",use_faces)
		var walk := path_check(world,plan)
		check(region.id+" all generated road/access centrelines satisfy 0.55m step",walk.ok,walk)
	var border_ok := true;var max_border := 0.0
	for x in 128:
		var a: float=world.surface_height((x+0.5)*0.5,-0.25)
		var b: float=world.surface_height((x+0.5)*0.5,0.25)
		max_border=maxf(max_border,absf(a-b));border_ok=border_ok and absf(a-b)<=0.5
	check("negative-Z dual-region boundary has no height seam greater than one cell",border_ok,max_border)
	var south: Dictionary=plans.filter(func(p: Dictionary)->bool:return p.region_id=="RH-VILLAGE")[0].road_ports[1]
	var north: Dictionary=plans.filter(func(p: Dictionary)->bool:return p.region_id=="RH-HOME")[0].road_ports[0]
	check("both sides persist identical shared port/height/width",south.id==north.id and south.position==north.position and south.width==north.width)
	var same := State.new();same.load_snapshot(Generator.generate(713,profiles))
	check("same seed/version/coordinate reproduces exact cells and plan",cell_fingerprint(world)==cell_fingerprint(same) and world.extension("generation:RH-HOME")==same.extension("generation:RH-HOME"))
	var other := State.new();other.load_snapshot(Generator.generate(2026,profiles))
	check("second seed is an actual valid populated dual-region world",other.regions().size()==2 and other.entities().size()>0)
	for region in other.regions():
		var route := path_check(other,other.extension("generation:"+region.id))
		check("seed2026 "+region.id+" road/access actual step",route.ok,route)
	check("different seed changes real voxel terrain/roads/resources, not only metadata",cell_fingerprint(world)!=cell_fingerprint(other) and world.extension("generation:RH-HOME").paths!=other.extension("generation:RH-HOME").paths)
	var ext := install(world,Vector2i(1,0))
	check("real adjacent coordinate region prepared and committed through C capability",ext.ok and world.regions().size()==3 and world.chunk_keys().size()==768,ext.get("cost",ext.get("reason")))
	var west := install(world,Vector2i(-1,0))
	check("real negative coordinate region generated",west.ok and world.region("R2:-1:0").bounds.min.x==-64,west.get("cost",west.get("reason")))
	var reverse_west := install(same,Vector2i(-1,0));var reverse_east := install(same,Vector2i(1,0))
	check("reverse region request order preserves exact cells/plans/resource IDs",reverse_west.ok and reverse_east.ok and cell_fingerprint(world)==cell_fingerprint(same) and world.extension("generation:R2:-1:0")==same.extension("generation:R2:-1:0") and entity_fingerprint(world)==entity_fingerprint(same))
	var seams := true;var seam_max := 0.0
	for edge in [0.0,64.0]:
		for z in 128:
			var h0: float=world.surface_height(edge-0.25,(z+0.5)*0.5)
			var h1: float=world.surface_height(edge+0.25,(z+0.5)*0.5)
			seam_max=maxf(seam_max,absf(h0-h1));seams=seams and absf(h0-h1)<=0.5
	check("east and negative-X adjacent generated borders stay continuous",seams,seam_max)
	var job := WorkerDraft.new()
	var task := WorkerThreadPool.add_task(job.execute.bind(713,Vector2i(2,0),profiles.duplicate(true)),false,"CCC isolated mapgen draft")
	WorkerThreadPool.wait_for_task_completion(task)
	check("actual Godot worker prepares only isolated CPU mapgen facts",job.result.get("ok",false) and job.result.plan==Generator.plan_region(713,Vector2i(2,0),profiles).plan,job.result.get("cost"))
	var worker_handoff := Generator.prepare_draft(world,job.result,world.get_revision())
	var worker_capability: Dictionary=world.prepare_changes(worker_handoff.world_changes,world.get_revision()) if worker_handoff.ok else worker_handoff
	check("worker DTO rejoins actual main-thread world capability without direct writes",worker_capability.ok and world.region("R2:2:0").is_empty(),worker_capability.get("reason"))
	if worker_capability.ok: world.discard_prepared(worker_capability.capability)
	check("worker handoff rejects stale expected revision",Generator.prepare_draft(world,job.result,world.get_revision()-1).code=="STALE_REVISION")
	var changed_profiles := profiles.duplicate(true);changed_profiles[0].version=999
	check("new region cannot silently switch original mapgen profile geometry/version",Generator.prepare_region(world,Vector2i(2,0),changed_profiles).code=="GENERATION_PROFILE_VERSION_MISMATCH")
	check("coordinate cap rejects instead of unbounded generation",not Generator.prepare_region(world,Vector2i(9,0),profiles).ok)
	check("stale precondition rejected before preparation",not Generator.prepare_region(world,Vector2i(2,0),profiles,world.get_revision()-1).ok)
	var legacy := State.new();legacy.load_snapshot(OldGenerator.generate())
	check("old/explored rural-1 never silently upgraded or regenerated",Generator.prepare_region(legacy,Vector2i(1,0),profiles).code=="GENERATOR_MISMATCH")
	# Mesh and native collision are created from the very same nonflat cells.
	var mesh_keys := ["1,0,4","3,0,4","4,-1,6","8,0,3","-1,0,3"]
	for key in mesh_keys:
		started=Time.get_ticks_usec()
		var data := Mesher.build(world,key)
		var native := Mesher.mesh(data)
		var collision := native.create_trimesh_shape() if native.get_surface_count()>0 else null
		costs.append({"mesh_chunk":key,"mesh_and_native_collision_ms":(Time.get_ticks_usec()-started)/1000.0,"quads":data.quads})
		check("nonflat actual greedy/native collision "+key,data.ok and collision is ConcavePolygonShape3D and collision.get_faces().size()==data.quads*6)
	var physics_view := TerrainView.new();root.add_child(physics_view)
	physics_view.configure({"world":world});physics_view.set_process(false)
	physics_view._rebuild("4,0,4")
	await physics_frame
	await physics_frame
	var surface: float=world.surface_height(34.25,36.25)
	var ray := PhysicsRayQueryParameters3D.create(Vector3(34.25,surface+3,36.25),Vector3(34.25,surface-1,36.25))
	var collision_hit: Dictionary=physics_view.get_world_3d().direct_space_state.intersect_ray(ray)
	check("actual native physics ray hits same nonflat voxel height",not collision_hit.is_empty() and absf(collision_hit.get("position",Vector3.INF).y-surface)<0.001,{"voxel_height":surface,"collision_point":str(collision_hit.get("position"))})
	physics_view.free()
	# Real A/B/C runtime, tools and initial empty drop stocks. Fixture is isolated
	# in memory; never loads user://saves or starts the formal application.
	var runtime := Runtime.new();var building := Building.new();var production := Production.new()
	var tree: Dictionary=world.entities("R2:1:0").filter(func(e: Dictionary)->bool:return e.kind=="tree")[0]
	var p: Dictionary=tree.position
	var actor := {"id":"player","x":p.x+1.75,"y":world.surface_height(p.x+1.75,p.z),"z":p.z,"regionId":tree.regionId,"buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"skills":{},"pack":{},"intent":null,"relationship":{"consent":true}}
	var prod := Production.empty_state()
	prod.tools=[{"id":"test:axe","kind":"salvaged_axe","holderId":"pack:player","durability":100.0},{"id":"test:shovel","kind":"shovel","holderId":"pack:player","durability":100.0,"qualities":{"shovel":1}}]
	var t: Dictionary=world.prepare_changes([{"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":prod}],world.get_revision())
	if t.ok: world.commit_prepared(t.capability)
	var configured: Dictionary=runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":stock_facts(world),"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":{"terrain":Terrain.new(),"buildings":building,"production":production,"actions":Actions.new()}})
	check("existing A runtime and B/C services accept nonflat world",configured.ok,configured)
	var harvest: Dictionary=runtime.command({"command_id":"r2:harvest","actor_id":"player","kind":"harvest","target_id":tree.id,"payload":{"tree_id":tree.id,"output_id":tree.data.outputId,"tool_ids":["test:axe"],"held":true}})
	check("real generated-coordinate tree starts through existing action/production path",harvest.ok,harvest)
	if harvest.ok:
		for i in 280: runtime.tick(0.1)
	check("actual labor fells same ID and credits only its real drop container",world.entity(tree.id).data.harvest.phase=="stump" and runtime.stock(tree.data.outputId).items.get("log",0)==3 and runtime.actor("player").pack.get("log",0)==0,{"phase":world.entity(tree.id).data.harvest.phase,"stock":runtime.stock(tree.data.outputId),"actor":runtime.actor("player")})
	# A nearby unprotected actual surface, derived from current coordinates.
	var a: Dictionary=runtime.actor("player")
	var cx := floori((a.x+0.5)*2);var cz := floori((a.z+0.5)*2)
	var y := roundi(float(world.surface_height((cx+0.5)*0.5,(cz+0.5)*0.5))*2)-1
	var hit := Queries.pick(world,Vector3((cx+0.5)*0.5,y*0.5+5,(cz+0.5)*0.5),Vector3((cx+0.5)*0.5,y*0.5-1,(cz+0.5)*0.5))
	check("real DDA target height and stable cell ID match new voxels",hit.get("target_id")=="terrain:%d:%d:%d"%[cx,y,cz] and hit.get("cell")=={"x":cx,"y":y,"z":cz},hit)
	var original := world.cell_at(cx,y,cz)
	var dig: Dictionary=runtime.command({"command_id":"r2:dig","actor_id":"player","kind":"terrain","payload":{"edit":{"operation":"dig","cells":[{"x":cx,"y":y,"z":cz}]},"tool_id":"test:shovel"}})
	check("new nonflat terrain uses actual dig labor route",dig.ok,dig)
	if dig.ok:
		for i in 100: runtime.tick(0.1)
	check("dig changes same authority and rewards real conserved volume",world.cell_at(cx,y,cz)==0 and runtime.actor("player").pack.get("soil_m3",0)==0.125,{"material":original,"actor":runtime.actor("player")})
	var fill: Dictionary=runtime.command({"command_id":"r2:fill","actor_id":"player","kind":"terrain","payload":{"edit":{"operation":"fill","material":2,"cells":[{"x":cx,"y":y,"z":cz}]},"tool_id":"test:shovel"}})
	if fill.ok:
		for i in 100: runtime.tick(0.1)
	check("fill restores same height using actual dig output, without free material",fill.ok and world.cell_at(cx,y,cz)==2 and runtime.actor("player").pack.get("soil_m3",0)==0,{"result":fill,"actor":runtime.actor("player")})
	var before := cell_fingerprint(world)
	var repeat := Generator.prepare_region(world,Vector2i(1,0),profiles)
	check("repeat prepare returns persisted facts; no reroll/stock duplication/tree resurrection",repeat.ok and repeat.already_generated and repeat.world_changes.is_empty() and repeat.initial_stocks.is_empty() and before==cell_fingerprint(world) and world.entity(tree.id).data.harvest.phase=="stump")
	var env := EnvironmentView.new();root.add_child(env);env.configure({"world":world})
	check("nonflat resources derive actual environmental geometry",env.statistics().tree_roots>0,env.statistics())
	var all_grounded := true
	for e in world.entities():
		if e.kind=="tree": all_grounded=all_grounded and world.surface_height(e.position.x,e.position.z)==e.position.y
	check("all actual tree feet follow authoritative height",all_grounded)
	var patches:=0;var patches_grounded:=true
	for node in env.get_children():
		if not node.has_meta("world_entity_id"):continue
		for child in node.get_children():
			if not str(child.name).begins_with("GroundShrub_"):continue
			var patch_position: Vector3=node.position+child.position
			var bottom: float=patch_position.y-0.3 if child.name=="GroundShrub_0" else patch_position.y
			patches_grounded=patches_grounded and world.surface_height(patch_position.x,patch_position.z)!=null and absf(bottom-float(world.surface_height(patch_position.x,patch_position.z)))<0.00001
			patches+=1
	check("actual shrub and low-cover geometry bottoms follow their own voxel surface",patches>0 and patches_grounded,{"patches":patches})
	var encoded := Codec.encode_checkpoint(world.snapshot(),{"runtime":runtime.facts()},"test:rural2:edited")
	var decoded := Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var restored := State.new()
	var restore: Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
	check("native codec saves and restores edited generated world",restore.ok,restore)
	if restore.ok:
		var facts_result := facts_roundtrip(decoded.extensions.runtime,runtime.facts())
		check("saved plans, modified cells and harvested IDs survive cold restore",Data.json_equal(restored.extension("generation:R2:1:0"),world.extension("generation:R2:1:0")) and restored.cell_at(cx,y,cz)==2 and restored.entity(tree.id).data.harvest.phase=="stump" and facts_result.ok,{"plan_difference":mismatch(restored.extension("generation:R2:1:0"),world.extension("generation:R2:1:0")),"facts":facts_result})
		var cold: Dictionary=Generator.prepare_region(restored,Vector2i(1,0),profiles)
		check("cold revisit does not regenerate nonresident facts",cold.ok and cold.already_generated and cold.world_changes.is_empty() and not restored.is_cell_resident(cx,y,cz))
		var key := Data.key(Data.cell_chunk(Vector3i(cx,y,cz),16))
		var warm: Dictionary=restored.prepare_changes([{"op":"chunk.residency","id":key,"before":false,"after":true}],restored.get_revision())
		if warm.ok: restored.commit_prepared(warm.capability)
		check("warm transition keeps modified voxel/harvest facts",warm.ok and restored.cell_at(cx,y,cz)==2 and restored.entity(tree.id).data.harvest.phase=="stump")
	# Handoff artifact is a genuine persisted world plan, never a render mockup.
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var handoff := {"scope":"actual generated plans from validated world; not formal application acceptance","world_id":world.identity().worldId,"generator_version":Generator.VERSION,"plans":[]}
		for region in world.regions(): handoff.plans.append(world.extension("generation:"+region.id))
		FileAccess.open(args[0]+".plans.json",FileAccess.WRITE).store_string(JSON.stringify(handoff,"\t",true,true)+"\n")
	env.free()
	finish()
func finish() -> void:
	var failed := checks.filter(func(c: Dictionary)->bool:return not c.ok).size()
	var result := {"scope":"C actual mapgen/cells/native collision/A runtime/B production/codec isolated headless checks; no official app/export/VA/FPS qualification","checks":checks,"costs":costs,"failed":failed}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"costs":costs}))
	quit(1 if failed else 0)
