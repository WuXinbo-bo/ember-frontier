extends "res://tests/buildings/domain_suite.gd"
## Actual B repair module/ports/entities and craft owner on a bounded flat
## diagnostic floor. Finite resources and generated-place fixture, not economy/VA.
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var observations:Array=[]
var approach_from_real_hints:=false

func run()->void:
	for turn:int in 4:run_turn(turn)
	var result:Dictionary={"scope":"real repair_shed_v2 geometry/port/owner/rig on explicit flat finite fixture; no actual generated-plan, OS, VA or reach acceptance","approach_from_real_hints":approach_from_real_hints,"checks":checks,"failures":failures,"observations":observations}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_REPAIR_PORT "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)

func run_turn(turn:int)->void:
	world=World.new();building=Building.new();actions=Actions.new();production=Production.new();runtime=Runtime.new()
	var source:Dictionary=Generator.generate(713)
	for key:String in source.chunks:
		var coord:Vector3i=Data.coord(key)
		if coord.x not in [2,3,4,5] or coord.z not in [2,3,4,5]:continue
		var cells:PackedInt32Array=source.chunks[key].cells.duplicate()
		for y:int in 16:
			for z:int in 16:
				for x:int in 16:cells[x+16*(z+16*y)]=2 if coord.y*16+y<0 else 0
		source.chunks[key].cells=cells
	source.entities={}
	expect("explicit floor loads q"+str(turn),world.load_snapshot(source).ok)
	var module:Dictionary=Modules.record_for({"id":"ddd:repair:"+str(turn),"definition_id":"r34.module.repair_shed_v2","region":"RH-HOME","position":{"x":32,"y":0,"z":32},"quarter_turn":turn,"player_built":false,"source_key":"ddd:finite-generated-place:"+str(turn)})
	var definition:Dictionary=Modules.definition(module.definition_id)
	var port:Dictionary=Shape.ports(module,definition).filter(func(p:Dictionary)->bool:return p.id=="work")[0]
	var at:Dictionary=port.location
	initialize_at(at,[],Modules.stock_rows(module,definition))
	var changes:Array=[];var structures:Dictionary={"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]}
	Modules.append_instance(world,building,module,definition,changes,structures)
	changes.append(building.extension_change(Building.EXTENSION,structures))
	var state:Dictionary=Modules.initial();state.instances.append(module);changes.append(building.extension_change(Modules.KEY,state))
	var p:Dictionary=Production.empty_state();p.knowledge={"player":["basic_woodwork"]};p.tools=[{"id":"ddd:saw","kind":"hand_saw","holderId":"pack:player","durability":100.0}]
	changes.append(building.extension_change(Production.KEY,p))
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	expect("actual full B module commits q"+str(turn),draft.ok and world.commit_prepared(draft.capability).ok,draft.get("reason"))
	if not draft.ok:return
	var facts:Dictionary=runtime.facts();facts.actors[0].pack={"log":1}
	var modules:=Modules.new()
	var configured:Dictionary=runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production,"modules":modules}})
	expect("real module schema and body configure at declared port q"+str(turn),configured.ok and modules.validate_extensions(runtime.facts()).ok,configured)
	if not configured.ok:return
	expect("declared port actually supports full original body q"+str(turn),not building.current_space().standing_point(at).is_empty())
	var selected_hint:Dictionary={}
	if approach_from_real_hints:
		var hints:Array=actions.work_points({"kind":"craft","target_id":module.config.workbench_id,"payload":{}})
		expect("actual B action owner exposes real approach hints q"+str(turn),not hints.is_empty())
		if hints.is_empty():return
		hints.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a).distance_squared_to(Geometry.point(at))<Geometry.point(b).distance_squared_to(Geometry.point(at)))
		selected_hint=hints[0]
		var moved:Dictionary=command("walk","",{},selected_hint)
		expect("real body accepts route to closest owner hint q"+str(turn),moved.ok,moved)
		if not moved.ok:return
		for i:int in 12:runtime.tick(0.1)
		expect("real movement reaches owner hint without presentation teleport q"+str(turn),Geometry.point(runtime.actor("player")).distance_to(Geometry.point(selected_hint))<0.02)
		var foot:Vector3=Geometry.point(runtime.actor("player"));var clearance:float=INF
		for volume:AABB in building.geometry.boxes(building.instance(module.config.workbench_id)):
			var nearest:Vector3=foot.max(volume.position).min(volume.end);nearest.y=foot.y
			clearance=minf(clearance,foot.distance_to(nearest))
		expect("near owner hint keeps original radius plus four centimetres q"+str(turn),absf(clearance-0.30)<0.002,{"body_radius_m":0.26,"clearance_m":clearance})
	var view:=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	var shoulder_origin:Vector3=view._arms.player.position
	var shoulder_scale:Vector3=view._arms.player.scale
	var body_origin:Vector3=view.roots.player.position
	var started:Dictionary=command("craft",module.config.workbench_id,{"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":["ddd:saw"]})
	expect("real craft admits declared repair port q"+str(turn),started.ok,started)
	if started.ok:
		var samples:Array=[]
		for i:int in 24:
			runtime.tick(0.1);view.sync(0)
			var row:Dictionary=view.statistics().work.player
			if row.get("contact_result") is Dictionary:
				var tool_node:Node3D=view._props.player
				var arm_node:Node3D=view._arms.player
				var preserved:bool=arm_node.position.is_equal_approx(shoulder_origin) and arm_node.scale.is_equal_approx(shoulder_scale) and tool_node.position.is_equal_approx(Vector3(0,-0.51,0.06)) and tool_node.scale.is_equal_approx(Vector3.ONE) and view.roots.player.position.is_equal_approx(body_origin) and is_equal_approx(arm_node.global_position.distance_to(tool_node.global_position),float(row.arm_contact.rigid_limb_m))
				samples.append({"progress":row.progress_seconds,"contact":row.contact,"arm":row.arm_contact,"result":row.contact_result,"original_body_grip_limb":preserved})
		expect("real owner yields full repair port contact samples q"+str(turn),samples.size()==24)
		expect("actual existing saw tooth reaches real work face during contact phase q"+str(turn),samples.any(func(s:Dictionary)->bool:return float(s.arm.retraction_meters)<=0.01 and float(s.result.gap_meters)<=0.04))
		expect("actual work face stays upward without tool penetration q"+str(turn),samples.all(func(s:Dictionary)->bool:return s.contact.normal==[0.0,1.0,0.0] and float(s.result.signed_plane_gap)>=-0.002))
		expect("intentional stroke lift remains present q"+str(turn),samples.any(func(s:Dictionary)->bool:return float(s.arm.retraction_meters)>0.1 and float(s.result.gap_meters)>0.08))
		expect("actual contact preserves original body shoulder grip and rigid limb q"+str(turn),samples.all(func(s:Dictionary)->bool:return s.original_body_grip_limb and float(s.arm.shoulder_degrees)<=65.001 and float(s.result.wrist_degrees)<=35.001 and float(s.arm.radial_shortfall_m)<0.00001))
		observations.append({"turn":turn,"port":at,"selected_hint":selected_hint,"actual_actor":Geometry.location(runtime.actor("player")),"bench":building.instance(module.config.workbench_id).position,"samples":samples})
		var before:Dictionary=runtime.capture_checkpoint();var arm:Transform3D=view._arms.player.transform;var tool:Transform3D=view._props.player.transform
		runtime.set_paused(true);view.sync(1.0)
		expect("real pause preserves corrected saw pose q"+str(turn),view._arms.player.transform.is_equal_approx(arm) and view._props.player.transform.is_equal_approx(tool))
		runtime.set_paused(false);view.sync(0)
		expect("view pause/resume never changes work stock or clock q"+str(turn),Data.json_equal(before,runtime.capture_checkpoint()))
		expect("real interrupted craft cancels q"+str(turn),command("cancel").ok)
		view.sync(0)
		expect("cancel removes manual work correction q"+str(turn),not view._manual_work.has("player"))
	view.free()
