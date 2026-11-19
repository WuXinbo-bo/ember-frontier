extends "res://tests/buildings/domain_suite.gd"
## Real construction/production transactions; explicit finite test pack/knowledge.
func material_present(root:Node,material:Material)->bool:
	if root is MeshInstance3D and root.mesh!=null:
		for surface in root.mesh.get_surface_count():
			if root.get_active_material(surface)==material:return true
	for child in root.get_children():
		if material_present(child,material):return true
	return false

func derived_state(scene:Node3D)->Dictionary:
	var geometry:Array=[]
	for key in scene.static_nodes:
		var node:MeshInstance3D=scene.static_nodes[key]
		geometry.append([key,node.visible,node.mesh.get_aabb(),node.mesh.get_surface_count()])
	var objects:Dictionary={};var doors:Dictionary={}
	for id in scene.objects:
		var node:Node3D=scene.objects[id]
		objects[id]=[node.transform,node.visible,node.has_node("PreparedBedding")]
	for id in scene.doors:
		var d:Dictionary=scene.doors[id]
		doors[id]=[d.node.transform,d.node.visible,d.full.visible,material_present(d.full,scene.material("b_wood_repair_detail")),material_present(d.full,scene.material("b_wood_damage_detail"))]
	return {"geometry":geometry,"objects":objects,"doors":doors,"state_details":scene.get_node("StateDetails").get_child_count(),"contents":scene.get_node("Contents").get_child_count()}

func wait_work(limit:int=400)->void:
	for i in range(limit):
		if runtime.actor("player").get("intent")==null:return
		runtime.tick(0.1)
func walk_to(x:float,z:float)->Dictionary:
	var result:=command("walk","",{}, {"x":x,"y":0,"z":z,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	if result.ok:wait_work()
	return result
func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real rural world valid",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seeded:Dictionary=building.seed_rural(world)
	var seed_draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("real structures commit",seed_draft.ok and world.commit_prepared(seed_draft.capability).ok)
	initialize_at({"x":31.2,"y":0,"z":42,"regionId":"RH-HOME","buildingId":null,"storeyId":null},[],seeded.initial_stocks)
	var facts:=runtime.facts();facts.actors[0].pack={"timber":20,"scrap":20,"cloth":2,"food":1,"log":1,"tool_handle":2,"axe_head":1}
	runtime.configure({"world":world,"services":{"buildings":building,"actions":actions,"production":production},"facts":facts})
	var p:Dictionary=Production.empty_state();p.tools=seeded.initial_tools;p.records=seeded.initial_records;p.knowledge={"player":["basic_woodwork","basic_tool_repair"]}
	for t in p.tools:t.holderId="pack:player";t.durability=0 if t.kind=="salvaged_axe" else 100
	var pd:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,p)],world.get_revision())
	expect("finite test production facts installed",pd.ok and world.commit_prepared(pd.capability).ok)
	var scene:Node3D=building.create_view({"runtime":runtime})
	var initial_gate:Dictionary=scene.doors["rural:v1:RH-HOME:old-house:yard-gate"]
	expect("real initial 60 HP gate binds approved wood damage on its original full leaf",material_present(initial_gate.full,scene.material("b_wood_damage_detail")) and not initial_gate.has("cut"))
	var hammer:=str(p.tools.filter(func(t:Dictionary)->bool:return t.kind=="hammer")[0].id)
	var saw:=str(p.tools.filter(func(t:Dictionary)->bool:return t.kind=="hand_saw")[0].id)
	var axe:=str(p.tools.filter(func(t:Dictionary)->bool:return t.kind=="salvaged_axe")[0].id)
	var cabinet:Dictionary=building.make_instance("cabinet","bbb:actual-cabinet",{"x":32,"y":0,"z":43,"regionId":"RH-HOME"})
	var build_payload:Dictionary={"kind":"place","instance":cabinet,"source_id":"pack:player","output_id":"pack:player","tool_id":hammer}
	var placed:=command("structure",cabinet.id,build_payload)
	expect("cabinet starts actual reserved construction",placed.ok,placed)
	if not placed.ok:finish(started);return
	wait_work()
	expect("cabinet creates one actual empty stock",not runtime.stock(cabinet.id).is_empty() and runtime.stock(cabinet.id).items.is_empty() and not building.instance(cabinet.id).is_empty())
	expect("same live derived view receives newly built cabinet",scene.objects.has(cabinet.id))
	expect("new stock supports real deposit",command("deposit",cabinet.id,{"items":{"food":1}}).ok)
	expect("deposited real inventory appears on same cabinet",scene.get_node("Contents").get_children().any(func(n:Node)->bool:return n.get_meta("piece",{}).get("id")==cabinet.id))
	var remove_payload:Dictionary={"kind":"remove","source_id":"pack:player","output_id":"pack:player","tool_id":hammer}
	var nonempty:=command("structure",cabinet.id,remove_payload)
	expect("nonempty cabinet removal specifically rejected",not nonempty.ok and str(nonempty.get("reason","")).contains("清空"),nonempty)
	var move_payload:Dictionary={"kind":"move","destination":{"position":{"x":32,"y":0,"z":43.8},"quarterTurn":0},"source_id":"pack:player","output_id":"pack:player","tool_id":hammer}
	expect("loaded cabinet move starts",command("structure",cabinet.id,move_payload).ok)
	wait_work()
	expect("stock follows moved actual furniture and keeps contents",is_equal_approx(building.instance(cabinet.id).position.z,43.8) and is_equal_approx(Geometry.location(runtime.stock(cabinet.id)).z,43.8) and runtime.stock(cabinet.id).items.get("food")==1)
	expect("same live view follows moved cabinet and exact old footprint",is_equal_approx(scene.objects[cabinet.id].position.z,43.8) and material_present(scene.get_node("StateDetails"),scene.materials.moved_trace))
	expect("moved stock supports actual take",command("take",cabinet.id,{"items":{"food":1}}).ok)
	var timber_before:=float(runtime.actor("player").pack.timber)
	expect("empty cabinet dismantle starts",command("structure",cabinet.id,remove_payload).ok)
	wait_work()
	var salvage:Dictionary=building.geometry.definitions.cabinet.salvage
	expect("dismantle removes matching entity extension and stock",building.instance(cabinet.id).is_empty() and world.entity(cabinet.id).is_empty() and runtime.stock(cabinet.id).is_empty())
	expect("same live view removes dismantled furniture",not scene.objects.has(cabinet.id))
	expect("actual full health salvage exactly once",is_equal_approx(float(runtime.actor("player").pack.timber),timber_before+float(salvage.get("timber",0))))
	expect("real walk to damaged yard gate",walk_to(29.2,40.2).ok)
	var gate:="rural:v1:RH-HOME:old-house:yard-gate"
	expect("damaged gate starts real opening",command("door",gate,{"operation":"open"}).ok)
	for i in 4:runtime.tick(0.1)
	expect("actual approved wood damage surfaces move with the original full hinge without a clipped substitute",absf(scene.doors[gate].node.rotation.y)>1 and scene.doors[gate].full.get_parent()==scene.doors[gate].node and not scene.doors[gate].has("cut") and material_present(scene.doors[gate].full,scene.material("b_wood_damage_detail")))
	expect("damaged gate starts actual closing",command("door",gate,{"operation":"close"}).ok)
	for i in 4:runtime.tick(0.1)
	var before:Dictionary=runtime.actor("player").pack.duplicate(true)
	var repair:=command("structure",gate,{"kind":"repair","source_id":"pack:player","output_id":"pack:player","tool_id":hammer})
	expect("real damaged gate repair starts",repair.ok,repair)
	for i in range(59):runtime.tick(0.1)
	expect("repair labor does not prematurely heal or consume",building.instance(gate).hp==60 and runtime.actor("player").pack==before)
	runtime.tick(0.1)
	expect("repair completes actual HP and exact one timber/scrap",building.instance(gate).hp==120 and runtime.actor("player").pack.timber==before.timber-1 and runtime.actor("player").pack.scrap==before.scrap-1)
	expect("live gate repair appears on its original hinged leaf",material_present(scene.doors[gate].full,scene.material("b_wood_repair_detail")))
	expect("full actual HP repair removes approved wood damage from the live leaf",not material_present(scene.doors[gate].full,scene.material("b_wood_damage_detail")))
	expect("same gate E default opens",command("door",gate,{}).ok)
	for i in range(4):runtime.tick(0.1)
	expect("door open state true",building.instance(gate).door.open)
	expect("same derived door hinge follows completed opening",absf(scene.doors[gate].node.rotation.y)>1)
	expect("same gate E default closes",command("door",gate,{}).ok)
	for i in range(4):runtime.tick(0.1)
	expect("door closed state true",not building.instance(gate).door.open)
	expect("real walk to construction point",walk_to(33.3,40.5).ok)
	var bench:Dictionary=building.make_instance("workbench","bbb:actual-bench",{"x":34,"y":0,"z":42,"regionId":"RH-HOME"})
	expect("knowledge-gated workbench construction starts",command("structure",bench.id,{"kind":"place","instance":bench,"source_id":"pack:player","tool_id":hammer}).ok)
	wait_work()
	expect("actual new workbench installed",not building.instance(bench.id).is_empty())
	expect("actual constructed station uses existing workbench model",scene.objects.has(bench.id) and scene.models.has("city_workbench"))
	var old_hammer:=float(runtime.tool(hammer).durability)
	var order:=command("craft",bench.id,{"recipe_id":"repair_axe","repair_tool_id":axe,"tool_ids":[saw,hammer],"source_id":"pack:player","output_id":"pack:player"})
	expect("broken physical axe repair starts at real workbench",order.ok,order)
	wait_work()
	expect("repair affects exact axe and required operator only",runtime.tool(axe).durability==60 and runtime.tool(saw).durability==100 and runtime.tool(hammer).durability<old_hammer)
	var foundation:Dictionary=building.structures().instances.filter(func(v:Dictionary)->bool:return v.definitionId=="foundation")[0]
	var footprint:AABB=building.geometry.bounds(foundation)
	var cell:=Vector3i(floori(footprint.position.x/0.5),floori((footprint.position.y-0.01)/0.5),floori(footprint.position.z/0.5))
	var edits:Array=[{"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":world.cell_at(cell.x,cell.y,cell.z),"after":0}]
	var excavation:Dictionary=world.prepare_changes(edits,world.get_revision())
	var safety:Dictionary=building.validate_world_draft(excavation.view,runtime.facts(),edits) if excavation.ok else excavation
	expect("dig under foundation rejected with full support retained",excavation.ok and not safety.ok and safety.code=="DEPENDENT",safety)
	# Sleeping place is a real world entity; no instant free cloth or bed flag.
	var bed:="rural:v1:RH-HOME:old-house:sleeping-place"
	var bed_position:Dictionary={"x":11.8,"y":0,"z":28.5,"regionId":"RH-HOME","buildingId":"rural:v1:RH-HOME:old-house","storeyId":"rural:v1:RH-HOME:old-house:ground"}
	var current:=runtime.facts();current.actors[0].merge(bed_position,true);current.actors[0].stamina=100
	runtime.configure({"world":world,"services":{"buildings":building,"actions":actions,"production":production},"facts":current})
	var care:=command("care",bed,{"source_id":"pack:player"})
	expect("bed preparation begins from real cloth and position",care.ok,care)
	for i in range(30):runtime.tick(0.1)
	expect("cloth held until bedding completes",runtime.actor("player").pack.cloth==2 and production.reserved("pack:player","cloth")==2 and not world.entity(bed).data.prepared)
	expect("cancel bedding releases material without consuming",command("cancel").ok and production.reserved("pack:player","cloth")==0 and runtime.actor("player").pack.cloth==2)
	expect("bedding can restart",command("care",bed,{"source_id":"pack:player"}).ok)
	wait_work()
	expect("completed bedding consumes exactly 2 cloth and persists state",runtime.actor("player").pack.cloth==0 and world.entity(bed).data.prepared)
	expect("cannot repeat bedding for rewards",not command("care",bed).ok)
	expect("prepared bed has actual textile mesh",scene.objects[bed].has_node("PreparedBedding"))
	var leaf:MeshInstance3D=scene.doors[gate].node.get_child(0)
	var patched:=false
	for surface in leaf.mesh.get_surface_count():
		if leaf.mesh.surface_get_material(surface)==scene.material("b_wood_repair_detail"):patched=true
	expect("completed gate repair material attached to actual door leaf",patched)
	var capture:=runtime.capture_checkpoint()
	var visible_before:=derived_state(scene)
	scene.free()
	expect("camp changes capture and restore in sole world",world.load_snapshot(capture.world).ok and runtime.configure({"world":world,"services":{"buildings":building,"actions":actions,"production":production},"facts":capture.facts}).ok)
	scene=building.create_view({"runtime":runtime})
	expect("restored buildings doors bedding contents and traces derive identically",derived_state(scene)==visible_before)
	scene.free()
	var snapshot:Dictionary=building.validate_snapshot(world,runtime.facts())
	expect("full camp final references valid",snapshot.ok,snapshot)
	finish(started)
